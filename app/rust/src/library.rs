//! Biblioteca local (músicas do aparelho, sem servidor): varre pastas, lê as
//! tags e a capa de cada arquivo e mantém um índice em JSON. Numa nova
//! varredura só relê os arquivos novos ou alterados (tamanho/data).

use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::UNIX_EPOCH;

use anyhow::{Context, Result};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, TrackType};
use symphonia::core::io::{MediaSourceStream, MediaSourceStreamOptions};
use symphonia::core::meta::{MetadataOptions, MetadataReader, MetadataRevision, StandardTag, StandardVisualKey, Tag, Visual};
use symphonia::default::meta::{ApeReader, Id3v1Reader, Id3v2Reader};

use crate::engine::decoder::Decoder;

/// Extensões que o motor sabe tocar em qualquer aparelho.
const AUDIO_EXT: &[&str] = &[
    "mp3", "mp2", "mp1", "mpa", "flac", "ogg", "oga", "opus", "m4a", "mp4", "m4b", "aac", "wav", "aiff", "aif", "aifc", "mka",
    "webm", "weba", "caf", "dsf", "dff", "ape", "wv",
];
/// No computador, com o ffmpeg do sistema, também estas (ver
/// `engine/decoder/ffmpeg.rs`).
#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
const FFMPEG_EXT: &[&str] =
    &["wma", "asf", "mpc", "mp+", "mpp", "tta", "ac3", "eac3", "dts", "amr", "awb", "spx", "tak", "ofr", "ofs", "shn", "ra", "au", "snd"];
/// Imagens de capa na pasta do álbum, em ordem de preferência.
const COVER_NAMES: &[&str] = &["cover", "folder", "front", "album", "albumart"];

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct LocalTrack {
    pub path: String,
    pub size: i64,
    pub mtime: i64,
    pub title: String,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub track: Option<u32>,
    pub disc: Option<u32>,
    pub year: Option<i32>,
    pub genre: Option<String>,
    pub duration_ms: Option<i64>,
    pub sample_rate: Option<u32>,
    pub bit_depth: Option<u32>,
    pub channels: Option<u32>,
    pub bitrate_kbps: Option<u32>,
    pub bpm: Option<u32>,
    /// Imagem da capa (da pasta ou extraída do arquivo).
    pub cover: Option<String>,
    pub rg_track_gain: Option<f32>,
    pub rg_album_gain: Option<f32>,
    pub rg_track_peak: Option<f32>,
    pub rg_album_peak: Option<f32>,
}

/// Arquivos lidos na varredura em andamento (para a barra de progresso).
pub static SCAN_PROGRESS: AtomicU32 = AtomicU32::new(0);

pub fn load_index(index: &Path) -> Vec<LocalTrack> {
    fs::read(index).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

fn save_index(index: &Path, tracks: &[LocalTrack]) -> Result<()> {
    if let Some(dir) = index.parent() {
        fs::create_dir_all(dir)?;
    }
    let tmp = index.with_extension("tmp");
    fs::write(&tmp, serde_json::to_vec(tracks)?)?;
    fs::rename(&tmp, index)?;
    Ok(())
}

fn is_audio(p: &Path) -> bool {
    p.extension().and_then(|e| e.to_str()).is_some_and(|e| {
        let e = e.to_ascii_lowercase();
        AUDIO_EXT.contains(&e.as_str()) || via_ffmpeg(&e)
    })
}

/// Formato que só o ffmpeg do sistema lê (e há um ffmpeg).
fn via_ffmpeg(ext: &str) -> bool {
    #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
    return FFMPEG_EXT.contains(&ext) && crate::engine::decoder::ffmpeg::available();
    #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
    {
        let _ = ext;
        false
    }
}

fn walk(dir: &Path, out: &mut Vec<PathBuf>, depth: usize) {
    if depth > 24 {
        return;
    }
    let Ok(rd) = fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let name = e.file_name();
        if name.to_string_lossy().starts_with('.') {
            continue;
        }
        let Ok(ft) = e.file_type() else { continue };
        let p = e.path();
        if ft.is_dir() {
            walk(&p, out, depth + 1);
        } else if ft.is_file() && is_audio(&p) {
            out.push(p);
        }
    }
}

