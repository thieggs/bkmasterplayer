//! Estado do coordenador, em arquivos na pasta de dados:
//! - `config.json` (0600): login do Navidrome (token) e o token dos trabalhadores;
//! - `songs.json`: a biblioteca e o estado da análise de cada música;
//! - `analyses/<id>.json`: as análises prontas, do jeito que o player usa;
//! - `sessions.json` (0600): logins no painel.
//! Quem está analisando o quê fica só na memória: se o coordenador reinicia, as
//! músicas em andamento voltam para a fila.

use std::collections::{HashMap, HashSet, VecDeque};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use parking_lot::Mutex;
use player_engine::engine::analysis::{TrackAnalysis, ANALYSIS_VERSION};
use player_engine::engine::automix::{bar_entry, bar_exit, AutomixSettings};
use serde::{Deserialize, Serialize};

use crate::navidrome::{random_hex, Login, RemoteSong};

/// Tentativas antes de desistir de uma música (erro de download/formato).
pub const MAX_ATTEMPTS: u32 = 3;
/// Sem sinal do trabalhador por esse tempo, a música volta para a fila.
const LEASE: Duration = Duration::from_secs(240);
/// Trabalhador sem aparecer há mais que isso aparece como desligado.
const ONLINE: u64 = 90;

pub fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    #[default]
    Pending,
    Done,
    Failed,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Song {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    #[serde(default)]
    pub duration: u32,
    #[serde(default)]
    pub suffix: String,
    #[serde(default)]
    pub size: u64,
    #[serde(default)]
    pub plays: u32,
    #[serde(default)]
    pub starred: bool,
    #[serde(default)]
    pub state: State,
    /// Sincroniza na entrada (começo) e na saída (fim).
    #[serde(default)]
    pub head: bool,
    #[serde(default)]
    pub tail: bool,
    /// Sem sincronizar, dá para entrar/sair no compasso (batida tocada).
    #[serde(default)]
    pub bar_in: bool,
    #[serde(default)]
    pub bar_out: bool,
    #[serde(default)]
    pub bpm: Option<f64>,
    #[serde(default)]
    pub camelot: Option<String>,
    /// Por que não deu (batida ou erro), em poucas palavras.
    #[serde(default)]
    pub problem: Option<String>,
    /// Números das grades (ou o erro completo).
    #[serde(default)]
    pub detail: String,
    #[serde(default)]
    pub attempts: u32,
    #[serde(default)]
    pub done_at: u64,
    #[serde(default)]
    pub secs: f32,
    #[serde(default)]
    pub worker: String,
    #[serde(default)]
    pub model: String,
    #[serde(default)]
    pub version: u32,
}

/// Formatos que o motor do app não decodifica: o player recebe convertido
/// para MP3 pelo servidor (ver `_undecodable` em player_controller.dart), e a
/// análise tem de ser desse mesmo arquivo.
const UNDECODABLE: &[&str] = &["opus", "wma", "ape", "wv", "dsf", "dff", "mpc", "tta", "ac3", "dts"];

