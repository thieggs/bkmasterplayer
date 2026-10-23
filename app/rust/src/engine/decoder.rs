//! Decodificação: qualquer formato suportado → f32 intercalado.
//!
//! Quase tudo passa pelo symphonia (MP3, AAC, ALAC, FLAC, Vorbis, WAV,
//! AIFF...), com o Opus vindo da libopus. O que ele não lê tem decodificador
//! próprio aqui: DSD (DSF/DFF), Monkey's Audio (.ape) e WavPack (.wv). No
//! computador, o que ainda sobrar (WMA, Musepack, AC-3...) vai para o ffmpeg
//! do sistema, se houver um. Quando nada abre o arquivo, o erro é
//! [`Unsupported`]: o motor então tenta a conversão do servidor, se a música
//! tiver uma (ver `open_track` em `engine/mod.rs`).

mod ape;
mod dsd;
#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
pub mod ffmpeg;
mod wavpack;

pub(crate) use dsd::{dsf_id3_offset, DffLayout};
#[cfg(test)]
pub(crate) use dsd::tests as dsd_tests;

use std::collections::VecDeque;
use std::fmt;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;
use std::sync::OnceLock;

use anyhow::{anyhow, Result};
use symphonia::core::codecs::audio::well_known::CODEC_ID_OPUS;
use symphonia::core::codecs::audio::{AudioCodecParameters, AudioDecoder, AudioDecoderOptions};
use symphonia::core::codecs::registry::CodecRegistry;
use symphonia::core::errors::Error as SymError;
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, FormatReader, SeekMode, SeekTo, TrackType};
use symphonia::core::io::{MediaSource, MediaSourceStream, MediaSourceStreamOptions};
use symphonia::core::meta::MetadataOptions;
use symphonia::core::units::{Time, TimeBase, Timestamp};

/// O arquivo pode estar perfeito, mas o formato ou o codec não é um dos que o
/// motor lê. Diferente de erro de rede ou de arquivo corrompido no meio: quem
/// chamou pode tentar outra fonte do mesmo áudio (a conversão do servidor).
#[derive(Debug)]
pub struct Unsupported(pub String);

impl fmt::Display for Unsupported {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "formato não suportado: {}", self.0)
    }
}

impl std::error::Error for Unsupported {}

/// Erro de formato não suportado, como `anyhow::Error`.
pub(crate) fn unsupported(what: impl Into<String>) -> anyhow::Error {
    Unsupported(what.into()).into()
}

/// O erro (ou a causa dele) é [`Unsupported`]?
pub fn is_unsupported(e: &anyhow::Error) -> bool {
    e.chain().any(|c| c.is::<Unsupported>())
}

/// Um decodificador por trás de [`Decoder`].
trait Backend: Send {
    /// Decodifica o próximo bloco em `out` (substitui o conteúdo; intercalado,
    /// `channels()` canais). `Ok(None)` no fim.
    fn next_chunk(&mut self, out: &mut Vec<f32>) -> Result<Option<usize>>;
    /// Canais do último bloco (alguns formatos mudam no meio).
    fn channels(&self) -> usize;
    /// Seek preciso para `position_ms`; devolve a posição real em frames
    /// (taxa original).
    fn seek(&mut self, position_ms: u64) -> Result<u64>;
}

pub struct Decoder {
    inner: Box<dyn Backend>,
    pub sample_rate: u32,
    pub channels: usize,
    /// Frames tocáveis (sem delay/padding do encoder) na taxa original, se conhecido.
    pub total_frames: Option<u64>,
    /// Bits por amostra do original, se o formato diz (só informativo).
    pub bits_per_sample: Option<u32>,
    /// Codec, para o diagnóstico e os registros (ex.: "flac", "opus", "dsd64").
    pub codec: String,
}

