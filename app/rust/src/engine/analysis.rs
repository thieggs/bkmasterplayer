//! Análise de faixa para o AutoMix: batidas, downbeats, BPM, tom (Camelot),
//! loudness, energia por compasso e estrutura (intro/outro).
//!
//! - Batidas/downbeats: rede "Beat This!" (ISMIR 2024) via crate `beat-this`
//!   (pesos MIT, modelo pequeno de ~10 MB, rodando em Rust puro).
//! - Tom: cromagrama + perfis de Krumhansl-Kessler.
//! - Loudness: EBU R128 (`ebur128`).
//! - Estrutura: energia RMS por compasso; intro = compassos iniciais abaixo da
//!   energia típica; outro = compassos finais abaixo dela.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{anyhow, Context, Result};
use beat_this::{BeatThis, RtenRuntime, Runtime};
use parking_lot::Mutex;
use rustfft::{num_complex::Complex, FftPlanner};
use serde::{Deserialize, Serialize};
use symphonia::core::io::MediaSource;

use super::decoder::Decoder;
use crate::stream::fnv1a64;

/// Muda quando o algoritmo muda (invalida o cache).
pub const ANALYSIS_VERSION: u32 = 3;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackAnalysis {
    pub version: u32,
    pub duration: f64,
    pub bpm: Option<f64>,
    /// 0..1 (regularidade das batidas).
    pub bpm_confidence: f32,
    pub beats: Vec<f64>,
    pub downbeats: Vec<f64>,
    pub beats_per_bar: u32,
    pub key: Option<String>,
    pub camelot: Option<String>,
    pub key_confidence: f32,
    pub lufs: Option<f64>,
    pub peak: f32,
    /// Grades de batida ajustadas (uma por região analisada: início e fim).
    pub grids: Vec<BeatGrid>,
    /// Energia (dB) por compasso da grade, na faixa média (200 Hz–2 kHz):
    /// separa "só bateria" (intro/outro) de "música cheia".
    pub bar_energy: Vec<f32>,
    /// Início de cada compasso da grade (s), alinhado com `bar_energy`.
    pub bars: Vec<f64>,
    pub first_sound: f64,
    pub last_sound: f64,
    /// Fim da intro / início da outro (segundos, em downbeats), se detectados.
    pub intro_end: Option<f64>,
    pub outro_start: Option<f64>,
}

/// Grade regular de batidas: batida k em `t0 + k·period`; compassos começam
/// nas batidas `phase + m·beats_per_bar`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BeatGrid {
    pub start: f64,
    pub end: f64,
    pub t0: f64,
    pub period: f64,
    pub phase: u32,
    pub beats_per_bar: u32,
    /// Erro RMS das batidas detectadas em relação à grade (s).
    pub residual: f64,
    /// Fração das batidas (com ataque no áudio) que caem na grade (0..1).
    pub coverage: f64,
    /// Quantas batidas sustentam a grade.
    #[serde(default)]
    pub inliers: u32,
    /// Onde os ataques do áudio caem em relação à grade, a cada 8 compassos:
    /// (centro da janela em s, deslocamento em s). Só janelas com bateria.
    #[serde(default)]
    pub windows: Vec<(f64, f64)>,
    /// Fração dessas janelas com os ataques a ±10 ms da grade.
    #[serde(default)]
    pub lock: f64,
    /// Confirmada pela grade da outra ponta da faixa (mesmo tempo e fase).
    #[serde(default)]
    pub validated: bool,
}

impl BeatGrid {
    pub fn bpm(&self) -> f64 {
        60.0 / self.period
    }

    pub fn bar_seconds(&self) -> f64 {
        self.period * self.beats_per_bar as f64
    }

    pub fn beat_time(&self, k: f64) -> f64 {
        self.t0 + k * self.period
    }

    /// Primeiro início de compasso em ou depois de `t`.
    pub fn bar_at_or_after(&self, t: f64) -> f64 {
        let bpb = self.beats_per_bar as f64;
        let m = ((t - self.t0) / self.period - self.phase as f64) / bpb;
        self.beat_time(self.phase as f64 + m.ceil() * bpb)
    }

    /// Início de compasso mais próximo de `t`.
    pub fn nearest_bar(&self, t: f64) -> f64 {
        let bpb = self.beats_per_bar as f64;
        let m = ((t - self.t0) / self.period - self.phase as f64) / bpb;
        self.beat_time(self.phase as f64 + m.round() * bpb)
    }

    /// Grade confiável para sincronizar: os ataques do áudio caem nela
    /// (janelas travadas) e a rede concorda — batidas no trilho (erro RMS
    /// < 12 ms), quase todas nele e em número suficiente, ou a grade foi
    /// confirmada pela outra ponta da faixa.
    pub fn is_steady(&self) -> bool {
        let audio = self.windows.len() >= 3 && self.lock >= 0.6;
        let network = self.residual < 0.012 && self.coverage > 0.6 && self.inliers >= 32;
        let validated = self.validated && self.residual < 0.012 && self.inliers >= 8;
        audio && (network || validated)
    }

    /// Correção local da fase (s) no trecho [a, b]: mediana das janelas ali
    /// (onde os ataques caem de fato). None se não há bateria por perto.
    pub fn offset_near(&self, a: f64, b: f64) -> Option<f64> {
        let mut v: Vec<f64> = self.windows.iter().filter(|(c, _)| *c >= a - 8.0 && *c <= b + 8.0).map(|(_, d)| *d).collect();
        if v.is_empty() {
            return None;
        }
        v.sort_by(|x, y| x.partial_cmp(y).unwrap());
        Some(v[v.len() / 2])
    }

    /// Confiança 0..1 (para mostrar): batidas no trilho (erro ≤ 3 ms) e
    /// ataques do áudio travados na grade; metade se nada confirma a grade.
    pub fn confidence(&self) -> f64 {
        let r = ((0.012 - self.residual) / 0.009).clamp(0.0, 1.0);
        let confirmed = self.validated || self.coverage > 0.6;
        (r * self.lock).sqrt() * if confirmed { 1.0 } else { 0.5 }
    }
}

