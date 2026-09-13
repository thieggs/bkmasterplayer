//! API exposta ao Dart pelo flutter_rust_bridge. Só adapta tipos; a lógica
//! fica em `crate::engine`.

use std::path::PathBuf;
use std::sync::{Arc, OnceLock};

use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;

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
}

pub struct TrackSource {
    /// Identificador único da entrada na fila (volta nos eventos).
    pub id: String,
    pub url: String,
    pub cache_key: Option<String>,
    pub format_hint: Option<String>,
    pub duration_ms: Option<u64>,
    /// ReplayGain já resolvido (dB), 0 se não houver.
    pub gain_db: f32,
    pub peak: Option<f32>,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub cover_url: Option<String>,
    pub cover_key: Option<String>,
}

impl From<TrackSource> for engine::TrackRequest {
    fn from(t: TrackSource) -> Self {
        Self {
            id: t.id,
            url: t.url,
            cache_key: t.cache_key,
            format_hint: t.format_hint,
            duration_ms: t.duration_ms,
            gain_db: t.gain_db,
            peak: t.peak,
            title: t.title,
            artist: t.artist,
            album: t.album,
            cover_url: t.cover_url,
            cover_key: t.cover_key,
        }
    }
}

pub enum TransitionMode {
    Gapless,
    Crossfade { ms: u32 },
    Cut,
}

impl From<TransitionMode> for engine::TransitionRequest {
    fn from(t: TransitionMode) -> Self {
        match t {
            TransitionMode::Gapless => Self::Gapless,
            TransitionMode::Crossfade { ms } => Self::Crossfade { ms },
            TransitionMode::Cut => Self::Cut,
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
    SeekTo { position_ms: u64 },
    SeekBy { delta_ms: i64 },
    SetVolume { volume: f64 },
    Raise,
    Quit,
}

pub enum PlayerEvent {
    TrackStarted { id: String },
    TrackEnded { id: String, error: Option<String> },
    Position { id: String, position_ms: u64, duration_ms: Option<u64>, buffered: Option<f32> },
    State { playing: bool, buffering: bool, has_track: bool },
    MediaControl { action: MediaAction },
    DeviceChanged { name: String, sample_rate: u32 },
    Error { message: String },
}

impl From<engine::EngineEvent> for PlayerEvent {
    fn from(e: engine::EngineEvent) -> Self {
        use engine::EngineEvent as E;
        match e {
            E::TrackStarted { id } => Self::TrackStarted { id },
            E::TrackEnded { id, error } => Self::TrackEnded { id, error },
            E::Position { id, position_ms, duration_ms, buffered } => {
                Self::Position { id, position_ms, duration_ms, buffered }
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
                    engine::MediaAction::SeekTo(p) => MediaAction::SeekTo { position_ms: p },
                    engine::MediaAction::SeekBy(d) => MediaAction::SeekBy { delta_ms: d },
                    engine::MediaAction::SetVolume(v) => MediaAction::SetVolume { volume: v },
                    engine::MediaAction::Raise => MediaAction::Raise,
                    engine::MediaAction::Quit => MediaAction::Quit,
                },
            },
            E::DeviceChanged { name, sample_rate } => Self::DeviceChanged { name, sample_rate },
            E::Error { message } => Self::Error { message },
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
    };
    let e = Engine::new(cfg, None)?;
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
pub fn player_play(track: TrackSource, start_ms: u64) -> Result<()> {
    engine()?.play(track.into(), start_ms);
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
pub fn player_seek(position_ms: u64) -> Result<()> {
    engine()?.seek(position_ms);
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

pub fn player_is_cached(cache_key: String) -> Result<bool> {
    Ok(engine()?.is_cached(&cache_key))
}

pub fn player_cache_size() -> Result<u64> {
    Ok(engine()?.cache_size())
}

pub fn player_clear_cache() -> Result<()> {
    engine()?.clear_cache();
    Ok(())
}

pub fn player_set_cache_limit(limit_mb: u32) -> Result<()> {
    engine()?.set_cache_limit(limit_mb as u64 * 1024 * 1024);
    Ok(())
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