fn fnv1a64(s: &str) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in s.bytes() {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

/// Capa da pasta (cover.jpg, folder.png...), se houver.
fn folder_cover(dir: &Path) -> Option<String> {
    let rd = fs::read_dir(dir).ok()?;
    let mut best: Option<(usize, PathBuf)> = None;
    for e in rd.flatten() {
        let p = e.path();
        let Some(ext) = p.extension().and_then(|x| x.to_str()).map(|x| x.to_ascii_lowercase()) else { continue };
        if !matches!(ext.as_str(), "jpg" | "jpeg" | "png" | "webp") {
            continue;
        }
        let stem = p.file_stem().and_then(|x| x.to_str()).unwrap_or("").to_ascii_lowercase();
        if let Some(rank) = COVER_NAMES.iter().position(|n| stem == *n) {
            if best.as_ref().is_none_or(|(r, _)| rank < *r) {
                best = Some((rank, p));
            }
        }
    }
    best.map(|(_, p)| p.to_string_lossy().into_owned())
}

fn parse_gain(s: &str) -> Option<f32> {
    s.trim().trim_end_matches("dB").trim_end_matches("db").trim().parse().ok()
}

fn year_of(s: &str) -> Option<i32> {
    let digits: String = s.chars().take_while(|c| c.is_ascii_digit()).collect();
    if digits.len() >= 4 {
        digits[..4].parse().ok()
    } else {
        None
    }
}

/// Tag sem tradução padrão no symphonia (o MKV/WebM só traduz parte dos
/// nomes; o APE do WavPack usa "Year"): pelo nome, sem passar por cima do
/// que veio traduzido.
fn apply_raw_tag(t: &mut LocalTrack, raw: &symphonia::core::meta::RawTag) {
    let symphonia::core::meta::RawValue::String(v) = &raw.value else { return };
    let v = v.trim();
    if v.is_empty() {
        return;
    }
    let number = |v: &str| v.split('/').next().and_then(|n| n.trim().parse::<u32>().ok());
    match raw.key.to_ascii_lowercase().as_str() {
        "artist" => t.artist = t.artist.take().or_else(|| Some(v.to_string())),
        "album" => t.album = t.album.take().or_else(|| Some(v.to_string())),
        "album_artist" | "albumartist" | "album artist" => t.album_artist = t.album_artist.take().or_else(|| Some(v.to_string())),
        "date" | "year" | "date_released" | "date_recorded" => t.year = t.year.or_else(|| year_of(v)),
        "track" | "tracknumber" | "part_number" => t.track = t.track.or_else(|| number(v)),
        "disc" | "discnumber" => t.disc = t.disc.or_else(|| number(v)),
        "genre" => t.genre = t.genre.take().or_else(|| Some(v.to_string())),
        _ => {}
    }
}

fn apply_tag(t: &mut LocalTrack, tag: &Tag) {
    let Some(std) = &tag.std else { return apply_raw_tag(t, &tag.raw) };
    let s = |v: &std::sync::Arc<String>| {
        let v = v.trim();
        (!v.is_empty()).then(|| v.to_string())
    };
    match std {
        StandardTag::TrackTitle(v) => {
            if let Some(v) = s(v) {
                t.title = v;
            }
        }
        StandardTag::Artist(v) => t.artist = s(v).or(t.artist.take()),
        StandardTag::AlbumArtist(v) => t.album_artist = s(v).or(t.album_artist.take()),
        StandardTag::Album(v) => t.album = s(v).or(t.album.take()),
        StandardTag::Genre(v) => t.genre = s(v).or(t.genre.take()),
        StandardTag::TrackNumber(n) => t.track = Some(*n as u32),
        StandardTag::DiscNumber(n) => t.disc = Some(*n as u32),
        StandardTag::Bpm(n) => t.bpm = Some(*n as u32),
        StandardTag::RecordingYear(y) | StandardTag::ReleaseYear(y) => t.year = t.year.or(Some(*y as i32)),
        StandardTag::RecordingDate(v) | StandardTag::ReleaseDate(v) | StandardTag::OriginalReleaseDate(v) => {
            t.year = t.year.or_else(|| year_of(v));
        }
        StandardTag::ReplayGainTrackGain(v) => t.rg_track_gain = parse_gain(v),
        StandardTag::ReplayGainAlbumGain(v) => t.rg_album_gain = parse_gain(v),
        StandardTag::ReplayGainTrackPeak(v) => t.rg_track_peak = parse_gain(v),
        StandardTag::ReplayGainAlbumPeak(v) => t.rg_album_peak = parse_gain(v),
        _ => {}
    }
}

fn pick_visual(visuals: &[Visual]) -> Option<&Visual> {
    visuals
        .iter()
        .find(|v| v.usage == Some(StandardVisualKey::FrontCover))
        .or_else(|| visuals.first())
}

type Cover = Option<(Vec<u8>, Option<String>)>;

/// Junta à faixa as tags de uma revisão de metadados e guarda a primeira capa.
fn apply_revision(t: &mut LocalTrack, rev: &MetadataRevision, cover: &mut Cover) {
    for tag in rev.media.tags.iter().chain(rev.per_track.iter().flat_map(|p| p.metadata.tags.iter())) {
        apply_tag(t, tag);
    }
    if cover.is_none() {
        if let Some(v) = pick_visual(&rev.media.visuals) {
            *cover = Some((v.data.to_vec(), v.media_type.clone()));
        }
    }
}

/// Lê um arquivo. `covers` guarda as capas extraídas; `dir_cover` é a capa
/// da pasta (tem prioridade sobre a embutida).
fn read_track(path: &Path, size: i64, mtime: i64, dir_cover: Option<String>, covers: &Path) -> Result<LocalTrack> {
    let mut t = LocalTrack {
        path: path.to_string_lossy().into_owned(),
        size,
        mtime,
        title: path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default(),
        ..Default::default()
    };
    let mut cover: Cover = None;
    if let Err(e) = read_with_symphonia(path, &mut t, &mut cover) {
        // DSD, APE, WavPack ou formato do ffmpeg: o symphonia não abre.
        read_other(path, &mut t, &mut cover).map_err(|e2| e2.context(format!("{e:#}")))?;
    }
    if let Some(ms) = t.duration_ms.filter(|ms| *ms > 0) {
        t.bitrate_kbps = Some((size as u128 * 8 / ms as u128) as u32);
    }

    t.cover = dir_cover.or_else(|| {
        let (data, mime) = cover?;
        let ext = match mime.as_deref() {
            Some("image/png") => "png",
            Some("image/webp") => "webp",
            _ => "jpg",
        };
        // Uma capa por álbum (as faixas do mesmo álbum dividem o arquivo).
        let key = format!(
            "{}|{}",
            path.parent().map(|d| d.to_string_lossy()).unwrap_or_default(),
            t.album.as_deref().unwrap_or(&t.title)
        );
        let out = covers.join(format!("{:016x}.{ext}", fnv1a64(&key)));
        if !out.exists() {
            let tmp = out.with_extension("tmp");
            fs::write(&tmp, &data).ok()?;
            fs::rename(&tmp, &out).ok()?;
        }
        Some(out.to_string_lossy().into_owned())
    });
    Ok(t)
}

fn read_with_symphonia(path: &Path, t: &mut LocalTrack, cover: &mut Cover) -> Result<()> {
    let file = File::open(path)?;
    let mss = MediaSourceStream::new(Box::new(file), MediaSourceStreamOptions::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }
    let mut format = symphonia::default::get_probe()
        .probe(&hint, mss, FormatOptions::default(), MetadataOptions::default())
        .context("formato não reconhecido")?;

    if let Some(track) = format.default_track(TrackType::Audio).or_else(|| format.first_track_known_codec(TrackType::Audio)) {
        if let Some(p) = track.codec_params.as_ref().and_then(|p| p.audio()) {
            t.sample_rate = p.sample_rate;
            t.bit_depth = p.bits_per_sample;
            t.channels = p.channels.as_ref().map(|c| c.count() as u32);
            if let (Some(frames), Some(rate)) = (track.num_frames, p.sample_rate) {
                if rate > 0 {
                    t.duration_ms = Some((frames as u128 * 1000 / rate as u128) as i64);
                }
            }
        }
        // Sem contagem de frames (MKV/WebM): a duração que o contêiner declara.
        if t.duration_ms.is_none() {
            let info = format.media_info();
            let declared = track.duration.zip(track.time_base).or(info.duration.zip(info.time_base));
            t.duration_ms = declared.map(|(d, tb)| (d.get() as u128 * tb.numer.get() as u128 * 1000 / tb.denom.get() as u128) as i64);
        }
    }

    // Todas as revisões de metadados (ex.: ID3v2 antes do áudio + tags do contêiner).
    let mut md = format.metadata();
    loop {
        if let Some(rev) = md.current() {
            apply_revision(t, rev, cover);
        }
        if md.pop().is_none() {
            break;
        }
    }
    Ok(())
}

/// O arquivo como `MediaSourceStream` já na posição `offset` (o leitor de
/// tags começa dali).
fn stream_at(file: &File, offset: u64) -> Option<MediaSourceStream<'static>> {
    let mut mss = MediaSourceStream::new(Box::new(file.try_clone().ok()?), MediaSourceStreamOptions::default());
    mss.seek(SeekFrom::Start(offset)).ok()?;
    Some(mss)
}