impl TrackAnalysis {
    /// Tem batida para sincronizar em algum trecho (o planejador ainda confere
    /// as grades exatas do fim de A e do começo de B).
    pub fn has_beat(&self) -> bool {
        self.bpm.is_some() && self.grids.iter().any(|g| g.is_steady())
    }

    /// Grade que cobre o instante `t`. Não estende grades de longe: minutos
    /// de extrapolação acumulam dezenas de ms de erro de fase.
    pub fn grid_at(&self, t: f64) -> Option<&BeatGrid> {
        self.grids.iter().find(|g| t >= g.start - 2.0 && t <= g.end + 2.0)
    }

    /// Duração média de um compasso (s).
    pub fn bar_seconds(&self) -> Option<f64> {
        self.bpm.map(|b| 60.0 / b * self.beats_per_bar as f64)
    }
}

/// Modelo de batidas: pequeno (~10 MB, rápido, vem com o app) ou completo
/// (~83 MB, mais preciso; baixado sob demanda para máquinas mais fortes).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BeatModel {
    Small,
    Full,
}

impl BeatModel {
    pub fn file_name(self) -> &'static str {
        match self {
            BeatModel::Small => "beat_this_small.onnx",
            BeatModel::Full => "beat_this.onnx",
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            BeatModel::Small => "small",
            BeatModel::Full => "full",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "small" => Some(BeatModel::Small),
            "full" => Some(BeatModel::Full),
            _ => None,
        }
    }
}

/// Endereço do modelo completo (release do beat-this-rs, pesos MIT).
pub const FULL_MODEL_URL: &str = "https://github.com/danigb/beat-this-rs/releases/download/model-large/beat_this.onnx";
pub const FULL_MODEL_SHA256: &str = "https://github.com/danigb/beat-this-rs/releases/download/model-large/beat_this.onnx.sha256";

/// Potência do aparelho, para escolher o modelo automaticamente.
#[derive(Debug, Clone)]
pub struct DeviceProfile {
    pub cores: usize,
    pub avx2: bool,
    pub recommended: BeatModel,
}

pub fn device_profile() -> DeviceProfile {
    let cores = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(2);
    #[cfg(target_arch = "x86_64")]
    let avx2 = std::arch::is_x86_feature_detected!("avx2") && std::arch::is_x86_feature_detected!("fma");
    #[cfg(not(target_arch = "x86_64"))]
    let avx2 = false;
    // Desktop x86 moderno com núcleos de sobra aguenta o completo; o resto usa o pequeno.
    let recommended = if avx2 && cores >= 8 && cfg!(not(any(target_os = "android", target_os = "ios"))) {
        BeatModel::Full
    } else {
        BeatModel::Small
    };
    DeviceProfile { cores, avx2, recommended }
}

pub struct Analyzer {
    model_dir: PathBuf,
    cache_dir: PathBuf,
    model: Mutex<BeatModel>,
    tracker: Mutex<Option<(BeatModel, BeatThis<<RtenRuntime as Runtime>::Model>)>>,
}

impl Analyzer {
    pub fn new(model_dir: impl Into<PathBuf>, cache_dir: impl Into<PathBuf>) -> Arc<Self> {
        let cache_dir = cache_dir.into();
        let _ = std::fs::create_dir_all(&cache_dir);
        Arc::new(Self {
            model_dir: model_dir.into(),
            cache_dir,
            model: Mutex::new(BeatModel::Small),
            tracker: Mutex::new(None),
        })
    }

    pub fn model_dir(&self) -> &Path {
        &self.model_dir
    }

    pub fn model_available(&self, m: BeatModel) -> bool {
        self.model_dir.join(m.file_name()).exists() && self.model_dir.join("mel_spectrogram.onnx").exists()
    }

    pub fn models_available(&self) -> bool {
        self.model_available(BeatModel::Small)
    }

    /// Escolhe o modelo (cai no pequeno se o completo não foi baixado).
    pub fn set_model(&self, m: BeatModel) -> BeatModel {
        let chosen = if self.model_available(m) { m } else { BeatModel::Small };
        *self.model.lock() = chosen;
        chosen
    }

    pub fn model(&self) -> BeatModel {
        *self.model.lock()
    }

    fn cache_path(&self, key: &str) -> PathBuf {
        let model = self.model().name();
        self.cache_dir.join(format!("{:016x}.json", fnv1a64(&format!("{key}|{model}"))))
    }

    pub fn cached(&self, key: &str) -> Option<TrackAnalysis> {
        let raw = std::fs::read(self.cache_path(key)).ok()?;
        let a: TrackAnalysis = serde_json::from_slice(&raw).ok()?;
        (a.version == ANALYSIS_VERSION).then_some(a)
    }

    pub fn store(&self, key: &str, a: &TrackAnalysis) {
        if let Ok(json) = serde_json::to_vec(a) {
            let path = self.cache_path(key);
            let tmp = path.with_extension("tmp");
            if std::fs::write(&tmp, json).is_ok() {
                let _ = std::fs::rename(tmp, path);
            }
        }
    }

    /// Analisa (ou devolve do cache). Bloqueia: rode fora da thread de áudio/UI.
    pub fn analyze(&self, key: &str, source: Box<dyn MediaSource>, ext: Option<&str>) -> Result<TrackAnalysis> {
        if let Some(a) = self.cached(key) {
            return Ok(a);
        }
        let a = self.analyze_uncached(source, ext)?;
        self.store(key, &a);
        Ok(a)
    }

