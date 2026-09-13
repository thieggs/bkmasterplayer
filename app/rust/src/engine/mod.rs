//! Motor de áudio. Independente do Flutter: recebe comandos e emite eventos
//! por callback. A camada `api` só adapta isso para o flutter_rust_bridge.

pub mod deck;
pub mod decoder;
pub mod mixer;
pub mod output;
pub mod resample;

#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
mod desktop;

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{anyhow, Result};
use parking_lot::Mutex;

use crate::stream::{fnv1a64, Download, DownloadManager};
use deck::{spawn_deck, DeckShared, DeckSource, Handoff, ProducerParams};
use decoder::Decoder;
use mixer::{Mixer, MixerCmd, MixerEvent, MixerShared, Transition};
use output::Output;

pub use output::DeviceInfo;

#[derive(Clone, Debug)]
pub struct EngineConfig {
    pub cache_dir: PathBuf,
    pub cache_limit_bytes: u64,
    pub device_id: Option<String>,
    /// Nome D-Bus (MPRIS) / identificador do app.
    pub app_id: String,
    pub app_name: String,
    pub media_controls: bool,
}

#[derive(Clone, Debug, Default)]
pub struct TrackRequest {
    /// Identificador único da entrada na fila (o Dart decide; volta nos eventos).
    pub id: String,
    pub url: String,
    pub cache_key: Option<String>,
    pub format_hint: Option<String>,
    pub duration_ms: Option<u64>,
    pub gain_db: f32,
    pub peak: Option<f32>,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub cover_url: Option<String>,
    pub cover_key: Option<String>,
}

#[derive(Clone, Copy, Debug)]
pub enum TransitionRequest {
    Gapless,
    Crossfade { ms: u32 },
    Cut,
}

#[derive(Clone, Debug)]
pub enum MediaAction {
    Play,
    Pause,
    Toggle,
    Next,
    Previous,
    Stop,
    SeekTo(u64),
    SeekBy(i64),
    SetVolume(f64),
    Raise,
    Quit,
}

#[derive(Clone, Debug)]
pub enum EngineEvent {
    TrackStarted { id: String },
    TrackEnded { id: String, error: Option<String> },
    Position { id: String, position_ms: u64, duration_ms: Option<u64>, buffered: Option<f32> },
    State { playing: bool, buffering: bool, has_track: bool },
    MediaControl(MediaAction),
    DeviceChanged { name: String, sample_rate: u32 },
    Error { message: String },
}

pub type EventCallback = Arc<dyn Fn(EngineEvent) + Send + Sync>;

struct Track {
    req: TrackRequest,
    deck: Arc<DeckShared>,
    download: Arc<Mutex<Option<Arc<Download>>>>,
}

struct Control {
    cmd: rtrb::Producer<MixerCmd>,
    output: Option<Output>,
    device_id: Option<String>,
    rate: u32,
    next_token: u64,
    next: Option<(TrackRequest, TransitionRequest)>,
    volume: f32,
}

struct Inner {
    ctl: Mutex<Control>,
    mixer: Arc<Mutex<Mixer>>,
    mixer_shared: Arc<MixerShared>,
    downloads: Arc<DownloadManager>,
    tracks: Mutex<HashMap<u64, Track>>,
    callback: Mutex<Option<EventCallback>>,
    stream_failed: Arc<AtomicBool>,
    running: AtomicBool,
    covers_dir: PathBuf,
    notifications: AtomicBool,
    #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
    desktop: Mutex<Option<desktop::Desktop>>,
    /// Faixa atual segundo os eventos do mixer (token).
    current: Mutex<Option<u64>>,
}

pub struct Engine {
    inner: Arc<Inner>,
}

impl Inner {
    fn open_output(self: &Arc<Self>) -> Result<()> {
        let device_id = self.ctl.lock().device_id.clone();
        let out = output::open(device_id.as_deref(), self.mixer.clone(), self.stream_failed.clone())?;
        self.stream_failed.store(false, Ordering::Relaxed);
        let (name, rate) = (out.device_name.clone(), out.sample_rate);
        let old_rate = {
            let mut ctl = self.ctl.lock();
            let old = ctl.rate;
            ctl.rate = rate;
            ctl.output = Some(out);
            old
        };
        self.emit(EngineEvent::DeviceChanged { name, sample_rate: rate });
        if old_rate != rate {
            // As faixas carregadas foram convertidas pra taxa antiga: recarrega.
            self.reload_at_current_position();
        }
        Ok(())
    }