fn id3v2_at(file: &File, offset: u64) -> Option<MetadataRevision> {
    let mut r = Id3v2Reader::try_new(stream_at(file, offset)?, MetadataOptions::default()).ok()?;
    r.read_all().ok().map(|b| b.revision)
}

/// Tag APEv1/v2 no fim do arquivo (antes de uma ID3v1, se houver), a do
/// Monkey's Audio e do WavPack.
fn ape_tag_at_end(file: &File, len: u64) -> Option<MetadataRevision> {
    [32u64, 160].into_iter().filter(|&back| len >= back).find_map(|back| {
        let mut r = ApeReader::try_new(stream_at(file, len - back)?, MetadataOptions::default()).ok()?;
        r.read_all().ok().map(|b| b.revision)
    })
}

fn id3v1_at_end(file: &File, len: u64) -> Option<MetadataRevision> {
    let mut r = Id3v1Reader::try_new(stream_at(file, len.checked_sub(128)?)?, MetadataOptions::default()).ok()?;
    r.read_all().ok().map(|b| b.revision)
}

/// Formatos que o symphonia não abre: os números vêm do decodificador do
/// motor e as tags de onde cada formato as guarda.
fn read_other(path: &Path, t: &mut LocalTrack, cover: &mut Cover) -> Result<()> {
    let ext = path.extension().and_then(|e| e.to_str()).map(str::to_ascii_lowercase);
    #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
    if ext.as_deref().is_some_and(via_ffmpeg) {
        // Só o ffprobe: abrir o decodificador do ffmpeg para cada arquivo da
        // varredura seria lento.
        let p = crate::engine::decoder::ffmpeg::probe(path).context("o ffmpeg não reconhece")?;
        t.sample_rate = p.sample_rate;
        t.channels = p.channels;
        t.bit_depth = p.bits_per_sample;
        t.duration_ms = p.duration_ms.map(|ms| ms as i64);
        apply_text_tags(t, &p.tags);
        return Ok(());
    }
    let dec = Decoder::open_file(Box::new(File::open(path)?), ext.as_deref(), None, Some(path))?;
    t.channels = Some(dec.channels as u32);
    t.duration_ms = dec.total_frames.map(|f| (f as u128 * 1000 / dec.sample_rate as u128) as i64);
    if let Some(mult) = dec.codec.strip_prefix("dsd").and_then(|m| m.parse::<u32>().ok()) {
        // DSD: mostra a taxa e os bits do original, não os do PCM convertido.
        t.sample_rate = Some(mult * if dec.sample_rate == 88_200 { 44_100 } else { 48_000 });
        t.bit_depth = Some(1);
    } else {
        t.sample_rate = Some(dec.sample_rate);
        t.bit_depth = dec.bits_per_sample;
    }
    drop(dec);

    let mut file = File::open(path)?;
    let len = file.metadata()?.len();
    let mut revs = Vec::new();
    if let Some(at) = crate::engine::decoder::dsf_id3_offset(&mut file) {
        revs.extend(id3v2_at(&file, at));
    }
    if let Ok(layout) = crate::engine::decoder::dff_layout(&mut file) {
        if let Some((at, _)) = layout.id3 {
            revs.extend(id3v2_at(&file, at));
        }
        t.title = layout.title.unwrap_or(std::mem::take(&mut t.title));
        t.artist = layout.artist.or(t.artist.take());
    }
    revs.extend(id3v2_at(&file, 0));
    revs.extend(ape_tag_at_end(&file, len));
    revs.extend(id3v1_at_end(&file, len));
    for rev in &revs {
        apply_revision(t, rev, cover);
    }
    Ok(())
}