impl Song {
    /// Conversão pedida ao Navidrome (None = arquivo original).
    pub fn stream_format(&self) -> Option<&'static str> {
        UNDECODABLE.contains(&self.suffix.as_str()).then_some("mp3")
    }

    fn from_remote(r: &RemoteSong) -> Self {
        Self {
            id: r.id.clone(),
            title: r.title.clone(),
            artist: r.artist.clone(),
            album: r.album.clone(),
            duration: r.duration,
            suffix: r.suffix.clone(),
            size: r.size,
            plays: r.plays,
            starred: r.starred,
            state: State::Pending,
            head: false,
            tail: false,
            bar_in: false,
            bar_out: false,
            bpm: None,
            camelot: None,
            problem: None,
            detail: String::new(),
            attempts: 0,
            done_at: 0,
            secs: 0.0,
            worker: String::new(),
            model: String::new(),
            version: 0,
        }
    }

    fn reset(&mut self) {
        let keep = Song::from_remote(&RemoteSong {
            id: self.id.clone(),
            title: self.title.clone(),
            artist: self.artist.clone(),
            album: self.album.clone(),
            duration: self.duration,
            suffix: self.suffix.clone(),
            size: self.size,
            plays: self.plays,
            starred: self.starred,
        });
        *self = keep;
    }

    /// Categoria no painel: sincroniza nas duas pontas; no compasso (as duas
    /// pontas pelo menos no compasso); só uma ponta; sem batida.
    pub fn category(&self) -> &'static str {
        let (entry, exit) = (self.head || self.bar_in, self.tail || self.bar_out);
        match self.state {
            State::Pending => "pending",
            State::Failed => "failed",
            State::Done if self.head && self.tail => "ok",
            State::Done if entry && exit => "bars",
            State::Done if entry || exit => "partial",
            State::Done => "nobeat",
        }
    }

    /// Resultado da análise (também recalculado ao abrir, se as regras mudarem).
    fn apply(&mut self, a: &TrackAnalysis) {
        let (head, tail) = a.sync_ends();
        let settings = AutomixSettings::default();
        (self.head, self.tail, self.bpm, self.camelot) = (head, tail, a.bpm, a.camelot.clone());
        self.bar_in = bar_entry(a).is_some();
        self.bar_out = bar_exit(a, &settings, 0.0).is_some();
        self.problem = a.beat_problem();
        self.detail = a.grid_summary();
        self.version = a.version;
    }
}

#[derive(Clone, Default, Serialize, Deserialize)]
pub struct Config {
    #[serde(default)]
    pub navidrome: Option<Login>,
    #[serde(default)]
    pub worker_token: String,
}

#[derive(Clone, Serialize, Deserialize)]
struct Session {
    user: String,
    expires: u64,
}

struct Lease {
    worker: String,
    since: Instant,
    beat: Instant,
}

#[derive(Clone, Serialize)]
pub struct WorkerInfo {
    pub name: String,
    pub model: String,
    pub cpu: String,
    pub jobs: u32,
    pub last_seen: u64,
    pub done: u32,
    pub failed: u32,
    pub secs_total: f64,
    pub paused: Option<String>,
}

#[derive(Clone, Serialize)]
pub struct Recent {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub category: &'static str,
    pub problem: Option<String>,
    pub secs: f32,
    pub worker: String,
    pub at: u64,
}

#[derive(Clone, Default, Serialize)]
pub struct SyncInfo {
    pub at: u64,
    pub error: Option<String>,
    pub running: bool,
    pub added: usize,
    pub removed: usize,
    pub changed: usize,
}

/// Resultado de um trabalhador.
pub enum Outcome {
    Ok(Box<TrackAnalysis>),
    Err(String),
}

struct Inner {
    config: Config,
    songs: HashMap<String, Song>,
    /// Pendentes na ordem de análise (as mais tocadas/favoritas primeiro).
    order: Vec<String>,
    /// Pedidas por um player agora (na frente de tudo).
    urgent: VecDeque<String>,
    leases: HashMap<String, Lease>,
    workers: HashMap<String, WorkerInfo>,
    sessions: HashMap<String, Session>,
    recent: VecDeque<Recent>,
    finished_at: VecDeque<u64>,
    sync: SyncInfo,
    sync_requested: bool,
    dirty: bool,
    sessions_dirty: bool,
}

pub struct Store {
    dir: PathBuf,
    inner: Mutex<Inner>,
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> Option<T> {
    serde_json::from_slice(&std::fs::read(path).ok()?).ok()
}

/// Grava de uma vez (arquivo temporário + rename); `private` = só o dono lê.
fn write_atomic(path: &Path, data: &[u8], private: bool) -> Result<()> {
    use std::io::Write;
    let tmp = path.with_extension("tmp");
    let mut opts = std::fs::OpenOptions::new();
    opts.write(true).create(true).truncate(true);
    #[cfg(unix)]
    if private {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600);
    }
    let mut f = opts.open(&tmp).with_context(|| format!("gravando {}", tmp.display()))?;
    f.write_all(data)?;
    f.sync_all()?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

/// Nome de arquivo seguro para o id da música.
fn file_id(id: &str) -> String {
    if !id.is_empty() && id.len() <= 64 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_') {
        id.to_string()
    } else {
        format!("h{:016x}", player_engine::stream::fnv1a64(id))
    }
}