    fn reload_at_current_position(self: &Arc<Self>) {
        let cur = *self.current.lock();
        let Some(token) = cur else { return };
        let (req, pos) = {
            let tracks = self.tracks.lock();
            let Some(t) = tracks.get(&token) else { return };
            (t.req.clone(), t.deck.position_ms())
        };
        self.replace_current(req, pos);
        let next = self.ctl.lock().next.clone();
        if let Some((req, tr)) = next {
            self.set_next(Some(req), tr);
        }
    }

    fn send(&self, cmd: MixerCmd) {
        let mut ctl = self.ctl.lock();
        if ctl.cmd.push(cmd).is_err() {
            log::error!("fila de comandos do mixer cheia");
        }
    }

    fn current_deck(&self) -> Option<Arc<DeckShared>> {
        let cur = (*self.current.lock())?;
        self.tracks.lock().get(&cur).map(|t| t.deck.clone())
    }

    /// Troca a atual por uma nova instância (seek/recarga), levando o vínculo gapless junto.
    fn replace_current(&self, req: TrackRequest, position_ms: u64) {
        let old = self.current_deck();
        let src = self.make_deck(req, position_ms, None);
        if let Some(old) = old {
            old.move_successor_to(&src.shared);
        }
        *self.current.lock() = Some(src.shared.token);
        self.send(MixerCmd::ReplaceCurrent(src));
    }

    fn make_deck(&self, req: TrackRequest, start_ms: u64, handoff: Option<Arc<Handoff>>) -> Box<DeckSource> {
        let (token, rate) = {
            let mut ctl = self.ctl.lock();
            let t = ctl.next_token;
            ctl.next_token += 1;
            (t, ctl.rate)
        };
        let gain = replay_gain(req.gain_db, req.peak);
        let dl_slot: Arc<Mutex<Option<Arc<Download>>>> = Arc::new(Mutex::new(None));
        let slot = dl_slot.clone();
        let downloads = self.downloads.clone();
        let (key, url, ext) = (req.cache_key.clone(), req.url.clone(), req.format_hint.clone());
        let params = ProducerParams {
            device_rate: rate,
            handoff_in: handoff,
            start_ms,
            duration_hint_ms: req.duration_ms,
            ring_seconds: 2.0,
        };
        let src = spawn_deck(token, gain, params, move |cancel| {
            let opened = downloads.open(key.as_deref(), &url, cancel)?;
            *slot.lock() = opened.download.clone();
            Decoder::open(opened.source, ext.as_deref(), opened.content_type.as_deref())
        });
        self.tracks.lock().insert(token, Track { req, deck: src.shared.clone(), download: dl_slot });
        Box::new(src)
    }

    fn set_next(&self, req: Option<TrackRequest>, transition: TransitionRequest) {
        let rate = self.ctl.lock().rate;
        let kind = match transition {
            TransitionRequest::Gapless => Transition::Gapless,
            TransitionRequest::Cut => Transition::Cut,
            TransitionRequest::Crossfade { ms } => Transition::Crossfade { frames: ms as u64 * rate as u64 / 1000 },
        };
        self.ctl.lock().next = req.clone().map(|r| (r, transition));
        // Gapless: a atual entrega o conversor de taxa para a próxima no fim do arquivo.
        let handoff = (req.is_some() && kind == Transition::Gapless).then(Handoff::new);
        match self.current_deck() {
            Some(cur) => cur.set_successor(handoff.clone()),
            None => {
                if let Some(h) = &handoff {
                    h.decline();
                }
            }
        }
        let src = req.map(|r| self.make_deck(r, 0, handoff));
        self.send(MixerCmd::SetNext(src, kind));
    }

    fn emit(&self, ev: EngineEvent) {
        let cb = self.callback.lock().clone();
        if let Some(cb) = cb {
            cb(ev);
        }
    }
}

fn replay_gain(gain_db: f32, peak: Option<f32>) -> f32 {
    let mut g = 10f32.powf(gain_db / 20.0);
    if let Some(p) = peak.filter(|p| *p > 0.0) {
        g = g.min(1.0 / p);
    }
    g.clamp(0.0, 4.0)
}

