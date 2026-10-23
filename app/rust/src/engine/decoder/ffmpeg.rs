//! No computador, o último recurso: o ffmpeg do sistema, se houver um, para
//! arquivos que nenhum decodificador embutido lê (WMA, Musepack, TTA, AC-3,
//! DTS, HE-AAC, AAC 5.1...). Só para arquivo no disco: o ffmpeg lê pelo
//! caminho e devolve PCM f32 por um pipe. O seek reabre o processo na
//! posição pedida.
//!
//! O app não traz o ffmpeg; no Linux ele quase sempre já está instalado (o
//! pacote .deb recomenda). No Windows, vale um `ffmpeg.exe` no PATH.

use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdout, Command, Stdio};
use std::sync::OnceLock;

use anyhow::{anyhow, Context, Result};

use super::{read_up_to, unsupported, Backend, Decoder};

/// Frames por leitura do pipe.
const CHUNK_FRAMES: usize = 4096;
/// Saída com mais canais vira estéreo no próprio ffmpeg (mistura melhor que a nossa).
const MAX_CHANNELS: u32 = 2;
/// Seek até aqui decodifica desde o começo e descarta: exato, e rápido (o
/// ffmpeg decodifica áudio centenas de vezes mais rápido que o tempo real).
/// O `-ss` do ffmpeg cai dezenas de ms fora em WMA, AC-3 e DTS, o que
/// desalinha as batidas do AutoMix; só vale para pulos mais longos.
const EXACT_SEEK_MS: u64 = 90_000;

fn find_in_path(name: &str) -> Option<PathBuf> {
    let exe = if cfg!(windows) { format!("{name}.exe") } else { name.to_string() };
    let mut dirs: Vec<PathBuf> = std::env::var_os("PATH").map(|p| std::env::split_paths(&p).collect()).unwrap_or_default();
    // Apps abertos pelo menu nem sempre herdam o PATH do terminal.
    dirs.extend(["/usr/bin", "/usr/local/bin", "/opt/homebrew/bin", "/opt/local/bin", "/snap/bin"].map(PathBuf::from));
    if let Some(here) = std::env::current_exe().ok().and_then(|p| p.parent().map(Path::to_path_buf)) {
        dirs.insert(0, here);
    }
    dirs.into_iter().map(|d| d.join(&exe)).find(|p| p.is_file())
}

fn ffmpeg_bin() -> Option<&'static Path> {
    static BIN: OnceLock<Option<PathBuf>> = OnceLock::new();
    BIN.get_or_init(|| find_in_path("ffmpeg")).as_deref()
}

fn ffprobe_bin() -> Option<&'static Path> {
    static BIN: OnceLock<Option<PathBuf>> = OnceLock::new();
    BIN.get_or_init(|| {
        // Primeiro o que veio junto com o ffmpeg achado.
        let sibling = ffmpeg_bin().and_then(|f| {
            let p = f.with_file_name(if cfg!(windows) { "ffprobe.exe" } else { "ffprobe" });
            p.is_file().then_some(p)
        });
        sibling.or_else(|| find_in_path("ffprobe"))
    })
    .as_deref()
}

/// Há um ffmpeg para usar?
pub fn available() -> bool {
    ffmpeg_bin().is_some()
}

fn command(bin: &Path) -> Command {
    let mut c = Command::new(bin);
    c.stdin(Stdio::null()).stderr(Stdio::null());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        // Sem piscar uma janela de console a cada música.
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        c.creation_flags(CREATE_NO_WINDOW);
    }
    c
}

/// O caminho como entrada do ffmpeg. O prefixo `file:` impede que um nome
/// começando com `-` vire opção, ou que algo como `concat:` vire protocolo.
fn input(path: &Path) -> OsString {
    let mut s = OsString::from("file:");
    s.push(path.as_os_str());
    s
}

/// O que o ffprobe sabe do arquivo.
#[derive(Debug, Default)]
pub struct Probe {
    pub codec: String,
    pub sample_rate: Option<u32>,
    pub channels: Option<u32>,
    pub bits_per_sample: Option<u32>,
    pub duration_ms: Option<u64>,
    /// Tags do arquivo e da faixa de áudio, chave em minúsculas.
    pub tags: Vec<(String, String)>,
}

/// Pergunta ao ffprobe sobre a primeira faixa de áudio do arquivo.
pub fn probe(path: &Path) -> Option<Probe> {
    let out = command(ffprobe_bin()?)
        .args(["-v", "error", "-select_streams", "a:0", "-show_entries"])
        .arg("stream=codec_name,sample_rate,channels,bits_per_raw_sample,bits_per_sample,duration:stream_tags:format=duration:format_tags")
        .args(["-of", "json"])
        .arg(input(path))
        .stdout(Stdio::piped())
        .output()
        .ok()?;
    let json: serde_json::Value = serde_json::from_slice(&out.stdout).ok()?;
    let stream = json["streams"].get(0)?;
    let num = |v: &serde_json::Value| v.as_str().and_then(|s| s.parse::<f64>().ok()).or_else(|| v.as_f64());
    let mut p = Probe {
        codec: stream["codec_name"].as_str().unwrap_or("?").to_string(),
        sample_rate: num(&stream["sample_rate"]).map(|v| v as u32).filter(|&r| r > 0),
        channels: stream["channels"].as_u64().map(|c| c as u32).filter(|&c| c > 0),
        bits_per_sample: [&stream["bits_per_raw_sample"], &stream["bits_per_sample"]]
            .into_iter()
            .filter_map(|v| num(v).map(|b| b as u32))
            .find(|&b| b > 0),
        duration_ms: num(&stream["duration"]).or_else(|| num(&json["format"]["duration"])).map(|s| (s * 1000.0) as u64),
        tags: Vec::new(),
    };
    for tags in [&json["format"]["tags"], &stream["tags"]] {
        if let Some(map) = tags.as_object() {
            for (k, v) in map {
                if let Some(v) = v.as_str() {
                    p.tags.push((k.to_ascii_lowercase(), v.to_string()));
                }
            }
        }
    }
    Some(p)
}