impl Store {
    pub fn open(dir: &Path) -> Result<Self> {
        std::fs::create_dir_all(dir.join("analyses")).with_context(|| format!("criando {}", dir.display()))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700));
        }
        let mut config: Config = read_json(&dir.join("config.json")).unwrap_or_default();
        if config.worker_token.is_empty() {
            config.worker_token = random_hex(24);
            write_atomic(&dir.join("config.json"), &serde_json::to_vec_pretty(&config)?, true)?;
        }
        let list: Vec<Song> = read_json(&dir.join("songs.json")).unwrap_or_default();
        let mut songs: HashMap<String, Song> = list.into_iter().map(|s| (s.id.clone(), s)).collect();
        // Algoritmo novo: tudo o que foi feito com o antigo volta para a fila.
        let mut stale = 0;
        for s in songs.values_mut() {
            if s.state == State::Done && s.version != ANALYSIS_VERSION {
                s.state = State::Pending;
                stale += 1;
            }
        }
        if stale > 0 {
            eprintln!("{stale} análises de uma versão antiga voltaram para a fila");
        }
        // As regras de "sincroniza" e "no compasso" rodam em cima da análise
        // guardada: recalcula, para valerem sem analisar de novo.
        for s in songs.values_mut().filter(|s| s.state == State::Done) {
            let path = dir.join("analyses").join(format!("{}.json", file_id(&s.id)));
            if let Some(a) = read_json::<TrackAnalysis>(&path) {
                s.apply(&a);
            }
        }
        let now_s = now();
        let sessions: HashMap<String, Session> =
            read_json::<HashMap<String, Session>>(&dir.join("sessions.json")).unwrap_or_default().into_iter().filter(|(_, s)| s.expires > now_s).collect();
        let store = Self {
            dir: dir.to_path_buf(),
            inner: Mutex::new(Inner {
                config,
                songs,
                order: Vec::new(),
                urgent: VecDeque::new(),
                leases: HashMap::new(),
                workers: HashMap::new(),
                sessions,
                recent: VecDeque::new(),
                finished_at: VecDeque::new(),
                sync: SyncInfo::default(),
                sync_requested: true,
                dirty: stale > 0,
                sessions_dirty: false,
            }),
        };
        store.inner.lock().reorder();
        Ok(store)
    }

    // ---------- configuração e sessões ----------

    pub fn config(&self) -> Config {
        self.inner.lock().config.clone()
    }

    pub fn set_login(&self, login: Login) -> Result<()> {
        let mut g = self.inner.lock();
        let changed_server = g.config.navidrome.as_ref().is_some_and(|l| l.url != login.url);
        g.config.navidrome = Some(login);
        if changed_server {
            // Outro servidor, outra biblioteca: os ids não valem mais.
            g.songs.clear();
            g.order.clear();
            g.urgent.clear();
            g.leases.clear();
            g.dirty = true;
            let _ = std::fs::remove_dir_all(self.dir.join("analyses"));
            let _ = std::fs::create_dir_all(self.dir.join("analyses"));
        }
        g.sync_requested = true;
        write_atomic(&self.dir.join("config.json"), &serde_json::to_vec_pretty(&g.config)?, true)
    }

    pub fn worker_token(&self) -> String {
        self.inner.lock().config.worker_token.clone()
    }

    pub fn new_session(&self, user: &str) -> String {
        let token = random_hex(24);
        let mut g = self.inner.lock();
        g.sessions.insert(token.clone(), Session { user: user.into(), expires: now() + 30 * 86400 });
        g.sessions_dirty = true;
        token
    }

    pub fn session_user(&self, token: &str) -> Option<String> {
        let g = self.inner.lock();
        g.sessions.get(token).filter(|s| s.expires > now()).map(|s| s.user.clone())
    }

    pub fn end_session(&self, token: &str) {
        let mut g = self.inner.lock();
        g.sessions.remove(token);
        g.sessions_dirty = true;
    }

    // ---------- biblioteca ----------

    pub fn sync_due(&self, every: Duration) -> bool {
        let g = self.inner.lock();
        g.config.navidrome.is_some() && !g.sync.running && (g.sync_requested || now().saturating_sub(g.sync.at) >= every.as_secs())
    }

    pub fn request_sync(&self) {
        self.inner.lock().sync_requested = true;
    }

    pub fn sync_started(&self) {
        let mut g = self.inner.lock();
        g.sync.running = true;
        g.sync_requested = false;
    }

    pub fn sync_failed(&self, error: String) {
        let mut g = self.inner.lock();
        g.sync.running = false;
        g.sync.at = now();
        g.sync.error = Some(error);
    }

    /// Junta a lista do servidor: novas entram na fila, as que mudaram de
    /// arquivo são refeitas e as que sumiram saem (com a análise).
    pub fn sync(&self, remote: Vec<RemoteSong>) {
        let mut g = self.inner.lock();
        let (mut added, mut changed) = (0, 0);
        let ids: HashSet<String> = remote.iter().map(|r| r.id.clone()).collect();
        for r in &remote {
            match g.songs.get_mut(&r.id) {
                None => {
                    g.songs.insert(r.id.clone(), Song::from_remote(r));
                    added += 1;
                }
                Some(s) => {
                    let file_changed = s.size != r.size || s.suffix != r.suffix;
                    (s.title, s.artist, s.album, s.duration, s.plays, s.starred) =
                        (r.title.clone(), r.artist.clone(), r.album.clone(), r.duration, r.plays, r.starred);
                    if file_changed {
                        (s.size, s.suffix) = (r.size, r.suffix.clone());
                        s.reset();
                        changed += 1;
                    }
                }
            }
        }
        let gone: Vec<String> = g.songs.keys().filter(|id| !ids.contains(*id)).cloned().collect();
        for id in &gone {
            g.songs.remove(id);
            let _ = std::fs::remove_file(self.analysis_path(id));
        }
        g.sync = SyncInfo { at: now(), error: None, running: false, added, removed: gone.len(), changed };
        g.dirty = true;
        g.reorder();
        if added + changed + gone.len() > 0 {
            eprintln!("biblioteca: {} músicas ({added} novas, {changed} mudaram, {} saíram)", g.songs.len(), gone.len());
        }
    }

    // ---------- fila ----------

    /// Próxima música para o trabalhador `worker` (e registra que ele está vivo).
    pub fn claim(&self, worker: &str, info: WorkerInfo) -> Option<Song> {
        let mut g = self.inner.lock();
        g.expire_leases();
        let seen = g.workers.entry(worker.into()).or_insert_with(|| info.clone());
        (seen.model, seen.cpu, seen.jobs, seen.paused, seen.last_seen) = (info.model, info.cpu, info.jobs, info.paused, now());
        if seen.paused.is_some() {
            return None;
        }
        let free = |g: &Inner, id: &String| g.songs.get(id).is_some_and(|s| s.state == State::Pending) && !g.leases.contains_key(id);
        let id = loop {
            match g.urgent.pop_front() {
                Some(id) if free(&g, &id) => break Some(id),
                Some(_) => continue,
                None => break None,
            }
        };
        let id = id.or_else(|| g.order.iter().find(|id| free(&g, id)).cloned())?;
        let t = Instant::now();
        g.leases.insert(id.clone(), Lease { worker: worker.into(), since: t, beat: t });
        g.songs.get(&id).cloned()
    }

    /// Sinal de vida durante uma análise longa. false = a música não é mais dele.
    pub fn heartbeat(&self, id: &str, worker: &str) -> bool {
        let mut g = self.inner.lock();
        if let Some(w) = g.workers.get_mut(worker) {
            w.last_seen = now();
        }
        match g.leases.get_mut(id) {
            Some(l) if l.worker == worker => {
                l.beat = Instant::now();
                true
            }
            _ => false,
        }
    }

    pub fn finish(&self, id: &str, worker: &str, secs: f32, model: &str, outcome: Outcome) -> Result<()> {
        let mut g = self.inner.lock();
        g.leases.remove(id);
        let Some(song) = g.songs.get(id).cloned() else { return Ok(()) };
        let mut s = song;
        s.worker = worker.into();
        s.secs = secs;
        s.done_at = now();
        match outcome {
            Outcome::Ok(a) => {
                let json = serde_json::to_vec(&*a)?;
                write_atomic(&self.analysis_path(id), &json, false)?;
                s.apply(&a);
                s.state = State::Done;
                s.model = model.into();
                s.attempts = 0;
            }
            Outcome::Err(e) => {
                s.attempts += 1;
                s.problem = Some(short_error(&e));
                s.detail = e;
                s.state = if s.attempts >= MAX_ATTEMPTS { State::Failed } else { State::Pending };
            }
        }
        let ok = s.state == State::Done;
        if let Some(w) = g.workers.get_mut(worker) {
            w.last_seen = now();
            if ok {
                w.done += 1;
                w.secs_total += secs as f64;
            } else {
                w.failed += 1;
            }
        }
        g.recent.push_front(Recent {
            id: s.id.clone(),
            title: s.title.clone(),
            artist: s.artist.clone(),
            category: s.category(),
            problem: s.problem.clone(),
            secs,
            worker: worker.into(),
            at: now(),
        });
        g.recent.truncate(40);
        g.finished_at.push_back(now());
        while g.finished_at.len() > 2000 {
            g.finished_at.pop_front();
        }
        let retry = s.state == State::Pending;
        g.songs.insert(id.into(), s);
        if retry {
            g.reorder();
        }
        g.dirty = true;
        Ok(())
    }

    /// Um player pediu e ainda não tem: vai para a frente da fila.
    pub fn bump(&self, id: &str) -> Option<State> {
        let mut g = self.inner.lock();
        let state = g.songs.get(id)?.state;
        if state == State::Pending && !g.urgent.iter().any(|x| x == id) {
            g.urgent.push_back(id.into());
            while g.urgent.len() > 200 {
                g.urgent.pop_front();
            }
        }
        Some(state)
    }

    /// Volta músicas para a fila (tentar de novo / reanalisar).
    pub fn retry(&self, ids: &[String], category: Option<&str>) -> usize {
        let mut g = self.inner.lock();
        let mut n = 0;
        let targets: Vec<String> = match category {
            Some(c) => g.songs.values().filter(|s| s.category() == c).map(|s| s.id.clone()).collect(),
            None => ids.to_vec(),
        };
        for id in targets {
            if let Some(s) = g.songs.get_mut(&id) {
                if s.state != State::Pending || s.attempts > 0 {
                    s.reset();
                    n += 1;
                }
            }
        }
        if n > 0 {
            g.dirty = true;
            g.reorder();
        }
        n
    }

    pub fn analysis_path(&self, id: &str) -> PathBuf {
        self.dir.join("analyses").join(format!("{}.json", file_id(id)))
    }

    /// Análise pronta (JSON) de uma música, se for da versão atual.
    pub fn analysis(&self, id: &str) -> Option<Vec<u8>> {
        {
            let g = self.inner.lock();
            let s = g.songs.get(id)?;
            if s.state != State::Done || s.version != ANALYSIS_VERSION {
                return None;
            }
        }
        std::fs::read(self.analysis_path(id)).ok()
    }

    /// Algum trabalhador ligado e sem pausa (vale o player esperar).
    pub fn worker_ready(&self) -> bool {
        let g = self.inner.lock();
        let t = now();
        g.workers.values().any(|w| w.paused.is_none() && t.saturating_sub(w.last_seen) <= ONLINE)
    }

    pub fn song(&self, id: &str) -> Option<Song> {
        self.inner.lock().songs.get(id).cloned()
    }

    // ---------- painel ----------

    pub fn status(&self) -> serde_json::Value {
        let mut g = self.inner.lock();
        g.expire_leases();
        let mut count: HashMap<&'static str, usize> = HashMap::new();
        for s in g.songs.values() {
            *count.entry(s.category()).or_default() += 1;
        }
        let working: Vec<serde_json::Value> = g
            .leases
            .iter()
            .filter_map(|(id, l)| {
                let s = g.songs.get(id)?;
                Some(serde_json::json!({
                    "id": id, "title": s.title, "artist": s.artist, "worker": l.worker,
                    "secs": l.since.elapsed().as_secs(),
                }))
            })
            .collect();
        let t = now();
        let window = 1800;
        let recent_done = g.finished_at.iter().filter(|x| t.saturating_sub(**x) <= window).count();
        let first = g.finished_at.iter().find(|x| t.saturating_sub(**x) <= window).copied();
        // Ritmo: músicas por hora na última meia hora (ou desde a primeira dela).
        let span = first.map(|f| (t - f).max(60)).unwrap_or(window);
        let rate = if recent_done >= 2 { recent_done as f64 * 3600.0 / span as f64 } else { 0.0 };
        let pending = count.get("pending").copied().unwrap_or(0);
        let workers: Vec<serde_json::Value> = g
            .workers
            .values()
            .map(|w| {
                let busy = g.leases.values().filter(|l| l.worker == w.name).count();
                serde_json::json!({
                    "name": w.name, "model": w.model, "cpu": w.cpu, "jobs": w.jobs, "busy": busy,
                    "online": t.saturating_sub(w.last_seen) <= ONLINE, "last_seen": w.last_seen,
                    "done": w.done, "failed": w.failed, "paused": w.paused,
                    "avg_secs": if w.done > 0 { w.secs_total / w.done as f64 } else { 0.0 },
                })
            })
            .collect();
        let login = g.config.navidrome.as_ref();
        serde_json::json!({
            "configured": login.is_some(),
            "navidrome": login.map(|l| l.url.clone()),
            "library_user": login.map(|l| l.username.clone()),
            "version": ANALYSIS_VERSION,
            "total": g.songs.len(),
            "counts": {
                "ok": count.get("ok").copied().unwrap_or(0),
                "bars": count.get("bars").copied().unwrap_or(0),
                "partial": count.get("partial").copied().unwrap_or(0),
                "nobeat": count.get("nobeat").copied().unwrap_or(0),
                "failed": count.get("failed").copied().unwrap_or(0),
                "pending": pending,
            },
            "working": working,
            "rate_per_hour": rate,
            "eta_minutes": if rate > 0.0 { Some((pending as f64 / rate * 60.0).round()) } else { None },
            "workers": workers,
            "sync": g.sync,
            "recent": g.recent,
            "urgent": g.urgent.len(),
        })
    }

    /// Página da lista de músicas por categoria e busca.
    pub fn list(&self, category: &str, query: &str, offset: usize, limit: usize) -> serde_json::Value {
        let g = self.inner.lock();
        let q = query.to_lowercase();
        let mut rows: Vec<&Song> = g
            .songs
            .values()
            .filter(|s| category == "all" || s.category() == category || (category == "problems" && matches!(s.category(), "failed" | "nobeat")))
            .filter(|s| q.is_empty() || format!("{} {} {}", s.title, s.artist, s.album).to_lowercase().contains(&q))
            .collect();
        if category == "pending" {
            let pos: HashMap<&String, usize> = g.order.iter().enumerate().map(|(i, id)| (id, i)).collect();
            rows.sort_by_key(|s| pos.get(&s.id).copied().unwrap_or(usize::MAX));
        } else {
            rows.sort_by(|a, b| b.done_at.cmp(&a.done_at).then_with(|| a.artist.cmp(&b.artist)).then_with(|| a.title.cmp(&b.title)));
        }
        let total = rows.len();
        let page: Vec<serde_json::Value> = rows
            .into_iter()
            .skip(offset)
            .take(limit)
            .map(|s| {
                serde_json::json!({
                    "id": s.id, "title": s.title, "artist": s.artist, "album": s.album, "duration": s.duration,
                    "suffix": s.suffix, "category": s.category(), "head": s.head, "tail": s.tail,
                    "bar_in": s.bar_in, "bar_out": s.bar_out, "bpm": s.bpm,
                    "camelot": s.camelot, "problem": s.problem, "detail": s.detail, "attempts": s.attempts,
                    "done_at": s.done_at, "secs": s.secs, "worker": s.worker, "model": s.model,
                })
            })
            .collect();
        serde_json::json!({ "total": total, "rows": page })
    }

    /// Grava o que mudou (chamado de tempos em tempos e ao sair).
    pub fn save(&self) -> Result<()> {
        let (songs, sessions) = {
            let mut g = self.inner.lock();
            let songs = if g.dirty {
                g.dirty = false;
                let mut list: Vec<&Song> = g.songs.values().collect();
                list.sort_by(|a, b| a.id.cmp(&b.id));
                Some(serde_json::to_vec(&list)?)
            } else {
                None
            };
            let sessions = if g.sessions_dirty {
                g.sessions_dirty = false;
                Some(serde_json::to_vec(&g.sessions)?)
            } else {
                None
            };
            (songs, sessions)
        };
        if let Some(b) = songs {
            write_atomic(&self.dir.join("songs.json"), &b, false)?;
        }
        if let Some(b) = sessions {
            write_atomic(&self.dir.join("sessions.json"), &b, true)?;
        }
        Ok(())
    }
}

