//! Motor de áudio. Independente do Flutter: recebe comandos e emite eventos
//! por callback. A camada `api` só adapta isso para o flutter_rust_bridge.

pub mod analysis;
pub mod analysis_worker;
pub mod automix;
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
use analysis::{Analyzer, BeatModel, TrackAnalysis};
use analysis_worker::{AnalysisJob, AnalysisWorker};
use automix::{AutomixSettings, MixPlan, TempoMap};
use deck::{spawn_deck, DeckShared, DeckSource, Handoff, ProducerParams};
use decoder::Decoder;
use mixer::{AutomixExec, Mixer, MixerCmd, MixerEvent, MixerShared, Transition};
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
    /// Pasta dos modelos de análise (beat_this_small.onnx, mel_spectrogram.onnx…).
    pub model_dir: Option<PathBuf>,
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
    /// Identidade da música para o cache de análise (independe da qualidade do stream).
    pub analysis_key: Option<String>,
}

#[derive(Clone, Copy, Debug)]
pub enum TransitionRequest {
    Gapless,
    Crossfade { ms: u32 },
    Cut,
    /// Transição DJ: analisa as duas faixas e planeja; enquanto não dá, usa um crossfade.
    Automix,
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
    /// Análise pronta para uma faixa (id = entrada da fila).
    Analysis { id: String, bpm: Option<f64>, key: Option<String>, camelot: Option<String>, reliable: bool },
    /// Transição DJ planejada entre a atual e a próxima.
    MixPlanned { from_id: String, to_id: String, summary: String, beatmatched: bool, starts_in_ms: u64 },
    /// A transição planejada começou agora (dura `duration_ms`).
    MixStarted { from_id: String, to_id: String, summary: String, style: String, duration_ms: u64 },
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
    analysis: Mutex<Option<Arc<AnalysisWorker>>>,
    automix: Mutex<AutomixSettings>,
    /// Plano enviado ao mixer (de, para, plano).
    planned: Mutex<Option<(String, String, MixPlan)>>,
}

pub struct Engine {
    inner: Arc<Inner>,
}