/// Tags em texto (chave em minúsculas), como as do ffprobe.
#[cfg_attr(not(any(target_os = "linux", target_os = "windows", target_os = "macos")), allow(dead_code))]
fn apply_text_tags(t: &mut LocalTrack, tags: &[(String, String)]) {
    let number = |v: &str| v.split('/').next().and_then(|n| n.trim().parse::<u32>().ok());
    for (k, v) in tags {
        let v = v.trim();
        if v.is_empty() {
            continue;
        }
        match k.as_str() {
            "title" => t.title = v.to_string(),
            "artist" => t.artist = Some(v.to_string()),
            "album_artist" | "albumartist" | "album artist" => t.album_artist = Some(v.to_string()),
            "album" => t.album = Some(v.to_string()),
            "genre" => t.genre = Some(v.to_string()),
            "track" | "tracknumber" => t.track = number(v),
            "disc" | "discnumber" => t.disc = number(v),
            "date" | "year" | "originaldate" => t.year = t.year.or_else(|| year_of(v)),
            "bpm" | "tbpm" => t.bpm = v.parse::<f32>().ok().map(|b| b.round() as u32),
            "replaygain_track_gain" => t.rg_track_gain = parse_gain(v),
            "replaygain_album_gain" => t.rg_album_gain = parse_gain(v),
            "replaygain_track_peak" => t.rg_track_peak = parse_gain(v),
            "replaygain_album_peak" => t.rg_album_peak = parse_gain(v),
            _ => {}
        }
    }
}

