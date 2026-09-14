//! Fila de análise em segundo plano (prioridade baixa de CPU): a faixa atual e
//! a próxima primeiro, depois as seguintes da fila (pré-análise).

use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use parking_lot::{Condvar, Mutex};

use super::analysis::{Analyzer, TrackAnalysis};
use crate::stream::DownloadManager;

#[derive(Clone, Debug)]
pub struct AnalysisJob {
    pub key: String,
    pub url: String,
    pub cache_key: Option<String>,
    pub ext: Option<String>,
    /// 0 = urgente (atual/próxima), maior = menos urgente.
    pub priority: u8,
}

pub type ReadyCallback = Arc<dyn Fn(&str, Option<&Arc<TrackAnalysis>>) + Send + Sync>;

pub struct AnalysisWorker {
    analyzer: Arc<Analyzer>,
    results: Mutex<HashMap<String, Arc<TrackAnalysis>>>,
    failed: Mutex<HashSet<String>>,
    queue: Mutex<VecDeque<AnalysisJob>>,
    cond: Condvar,
    running: AtomicBool,
}

impl AnalysisWorker {
    pub fn start(analyzer: Arc<Analyzer>, downloads: Arc<DownloadManager>, on_ready: ReadyCallback) -> Arc<Self> {
        let w = Arc::new(Self {
            analyzer,
            results: Mutex::new(HashMap::new()),
            failed: Mutex::new(HashSet::new()),
            queue: Mutex::new(VecDeque::new()),
            cond: Condvar::new(),
            running: AtomicBool::new(true),
        });
        let worker = w.clone();
        let _ = std::thread::Builder::new().name("analysis".into()).spawn(move || {
            lower_priority();
            worker.run(downloads, on_ready);
        });
        w
    }

    pub fn analyzer(&self) -> &Arc<Analyzer> {
        &self.analyzer
    }

    /// Resultado já pronto (memória ou disco).
    pub fn get(&self, key: &str) -> Option<Arc<TrackAnalysis>> {
        if let Some(a) = self.results.lock().get(key) {
            return Some(a.clone());
        }
        let a = Arc::new(self.analyzer.cached(key)?);
        self.results.lock().insert(key.to_string(), a.clone());
        Some(a)
    }

    pub fn has_failed(&self, key: &str) -> bool {
        self.failed.lock().contains(key)
    }

    /// Enfileira (ou sobe a prioridade, se já estiver na fila).
    pub fn request(&self, job: AnalysisJob) {
        if self.get(&job.key).is_some() || self.has_failed(&job.key) {
            return;
        }
        let mut q = self.queue.lock();
        if let Some(existing) = q.iter_mut().find(|j| j.key == job.key) {
            existing.priority = existing.priority.min(job.priority);
        } else {
            q.push_back(job);
        }
        self.cond.notify_one();
    }

    /// Análises urgentes (a que toca e a próxima), na frente da fila e nessa
    /// ordem. Urgentes de antes perdem a urgência: ao pular várias músicas
    /// seguidas, as que já passaram não seguram as de agora.
    pub fn request_urgent(&self, jobs: Vec<AnalysisJob>) {
        let jobs: Vec<AnalysisJob> = jobs
            .into_iter()
            .filter(|j| self.get(&j.key).is_none() && !self.has_failed(&j.key))
            .collect();
        let mut q = self.queue.lock();
        for j in q.iter_mut().filter(|j| j.priority == 0) {
            j.priority = 1;
        }
        q.retain(|j| !jobs.iter().any(|n| n.key == j.key));
        for mut job in jobs.into_iter().rev() {
            job.priority = 0;
            q.push_front(job);
        }
        self.cond.notify_one();
    }

    /// Esquece resultados em memória (ex.: trocou o modelo).
    pub fn clear_memory(&self) {
        self.results.lock().clear();
        self.failed.lock().clear();
    }

    pub fn stop(&self) {
        self.running.store(false, Ordering::Relaxed);
        self.cond.notify_all();
    }

    fn next_job(&self) -> Option<AnalysisJob> {
        let mut q = self.queue.lock();
        loop {
            if !self.running.load(Ordering::Relaxed) {
                return None;
            }
            if let Some(i) = q.iter().enumerate().min_by_key(|(_, j)| j.priority).map(|(i, _)| i) {
                return q.remove(i);
            }
            self.cond.wait_for(&mut q, Duration::from_secs(1));
        }
    }

    fn run(&self, downloads: Arc<DownloadManager>, on_ready: ReadyCallback) {
        while let Some(job) = self.next_job() {
            if self.get(&job.key).is_some() {
                continue;
            }
            if !self.analyzer.models_available() {
                self.failed.lock().insert(job.key.clone());
                on_ready(&job.key, None);
                continue;
            }
            let cancel = Arc::new(AtomicBool::new(false));
            let result = downloads
                .open(job.cache_key.as_deref(), &job.url, cancel)
                .and_then(|opened| self.analyzer.analyze(&job.key, opened.source, job.ext.as_deref()));
            match result {
                Ok(a) => {
                    let a = Arc::new(a);
                    self.results.lock().insert(job.key.clone(), a.clone());
                    on_ready(&job.key, Some(&a));
                }
                Err(e) => {
                    log::warn!("análise de {} falhou: {e:#}", job.key);
                    self.failed.lock().insert(job.key.clone());
                    on_ready(&job.key, None);
                }
            }
        }
    }
}

/// A análise é pesada (rede neural): roda com prioridade baixa para nunca
/// disputar CPU com a decodificação/áudio. As threads do rayon criadas a partir
/// desta herdam a prioridade.
fn lower_priority() {
    #[cfg(any(target_os = "linux", target_os = "android"))]
    unsafe {
        let tid = libc::syscall(libc::SYS_gettid) as libc::id_t;
        libc::setpriority(libc::PRIO_PROCESS, tid, 10);
    }
}