    pub fn analyze_uncached(&self, source: Box<dyn MediaSource>, ext: Option<&str>) -> Result<TrackAnalysis> {
        let audio = decode_all(source, ext)?;
        let model = self.model();
        let mut guard = self.tracker.lock();
        if guard.as_ref().is_none_or(|(m, _)| *m != model) {
            let t = BeatThis::new(
                &RtenRuntime,
                &self.model_dir.join("mel_spectrogram.onnx"),
                &self.model_dir.join(model.file_name()),
            )
            .context("carregando modelos de batida")?;
            *guard = Some((model, t));
        }
        let tracker = &mut guard.as_mut().unwrap().1;
        // A rede é o passo caro: roda só no começo e no fim da faixa, onde as
        // transições acontecem (em faixas curtas, na faixa inteira).
        let mut regions = Vec::new();
        for (a, b) in analysis_regions(audio.mono.len() as f64 / audio.rate as f64) {
            let i0 = (a * audio.rate as f64) as usize;
            let i1 = ((b * audio.rate as f64) as usize).min(audio.mono.len());
            let r = tracker
                .analyze_audio(&audio.mono[i0..i1], audio.rate)
                .map_err(|e| anyhow!("beat tracking: {e}"))?;
            regions.push(BeatRegion {
                start: a,
                end: b,
                beats: r.beats.iter().map(|t| *t as f64 + a).collect(),
                downbeats: r.downbeats.iter().map(|t| *t as f64 + a).collect(),
            });
        }
        drop(guard);
        Ok(build_analysis(&audio, &regions))
    }
}

pub struct DecodedAudio {
    pub rate: u32,
    pub mono: Vec<f32>,
    pub stereo: Vec<f32>,
}

pub fn decode_all(source: Box<dyn MediaSource>, ext: Option<&str>) -> Result<DecodedAudio> {
    let mut dec = Decoder::open(source, ext, None)?;
    let rate = dec.sample_rate;
    let mut buf = Vec::new();
    let mut mono = Vec::new();
    let mut stereo = Vec::new();
    while dec.next_chunk(&mut buf)?.is_some() {
        let ch = dec.channels;
        for f in buf.chunks_exact(ch) {
            let (l, r) = if ch == 1 { (f[0], f[0]) } else { (f[0], f[1]) };
            mono.push((l + r) * 0.5);
            stereo.push(l);
            stereo.push(r);
        }
    }
    if mono.is_empty() {
        return Err(anyhow!("áudio vazio"));
    }
    Ok(DecodedAudio { rate, mono, stereo })
}

/// Regiões onde rodar a rede de batidas: começo e fim (ou tudo, se curta).
pub fn analysis_regions(duration: f64) -> Vec<(f64, f64)> {
    const HEAD: f64 = 75.0;
    const TAIL: f64 = 105.0;
    if duration <= HEAD + TAIL + 20.0 {
        vec![(0.0, duration)]
    } else {
        vec![(0.0, HEAD), (duration - TAIL, duration)]
    }
}

/// Batidas detectadas numa região da faixa (tempos absolutos, em s).
pub struct BeatRegion {
    pub start: f64,
    pub end: f64,
    pub beats: Vec<f64>,
    pub downbeats: Vec<f64>,
}

/// Monta a análise a partir do áudio e das batidas (separado para testar sem a rede).
pub fn build_analysis(audio: &DecodedAudio, regions: &[BeatRegion]) -> TrackAnalysis {
    let rate = audio.rate as f64;
    let duration = audio.mono.len() as f64 / rate;
    let beats: Vec<f64> = regions.iter().flat_map(|r| r.beats.iter().copied()).collect();
    let downbeats: Vec<f64> = regions.iter().flat_map(|r| r.downbeats.iter().copied()).collect();
    let beats_per_bar = estimate_beats_per_bar(&beats, &downbeats);
    let odf = OnsetEnvelope::new(&audio.mono, audio.rate);
    let mut fitted: Vec<Option<BeatGrid>> = regions.iter().map(|r| fit_grid(r, beats_per_bar, &odf)).collect();
    join_regions(&mut fitted, regions, &odf, &downbeats);
    let mut grids: Vec<BeatGrid> = fitted.into_iter().flatten().collect();
    for g in &mut grids {
        g.windows = local_windows(&odf, g);
        let locked = g.windows.iter().filter(|(_, d)| d.abs() <= 0.010).count();
        g.lock = if g.windows.is_empty() { 0.0 } else { locked as f64 / g.windows.len() as f64 };
    }
    let steady: Vec<&BeatGrid> = grids.iter().filter(|g| g.is_steady()).collect();
    let (bpm, bpm_confidence) = if steady.is_empty() {
        let (b, c) = estimate_bpm(&beats);
        (b, c.min(0.4))
    } else {
        // Média ponderada pela duração das regiões estáveis.
        let w: f64 = steady.iter().map(|g| g.end - g.start).sum();
        let p = steady.iter().map(|g| g.period * (g.end - g.start)).sum::<f64>() / w;
        let conf = steady.iter().map(|g| g.confidence()).sum::<f64>() / steady.len() as f64;
        (Some((60.0 / p * 100.0).round() / 100.0), conf as f32)
    };
    let (key, camelot, key_confidence) = match detect_key(&audio.mono, audio.rate) {
        Some((k, c, conf)) => (Some(k), Some(c), conf),
        None => (None, None, 0.0),
    };
    let lufs = loudness(&audio.stereo, audio.rate);
    let peak = audio.mono.iter().fold(0.0f32, |m, s| m.max(s.abs()));
    let (first_sound, last_sound) = sound_bounds(&audio.mono, audio.rate);
    let bars = bar_starts(&grids, beats_per_bar, duration);
    let bar_energy = bar_energies(&mid_band(&audio.mono, audio.rate), audio.rate, &bars, duration);
    let (intro_end, outro_start) = structure(&bars, &bar_energy);

    TrackAnalysis {
        version: ANALYSIS_VERSION,
        duration,
        bpm,
        bpm_confidence,
        beats,
        downbeats,
        beats_per_bar,
        key,
        camelot,
        key_confidence,
        lufs,
        peak,
        grids,
        bar_energy,
        bars,
        first_sound,
        last_sound,
        intro_end,
        outro_start,
    }
}

fn median(v: &mut [f64]) -> Option<f64> {
    if v.is_empty() {
        return None;
    }
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    Some(v[v.len() / 2])
}

