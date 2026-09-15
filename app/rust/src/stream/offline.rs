//! Downloads para ouvir offline: fila com N ao mesmo tempo, pausa, tentativas
//! e progresso por música e total (bytes, velocidade).
//!
//! Pausar para na hora os downloads em andamento (menos o de uma música que
//! está tocando, que é o mesmo arquivo): o `.part` é apagado e a música volta
//! para o começo da fila; ao continuar, ela recomeça. Apagar antes de criar de
//! novo garante que a thread antiga, se ainda escrever um último pedaço,
//! escreva num arquivo que já saiu do disco.

use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use std::time::{Duration, Instant};

use super::{Download, DownloadManager};

/// Tentativas por música antes de ficar em "falharam".
const ATTEMPTS: u32 = 3;
/// Espera antes de tentar de novo (vezes o nº da tentativa).
const RETRY_DELAY: Duration = if cfg!(test) { Duration::from_millis(50) } else { Duration::from_secs(5) };

#[derive(Clone, Debug)]
pub struct OfflineTrack {
    pub key: String,
    pub url: String,
    pub title: String,
    pub artist: String,
    /// Tamanho informado pelo servidor (0 = desconhecido): o total antes de começar.
    pub size: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OfflineState {
    Queued,
    Active,
    Done,
    Failed,
}

#[derive(Clone, Debug)]
pub struct OfflineItem {
    pub key: String,
    pub title: String,
    pub artist: String,
    pub state: OfflineState,
    pub bytes: u64,
    pub total: u64,
    pub error: Option<String>,
}

#[derive(Clone, Debug, Default)]
pub struct OfflineStatus {
    pub paused: bool,
    pub parallel: u32,
    pub total: u32,
    pub done: u32,
    pub failed: u32,
    pub queued: u32,
    pub active: u32,
    pub bytes_done: u64,
    pub bytes_total: u64,
    /// Bytes por segundo (média dos últimos segundos).
    pub speed: u64,
    /// Ativas, depois as que falharam, depois o começo da fila.
    pub items: Vec<OfflineItem>,
}

struct Entry {
    track: OfflineTrack,
    state: OfflineState,
    bytes: u64,
    total: u64,
    error: Option<String>,
    attempts: u32,
    dl: Option<Arc<Download>>,
    retry_at: Option<Instant>,
}

pub(super) struct Offline {
    entries: HashMap<String, Entry>,
    /// Ordem das que esperam.
    queue: VecDeque<String>,
    parallel: usize,
    paused: bool,
    /// (quando, bytes baixados na sessão): para a velocidade.
    samples: VecDeque<(Instant, u64)>,
}

impl Default for Offline {
    fn default() -> Self {
        Self { entries: HashMap::new(), queue: VecDeque::new(), parallel: 3, paused: false, samples: VecDeque::new() }
    }
}

impl DownloadManager {
    /// Marca faixas para ouvir offline e enfileira as que ainda não estão no disco.
    pub fn pin(self: &Arc<Self>, tracks: Vec<OfflineTrack>) {
        {
            let mut pinned = self.pinned.lock();
            for t in &tracks {
                pinned.insert(t.key.clone());
            }
        }
        self.save_pinned();
        let mut o = self.offline.lock();
        for t in tracks {
            if self.is_cached(&t.key) {
                continue;
            }
            if o.entries.get(&t.key).is_some_and(|e| matches!(e.state, OfflineState::Queued | OfflineState::Active)) {
                continue;
            }
            let key = t.key.clone();
            let total = t.size;
            o.entries.insert(key.clone(), Entry { track: t, state: OfflineState::Queued, bytes: 0, total, error: None, attempts: 0, dl: None, retry_at: None });
            o.queue.retain(|k| *k != key);
            o.queue.push_back(key);
        }
        self.offline_cond.notify_all();
    }

    /// Remove das offline e apaga os arquivos.
    pub fn unpin(&self, keys: &[String]) {
        {
            let mut pinned = self.pinned.lock();
            for k in keys {
                pinned.remove(k);
            }
        }
        self.save_pinned();
        {
            let mut o = self.offline.lock();
            o.queue.retain(|k| !keys.contains(k));
            for k in keys {
                if let Some(e) = o.entries.remove(k) {
                    if let Some(dl) = e.dl {
                        // Donos: o mapa de ativos e esta variável.
                        self.stop_download(&dl, 2);
                    }
                }
            }
        }
        for k in keys {
            let _ = std::fs::remove_file(self.paths(k).1);
        }
    }