impl Engine {
    pub fn new(config: EngineConfig, callback: Option<EventCallback>) -> Result<Self> {
        let downloads = Arc::new(DownloadManager::new(config.cache_dir.join("audio"), config.cache_limit_bytes)?);
        let covers_dir = config.cache_dir.join("covers");
        std::fs::create_dir_all(&covers_dir)?;

        let (cmd_tx, cmd_rx) = rtrb::RingBuffer::<MixerCmd>::new(256);
        let (ev_tx, ev_rx) = rtrb::RingBuffer::<MixerEvent>::new(1024);
        let rate = output::device_rate(config.device_id.as_deref()).unwrap_or(48_000);
        let mixer = Mixer::new(rate, cmd_rx, ev_tx);
        let mixer_shared = mixer.shared.clone();
        let mixer = Arc::new(Mutex::new(mixer));
        let stream_failed = Arc::new(AtomicBool::new(false));

        let inner = Arc::new(Inner {
            ctl: Mutex::new(Control {
                cmd: cmd_tx,
                output: None,
                device_id: config.device_id.clone(),
                rate,
                next_token: 1,
                next: None,
                volume: 1.0,
            }),
            mixer,
            mixer_shared,
            downloads,
            tracks: Mutex::new(HashMap::new()),
            callback: Mutex::new(callback),
            stream_failed,
            running: AtomicBool::new(true),
            covers_dir,
            notifications: AtomicBool::new(false),
            #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
            desktop: Mutex::new(None),
            current: Mutex::new(None),
        });

        if let Err(e) = inner.open_output() {
            log::warn!("sem saída de áudio: {e:#}");
            inner.emit(EngineEvent::Error { message: format!("Sem saída de áudio: {e:#}") });
        }

        #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
        if config.media_controls {
            let weak = Arc::downgrade(&inner);
            let cb: EventCallback = Arc::new(move |ev| {
                if let Some(i) = weak.upgrade() {
                    i.emit(ev);
                }
            });
            *inner.desktop.lock() = Some(desktop::Desktop::new(&config.app_id, &config.app_name, cb));
        }

        let loop_inner = inner.clone();
        std::thread::Builder::new()
            .name("engine-events".into())
            .spawn(move || event_loop(loop_inner, ev_rx))?;
        Ok(Engine { inner })
    }

    pub fn set_callback(&self, callback: Option<EventCallback>) {
        *self.inner.callback.lock() = callback;
    }

    // ---- Comandos ----

    pub fn play(&self, req: TrackRequest, start_ms: u64) {
        self.inner.ctl.lock().next = None;
        let src = self.inner.make_deck(req, start_ms, None);
        *self.inner.current.lock() = Some(src.shared.token);
        self.inner.send(MixerCmd::Play(src));
    }

    pub fn set_next(&self, req: Option<TrackRequest>, transition: TransitionRequest) -> Result<()> {
        self.inner.set_next(req, transition);
        Ok(())
    }

    pub fn seek(&self, position_ms: u64) {
        let cur = *self.inner.current.lock();
        let Some(token) = cur else { return };
        let req = match self.inner.tracks.lock().get(&token) {
            Some(t) => t.req.clone(),
            None => return,
        };
        self.inner.replace_current(req, position_ms);
    }

    pub fn seek_by(&self, delta_ms: i64) {
        let pos = self.position_ms().unwrap_or(0) as i64;
        self.seek((pos + delta_ms).max(0) as u64);
    }

    pub fn position_ms(&self) -> Option<u64> {
        let cur = (*self.inner.current.lock())?;
        self.inner.tracks.lock().get(&cur).map(|t| t.deck.position_ms())
    }

    pub fn pause(&self) {
        self.inner.send(MixerCmd::Pause);
    }

    pub fn resume(&self) {
        self.inner.send(MixerCmd::Resume);
    }

    pub fn toggle(&self) {
        if self.inner.mixer_shared.playing.load(Ordering::Relaxed) {
            self.pause();
        } else {
            self.resume();
        }
    }

    pub fn stop(&self) {
        self.inner.ctl.lock().next = None;
        self.inner.send(MixerCmd::Stop);
    }

    pub fn set_volume(&self, volume: f32) {
        self.inner.ctl.lock().volume = volume;
        self.inner.send(MixerCmd::SetVolume(volume));
        #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
        if let Some(d) = self.inner.desktop.lock().as_mut() {
            d.set_volume(volume as f64);
        }
    }

    pub fn set_notifications(&self, enabled: bool) {
        self.inner.notifications.store(enabled, Ordering::Relaxed);
    }