struct Ffmpeg {
    path: PathBuf,
    rate: u32,
    channels: usize,
    /// Onde o processo começa a decodificar (`-ss`).
    start_ms: u64,
    /// Frames a descartar até a posição pedida.
    skip: u64,
    child: Option<(Child, ChildStdout)>,
    raw: Vec<u8>,
    /// Primeiro bloco, decodificado já na abertura.
    pending: Option<Vec<f32>>,
}

pub fn open(path: &Path) -> Result<Decoder> {
    let p = probe(path).ok_or_else(|| unsupported("nem o ffmpeg reconhece o arquivo"))?;
    if p.channels.is_none() {
        return Err(unsupported(format!("ffmpeg: sem áudio ({})", p.codec)));
    }
    let rate = p.sample_rate.unwrap_or(48_000);
    let channels = p.channels.unwrap_or(2).min(MAX_CHANNELS) as usize;
    let total = p.duration_ms.map(|ms| ms * rate as u64 / 1000);
    let mut ff = Ffmpeg { path: path.to_path_buf(), rate, channels, start_ms: 0, skip: 0, child: None, raw: Vec::new(), pending: None };
    // Decodifica o primeiro bloco já: se o ffmpeg não lê o arquivo, o erro
    // sai aqui (e quem abriu ainda pode tentar outra fonte), não no meio.
    let mut first = Vec::new();
    match ff.read_chunk(&mut first) {
        Ok(Some(_)) => ff.pending = Some(first),
        Ok(None) => return Err(unsupported(format!("ffmpeg: nada decodificado ({})", p.codec))),
        Err(e) => return Err(unsupported(format!("ffmpeg: {e:#}"))),
    }
    Decoder::new(Box::new(ff), rate, total, p.bits_per_sample, format!("ffmpeg:{}", p.codec))
}

impl Ffmpeg {
    fn spawn(&mut self) -> Result<()> {
        self.stop();
        let bin = ffmpeg_bin().ok_or_else(|| anyhow!("ffmpeg sumiu"))?;
        let mut cmd = command(bin);
        cmd.args(["-nostdin", "-hide_banner", "-loglevel", "error"]);
        if self.start_ms > 0 {
            cmd.arg("-ss").arg(format!("{:.3}", self.start_ms as f64 / 1000.0));
        }
        cmd.arg("-i").arg(input(&self.path));
        cmd.args(["-map", "0:a:0", "-vn", "-sn", "-dn", "-f", "f32le", "-acodec", "pcm_f32le"]);
        cmd.arg("-ar").arg(self.rate.to_string()).arg("-ac").arg(self.channels.to_string());
        cmd.arg("pipe:1").stdout(Stdio::piped());
        let mut child = cmd.spawn().context("iniciando o ffmpeg")?;
        let out = child.stdout.take().ok_or_else(|| anyhow!("ffmpeg sem saída"))?;
        self.child = Some((child, out));
        Ok(())
    }

    fn read_chunk(&mut self, out: &mut Vec<f32>) -> Result<Option<usize>> {
        if self.child.is_none() {
            self.spawn()?;
        }
        let Some((child, pipe)) = self.child.as_mut() else { return Ok(None) };
        let frame = 4 * self.channels;
        self.raw.resize(CHUNK_FRAMES * frame, 0);
        let n = read_up_to(pipe, &mut self.raw)? / frame * frame;
        if n == 0 {
            let status = child.wait()?;
            self.child = None;
            if !status.success() {
                return Err(anyhow!("o ffmpeg parou com erro ({status})"));
            }
            return Ok(None);
        }
        out.clear();
        out.extend(self.raw[..n].chunks_exact(4).map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]])));
        Ok(Some(n / frame))
    }

    fn stop(&mut self) {
        if let Some((mut child, _)) = self.child.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

impl Drop for Ffmpeg {
    fn drop(&mut self) {
        self.stop();
    }
}

impl Backend for Ffmpeg {
    fn channels(&self) -> usize {
        self.channels
    }

    fn next_chunk(&mut self, out: &mut Vec<f32>) -> Result<Option<usize>> {
        if let Some(first) = self.pending.take() {
            *out = first;
            return Ok(Some(out.len() / self.channels));
        }
        loop {
            let Some(mut frames) = self.read_chunk(out)? else { return Ok(None) };
            if self.skip > 0 {
                let drop = (self.skip as usize).min(frames);
                out.drain(..drop * self.channels);
                self.skip -= drop as u64;
                frames -= drop;
            }
            if frames > 0 {
                return Ok(Some(frames));
            }
        }
    }

    fn seek(&mut self, position_ms: u64) -> Result<u64> {
        self.pending = None;
        let target = position_ms * self.rate as u64 / 1000;
        (self.start_ms, self.skip) = if position_ms <= EXACT_SEEK_MS { (0, target) } else { (position_ms, 0) };
        self.spawn()?;
        Ok(target)
    }
}