    pub fn is_pinned(&self, key: &str) -> bool {
        self.pinned.lock().contains(key)
    }

    pub fn set_offline_parallel(&self, n: usize) {
        self.offline.lock().parallel = n.clamp(1, 8);
        self.offline_cond.notify_all();
    }

    pub fn set_offline_paused(&self, paused: bool) {
        self.offline.lock().paused = paused;
        self.offline_cond.notify_all();
    }

    /// Volta as que falharam para a fila.
    pub fn retry_offline_failed(&self) {
        let mut o = self.offline.lock();
        let failed: Vec<String> = o.entries.iter().filter(|(_, e)| e.state == OfflineState::Failed).map(|(k, _)| k.clone()).collect();
        for k in failed {
            if let Some(e) = o.entries.get_mut(&k) {
                (e.state, e.attempts, e.error, e.retry_at, e.bytes) = (OfflineState::Queued, 0, None, None, 0);
            }
            o.queue.push_back(k);
        }
        self.offline_cond.notify_all();
    }

    /// Tira da lista as concluídas e as que falharam (as que falharam continuam
    /// marcadas para offline: voltam na próxima vez que o app abrir).
    pub fn clear_offline_finished(&self) {
        let mut o = self.offline.lock();
        o.entries.retain(|_, e| matches!(e.state, OfflineState::Queued | OfflineState::Active));
    }

    pub fn offline_status(&self) -> OfflineStatus {
        let o = self.offline.lock();
        let mut st = OfflineStatus { paused: o.paused, parallel: o.parallel as u32, ..Default::default() };
        for e in o.entries.values() {
            st.total += 1;
            match e.state {
                OfflineState::Done => st.done += 1,
                OfflineState::Failed => st.failed += 1,
                OfflineState::Queued => st.queued += 1,
                OfflineState::Active => st.active += 1,
            }
            st.bytes_total += e.total.max(e.bytes);
            st.bytes_done += if e.state == OfflineState::Done { e.total.max(e.bytes) } else { e.bytes };
        }
        st.speed = speed(&o.samples);
        let item = |e: &Entry| OfflineItem {
            key: e.track.key.clone(),
            title: e.track.title.clone(),
            artist: e.track.artist.clone(),
            state: e.state,
            bytes: e.bytes,
            total: e.total,
            error: e.error.clone(),
        };
        let mut active: Vec<&Entry> = o.entries.values().filter(|e| e.state == OfflineState::Active).collect();
        active.sort_by(|a, b| a.track.title.cmp(&b.track.title));
        st.items.extend(active.into_iter().map(item));
        st.items.extend(o.entries.values().filter(|e| e.state == OfflineState::Failed).take(200).map(item));
        st.items.extend(o.queue.iter().filter_map(|k| o.entries.get(k)).filter(|e| e.state == OfflineState::Queued).take(50).map(item));
        st
    }

    /// Para um download que só a fila offline usa (o de uma música tocando
    /// fica). `owners`: quantas referências são nossas (mapa de ativos, a
    /// entrada da fila, a variável de quem chamou); a thread que baixa guarda
    /// mais uma enquanto roda.
    fn stop_download(&self, dl: &Arc<Download>, owners: usize) -> bool {
        let running = !dl.is_complete() && dl.error().is_none();
        if Arc::strong_count(dl) > owners + running as usize {
            return false;
        }
        dl.cancel();
        {
            let mut active = self.active.lock();
            if active.get(&dl.key).is_some_and(|d| Arc::ptr_eq(d, dl)) {
                active.remove(&dl.key);
            }
        }
        let _ = std::fs::remove_file(&dl.part_path);
        true
    }

    /// Thread que toca a fila offline (N ao mesmo tempo).
    pub fn start_offline_worker(self: &Arc<Self>) {
        let me = Arc::downgrade(self);
        let _ = std::thread::Builder::new().name("offline".into()).spawn(move || loop {
            let Some(mgr) = me.upgrade() else { return };
            mgr.offline_tick();
            let mut o = mgr.offline.lock();
            let idle = o.entries.values().all(|e| e.state != OfflineState::Active) && (o.queue.is_empty() || o.paused);
            mgr.offline_cond.wait_for(&mut o, Duration::from_millis(if idle { 2000 } else { 250 }));
        });
    }