impl Decoder {
    fn new(
        inner: Box<dyn Backend>,
        sample_rate: u32,
        total_frames: Option<u64>,
        bits_per_sample: Option<u32>,
        codec: impl Into<String>,
    ) -> Result<Self> {
        if sample_rate == 0 {
            return Err(unsupported("taxa de amostragem desconhecida"));
        }
        let channels = inner.channels().max(1);
        Ok(Self { inner, sample_rate, channels, total_frames, bits_per_sample, codec: codec.into() })
    }

    pub fn open(source: Box<dyn MediaSource>, ext_hint: Option<&str>, mime_hint: Option<&str>) -> Result<Self> {
        Self::open_file(source, ext_hint, mime_hint, None)
    }

    /// Como [`open`](Self::open), sabendo onde o arquivo está no disco
    /// (`path`): no computador, o ffmpeg do sistema lê por caminho o que
    /// nenhum decodificador embutido lê.
    pub fn open_file(
        mut source: Box<dyn MediaSource>,
        ext_hint: Option<&str>,
        mime_hint: Option<&str>,
        path: Option<&Path>,
    ) -> Result<Self> {
        let ext = ext_hint.map(str::to_ascii_lowercase);
        let opened = match sniff(&mut source)? {
            Magic::Dsf => dsd::open_dsf(source),
            Magic::Dff => dsd::open_dff(source),
            Magic::Ape => ape::open(source),
            Magic::WavPack => wavpack::open(source),
            // ID3v2 na frente de um APE ou WavPack (raro): os dois acham o
            // começo de verdade sozinhos. Em MP3 é o normal, e lá não se pula
            // a tag (com capa grande, seria baixar à toa no streaming).
            Magic::Id3 if ext.as_deref() == Some("ape") => ape::open(source),
            Magic::Id3 if ext.as_deref() == Some("wv") => wavpack::open(source),
            Magic::Known(name) => Err(unsupported(name)),
            Magic::Id3 | Magic::Other => open_symphonia(source, ext.as_deref(), mime_hint),
        };
        #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
        if let (Err(e), Some(path)) = (&opened, path) {
            if is_unsupported(e) && ffmpeg::available() {
                log::info!("{}: {e:#}; tentando o ffmpeg", path.display());
                return ffmpeg::open(path);
            }
        }
        #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
        let _ = path;
        opened
    }

    /// Decodifica o próximo pacote em `out` (intercalado, `self.channels` canais).
    /// Retorna `Ok(None)` no fim do arquivo.
    pub fn next_chunk(&mut self, out: &mut Vec<f32>) -> Result<Option<usize>> {
        let r = self.inner.next_chunk(out)?;
        self.channels = self.inner.channels().max(1);
        Ok(r)
    }

    /// Seek preciso. Retorna a posição real em frames (taxa original).
    pub fn seek(&mut self, position_ms: u64) -> Result<u64> {
        self.inner.seek(position_ms)
    }
}