/// BPM pela mediana dos intervalos; confiança = fração de intervalos a ±4% dela.
pub fn estimate_bpm(beats: &[f64]) -> (Option<f64>, f32) {
    if beats.len() < 8 {
        return (None, 0.0);
    }
    let mut iv: Vec<f64> = beats.windows(2).map(|w| w[1] - w[0]).filter(|d| *d > 0.2 && *d < 2.0).collect();
    let Some(med) = median(&mut iv.clone()) else { return (None, 0.0) };
    let close: Vec<f64> = iv.iter().copied().filter(|d| (d / med - 1.0).abs() < 0.04).collect();
    let conf = close.len() as f32 / iv.len().max(1) as f32;
    // Refina com a média dos intervalos "bons" (mais precisa que a mediana).
    let mean = close.iter().sum::<f64>() / close.len().max(1) as f64;
    iv.clear();
    let bpm = 60.0 / mean;
    (Some((bpm * 100.0).round() / 100.0), conf)
}

/// Envelope de ataques (fluxo espectral, passo de 2,5 ms) para refinar a fase.
pub struct OnsetEnvelope {
    hop_s: f64,
    /// Centro do quadro 0 (meia janela), em s.
    offset: f64,
    values: Vec<f32>,
}

impl OnsetEnvelope {
    pub fn new(mono: &[f32], rate: u32) -> Self {
        const N: usize = 1024;
        let hop = (rate as usize / 400).max(32);
        let fft = FftPlanner::<f32>::new().plan_fft_forward(N);
        let window: Vec<f32> = (0..N).map(|i| 0.5 - 0.5 * (2.0 * std::f32::consts::PI * i as f32 / N as f32).cos()).collect();
        let mut prev = vec![0.0f32; N / 2];
        let mut buf = vec![Complex::new(0.0f32, 0.0); N];
        let mut values = Vec::with_capacity(mono.len() / hop + 1);
        let mut pos = 0;
        while pos + N <= mono.len() {
            for i in 0..N {
                buf[i] = Complex::new(mono[pos + i] * window[i], 0.0);
            }
            fft.process(&mut buf);
            let mut flux = 0.0f32;
            for k in 1..N / 2 {
                let m = (1.0 + 100.0 * buf[k].norm()).ln();
                flux += (m - prev[k]).max(0.0);
                prev[k] = m;
            }
            values.push(flux);
            pos += hop;
        }
        Self { hop_s: hop as f64 / rate as f64, offset: (N / 2) as f64 / rate as f64, values }
    }

    /// Valor no instante `t` (o quadro i representa o centro da janela i).
    fn at(&self, t: f64) -> f32 {
        let x = ((t - self.offset) / self.hop_s).max(0.0);
        let i = x.floor() as usize;
        let f = (x - i as f64) as f32;
        let a = self.values.get(i).copied().unwrap_or(0.0);
        let b = self.values.get(i + 1).copied().unwrap_or(0.0);
        a + (b - a) * f
    }
}

/// Encaixa cada batida da rede (quantizada em 20 ms) no pico de ataque do
/// áudio mais próximo (±30 ms). Batidas sem ataque claro (trechos sem bateria)
/// são descartadas: só atrapalhariam a regressão.
fn snap_to_onsets(beats: &[f64], odf: &OnsetEnvelope) -> Vec<f64> {
    let mut out = Vec::with_capacity(beats.len());
    for &t in beats {
        // Pico no ±30 ms, amostrado a cada 1 ms.
        let mut best = (f32::MIN, t);
        for d in -30..=30 {
            let tt = t + d as f64 * 0.001;
            let v = odf.at(tt);
            if v > best.0 {
                best = (v, tt);
            }
        }
        // Referência local: mediana do envelope em ±1 s.
        let mut local: Vec<f32> = (-20..=20).map(|k| odf.at(t + k as f64 * 0.05)).collect();
        local.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let med = local[local.len() / 2];
        if best.0 > 1.3 * med + 1e-6 {
            out.push(best.1);
        }
    }
    out
}

/// Coerência de fase das batidas para um período `p` (0..1) e o t0 correspondente.
/// Batidas no mesmo "trilho" somam; batidas fora de fase (meia batida) subtraem.
fn phase_coherence(beats: &[f64], p: f64) -> (f64, f64) {
    let (mut re, mut im) = (0.0, 0.0);
    for t in beats {
        let a = 2.0 * std::f64::consts::PI * (t / p);
        re += a.cos();
        im += a.sin();
    }
    let r = (re * re + im * im).sqrt() / beats.len() as f64;
    let angle = im.atan2(re);
    (r, (angle / (2.0 * std::f64::consts::PI)).rem_euclid(1.0) * p)
}