    fn offline_tick(self: &Arc<Self>) {
        let mut o = self.offline.lock();
        let now = Instant::now();
        // Andamento das ativas.
        let keys: Vec<String> = o.entries.iter().filter(|(_, e)| e.state == OfflineState::Active).map(|(k, _)| k.clone()).collect();
        for k in &keys {
            let Some(e) = o.entries.get_mut(k) else { continue };
            let Some(dl) = e.dl.clone() else {
                e.state = OfflineState::Queued;
                let key = k.clone();
                o.queue.push_front(key);
                continue;
            };
            let (bytes, total) = dl.bytes();
            e.bytes = bytes;
            if let Some(t) = total {
                e.total = t;
            }
            if dl.is_complete() {
                (e.state, e.dl, e.bytes) = (OfflineState::Done, None, e.total.max(bytes));
            } else if let Some(err) = dl.error() {
                e.dl = None;
                e.attempts += 1;
                e.error = Some(err);
                if e.attempts >= ATTEMPTS {
                    e.state = OfflineState::Failed;
                } else {
                    // Tenta de novo depois, no fim da fila.
                    (e.state, e.bytes, e.retry_at) = (OfflineState::Queued, 0, Some(now + RETRY_DELAY * e.attempts));
                    let key = k.clone();
                    o.queue.push_back(key);
                }
            }
        }
        // Pausa, ou menos ao mesmo tempo do que está rodando: para as que sobram.
        let active: Vec<String> = o.entries.iter().filter(|(_, e)| e.state == OfflineState::Active).map(|(k, _)| k.clone()).collect();
        let limit = if o.paused { 0 } else { o.parallel };
        if active.len() > limit {
            for k in active.iter().skip(limit) {
                let Some(e) = o.entries.get_mut(k) else { continue };
                let Some(dl) = e.dl.clone() else { continue };
                // Donos: o mapa de ativos, a entrada e o clone acima.
                if self.stop_download(&dl, 3) {
                    (e.state, e.dl, e.bytes) = (OfflineState::Queued, None, 0);
                    let key = k.clone();
                    o.queue.push_front(key);
                }
            }
        }
        // Começa as próximas.
        let mut running = o.entries.values().filter(|e| e.state == OfflineState::Active).count();
        let mut skipped = Vec::new();
        while running < limit {
            let Some(k) = o.queue.pop_front() else { break };
            let Some(e) = o.entries.get_mut(&k) else { continue };
            if e.state != OfflineState::Queued {
                continue;
            }
            if e.retry_at.is_some_and(|t| t > now) {
                skipped.push(k);
                continue;
            }
            if self.is_cached(&k) {
                (e.state, e.bytes) = (OfflineState::Done, e.total);
                continue;
            }
            if !self.pinned.lock().contains(&k) {
                continue;
            }
            match self.ensure_download(&k, &e.track.url) {
                Some(dl) => {
                    (e.state, e.dl, e.retry_at) = (OfflineState::Active, Some(dl), None);
                    running += 1;
                }
                // Já no disco (terminou agora) ou sem como criar o arquivo.
                None => {
                    if self.is_cached(&k) {
                        (e.state, e.bytes) = (OfflineState::Done, e.total);
                    } else {
                        (e.state, e.error) = (OfflineState::Failed, Some("não deu para gravar no cache".into()));
                    }
                }
            }
        }
        for k in skipped.into_iter().rev() {
            o.queue.push_front(k);
        }
        // Velocidade: bytes baixados na sessão ao longo do tempo.
        let downloaded: u64 = o
            .entries
            .values()
            .map(|e| match e.state {
                OfflineState::Done => e.total.max(e.bytes),
                OfflineState::Active => e.bytes,
                _ => 0,
            })
            .sum();
        o.samples.push_back((now, downloaded));
        while o.samples.front().is_some_and(|(t, _)| now.duration_since(*t) > Duration::from_secs(6)) {
            o.samples.pop_front();
        }
    }
}

/// Bytes por segundo entre a amostra mais antiga e a mais nova.
fn speed(samples: &VecDeque<(Instant, u64)>) -> u64 {
    let (Some(a), Some(b)) = (samples.front(), samples.back()) else { return 0 };
    let secs = b.0.duration_since(a.0).as_secs_f64();
    if secs < 0.5 {
        return 0;
    }
    (b.1.saturating_sub(a.1) as f64 / secs) as u64
}
