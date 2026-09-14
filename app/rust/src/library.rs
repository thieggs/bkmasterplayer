//! Biblioteca local (músicas do aparelho, sem servidor): varre pastas, lê as
//! tags e a capa de cada arquivo e mantém um índice em JSON. Numa nova
//! varredura só relê os arquivos novos ou alterados (tamanho/data).

use std::collections::HashMap;
use std::fs::{self, File};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::UNIX_EPOCH;

use anyhow::{Context, Result};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, TrackType};
use symphonia::core::io::{MediaSourceStream, MediaSourceStreamOptions};
use symphonia::core::meta::{MetadataOptions, StandardTag, StandardVisualKey, Tag, Visual};

/// Extensões que o motor sabe tocar.
const AUDIO_EXT: &[&str] = &["mp3", "flac", "ogg", "oga", "m4a", "mp4", "m4b", "aac", "wav", "aiff", "aif", "aifc", "mka", "caf"];
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
    p.extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| AUDIO_EXT.contains(&e.to_ascii_lowercase().as_str()))
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

fn apply_tag(t: &mut LocalTrack, tag: &Tag) {
    let Some(std) = &tag.std else { return };
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

/// Lê um arquivo. `covers` guarda as capas extraídas; `dir_cover` é a capa
/// da pasta (tem prioridade sobre a embutida).
fn read_track(path: &Path, size: i64, mtime: i64, dir_cover: Option<String>, covers: &Path) -> Result<LocalTrack> {
    let file = File::open(path)?;
    let mss = MediaSourceStream::new(Box::new(file), MediaSourceStreamOptions::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }
    let mut format = symphonia::default::get_probe()
        .probe(&hint, mss, FormatOptions::default(), MetadataOptions::default())
        .context("formato não reconhecido")?;

    let mut t = LocalTrack {
        path: path.to_string_lossy().into_owned(),
        size,
        mtime,
        title: path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default(),
        ..Default::default()
    };

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
    }
    if let Some(ms) = t.duration_ms.filter(|ms| *ms > 0) {
        t.bitrate_kbps = Some((size as u128 * 8 / ms as u128) as u32);
    }

    // Todas as revisões de metadados (ex.: ID3v2 antes do áudio + tags do contêiner).
    let mut cover_data: Option<(Vec<u8>, Option<String>)> = None;
    {
        let mut md = format.metadata();
        loop {
            if let Some(rev) = md.current() {
                for tag in rev.media.tags.iter().chain(rev.per_track.iter().flat_map(|p| p.metadata.tags.iter())) {
                    apply_tag(&mut t, tag);
                }
                if cover_data.is_none() && dir_cover.is_none() {
                    if let Some(v) = pick_visual(&rev.media.visuals) {
                        cover_data = Some((v.data.to_vec(), v.media_type.clone()));
                    }
                }
            }
            if md.pop().is_none() {
                break;
            }
        }
    }

    t.cover = dir_cover.or_else(|| {
        let (data, mime) = cover_data?;
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
}
