//! API exposta ao Dart pelo flutter_rust_bridge. Só adapta tipos; a lógica
//! fica em `crate::engine`.

use std::path::PathBuf;
use std::sync::{Arc, OnceLock};

use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;

use crate::engine::analysis::{self as an, BeatModel};
use crate::engine::automix::{AutomixSettings, MixStyle};
use crate::engine::{self, Engine, EngineConfig};
use crate::frb_generated::StreamSink;

static ENGINE: OnceLock<Engine> = OnceLock::new();

fn engine() -> Result<&'static Engine> {
    ENGINE.get().ok_or_else(|| anyhow!("motor não inicializado"))
}

pub struct PlayerConfig {
    pub cache_dir: String,
    pub cache_limit_mb: u32,
    pub device_id: Option<String>,
    pub app_id: String,
    pub app_name: String,
    pub media_controls: bool,
    /// Pasta com os modelos de análise (AutoMix). Sem ela, o AutoMix fica desligado.
    pub model_dir: Option<String>,
    /// "small" | "full" (cai no pequeno se o completo não estiver baixado).
    pub analysis_model: String,
}

pub struct TrackSource {
    /// Identificador único da entrada na fila (volta nos eventos).
    pub id: String,
    pub url: String,
    pub cache_key: Option<String>,
    pub format_hint: Option<String>,
    pub duration_ms: Option<i64>,
    /// ReplayGain já resolvido (dB), 0 se não houver.
    pub gain_db: f32,
    pub peak: Option<f32>,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub cover_url: Option<String>,
    pub cover_key: Option<String>,
    /// Identidade da música para o cache de análise (ex.: "conta:song:id").
    pub analysis_key: Option<String>,
}

impl From<TrackSource> for engine::TrackRequest {
    fn from(t: TrackSource) -> Self {
        Self {
            id: t.id,
            url: t.url,
            cache_key: t.cache_key,
            format_hint: t.format_hint,
            duration_ms: t.duration_ms.map(|d| d.max(0) as u64),
            gain_db: t.gain_db,
            peak: t.peak,
            title: t.title,
            artist: t.artist,
            album: t.album,
            cover_url: t.cover_url,
            cover_key: t.cover_key,
            analysis_key: t.analysis_key,
        }
    }
}

pub enum TransitionMode {
    Gapless,
    Crossfade { ms: u32 },
    Cut,
    /// Transição DJ (AutoMix).
    Automix,
    /// AutoMix entre faixas seguidas de um álbum: se o áudio emenda sem
    /// silêncio (ao vivo, mixado, conceitual), toca sem pausa e sem mixar.
    AutomixAlbum,
}

impl From<TransitionMode> for engine::TransitionRequest {
    fn from(t: TransitionMode) -> Self {
        match t {
            TransitionMode::Gapless => Self::Gapless,
            TransitionMode::Crossfade { ms } => Self::Crossfade { ms },
            TransitionMode::Cut => Self::Cut,
            TransitionMode::Automix => Self::Automix,
            TransitionMode::AutomixAlbum => Self::AutomixAlbum,
        }
    }
}

pub enum MediaAction {
    Play,
    Pause,
    Toggle,
    Next,
    Previous,
    Stop,
    SeekTo { position_ms: i64 },
    SeekBy { delta_ms: i64 },
    SetVolume { volume: f64 },
    Raise,
    Quit,
}

pub enum PlayerEvent {
    TrackStarted { id: String },
    TrackEnded { id: String, error: Option<String> },
    Position { id: String, position_ms: i64, duration_ms: Option<i64>, buffered: Option<f32> },
    State { playing: bool, buffering: bool, has_track: bool },
    MediaControl { action: MediaAction },
    DeviceChanged { name: String, sample_rate: u32 },
    Error { message: String },
    Analysis { id: String, bpm: Option<f64>, key: Option<String>, camelot: Option<String>, reliable: bool },
    MixPlanned { from_id: String, to_id: String, summary: String, beatmatched: bool, starts_in_ms: i64 },
    MixStarted { from_id: String, to_id: String, summary: String, style: String, duration_ms: i64 },
}