/// Ajusta uma grade regular às batidas da rede: acha o período em que o maior
/// número de batidas fica em fase (robusto a batidas extras, faltando ou
/// trechos em que a rede "pulou" meia batida), refina por mínimos quadrados só
/// com as batidas no trilho, ajusta a fase pelo envelope de ataques e escolhe
/// a fase dos compassos por votação dos downbeats.
pub fn fit_grid(region: &BeatRegion, beats_per_bar: u32, odf: &OnsetEnvelope) -> Option<BeatGrid> {
    let snapped = snap_to_onsets(&region.beats, odf);
    // Se o áudio quase não tem ataques claros, usa as batidas da rede mesmo.
    let b: &Vec<f64> = if snapped.len() * 2 >= region.beats.len() { &snapped } else { &region.beats };
    if b.len() < 8 {
        return None;
    }
    let mut iv: Vec<f64> = b.windows(2).map(|w| w[1] - w[0]).filter(|d| *d > 0.25 && *d < 1.5).collect();
    let p0 = median(&mut iv)?;
    // Busca fina do período (±3%) pela coerência de fase.
    let search = |center: f64| -> (f64, f64, f64) {
        let mut best = (0.0, center, 0.0);
        let steps = 1200;
        for i in 0..=steps {
            let p = center * (0.97 + 0.06 * i as f64 / steps as f64);
            let (r, t0) = phase_coherence(b, p);
            if r > best.0 {
                best = (r, p, t0);
            }
        }
        best
    };
    let (mut r_best, mut p, mut t0) = search(p0);
    // O período da maioria da rede vence; meio/dobro só se ele for fraco
    // (ex.: a rede alternando entre tempo e dobro a faixa toda).
    if r_best < 0.5 {
        for cand in [p0 / 2.0, p0 * 2.0] {
            if !(0.25..=1.5).contains(&cand) {
                continue;
            }
            let (r, pc, tc) = search(cand);
            if r > r_best + 0.2 {
                (r_best, p, t0) = (r, pc, tc);
            }
        }
    }
    if r_best < 0.3 {
        return None;
    }
    let lsq = |pts: &[(f64, f64)]| -> Option<(f64, f64)> {
        let n = pts.len() as f64;
        if n < 4.0 {
            return None;
        }
        let (sx, sy) = pts.iter().fold((0.0, 0.0), |(a, c), (x, y)| (a + x, c + y));
        let (mx, my) = (sx / n, sy / n);
        let (mut sxx, mut sxy) = (0.0, 0.0);
        for (x, y) in pts {
            sxx += (x - mx) * (x - mx);
            sxy += (x - mx) * (y - my);
        }
        if sxx == 0.0 {
            return None;
        }
        let slope = sxy / sxx;
        Some((my - slope * mx, slope))
    };
    // Refino com as batidas no trilho (±25 ms), iterando.
    for _ in 0..3 {
        let pts: Vec<(f64, f64)> = b
            .iter()
            .map(|t| (((t - t0) / p).round(), *t))
            .filter(|(k, t)| (t - (t0 + p * k)).abs() < 0.025)
            .collect();
        (t0, p) = lsq(&pts)?;
    }
    // Fase pelos ataques do áudio e BPM redondo, se eles concordarem.
    let (p, t0) = tune_grid(odf, &[(region.start, region.end)], p, t0);
    let phase = vote_phase(&region.downbeats, t0, p, beats_per_bar);
    let (residual, coverage, inliers) = grid_stats(b, t0, p);
    if inliers < 4 {
        return None;
    }
    Some(BeatGrid {
        start: region.start,
        end: region.end,
        t0,
        period: p,
        phase,
        beats_per_bar: beats_per_bar.max(1),
        residual,
        coverage,
        inliers,
        windows: Vec::new(),
        lock: 0.0,
        validated: false,
    })
}

/// Erro RMS, cobertura e nº das batidas (com ataque) que caem na grade (±25 ms).
/// Breakdown sem bateria (a rede continua marcando o pulso) não conta contra.
fn grid_stats(beats: &[f64], t0: f64, p: f64) -> (f64, f64, u32) {
    let pts: Vec<f64> = beats
        .iter()
        .map(|t| t - (t0 + p * ((t - t0) / p).round()))
        .filter(|e| e.abs() < 0.025)
        .collect();
    if pts.is_empty() {
        return (1.0, 0.0, 0);
    }
    let rms = (pts.iter().map(|e| e * e).sum::<f64>() / pts.len() as f64).sqrt();
    (rms, pts.len() as f64 / beats.len().max(1) as f64, pts.len() as u32)
}

/// Fase dos compassos: em que batida (mod bpb) caem os downbeats da rede.
fn vote_phase(downbeats: &[f64], t0: f64, p: f64, bpb: u32) -> u32 {
    let bpb = bpb.max(1);
    let mut votes = vec![0u32; bpb as usize];
    for db in downbeats {
        let idx = ((db - t0) / p).round() as i64;
        votes[idx.rem_euclid(bpb as i64) as usize] += 1;
    }
    votes.iter().enumerate().max_by_key(|(_, v)| **v).map(|(i, _)| i as u32).unwrap_or(0)
}

fn grid_score(odf: &OnsetEnvelope, start: f64, end: f64, p: f64, t0: f64) -> f32 {
    let first = ((start - t0) / p).ceil() as i64;
    let last = ((end - t0) / p).floor() as i64;
    if last <= first {
        return 0.0;
    }
    (first..=last).map(|k| odf.at(t0 + k as f64 * p)).sum::<f32>() / (last - first + 1) as f32
}

/// Afina a grade pelos ataques do áudio nos trechos `spans`: fase (±20 ms) com
/// o período dado e com os BPMs redondos vizinhos (128, 136, 87,5…). Fica com
/// o redondo se ele explica os ataques quase tão bem (99%): música de DAW tem
/// BPM redondo, e isso some com a deriva de centésimos de BPM que se acumula
/// durante a mixagem.
fn tune_grid(odf: &OnsetEnvelope, spans: &[(f64, f64)], p_ref: f64, t0_ref: f64) -> (f64, f64) {
    // Gira em torno da batida do centro dos trechos: variar o período não
    // desloca a fase no meio, só nas pontas.
    let center = (spans[0].0 + spans[spans.len() - 1].1) / 2.0;
    let mid_k = ((center - t0_ref) / p_ref).round();
    let anchor = t0_ref + mid_k * p_ref;
    let score = |p: f64, t0: f64| spans.iter().map(|(s, e)| grid_score(odf, *s, *e, p, t0)).sum::<f32>();
    let phase = |p: f64| -> (f32, f64) {
        let mut best = (f32::MIN, t0_ref);
        for d in -40..=40 {
            let t0 = anchor + d as f64 * 0.0005 - mid_k * p;
            let sc = score(p, t0);
            if sc > best.0 {
                best = (sc, t0);
            }
        }
        best
    };
    let (free, t0_free) = phase(p_ref);
    let bpm = 60.0 / p_ref;
    for cand in [bpm.round(), (bpm * 2.0).round() / 2.0] {
        if (cand - bpm).abs() > 0.15 || cand <= 0.0 {
            continue;
        }
        let (sc, tc) = phase(60.0 / cand);
        if sc >= 0.99 * free {
            return (60.0 / cand, tc);
        }
    }
    (p_ref, t0_free)
}