    pub fn devices(&self) -> Result<Vec<DeviceInfo>> {
        output::list_devices()
    }

    pub fn set_device(&self, device_id: Option<String>) -> Result<()> {
        {
            let mut ctl = self.inner.ctl.lock();
            ctl.device_id = device_id;
            ctl.output = None;
        }
        self.inner.open_output()
    }

    pub fn prefetch(&self, req: &TrackRequest) {
        if let Some(key) = &req.cache_key {
            self.inner.downloads.prefetch(key, &req.url);
        }
    }

    pub fn is_cached(&self, key: &str) -> bool {
        self.inner.downloads.is_cached(key)
    }

    pub fn cache_size(&self) -> u64 {
        self.inner.downloads.cache_size()
    }

    pub fn clear_cache(&self) {
        self.inner.downloads.clear();
    }

    pub fn set_cache_limit(&self, bytes: u64) {
        self.inner.downloads.set_limit(bytes);
        self.inner.downloads.evict(&[]);
    }

    pub fn shutdown(&self) {
        self.stop();
        self.inner.running.store(false, Ordering::Relaxed);
        self.inner.ctl.lock().output = None;
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        self.inner.running.store(false, Ordering::Relaxed);
    }
}

// ---- Thread de eventos ----

fn event_loop(inner: Arc<Inner>, mut ev_rx: rtrb::Consumer<MixerEvent>) {
    let mut last_pos = Instant::now();
    let mut last_gc = Instant::now();
    let mut last_reopen = Instant::now() - Duration::from_secs(10);
    let mut last_state = (false, false, false);
    let mut last_mpris_pos = Instant::now();

    while inner.running.load(Ordering::Relaxed) {
        while let Ok(ev) = ev_rx.pop() {
            handle_mixer_event(&inner, ev);
        }

        let has_track = inner.current.lock().is_some();
        let state = (
            inner.mixer_shared.playing.load(Ordering::Relaxed) && has_track,
            inner.mixer_shared.buffering.load(Ordering::Relaxed),
            has_track,
        );
        if state != last_state {
            last_state = state;
            inner.emit(EngineEvent::State { playing: state.0, buffering: state.1, has_track: state.2 });
            update_desktop_playback(&inner);
        }

        if last_pos.elapsed() >= Duration::from_millis(250) {
            last_pos = Instant::now();
            emit_position(&inner);
        }
        // MPRIS: reenvia a posição de vez em quando para relógio/celular não desalinharem.
        if state.0 && last_mpris_pos.elapsed() >= Duration::from_secs(5) {
            last_mpris_pos = Instant::now();
            update_desktop_playback(&inner);
        }

        if inner.stream_failed.load(Ordering::Relaxed) && last_reopen.elapsed() >= Duration::from_secs(2) {
            last_reopen = Instant::now();
            inner.ctl.lock().output = None;
            if let Err(e) = inner.open_output() {
                log::warn!("reabrindo saída de áudio: {e:#}");
            }
        }

        if last_gc.elapsed() >= Duration::from_secs(5) {
            last_gc = Instant::now();
            let keep: Vec<String> = {
                let tracks = inner.tracks.lock();
                tracks.values().filter_map(|t| t.req.cache_key.clone()).collect()
            };
            inner.downloads.gc(&keep);
        }

        std::thread::sleep(Duration::from_millis(15));
    }
}

fn emit_position(inner: &Inner) {
    let cur = *inner.current.lock();
    let Some(token) = cur else { return };
    let info = {
        let tracks = inner.tracks.lock();
        tracks.get(&token).map(|t| {
            let buffered = t.download.lock().as_ref().and_then(|d| d.progress()).or(Some(1.0));
            (
                t.req.id.clone(),
                t.deck.position_ms(),
                t.deck.duration_ms().or(t.req.duration_ms),
                buffered,
            )
        })
    };
    if let Some((id, position_ms, duration_ms, buffered)) = info {
        inner.emit(EngineEvent::Position { id, position_ms, duration_ms, buffered });
    }
}