impl From<engine::EngineEvent> for PlayerEvent {
    fn from(e: engine::EngineEvent) -> Self {
        use engine::EngineEvent as E;
        match e {
            E::TrackStarted { id } => Self::TrackStarted { id },
            E::TrackEnded { id, error } => Self::TrackEnded { id, error },
            E::Position { id, position_ms, duration_ms, buffered } => {
                Self::Position {
                    id,
                    position_ms: position_ms as i64,
                    duration_ms: duration_ms.map(|d| d as i64),
                    buffered,
                }
            }
            E::State { playing, buffering, has_track } => Self::State { playing, buffering, has_track },
            E::MediaControl(a) => Self::MediaControl {
                action: match a {
                    engine::MediaAction::Play => MediaAction::Play,
                    engine::MediaAction::Pause => MediaAction::Pause,
                    engine::MediaAction::Toggle => MediaAction::Toggle,
                    engine::MediaAction::Next => MediaAction::Next,
                    engine::MediaAction::Previous => MediaAction::Previous,
                    engine::MediaAction::Stop => MediaAction::Stop,
                    engine::MediaAction::SeekTo(p) => MediaAction::SeekTo { position_ms: p as i64 },
                    engine::MediaAction::SeekBy(d) => MediaAction::SeekBy { delta_ms: d },
                    engine::MediaAction::SetVolume(v) => MediaAction::SetVolume { volume: v },
                    engine::MediaAction::Raise => MediaAction::Raise,
                    engine::MediaAction::Quit => MediaAction::Quit,
                },
            },
            E::DeviceChanged { name, sample_rate } => Self::DeviceChanged { name, sample_rate },
            E::Error { message } => Self::Error { message },
            E::Analysis { id, bpm, key, camelot, reliable } => Self::Analysis { id, bpm, key, camelot, reliable },
            E::MixPlanned { from_id, to_id, summary, beatmatched, starts_in_ms } => {
                Self::MixPlanned { from_id, to_id, summary, beatmatched, starts_in_ms: starts_in_ms as i64 }
            }
            E::MixStarted { from_id, to_id, summary, style, duration_ms } => {
                Self::MixStarted { from_id, to_id, summary, style, duration_ms: duration_ms as i64 }
            }
        }
    }
}