/// Onde os ataques do áudio caem em relação à grade, em janelas de 8
/// compassos: (centro da janela, deslocamento em s). Só janelas com pico
/// claro (trechos sem bateria ficam de fora).
fn local_windows(odf: &OnsetEnvelope, g: &BeatGrid) -> Vec<(f64, f64)> {
    let win = 8 * g.beats_per_bar.max(1) as i64;
    let first = ((g.start - g.t0) / g.period).ceil() as i64;
    let last = ((g.end - g.t0) / g.period).floor() as i64;
    let mut out = Vec::new();
    let mut k0 = first;
    while k0 + win <= last + 1 {
        let scores: Vec<(f64, f32)> = (-60..=60)
            .map(|i| {
                let d = i as f64 * 0.0005;
                (d, (k0..k0 + win).map(|k| odf.at(g.beat_time(k as f64) + d)).sum::<f32>())
            })
            .collect();
        let best = scores.iter().cloned().fold((0.0, f32::MIN), |m, x| if x.1 > m.1 { x } else { m });
        let mut s: Vec<f32> = scores.iter().map(|x| x.1).collect();
        s.sort_by(|a, b| a.partial_cmp(b).unwrap());
        if best.1 > 1.3 * s[s.len() / 2] {
            out.push((g.beat_time(k0 as f64 + win as f64 / 2.0), best.0));
        }
        k0 += win;
    }
    out
}

/// Faixa de tempo constante (o normal em música eletrônica): as grades do
/// começo e do fim viram uma só, com o tempo tirado da distância entre elas
/// (base longa = BPM preciso), e uma valida a outra. Se só uma região achou
/// grade, estende para a outra e confere nos ataques do áudio.
fn join_regions(fitted: &mut [Option<BeatGrid>], regions: &[BeatRegion], odf: &OnsetEnvelope, downbeats: &[f64]) {
    if fitted.len() != 2 || regions.len() != 2 {
        return;
    }
    match (fitted[0].clone(), fitted[1].clone()) {
        (Some(g1), Some(g2)) => {
            let p = (g1.period + g2.period) / 2.0;
            // Batida de cada grade no meio da sua região; o tempo que liga as
            // duas (base longa) tem de estar a menos de 1/4 de batida do medido.
            let mid = |g: &BeatGrid| g.beat_time((((g.start + g.end) / 2.0 - g.t0) / g.period).round());
            let (t1, t2) = (mid(&g1), mid(&g2));
            let k = ((t2 - t1) / p).round();
            if (g1.period / g2.period - 1.0).abs() > 1e-3 || k < 1.0 || ((t2 - t1) - k * p).abs() > 0.25 * p {
                // Não são a mesma grade. Se uma ponta é boa e a outra fraca
                // (ex.: rede lendo 3/4 do tempo na intro), tenta estender a boa.
                let good = |g: &BeatGrid| g.residual < 0.012 && g.coverage > 0.6 && g.inliers >= 32;
                for (src, dst) in [(0usize, 1usize), (1, 0)] {
                    let (s, d) = if src == 0 { (&g1, &g2) } else { (&g2, &g1) };
                    if good(s) && !good(d) {
                        if let Some(ext) = extend_into(s, &regions[dst], odf) {
                            fitted[dst] = Some(ext);
                            if let Some(g) = &mut fitted[src] {
                                g.validated = true;
                            }
                        }
                        return;
                    }
                }
                return;
            }
            let pj = (t2 - t1) / k;
            let spans = [(g1.start, g1.end), (g2.start, g2.end)];
            let (pc, tc) = tune_grid(odf, &spans, pj, t1);
            let joint: f32 = spans.iter().map(|(s, e)| grid_score(odf, *s, *e, pc, tc)).sum();
            let apart = grid_score(odf, g1.start, g1.end, g1.period, g1.t0) + grid_score(odf, g2.start, g2.end, g2.period, g2.t0);
            if joint < 0.97 * apart {
                return; // uma grade só explica pior: tempo não é constante
            }
            let phase = vote_phase(downbeats, tc, pc, g1.beats_per_bar);
            for (slot, r) in fitted.iter_mut().zip(regions) {
                if let Some(g) = slot {
                    let (residual, coverage, inliers) = grid_stats(&region_beats(r, odf), tc, pc);
                    (g.period, g.t0, g.phase, g.residual, g.coverage, g.inliers, g.validated) =
                        (pc, tc, phase, residual, coverage, inliers, true);
                }
            }
        }
        (Some(g), None) | (None, Some(g)) => {
            let miss = if fitted[0].is_none() { 0 } else { 1 };
            if let Some(ext) = extend_into(&g, &regions[miss], odf) {
                fitted[miss] = Some(ext);
                if let Some(src) = &mut fitted[1 - miss] {
                    src.validated = true;
                }
            }
        }
        _ => {}
    }
}

/// Estende a grade `g` para a região `r` (mesmo tempo, fase afinada ±20 ms)
/// se os ataques do áudio ali confirmarem: 4+ janelas com bateria e 70%
/// delas a ±10 ms da grade.
fn extend_into(g: &BeatGrid, r: &BeatRegion, odf: &OnsetEnvelope) -> Option<BeatGrid> {
    let (pc, tc) = tune_grid(odf, &[(r.start, r.end)], g.period, g.t0);
    let mut ext = BeatGrid { start: r.start, end: r.end, t0: tc, period: pc, validated: true, ..g.clone() };
    let w = local_windows(odf, &ext);
    let locked = w.iter().filter(|(_, d)| d.abs() <= 0.010).count();
    if w.len() < 4 || (locked as f64) < 0.7 * w.len() as f64 {
        return None;
    }
    let (residual, coverage, inliers) = grid_stats(&region_beats(r, odf), tc, pc);
    (ext.residual, ext.coverage, ext.inliers) = (residual, coverage, inliers);
    Some(ext)
}

/// Batidas da rede na região encaixadas nos ataques (ou as brutas, se o
/// áudio quase não tem ataques claros).
fn region_beats(r: &BeatRegion, odf: &OnsetEnvelope) -> Vec<f64> {
    let snapped = snap_to_onsets(&r.beats, odf);
    if snapped.len() * 2 >= r.beats.len() {
        snapped
    } else {
        r.beats.clone()
    }
}