/// O que os primeiros bytes dizem do arquivo.
enum Magic {
    Dsf,
    Dff,
    Ape,
    WavPack,
    /// Tag ID3v2: o contêiner vem depois dela.
    Id3,
    /// Formato conhecido que não tem decodificador embutido.
    Known(&'static str),
    /// O symphonia decide.
    Other,
}

/// Olha os primeiros bytes e volta a fonte para o início.
fn sniff(src: &mut Box<dyn MediaSource>) -> Result<Magic> {
    let mut head = [0u8; 16];
    let n = read_up_to(src, &mut head)?;
    src.seek(SeekFrom::Start(0))?;
    let h = &head[..n];
    let starts = |m: &[u8]| h.starts_with(m);
    Ok(if starts(b"DSD ") {
        Magic::Dsf
    } else if starts(b"FRM8") {
        Magic::Dff
    } else if starts(b"MAC ") {
        Magic::Ape
    } else if starts(b"wvpk") {
        Magic::WavPack
    } else if starts(b"ID3") {
        Magic::Id3
    } else if starts(&[0x30, 0x26, 0xb2, 0x75, 0x8e, 0x66, 0xcf, 0x11]) {
        Magic::Known("WMA")
    } else if starts(b"MPCK") || starts(b"MP+") {
        Magic::Known("Musepack")
    } else if starts(b"TTA1") {
        Magic::Known("TTA")
    } else if starts(b"tBaK") {
        Magic::Known("TAK")
    } else if starts(b"OFR ") {
        Magic::Known("OptimFROG")
    } else if starts(b"ajkg") {
        Magic::Known("Shorten")
    } else if starts(b"#!AMR") {
        Magic::Known("AMR")
    } else if starts(b".ra\xfd") || starts(b".RMF") {
        Magic::Known("RealAudio")
    } else if starts(&[0x0b, 0x77]) {
        Magic::Known("AC-3")
    } else if starts(&[0x7f, 0xfe, 0x80, 0x01]) {
        Magic::Known("DTS")
    } else {
        Magic::Other
    })
}

/// Lê até encher `buf` ou acabar a fonte.
fn read_up_to(src: &mut impl Read, buf: &mut [u8]) -> std::io::Result<usize> {
    let mut n = 0;
    while n < buf.len() {
        match src.read(&mut buf[n..]) {
            Ok(0) => break,
            Ok(k) => n += k,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted && n > 0 => continue,
            Err(e) => return Err(e),
        }
    }
    Ok(n)
}

/// Codecs do symphonia e o Opus da libopus.
fn codecs() -> &'static CodecRegistry {
    static REGISTRY: OnceLock<CodecRegistry> = OnceLock::new();
    REGISTRY.get_or_init(|| {
        let mut r = CodecRegistry::new();
        symphonia::default::register_enabled_codecs(&mut r);
        r.register_audio_decoder::<symphonia_adapter_libopus::OpusDecoder>();
        r
    })
}

/// Erro do symphonia ao abrir: formato ou codec que ele não lê (ou que ele
/// acha que é outro e não consegue ler) vira [`Unsupported`]; erro de leitura
/// continua erro de leitura.
fn open_error(e: SymError, what: &str) -> anyhow::Error {
    match e {
        SymError::Unsupported(detail) | SymError::DecodeError(detail) => unsupported(format!("{what} ({detail})")),
        e => anyhow::Error::from(e).context(what.to_string()),
    }
}

fn open_symphonia(source: Box<dyn MediaSource>, ext_hint: Option<&str>, mime_hint: Option<&str>) -> Result<Decoder> {
    let mss = MediaSourceStream::new(source, MediaSourceStreamOptions::default());
    let mut hint = Hint::new();
    if let Some(ext) = ext_hint {
        hint.with_extension(ext);
    }
    if let Some(mime) = mime_hint {
        hint.mime_type(mime);
    }
    let format = symphonia::default::get_probe()
        .probe(&hint, mss, FormatOptions::default(), MetadataOptions::default())
        .map_err(|e| open_error(e, "formato não reconhecido"))?;

    let track = format
        .default_track(TrackType::Audio)
        .or_else(|| format.first_track_known_codec(TrackType::Audio))
        .ok_or_else(|| unsupported("nenhuma faixa de áudio que o player leia"))?;
    let mut params = track
        .codec_params
        .as_ref()
        .and_then(|p| p.audio())
        .ok_or_else(|| unsupported("faixa sem parâmetros de áudio"))?
        .clone();
    let track_id = track.id;
    let time_base = track.time_base;
    let total_frames = track.num_frames;
    if params.codec == CODEC_ID_OPUS {
        fix_mp4_opus_head(&mut params);
    }

    let decoder = codecs()
        .make_audio_decoder(&params, &AudioDecoderOptions::default())
        .map_err(|e| open_error(e, "codec não suportado"))?;
    let codec = decoder.codec_info().short_name.to_string();
    let sample_rate = params.sample_rate.ok_or_else(|| unsupported("taxa de amostragem desconhecida"))?;
    let channels = params.channels.as_ref().map(|c| c.count()).unwrap_or(2).max(1);

    let preroll = preroll_ms(&codec);
    let mut backend =
        Symphonia { format, decoder, track_id, time_base, sample_rate, channels, preroll, origin: 0, pending: VecDeque::new() };
    // Os dois primeiros blocos com som saem já. Um arquivo que não decodifica
    // falha aqui, e não no meio da música. E é deles que sai a origem (ver
    // `origin`): o segundo bloco começa no relógio do contêiner onde a saída
    // já tem o primeiro inteiro.
    let mut first = Vec::new();
    if let Some((frames, _)) = backend.read_packet(&mut first)? {
        backend.pending.push_back(first);
        let mut second = Vec::new();
        if let Some((_, at)) = backend.read_packet(&mut second)? {
            backend.origin = at - frames as i64;
            backend.pending.push_back(second);
        }
    }
    Decoder::new(Box::new(backend), sample_rate, total_frames, params.bits_per_sample, codec)
}