/// Lê um arquivo avulso (ex.: escolhido para mandar numa Jam).
pub fn read_file(path: &Path, covers: &Path) -> Option<LocalTrack> {
    let meta = fs::metadata(path).ok()?;
    let mtime = meta.modified().ok()?.duration_since(UNIX_EPOCH).ok()?.as_secs() as i64;
    fs::create_dir_all(covers).ok()?;
    read_track(path, meta.len() as i64, mtime, None, covers).ok()
}

/// Varre as pastas e atualiza o índice. Devolve todas as faixas.
pub fn scan(folders: &[String], index: &Path, covers: &Path) -> Result<Vec<LocalTrack>> {
    SCAN_PROGRESS.store(0, Ordering::Relaxed);
    fs::create_dir_all(covers)?;
    let previous: HashMap<String, LocalTrack> = load_index(index).into_iter().map(|t| (t.path.clone(), t)).collect();

    let mut files = Vec::new();
    for f in folders {
        walk(Path::new(f), &mut files, 0);
    }
    files.sort();
    files.dedup();

    let dir_covers: Mutex<HashMap<PathBuf, Option<String>>> = Mutex::new(HashMap::new());
    let read_one = |path: &PathBuf| -> Option<LocalTrack> {
        let meta = fs::metadata(path).ok()?;
        let size = meta.len() as i64;
        let mtime = meta
            .modified()
            .ok()
            .and_then(|m| m.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        SCAN_PROGRESS.fetch_add(1, Ordering::Relaxed);
        let key = path.to_string_lossy();
        if let Some(old) = previous.get(key.as_ref()) {
            let cover_ok = old.cover.as_ref().is_none_or(|c| Path::new(c).exists());
            if old.size == size && old.mtime == mtime && cover_ok {
                return Some(old.clone());
            }
        }
        let dir = path.parent().map(Path::to_path_buf).unwrap_or_default();
        let dir_cover = {
            let mut cache = dir_covers.lock();
            cache.entry(dir.clone()).or_insert_with(|| folder_cover(&dir)).clone()
        };
        match read_track(path, size, mtime, dir_cover, covers) {
            Ok(t) => Some(t),
            Err(e) => {
                log::debug!("biblioteca: {path:?}: {e:#}");
                None
            }
        }
    };

    use rayon::prelude::*;
    let tracks: Vec<LocalTrack> = files.par_iter().filter_map(read_one).collect();
    save_index(index, &tracks)?;
    Ok(tracks)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scans_wav_with_folder_cover_and_reuses_index() {
        let dir = std::env::temp_dir().join(format!("bk-lib-{}", std::process::id()));
        let album = dir.join("Artista/Disco");
        fs::create_dir_all(&album).unwrap();
        // WAV de 1 s, 8 kHz, 16 bits.
        let spec = hound::WavSpec { channels: 1, sample_rate: 8000, bits_per_sample: 16, sample_format: hound::SampleFormat::Int };
        let mut w = hound::WavWriter::create(album.join("01 Faixa.wav"), spec).unwrap();
        for i in 0..8000 {
            w.write_sample(((i as f32 * 0.05).sin() * 8000.0) as i16).unwrap();
        }
        w.finalize().unwrap();
        fs::write(album.join("Cover.JPG"), b"jpeg").unwrap();
        fs::write(album.join("notas.txt"), b"x").unwrap();

        let index = dir.join("index.json");
        let covers = dir.join("covers");
        let tracks = scan(&[dir.to_string_lossy().into_owned()], &index, &covers).unwrap();
        assert_eq!(tracks.len(), 1);
        let t = &tracks[0];
        assert_eq!(t.title, "01 Faixa");
        assert_eq!(t.duration_ms, Some(1000));
        assert_eq!(t.sample_rate, Some(8000));
        assert!(t.cover.as_deref().unwrap().ends_with("Cover.JPG"));

        // Segunda varredura: reaproveita o índice.
        let again = scan(&[dir.to_string_lossy().into_owned()], &index, &covers).unwrap();
        assert_eq!(again.len(), 1);
        assert_eq!(load_index(&index).len(), 1);
        let _ = fs::remove_dir_all(&dir);
    }

    /// Tag ID3v2.3 mínima com título, artista e faixa.
    fn id3(title: &str, artist: &str) -> Vec<u8> {
        let frame = |id: &[u8], text: &str| {
            let mut f = id.to_vec();
            f.extend_from_slice(&(text.len() as u32 + 1).to_be_bytes());
            f.extend_from_slice(&[0, 0, 3]);
            f.extend_from_slice(text.as_bytes());
            f
        };
        let body = [frame(b"TIT2", title), frame(b"TPE1", artist), frame(b"TRCK", "2/9")].concat();
        let n = body.len() as u32;
        let size = [(n >> 21) as u8 & 0x7f, (n >> 14) as u8 & 0x7f, (n >> 7) as u8 & 0x7f, n as u8 & 0x7f];
        [&b"ID3\x03\x00\x00"[..], &size, &body].concat()
    }

    #[test]
    fn scans_dsd_with_its_id3_tag() {
        use crate::engine::decoder::dsd_tests::{dsf_file_with_tag, modulate};
        let dir = std::env::temp_dir().join(format!("bk-lib-dsd-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let rate = 2_822_400;
        let ch = modulate(|t| 0.4 * (2.0 * std::f64::consts::PI * 500.0 * t).sin(), rate, 0.5);
        fs::write(dir.join("faixa.dsf"), dsf_file_with_tag(&[ch.clone(), ch], rate, &id3("Tema Lírico", "Cantora"))).unwrap();
        let tracks = scan(&[dir.to_string_lossy().into_owned()], &dir.join("index.json"), &dir.join("covers")).unwrap();
        assert_eq!(tracks.len(), 1);
        let t = &tracks[0];
        assert_eq!((t.title.as_str(), t.artist.as_deref(), t.track), ("Tema Lírico", Some("Cantora"), Some(2)));
        assert_eq!((t.sample_rate, t.bit_depth, t.channels, t.duration_ms), (Some(rate), Some(1), Some(2), Some(500)));
        let _ = fs::remove_dir_all(&dir);
    }
}