/// Inícios de compasso na faixa toda, usando a grade de cada região (e
/// interpolando entre elas, onde a rede não rodou).
fn bar_starts(grids: &[BeatGrid], bpb: u32, duration: f64) -> Vec<f64> {
    let Some(g0) = grids.first() else { return Vec::new() };
    let mut bars = Vec::new();
    let mut t = g0.bar_at_or_after(0.0);
    if t - g0.bar_seconds() >= -0.05 {
        t -= g0.bar_seconds();
    }
    let _ = bpb;
    while t < duration {
        if t >= -0.05 {
            bars.push(t.max(0.0));
        }
        let g = grids
            .iter()
            .find(|g| t >= g.start && t < g.end)
            .or_else(|| grids.iter().find(|g| g.start > t))
            .unwrap_or(grids.last().unwrap());
        // Ao entrar numa nova grade, realinha no compasso dela.
        let next = t + g.bar_seconds();
        t = if g.start > t || next > g.end { g.nearest_bar(next).max(t + g.bar_seconds() * 0.5) } else { next };
    }
    bars
}

/// Banda média (200 Hz–2 kHz) com dois biquads (RBJ).
fn mid_band(mono: &[f32], rate: u32) -> Vec<f32> {
    let mut hp = Biquad::highpass(200.0, rate as f32);
    let mut lp = Biquad::lowpass(2000.0, rate as f32);
    mono.iter().map(|x| lp.run(hp.run(*x))).collect()
}

struct Biquad {
    b0: f32,
    b1: f32,
    b2: f32,
    a1: f32,
    a2: f32,
    z1: f32,
    z2: f32,
}

impl Biquad {
    fn new(b0: f32, b1: f32, b2: f32, a0: f32, a1: f32, a2: f32) -> Self {
        Self { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0, z1: 0.0, z2: 0.0 }
    }
    fn lowpass(f: f32, rate: f32) -> Self {
        let w = 2.0 * std::f32::consts::PI * f / rate;
        let (s, c) = w.sin_cos();
        let alpha = s / (2.0 * std::f32::consts::FRAC_1_SQRT_2);
        Self::new((1.0 - c) / 2.0, 1.0 - c, (1.0 - c) / 2.0, 1.0 + alpha, -2.0 * c, 1.0 - alpha)
    }
    fn highpass(f: f32, rate: f32) -> Self {
        let w = 2.0 * std::f32::consts::PI * f / rate;
        let (s, c) = w.sin_cos();
        let alpha = s / (2.0 * std::f32::consts::FRAC_1_SQRT_2);
        Self::new((1.0 + c) / 2.0, -(1.0 + c), (1.0 + c) / 2.0, 1.0 + alpha, -2.0 * c, 1.0 - alpha)
    }
    #[inline]
    fn run(&mut self, x: f32) -> f32 {
        let y = self.b0 * x + self.z1;
        self.z1 = self.b1 * x - self.a1 * y + self.z2;
        self.z2 = self.b2 * x - self.a2 * y;
        y
    }
}

fn estimate_beats_per_bar(beats: &[f64], downbeats: &[f64]) -> u32 {
    if downbeats.len() < 3 {
        return 4;
    }
    let mut counts: Vec<f64> = downbeats
        .windows(2)
        .map(|w| beats.iter().filter(|b| **b >= w[0] - 1e-3 && **b < w[1] - 1e-3).count() as f64)
        .filter(|c| *c >= 2.0 && *c <= 7.0)
        .collect();
    median(&mut counts).map(|m| m as u32).unwrap_or(4)
}

const KEY_NAMES: [&str; 12] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
const MAJOR_PROFILE: [f64; 12] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
const MINOR_PROFILE: [f64; 12] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17];

/// Código Camelot para (tônica 0..11, menor?).
pub fn camelot(root: usize, minor: bool) -> String {
    // Posição no círculo das quintas a partir de C (maior) / A (menor).
    const MAJOR: [u32; 12] = [8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1];
    const MINOR: [u32; 12] = [5, 12, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10];
    let n = if minor { MINOR[root] } else { MAJOR[root] };
    format!("{n}{}", if minor { 'A' } else { 'B' })
}

/// Compatibilidade harmônica pela roda Camelot: mesmo código, ±1, ou troca A/B.
pub fn camelot_compatible(a: &str, b: &str) -> bool {
    let parse = |s: &str| -> Option<(u32, char)> {
        let (num, letter) = s.split_at(s.len() - 1);
        Some((num.parse().ok()?, letter.chars().next()?))
    };
    let (Some((na, la)), Some((nb, lb))) = (parse(a), parse(b)) else { return false };
    let dist = (na as i32 - nb as i32).rem_euclid(12).min((nb as i32 - na as i32).rem_euclid(12));
    (la == lb && dist <= 1) || (na == nb)
}

fn pearson(a: &[f64; 12], b: &[f64]) -> f64 {
    let ma = a.iter().sum::<f64>() / 12.0;
    let mb = b.iter().sum::<f64>() / 12.0;
    let (mut num, mut da, mut db) = (0.0, 0.0, 0.0);
    for i in 0..12 {
        let x = a[i] - ma;
        let y = b[i] - mb;
        num += x * y;
        da += x * x;
        db += y * y;
    }
    if da == 0.0 || db == 0.0 {
        0.0
    } else {
        num / (da.sqrt() * db.sqrt())
    }
}