fn handle_mixer_event(inner: &Arc<Inner>, ev: MixerEvent) {
    match ev {
        MixerEvent::Started(token) => {
            *inner.current.lock() = Some(token);
            let req = inner.tracks.lock().get(&token).map(|t| t.req.clone());
            if let Some(req) = req {
                // A "próxima" virou atual: esquece o pedido de próxima.
                {
                    let mut ctl = inner.ctl.lock();
                    if ctl.next.as_ref().is_some_and(|(n, _)| n.id == req.id) {
                        ctl.next = None;
                    }
                }
                inner.emit(EngineEvent::TrackStarted { id: req.id.clone() });
                on_track_started(inner, token, &req);
            }
            emit_position(inner);
        }
        MixerEvent::Replaced(token) => {
            *inner.current.lock() = Some(token);
            emit_position(inner);
            update_desktop_playback(inner);
        }
        MixerEvent::Finished(token) => {
            let info = inner.tracks.lock().get(&token).map(|t| (t.req.id.clone(), t.deck.error.lock().clone()));
            if let Some((id, error)) = info {
                inner.emit(EngineEvent::TrackEnded { id, error });
            }
            let mut cur = inner.current.lock();
            if *cur == Some(token) {
                *cur = None;
            }
        }
        MixerEvent::Stopped => {
            *inner.current.lock() = None;
        }
        MixerEvent::Buffering(_) => {}
        MixerEvent::Garbage(src) => {
            let token = src.shared.token;
            drop(src);
            inner.tracks.lock().remove(&token);
        }
    }
}

fn cover_path(inner: &Inner, req: &TrackRequest) -> Option<PathBuf> {
    let url = req.cover_url.as_ref()?;
    if !url.contains("://") || url.starts_with("file://") {
        return Some(PathBuf::from(url.trim_start_matches("file://")));
    }
    let key = req.cover_key.clone().unwrap_or_else(|| url.clone());
    Some(inner.covers_dir.join(format!("{:016x}.jpg", fnv1a64(&key))))
}

fn on_track_started(inner: &Arc<Inner>, token: u64, req: &TrackRequest) {
    let path = cover_path(inner, req);
    let have_cover = path.as_ref().is_some_and(|p| p.exists());
    let will_fetch = !have_cover && path.is_some();
    // Se a capa ainda vai ser baixada, a notificação espera por ela (evita mostrar sem imagem).
    publish_track(inner, req, if have_cover { path.clone() } else { None }, !will_fetch);

    // Baixa a capa em segundo plano e atualiza MPRIS/notificação quando chegar.
    if let (false, Some(path), Some(url)) = (have_cover, path, req.cover_url.clone()) {
        let weak = Arc::downgrade(inner);
        let req = req.clone();
        let _ = std::thread::Builder::new().name("cover".into()).spawn(move || {
            let ok = download_cover(&url, &path).is_ok();
            if let Some(inner) = weak.upgrade() {
                if *inner.current.lock() == Some(token) {
                    publish_track(&inner, &req, ok.then_some(path), true);
                }
            }
        });
    }
}

fn download_cover(url: &str, path: &std::path::Path) -> Result<()> {
    let mut resp = ureq::get(url).call()?;
    let bytes = resp.body_mut().with_config().limit(20 * 1024 * 1024).read_to_vec()?;
    if bytes.is_empty() {
        return Err(anyhow!("capa vazia"));
    }
    let tmp = path.with_extension("tmp");
    std::fs::write(&tmp, &bytes)?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

#[allow(unused_variables)]
fn publish_track(inner: &Arc<Inner>, req: &TrackRequest, cover: Option<PathBuf>, notify: bool) {
    #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
    {
        let mut desktop = inner.desktop.lock();
        if let Some(d) = desktop.as_mut() {
            d.set_metadata(&req.title, &req.artist, &req.album, cover.as_deref(), req.duration_ms);
            if notify && inner.notifications.load(Ordering::Relaxed) {
                let body = match (req.artist.is_empty(), req.album.is_empty()) {
                    (false, false) => format!("{} — {}", req.artist, req.album),
                    (false, true) => req.artist.clone(),
                    _ => req.album.clone(),
                };
                d.notify(desktop::NotifyMsg { title: req.title.clone(), body, image: cover });
            }
        }
    }
}

fn update_desktop_playback(inner: &Arc<Inner>) {
    #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
    {
        let cur = *inner.current.lock();
        let pos = cur.and_then(|t| inner.tracks.lock().get(&t).map(|t| t.deck.position_ms()));
        let playing = inner.mixer_shared.playing.load(Ordering::Relaxed);
        if let Some(d) = inner.desktop.lock().as_mut() {
            d.set_playback(playing, cur.is_some(), pos);
        }
    }
}