impl Inner {
    fn open_output(self: &Arc<Self>) -> Result<()> {
        let device_id = self.ctl.lock().device_id.clone();
        // Fecha a saída atual antes de abrir a nova (dois streams disputariam o mixer).
        self.ctl.lock().output = None;
        let out = match output::open(device_id.as_deref(), self.mixer.clone(), self.stream_failed.clone()) {
            Ok(o) => o,
            Err(e) => {
                // O servidor de som pode ter reiniciado: tenta com uma conexão nova.
                output::reset_host();
                output::open(device_id.as_deref(), self.mixer.clone(), self.stream_failed.clone()).map_err(|_| e)?
            }
        };
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

    /// Se o app segue a saída padrão e ela mudou (ex.: fone Bluetooth conectou), migra.
    fn follow_default_output(self: &Arc<Self>) {
        let (following, current) = {
            let ctl = self.ctl.lock();
            (ctl.device_id.is_none(), ctl.output.as_ref().and_then(|o| o.device_id.clone()))
        };
        if !following {
            return;
        }
        let Some(default) = output::default_device_id() else { return };
        if current.as_deref() != Some(default.as_str()) {
            if let Err(e) = self.open_output() {
                log::warn!("migrando para a nova saída padrão: {e:#}");
            }
        }
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

    /// Depois de um seek, uma transição DJ planejada pode ter ficado no passado: replaneja.
    fn replan_after_seek(self: &Arc<Self>) {
        let next = self.ctl.lock().next.clone();
        if let Some((req, TransitionRequest::Automix)) = next {
            self.set_next(Some(req), TransitionRequest::Automix);
        }
    }

    fn make_deck(&self, req: TrackRequest, start_ms: u64, handoff: Option<Arc<Handoff>>) -> Box<DeckSource> {
        self.make_deck_tempo(req, start_ms, handoff, None)
    }

    fn make_deck_tempo(
        &self,
        req: TrackRequest,
        start_ms: u64,
        handoff: Option<Arc<Handoff>>,
        tempo: Option<TempoMap>,
    ) -> Box<DeckSource> {
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
            tempo,
        };
        let src = spawn_deck(token, gain, params, move |cancel| {
            let opened = downloads.open(key.as_deref(), &url, cancel)?;
            *slot.lock() = opened.download.clone();
            Decoder::open(opened.source, ext.as_deref(), opened.content_type.as_deref())
        });
        // Posição provisória até a produtora fazer o seek exato (a UI e o
        // planejador do AutoMix já veem a posição certa logo após um seek).
        src.shared.start_frame.store(start_ms * rate as u64 / 1000, std::sync::atomic::Ordering::Relaxed);
        self.tracks.lock().insert(token, Track { req, deck: src.shared.clone(), download: dl_slot });
        Box::new(src)
    }

    fn set_next(self: &Arc<Self>, req: Option<TrackRequest>, transition: TransitionRequest) {
        let rate = self.ctl.lock().rate;
        *self.planned.lock() = None;
        let kind = match transition {
            TransitionRequest::Gapless => Transition::Gapless,
            TransitionRequest::Cut => Transition::Cut,
            TransitionRequest::Crossfade { ms } => Transition::Crossfade { frames: ms as u64 * rate as u64 / 1000 },
            // Reserva enquanto a análise não fica pronta: crossfade da duração "sem estrutura".
            TransitionRequest::Automix => {
                let secs = self.automix.lock().unclear_seconds;
                Transition::Crossfade { frames: (secs * rate as f64) as u64 }
            }
        };
        self.ctl.lock().next = req.clone().map(|r| (r, transition));
        // Gapless: a atual entrega o conversor de taxa para a próxima no fim do arquivo.
        let handoff = (req.is_some() && matches!(kind, Transition::Gapless)).then(Handoff::new);
        match self.current_deck() {
            Some(cur) => cur.set_successor(handoff.clone()),
            None => {
                if let Some(h) = &handoff {
                    h.decline();
                }
            }
        }
        let src = req.clone().map(|r| self.make_deck(r, 0, handoff));
        self.send(MixerCmd::SetNext(src, kind));
        if let (Some(next), TransitionRequest::Automix) = (req, transition) {
            if let Some(cur) = self.current_request() {
                self.request_analysis(&cur, 0);
            }
            self.request_analysis(&next, 0);
            self.try_plan();
        }
    }

    fn current_request(&self) -> Option<TrackRequest> {
        let cur = (*self.current.lock())?;
        self.tracks.lock().get(&cur).map(|t| t.req.clone())
    }

    fn request_analysis(&self, req: &TrackRequest, priority: u8) {
        let Some(worker) = self.analysis.lock().clone() else { return };
        let Some(key) = req.analysis_key.clone() else { return };
        worker.request(AnalysisJob {
            key,
            url: req.url.clone(),
            cache_key: req.cache_key.clone(),
            ext: req.format_hint.clone(),
            priority,
        });
    }

    fn analysis_of(&self, req: &TrackRequest) -> Option<Arc<TrackAnalysis>> {
        let worker = self.analysis.lock().clone()?;
        worker.get(req.analysis_key.as_deref()?)
    }

    /// Com as duas análises prontas, planeja e troca a reserva pela transição DJ.
    fn try_plan(self: &Arc<Self>) {
        let next = self.ctl.lock().next.clone();
        let Some((b_req, TransitionRequest::Automix)) = next else { return };
        let Some(cur_token) = *self.current.lock() else { return };
        let (a_req, a_deck) = match self.tracks.lock().get(&cur_token) {
            Some(t) => (t.req.clone(), t.deck.clone()),
            None => return,
        };
        if self.planned.lock().as_ref().is_some_and(|(f, t, _)| *f == a_req.id && *t == b_req.id) {
            return;
        }
        let (Some(aa), Some(ab)) = (self.analysis_of(&a_req), self.analysis_of(&b_req)) else { return };
        let rate = self.ctl.lock().rate;
        let a_now = a_deck.native_position() as f64 / rate as f64;
        let settings = self.automix.lock().clone();
        let plan = automix::plan(&aa, &ab, &settings, a_now);

        let start_native = (plan.from_start * rate as f64).round() as u64;
        // Precisa de folga para B ser preparado (decodificar/baixar o começo).
        if start_native <= a_deck.native_position() + rate as u64 * 2 {
            return;
        }
        let len = ((plan.duration * rate as f64).round() as u64).max(rate as u64 / 100);
        let tempo = ((plan.speed - 1.0).abs() > 1e-4).then(|| TempoMap {
            speed: plan.speed,
            hold: len as f64,
            ramp: plan.ramp * rate as f64,
        });
        let deck_b = self.make_deck_tempo(b_req.clone(), (plan.to_start * 1000.0).round() as u64, None, tempo);
        let exec = AutomixExec {
            style: plan.style,
            start_native,
            len,
            swap_at: (plan.swap_at * len as f64) as u64,
            beat: (plan.beat * rate as f64) as u64,
            echo_buf: vec![0.0; rate as usize * 2 * 2],
            mute_from: false,
        };
        if let Some(cur) = self.current_deck() {
            cur.set_successor(None);
        }
        self.send(MixerCmd::SetNext(Some(deck_b), Transition::Automix(Box::new(exec))));
        let starts_in_ms = (start_native - a_deck.native_position()) * 1000 / rate as u64;
        self.emit(EngineEvent::MixPlanned {
            from_id: a_req.id.clone(),
            to_id: b_req.id.clone(),
            summary: plan.summary.clone(),
            beatmatched: plan.beatmatched,
            starts_in_ms,
        });
        *self.planned.lock() = Some((a_req.id, b_req.id, plan));
    }

    /// Chamado pela fila de análise quando um resultado fica pronto.
    fn on_analysis(self: &Arc<Self>, key: &str, result: Option<&Arc<TrackAnalysis>>) {
        // Informa a UI (BPM/tom) para as entradas da fila com essa música.
        if let Some(a) = result {
            let ids: Vec<String> = self
                .tracks
                .lock()
                .values()
                .filter(|t| t.req.analysis_key.as_deref() == Some(key))
                .map(|t| t.req.id.clone())
                .collect();
            let next_id = self.ctl.lock().next.as_ref().and_then(|(r, _)| (r.analysis_key.as_deref() == Some(key)).then(|| r.id.clone()));
            let mut seen = std::collections::HashSet::new();
            for id in ids.into_iter().chain(next_id).filter(|id| seen.insert(id.clone())) {
                self.emit(EngineEvent::Analysis {
                    id,
                    bpm: a.bpm,
                    key: a.key.clone(),
                    camelot: a.camelot.clone(),
                    reliable: a.has_beat(),
                });
            }
        }
        self.try_plan();
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
            analysis: Mutex::new(None),
            automix: Mutex::new(AutomixSettings::default()),
            planned: Mutex::new(None),
        });