impl Inner {
    /// Pendentes: primeiro as que nunca falharam, favoritas, mais tocadas.
    fn reorder(&mut self) {
        let mut ids: Vec<&Song> = self.songs.values().filter(|s| s.state == State::Pending).collect();
        ids.sort_by(|a, b| {
            a.attempts
                .cmp(&b.attempts)
                .then(b.starred.cmp(&a.starred))
                .then(b.plays.cmp(&a.plays))
                .then_with(|| a.artist.cmp(&b.artist))
                .then_with(|| a.album.cmp(&b.album))
                .then_with(|| a.title.cmp(&b.title))
        });
        self.order = ids.into_iter().map(|s| s.id.clone()).collect();
    }

    /// Trabalhador sumiu no meio: a música volta para a fila (conta como tentativa).
    fn expire_leases(&mut self) {
        let dead: Vec<(String, String)> =
            self.leases.iter().filter(|(_, l)| l.beat.elapsed() > LEASE).map(|(id, l)| (id.clone(), l.worker.clone())).collect();
        for (id, worker) in dead {
            self.leases.remove(&id);
            if let Some(s) = self.songs.get_mut(&id) {
                s.attempts += 1;
                s.problem = Some("o trabalhador parou no meio".into());
                s.detail = format!("{worker} parou de responder durante a análise");
                if s.attempts >= MAX_ATTEMPTS {
                    s.state = State::Failed;
                }
                self.dirty = true;
            }
        }
    }
}

/// O erro em poucas palavras (o completo fica no detalhe).
fn short_error(e: &str) -> String {
    let l = e.to_lowercase();
    let http = l.split("http ").nth(1).and_then(|r| r.split_whitespace().next()).map(|c| format!(" (HTTP {c})")).unwrap_or_default();
    if l.contains("codec") || l.contains("unsupported") || l.contains("formato") {
        "formato de áudio não suportado".into()
    } else if l.contains("áudio vazio") || l.contains("arquivo vazio") {
        "arquivo sem áudio".into()
    } else if l.contains("download") || l.contains("navidrome") {
        format!("não deu para baixar o arquivo{http}")
    } else if l.contains("travou") {
        "a análise travou (erro no programa)".into()
    } else if l.contains("modelo") {
        "problema com o modelo de batidas no trabalhador".into()
    } else {
        let root = e.rsplit(": ").next().unwrap_or(e);
        root.chars().take(100).collect()
    }
}