pub struct OutputDevice {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

/// Inicializa o motor (idempotente: num hot restart só reaproveita).
pub fn player_init(config: PlayerConfig) -> Result<()> {
    if let Some(e) = ENGINE.get() {
        e.stop();
        return Ok(());
    }
    let cfg = EngineConfig {
        cache_dir: PathBuf::from(config.cache_dir),
        cache_limit_bytes: config.cache_limit_mb as u64 * 1024 * 1024,
        device_id: config.device_id,
        app_id: config.app_id,
        app_name: config.app_name,
        media_controls: config.media_controls,
        model_dir: config.model_dir.map(PathBuf::from),
    };
    let e = Engine::new(cfg, None)?;
    e.set_analysis_model(BeatModel::parse(&config.analysis_model).unwrap_or(BeatModel::Small));
    let _ = ENGINE.set(e);
    Ok(())
}

/// Stream de eventos do motor. Chamar de novo substitui o anterior.
pub fn player_events(sink: StreamSink<PlayerEvent>) -> Result<()> {
    let e = engine()?;
    e.set_callback(Some(Arc::new(move |ev| {
        let _ = sink.add(PlayerEvent::from(ev));
    })));
    Ok(())
}

#[frb(sync)]
pub fn player_play(track: TrackSource, start_ms: i64) -> Result<()> {
    engine()?.play(track.into(), start_ms.max(0) as u64);
    Ok(())
}

#[frb(sync)]
pub fn player_set_next(track: Option<TrackSource>, mode: TransitionMode) -> Result<()> {
    engine()?.set_next(track.map(Into::into), mode.into())
}

#[frb(sync)]
pub fn player_pause() -> Result<()> {
    engine()?.pause();
    Ok(())
}

#[frb(sync)]
pub fn player_resume() -> Result<()> {
    engine()?.resume();
    Ok(())
}

#[frb(sync)]
pub fn player_toggle() -> Result<()> {
    engine()?.toggle();
    Ok(())
}

#[frb(sync)]
pub fn player_stop() -> Result<()> {
    engine()?.stop();
    Ok(())
}

#[frb(sync)]
pub fn player_seek(position_ms: i64) -> Result<()> {
    engine()?.seek(position_ms.max(0) as u64);
    Ok(())
}

#[frb(sync)]
pub fn player_seek_by(delta_ms: i64) -> Result<()> {
    engine()?.seek_by(delta_ms);
    Ok(())
}

#[frb(sync)]
pub fn player_set_volume(volume: f32) -> Result<()> {
    engine()?.set_volume(volume);
    Ok(())
}

#[frb(sync)]
pub fn player_set_notifications(enabled: bool) -> Result<()> {
    engine()?.set_notifications(enabled);
    Ok(())
}

pub fn player_prefetch(track: TrackSource) -> Result<()> {
    engine()?.prefetch(&track.into());
    Ok(())
}

pub fn player_output_devices() -> Result<Vec<OutputDevice>> {
    Ok(engine()?
        .devices()?
        .into_iter()
        .map(|d| OutputDevice { id: d.id, name: d.name, is_default: d.is_default })
        .collect())
}

pub fn player_set_output_device(device_id: Option<String>) -> Result<()> {
    engine()?.set_device(device_id)
}

/// Baixa faixas para ouvir offline (uma de cada vez, em segundo plano).
pub fn player_download_offline(tracks: Vec<TrackSource>) -> Result<()> {
    let list = tracks
        .into_iter()
        .filter_map(|t| t.cache_key.map(|k| (k, t.url)))
        .collect();
    engine()?.download_offline(list);
    Ok(())
}

pub fn player_remove_offline(cache_keys: Vec<String>) -> Result<()> {
    engine()?.remove_offline(&cache_keys);
    Ok(())
}

/// Quais dessas faixas já estão no disco.
pub fn player_cached_state(cache_keys: Vec<String>) -> Result<Vec<bool>> {
    let e = engine()?;
    Ok(cache_keys.iter().map(|k| e.is_cached(k)).collect())
}

pub fn player_is_cached(cache_key: String) -> Result<bool> {
    Ok(engine()?.is_cached(&cache_key))
}

pub fn player_cache_size() -> Result<i64> {
    Ok(engine()?.cache_size() as i64)
}

pub fn player_clear_cache() -> Result<()> {
    engine()?.clear_cache();
    Ok(())
}

pub fn player_set_cache_limit(limit_mb: u32) -> Result<()> {
    engine()?.set_cache_limit(limit_mb as u64 * 1024 * 1024);
    Ok(())
}

/// Equalizador de 10 bandas (31 Hz … 16 kHz), ganhos em dB (±12).
#[frb(sync)]
pub fn player_set_eq(enabled: bool, preamp_db: f32, gains_db: Vec<f32>) -> Result<()> {
    let mut g = [0.0f32; 10];
    for (i, v) in gains_db.iter().take(10).enumerate() {
        g[i] = v.clamp(-15.0, 15.0);
    }
    engine()?.set_eq(crate::engine::mixer::EqSettings { enabled, preamp_db: preamp_db.clamp(-15.0, 15.0), gains_db: g });
    Ok(())
}

// ---- AutoMix ----

pub enum AutomixStyle {
    Auto,
    BassSwap,
    Blend,
    Filter,
    Echo,
    Cut,
}

pub struct AutomixConfig {
    pub style: AutomixStyle,
    /// Mudança máxima de velocidade (0.08 = ±8%).
    pub max_tempo_change: f64,
    pub preferred_bars: u32,
    pub min_bars: u32,
    pub max_seconds: f64,
    /// Duração da transição quando não há batida/estrutura clara.
    pub unclear_seconds: f64,
    pub harmonic: bool,
    pub tempo_ramp_bars: u32,
    pub trim_silence: bool,
}

#[frb(sync)]
pub fn player_set_automix(config: AutomixConfig) -> Result<()> {
    let style = match config.style {
        AutomixStyle::Auto => MixStyle::Auto,
        AutomixStyle::BassSwap => MixStyle::BassSwap,
        AutomixStyle::Blend => MixStyle::Blend,
        AutomixStyle::Filter => MixStyle::Filter,
        AutomixStyle::Echo => MixStyle::Echo,
        AutomixStyle::Cut => MixStyle::Cut,
    };
    engine()?.set_automix(AutomixSettings {
        style,
        max_tempo_change: config.max_tempo_change.clamp(0.0, 0.25),
        preferred_bars: config.preferred_bars.clamp(1, 64),
        min_bars: config.min_bars.clamp(1, 32),
        max_seconds: config.max_seconds.clamp(1.0, 120.0),
        unclear_seconds: config.unclear_seconds.clamp(0.5, 60.0),
        harmonic: config.harmonic,
        tempo_ramp_bars: config.tempo_ramp_bars.min(64),
        trim_silence: config.trim_silence,
    });
    Ok(())
}

/// Pré-análise (prioridade baixa) de uma faixa que vem depois na fila.
pub fn player_analyze(track: TrackSource) -> Result<()> {
    engine()?.analyze(&track.into());
    Ok(())
}

pub struct DeviceProfile {
    pub cores: u32,
    pub avx2: bool,
    /// "small" | "full"
    pub recommended_model: String,
    pub full_model_downloaded: bool,
    /// Modelo em uso agora.
    pub active_model: String,
}

pub fn player_device_profile() -> Result<DeviceProfile> {
    let p = an::device_profile();
    let dir = engine()?.analysis_model_dir();
    let full = dir.as_ref().is_some_and(|d| d.join(BeatModel::Full.file_name()).exists());
    Ok(DeviceProfile {
        cores: p.cores as u32,
        avx2: p.avx2,
        recommended_model: p.recommended.name().into(),
        full_model_downloaded: full,
        active_model: engine()?.set_analysis_model_query().name().into(),
    })
}

/// Troca o modelo de análise; retorna o que ficou em uso.
pub fn player_set_analysis_model(model: String) -> Result<String> {
    let m = BeatModel::parse(&model).unwrap_or(BeatModel::Small);
    Ok(engine()?.set_analysis_model(m).name().into())
}

static MODEL_PROGRESS: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);