/// Tom por cromagrama (Krumhansl-Kessler). Retorna (nome, camelot, confiança).
pub fn detect_key(mono: &[f32], rate: u32) -> Option<(String, String, f32)> {
    const N: usize = 8192;
    const HOP: usize = 4096;
    if mono.len() < N * 4 {
        return None;
    }
    let fft = FftPlanner::<f32>::new().plan_fft_forward(N);
    let window: Vec<f32> = (0..N).map(|i| 0.5 - 0.5 * (2.0 * std::f32::consts::PI * i as f32 / N as f32).cos()).collect();
    // Mapa bin → classe de altura (55 Hz a 5 kHz).
    let bin_pc: Vec<Option<usize>> = (0..N / 2)
        .map(|k| {
            let f = k as f64 * rate as f64 / N as f64;
            if !(55.0..=5000.0).contains(&f) {
                return None;
            }
            let midi = 69.0 + 12.0 * (f / 440.0).log2();
            Some((midi.round() as i64).rem_euclid(12) as usize)
        })
        .collect();
    let mut chroma = [0.0f64; 12];
    let mut buf = vec![Complex::new(0.0f32, 0.0); N];
    let mut pos = 0;
    while pos + N <= mono.len() {
        for i in 0..N {
            buf[i] = Complex::new(mono[pos + i] * window[i], 0.0);
        }
        fft.process(&mut buf);
        let mut frame = [0.0f64; 12];
        for (k, pc) in bin_pc.iter().enumerate() {
            if let Some(pc) = pc {
                frame[*pc] += buf[k].norm() as f64;
            }
        }
        let sum: f64 = frame.iter().sum();
        if sum > 1e-6 {
            for i in 0..12 {
                chroma[i] += frame[i] / sum;
            }
        }
        pos += HOP;
    }
    let mut scores: Vec<(f64, usize, bool)> = Vec::with_capacity(24);
    for root in 0..12 {
        for (minor, profile) in [(false, &MAJOR_PROFILE), (true, &MINOR_PROFILE)] {
            let rotated: Vec<f64> = (0..12).map(|i| profile[(i + 12 - root) % 12]).collect();
            scores.push((pearson(&chroma, &rotated), root, minor));
        }
    }
    scores.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap());
    let (best, root, minor) = scores[0];
    if best <= 0.0 {
        return None;
    }
    let conf = ((best - scores[1].0) * 5.0).clamp(0.0, 1.0) as f32;
    let name = format!("{}{}", KEY_NAMES[root], if minor { "m" } else { "" });
    Some((name, camelot(root, minor), conf))
}

fn loudness(stereo: &[f32], rate: u32) -> Option<f64> {
    let mut m = ebur128::EbuR128::new(2, rate, ebur128::Mode::I).ok()?;
    m.add_frames_f32(stereo).ok()?;
    m.loudness_global().ok().filter(|l| l.is_finite())
}

/// Primeiro e último instante com som (janelas de 10 ms acima de -50 dBFS).
fn sound_bounds(mono: &[f32], rate: u32) -> (f64, f64) {
    let win = (rate as usize / 100).max(1);
    let thr = 10f32.powf(-50.0 / 20.0);
    let rms = |c: &[f32]| (c.iter().map(|s| s * s).sum::<f32>() / c.len() as f32).sqrt();
    let chunks: Vec<f32> = mono.chunks(win).map(rms).collect();
    let first = chunks.iter().position(|r| *r > thr).unwrap_or(0);
    let last = chunks.iter().rposition(|r| *r > thr).unwrap_or(chunks.len().saturating_sub(1));
    (first as f64 * win as f64 / rate as f64, ((last + 1) * win) as f64 / rate as f64)
}

fn bar_energies(mono: &[f32], rate: u32, bars: &[f64], duration: f64) -> Vec<f32> {
    let mut out = Vec::with_capacity(bars.len());
    for (i, &start) in bars.iter().enumerate() {
        let end = bars.get(i + 1).copied().unwrap_or(duration.min(start + 4.0));
        let a = (start * rate as f64) as usize;
        let b = ((end * rate as f64) as usize).min(mono.len());
        if b <= a {
            out.push(-100.0);
            continue;
        }
        let e = mono[a..b].iter().map(|s| (*s as f64) * (*s as f64)).sum::<f64>() / (b - a) as f64;
        out.push((10.0 * e.max(1e-12).log10()) as f32);
    }
    out
}

/// Intro/outro pela energia (banda média) por compasso, alinhados a grupos de 4 compassos.
fn structure(downbeats: &[f64], energy: &[f32]) -> (Option<f64>, Option<f64>) {
    let n = energy.len();
    if n < 16 {
        return (None, None);
    }
    let mut sorted: Vec<f32> = energy.iter().copied().filter(|e| *e > -90.0).collect();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    // Referência: energia típica das partes "cheias" (percentil 75).
    let reference = sorted[sorted.len() * 3 / 4];
    let high = |i: usize| energy[i] >= reference - 4.0;
    let sustained = |i: usize, dir: i32| {
        (0..4).filter(|k| {
            let j = i as i32 + dir * *k as i32;
            j >= 0 && (j as usize) < n && high(j as usize)
        })
        .count()
            >= 3
    };
    let first_high = (0..n).find(|&i| high(i) && sustained(i, 1));
    let last_high = (0..n).rev().find(|&i| high(i) && sustained(i, -1));

    let intro_end = first_high.filter(|&i| i >= 4).map(|i| {
        let snapped = (i + 2) / 4 * 4;
        downbeats[snapped.min(n - 1)]
    });
    let outro_start = last_high.filter(|&i| i + 4 < n).map(|i| {
        let snapped = ((i + 1) + 2) / 4 * 4;
        downbeats[snapped.min(n - 1)]
    });
    (intro_end, outro_start)
}

/// Caminho dos modelos a partir de uma pasta (usado pelo motor e testes).
pub fn default_model_dir(base: &Path) -> PathBuf {
    base.join("models")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn camelot_codes() {
        assert_eq!(camelot(9, true), "8A"); // Am
        assert_eq!(camelot(0, false), "8B"); // C
        assert_eq!(camelot(4, true), "9A"); // Em
        assert_eq!(camelot(7, false), "9B"); // G
        assert_eq!(camelot(5, true), "4A"); // Fm
        assert!(camelot_compatible("8A", "9A"));
        assert!(camelot_compatible("8A", "8B"));
        assert!(camelot_compatible("12A", "1A"));
        assert!(!camelot_compatible("8A", "10A"));
        assert!(!camelot_compatible("8A", "3B"));
    }

    #[test]
    fn bpm_from_regular_beats() {
        let beats: Vec<f64> = (0..100).map(|i| i as f64 * 0.5).collect();
        let (bpm, conf) = estimate_bpm(&beats);
        assert_eq!(bpm, Some(120.0));
        assert!(conf > 0.99);
    }
}