        if let Some(model_dir) = config.model_dir.clone() {
            let analyzer = Analyzer::new(model_dir, config.cache_dir.join("analysis"));
            let weak = Arc::downgrade(&inner);
            let worker = AnalysisWorker::start(
                analyzer,
                inner.downloads.clone(),
                Arc::new(move |key, result| {
                    if let Some(i) = weak.upgrade() {
                        i.on_analysis(key, result);
                    }
                }),
            );
            *inner.analysis.lock() = Some(worker);
        }

        if let Err(e) = inner.open_output() {
            if inner.ctl.lock().device_id.take().is_some() {
                // O dispositivo salvo sumiu (ex.: fone desconectado): usa o padrão.
                log::warn!("dispositivo salvo indisponível ({e:#}), usando o padrão");
                if let Err(e2) = inner.open_output() {
                    inner.emit(EngineEvent::Error { message: format!("Sem saída de áudio: {e2:#}") });
                }
            } else {
                log::warn!("sem saída de áudio: {e:#}");
                inner.emit(EngineEvent::Error { message: format!("Sem saída de áudio: {e:#}") });
            }
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
        self.inner.replan_after_seek();
    }

    pub fn set_eq(&self, eq: mixer::EqSettings) {
        self.inner.send(MixerCmd::SetEq(eq));
    }

    pub fn set_automix(&self, settings: AutomixSettings) {
        *self.inner.automix.lock() = settings;
        // Replaneja a transição pendente com as regras novas.
        self.inner.replan_after_seek();
    }

    /// Pré-análise (prioridade baixa) de faixas que vêm depois na fila.
    pub fn analyze(&self, req: &TrackRequest) {
        self.inner.request_analysis(req, 5);
    }

    pub fn set_analysis_model(&self, model: BeatModel) -> BeatModel {
        let Some(worker) = self.inner.analysis.lock().clone() else { return BeatModel::Small };
        let chosen = worker.analyzer().set_model(model);
        worker.clear_memory();
        chosen
    }

    /// Modelo em uso (sem trocar).
    pub fn set_analysis_model_query(&self) -> BeatModel {
        self.inner.analysis.lock().as_ref().map(|w| w.analyzer().model()).unwrap_or(BeatModel::Small)
    }

    pub fn analysis_model_dir(&self) -> Option<PathBuf> {
        self.inner.analysis.lock().as_ref().map(|w| w.analyzer().model_dir().to_path_buf())
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
        let previous = std::mem::replace(&mut self.inner.ctl.lock().device_id, device_id);
        if let Err(e) = self.inner.open_output() {
            // Não fica mudo: volta para o que estava funcionando.
            self.inner.ctl.lock().device_id = previous;
            let _ = self.inner.open_output();
            return Err(e);
        }
        Ok(())
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
        if let Some(w) = self.inner.analysis.lock().as_ref() {
            w.stop();
        }
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
    let mut last_default_check = Instant::now();

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
            if let Err(e) = inner.open_output() {
                log::warn!("reabrindo saída de áudio: {e:#}");
            }
        }

        if last_default_check.elapsed() >= Duration::from_secs(2) {
            last_default_check = Instant::now();
            inner.follow_default_output();
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
                let planned = inner.planned.lock().take();
                if let Some((from_id, to_id, plan)) = planned {
                    if to_id == req.id {
                        inner.emit(EngineEvent::MixStarted {
                            from_id,
                            to_id,
                            summary: plan.summary.clone(),
                            style: format!("{:?}", plan.style),
                            duration_ms: (plan.duration * 1000.0) as u64,
                        });
                    }
                }
                on_track_started(inner, token, &req);
                // Análise da nova atual (se ainda não tem) já na frente da fila.
                inner.request_analysis(&req, 0);
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