/// Os codecs com perdas dependem do que veio antes: o MP3 guarda bits no
/// quadro anterior, o AAC e o Vorbis somam a metade do bloco anterior, e o
/// Opus só converge depois de alguns pacotes (a especificação pede 80 ms; com
/// 400 ms a diferença para a decodificação contínua fica abaixo de −100 dB).
/// Sem isso, o primeiro pedaço depois de um seek sai errado (um estalo).
fn preroll_ms(codec: &str) -> u64 {
    match codec {
        "opus" => 400,
        "mp1" | "mp2" | "mp3" | "aac" | "vorbis" => 100,
        _ => 0,
    }
}

/// O leitor de MP4 do symphonia monta o cabeçalho `OpusHead` copiando a caixa
/// `dOps` sem converter: fica a versão 0 dela e os números em big-endian (no
/// `OpusHead` são little-endian). O pre-skip de 312 virava 14337, e o
/// decodificador jogava fora o primeiro pacote inteiro.
fn fix_mp4_opus_head(params: &mut AudioCodecParameters) {
    let Some(e) = params.extra_data.as_deref() else { return };
    if e.len() < 19 || &e[..8] != b"OpusHead" || e[8] != 0 {
        return;
    }
    let mut fixed = e.to_vec();
    fixed[8] = 1;
    fixed[10..12].copy_from_slice(&u16::from_be_bytes([e[10], e[11]]).to_le_bytes());
    fixed[12..16].copy_from_slice(&u32::from_be_bytes([e[12], e[13], e[14], e[15]]).to_le_bytes());
    fixed[16..18].copy_from_slice(&i16::from_be_bytes([e[16], e[17]]).to_le_bytes());
    params.extra_data = Some(fixed.into_boxed_slice());
}

struct Symphonia {
    format: Box<dyn FormatReader + 'static>,
    decoder: Box<dyn AudioDecoder>,
    track_id: u32,
    time_base: Option<TimeBase>,
    sample_rate: u32,
    channels: usize,
    /// Quanto decodificar antes do ponto de um seek (ms), ver [`preroll_ms`].
    preroll: u64,
    /// Onde a saída começa no relógio do contêiner (em frames): o frame N da
    /// saída está no instante N + `origin` do contêiner. Cada contêiner conta
    /// o começo de um jeito (o Ogg inclui o pre-skip do Opus, o MKV desconta,
    /// o decodificador do Vorbis não dá som no primeiro pacote...); medindo
    /// na abertura, o seek cai exatamente onde a decodificação contínua cairia.
    origin: i64,
    /// Blocos já decodificados que ainda não foram entregues.
    pending: VecDeque<Vec<f32>>,
}

/// Timestamp do contêiner em frames (pode ser negativo: em alguns arquivos o
/// começo vem antes do zero).
fn ts_frames(ts: Timestamp, tb: Option<TimeBase>, sample_rate: u32) -> i64 {
    let v = ts.get() as i128;
    match tb {
        Some(tb) => (v * tb.numer.get() as i128 * sample_rate as i128).div_euclid(tb.denom.get() as i128) as i64,
        None => v as i64,
    }
}