/// Progresso do download do modelo completo (0–1000).
#[frb(sync)]
pub fn player_model_download_progress() -> u32 {
    MODEL_PROGRESS.load(std::sync::atomic::Ordering::Relaxed)
}

/// Baixa o modelo completo (~83 MB), confere o SHA-256 e ativa.
pub fn player_download_full_model() -> Result<String> {
    use sha2::{Digest, Sha256};
    use std::io::{Read, Write};
    let dir = engine()?.analysis_model_dir().ok_or_else(|| anyhow!("sem pasta de modelos"))?;
    let expected = ureq::get(an::FULL_MODEL_SHA256)
        .call()?
        .body_mut()
        .read_to_string()?
        .split_whitespace()
        .next()
        .unwrap_or_default()
        .to_lowercase();
    let mut resp = ureq::get(an::FULL_MODEL_URL).call()?;
    let total: u64 = resp
        .headers()
        .get("content-length")
        .and_then(|v| v.to_str().ok()?.parse().ok())
        .unwrap_or(83_162_650);
    let part = dir.join("beat_this.onnx.part");
    let mut file = std::fs::File::create(&part)?;
    let mut reader = resp.body_mut().as_reader();
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 256 * 1024];
    let mut done: u64 = 0;
    MODEL_PROGRESS.store(0, std::sync::atomic::Ordering::Relaxed);
    loop {
        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        file.write_all(&buf[..n])?;
        hasher.update(&buf[..n]);
        done += n as u64;
        MODEL_PROGRESS.store(((done * 1000) / total.max(1)).min(1000) as u32, std::sync::atomic::Ordering::Relaxed);
    }
    file.flush()?;
    let got: String = hasher.finalize().iter().map(|b| format!("{b:02x}")).collect();
    if !expected.is_empty() && got != expected {
        let _ = std::fs::remove_file(&part);
        return Err(anyhow!("download corrompido (checksum não confere)"));
    }
    std::fs::rename(&part, dir.join(BeatModel::Full.file_name()))?;
    MODEL_PROGRESS.store(1000, std::sync::atomic::Ordering::Relaxed);
    Ok(engine()?.set_analysis_model(BeatModel::Full).name().into())
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