impl Symphonia {
    /// Decodifica pacotes até um que dê som. Devolve os frames e o instante
    /// (relógio do contêiner, em frames) do primeiro deles.
    fn read_packet(&mut self, out: &mut Vec<f32>) -> Result<Option<(usize, i64)>> {
        loop {
            let packet = match self.format.next_packet() {
                Ok(Some(p)) => p,
                Ok(None) => return Ok(None),
                Err(SymError::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
                Err(SymError::ResetRequired) => {
                    self.decoder.reset();
                    continue;
                }
                Err(e) => return Err(e.into()),
            };
            if packet.track_id != self.track_id {
                continue;
            }
            let at = ts_frames(packet.pts, self.time_base, self.sample_rate) + packet.trim_start.get() as i64;
            match self.decoder.decode(&packet) {
                Ok(buf) => {
                    let spec_channels = buf.spec().channels().count().max(1);
                    buf.copy_to_vec_interleaved::<f32>(out);
                    if spec_channels != self.channels {
                        self.channels = spec_channels;
                    }
                    let frames = out.len() / self.channels;
                    if frames > 0 {
                        return Ok(Some((frames, at)));
                    }
                }
                // Pacote corrompido: pula e segue.
                Err(SymError::DecodeError(msg)) => log::debug!("pacote inválido ignorado: {msg}"),
                Err(SymError::IoError(e)) if e.kind() != std::io::ErrorKind::Interrupted => {
                    log::debug!("erro de IO no pacote ignorado: {e}")
                }
                Err(SymError::ResetRequired) => self.decoder.reset(),
                Err(e) => return Err(e.into()),
            }
        }
    }
}

impl Backend for Symphonia {
    fn channels(&self) -> usize {
        self.channels
    }

    fn next_chunk(&mut self, out: &mut Vec<f32>) -> Result<Option<usize>> {
        if let Some(chunk) = self.pending.pop_front() {
            *out = chunk;
            return Ok(Some(out.len() / self.channels));
        }
        Ok(self.read_packet(out)?.map(|(frames, _)| frames))
    }

    fn seek(&mut self, position_ms: u64) -> Result<u64> {
        self.pending.clear();
        let target = position_ms as i64 * self.sample_rate as i64 / 1000;
        let mut back = self.preroll;
        loop {
            let from = position_ms.saturating_sub(back);
            self.format
                .seek(SeekMode::Accurate, SeekTo::Time { time: Time::from_millis_u64(from), track_id: Some(self.track_id) })
                .map_err(|e| anyhow!("seek falhou: {e}"))?;
            self.decoder.reset();
            // O primeiro bloco com som diz onde o seek caiu, no relógio da saída.
            let mut buf = Vec::new();
            let Some((mut frames, at)) = self.read_packet(&mut buf)? else { return Ok(target.max(0) as u64) };
            let landed = at - self.origin;
            if landed > target && from > 0 && back < 16_000 {
                // Parou depois do ponto pedido (o MKV só pula para o começo
                // de um bloco): volta mais.
                back = back * 2 + 1000;
                continue;
            }
            if landed >= target {
                self.pending.push_back(buf);
                return Ok(landed.max(0) as u64);
            }
            // Descarta até o ponto pedido.
            let mut skip = (target - landed) as usize;
            loop {
                if skip < frames {
                    buf.drain(..skip * self.channels);
                    self.pending.push_back(buf);
                    return Ok(target as u64);
                }
                skip -= frames;
                match self.read_packet(&mut buf)? {
                    Some((f, _)) => frames = f,
                    None => return Ok(target as u64),
                }
            }
        }
    }
}

/// As partes de um DFF que a biblioteca local usa (tags), lendo o arquivo
/// todo (as tags costumam vir depois do áudio).
pub(crate) fn dff_layout(src: &mut (impl Read + Seek)) -> Result<DffLayout> {
    dsd::dff_layout(src, true)
}

/// Posição em frames de um seek para `position_ms`, limitada ao fim conhecido.
fn frame_at(position_ms: u64, rate: u32, total: Option<u64>) -> u64 {
    let f = (position_ms as u128 * rate as u128 / 1000) as u64;
    total.map_or(f, |t| f.min(t))
}
