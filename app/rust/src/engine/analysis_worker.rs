//! Fila de análise em segundo plano (prioridade baixa de CPU): a faixa atual e
//! a próxima primeiro, depois as seguintes da fila (pré-análise).
//!
//! Com um servidor de análise (BK Analyzer), pergunta a ele antes: a análise
//! de lá (modelo completo, feita num PC) vale mais que a local e fica num
//! cache à parte. Se o servidor ainda não tem, ele passa a música para a
//! frente da fila dele; com um trabalhador ligado, espera um pouco por ela
//! antes de analisar aqui.

use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use parking_lot::{Condvar, Mutex};

use super::analysis::{Analyzer, TrackAnalysis, ANALYSIS_VERSION};
use crate::stream::DownloadManager;

#[derive(Clone, Debug)]
pub struct AnalysisJob {
    pub key: String,
    pub url: String,
    pub cache_key: Option<String>,
    pub ext: Option<String>,
    /// Análise pronta no servidor (tentada antes da local).
    pub remote: Option<String>,
    /// 0 = urgente (atual/próxima), maior = menos urgente.
    pub priority: u8,
}

pub type ReadyCallback = Arc<dyn Fn(&str, Option<&Arc<TrackAnalysis>>) + Send + Sync>;

/// Perguntas ao servidor por música, por sessão, enquanto ele analisa.
const REMOTE_TRIES: u8 = 4;
/// Intervalo entre elas.
const REMOTE_WAIT: Duration = Duration::from_secs(10);

enum Remote {
    Ready(Box<TrackAnalysis>),
    /// Ainda não tem, mas um trabalhador está ligado: vale esperar.
    Soon,
    No,
}

pub struct AnalysisWorker {
    analyzer: Arc<Analyzer>,
    results: Mutex<HashMap<String, Arc<TrackAnalysis>>>,
    failed: Mutex<HashSet<String>>,
    queue: Mutex<VecDeque<AnalysisJob>>,
    cond: Condvar,
    running: AtomicBool,
    /// Músicas cujo resultado veio do servidor.
    from_server: Mutex<HashSet<String>>,
    /// Quantas vezes já perguntou ao servidor por música (nesta sessão).
    remote_tries: Mutex<HashMap<String, u8>>,
    /// Esperando o servidor terminar: voltam para a fila na hora marcada.
    waiting: Mutex<Vec<(Instant, AnalysisJob)>>,
    /// Servidor fora do ar ou recusando o login: não pergunta até essa hora.
    server_down_until: Mutex<Option<Instant>>,
    agent: ureq::Agent,
}

impl AnalysisWorker {
    pub fn start(analyzer: Arc<Analyzer>, downloads: Arc<DownloadManager>, on_ready: ReadyCallback) -> Arc<Self> {
        let agent = ureq::Agent::config_builder()
            .timeout_connect(Some(Duration::from_secs(3)))
            .timeout_global(Some(Duration::from_secs(15)))
            .http_status_as_error(false)
            .user_agent(concat!("BKmasterplayer/", env!("CARGO_PKG_VERSION")))
            .build()
            .into();
        let w = Arc::new(Self {
            analyzer,
            results: Mutex::new(HashMap::new()),
            failed: Mutex::new(HashSet::new()),
            queue: Mutex::new(VecDeque::new()),
            cond: Condvar::new(),
            running: AtomicBool::new(true),
            from_server: Mutex::new(HashSet::new()),
            remote_tries: Mutex::new(HashMap::new()),
            waiting: Mutex::new(Vec::new()),
            server_down_until: Mutex::new(None),
            agent,
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

    /// Resultado já pronto (memória ou disco; o do servidor antes do local).
    pub fn get(&self, key: &str) -> Option<Arc<TrackAnalysis>> {
        if let Some(a) = self.results.lock().get(key) {
            return Some(a.clone());
        }
        let a = if let Some(a) = self.analyzer.cached_remote(key) {
            self.from_server.lock().insert(key.to_string());
            Arc::new(a)
        } else {
            Arc::new(self.analyzer.cached(key)?)
        };
        self.results.lock().insert(key.to_string(), a.clone());
        Some(a)
    }

    /// A análise desta música veio do servidor.
    pub fn is_from_server(&self, key: &str) -> bool {
        self.from_server.lock().contains(key)
    }

    pub fn has_failed(&self, key: &str) -> bool {
        self.failed.lock().contains(key)
    }

    fn server_up(&self) -> bool {
        self.server_down_until.lock().is_none_or(|t| Instant::now() >= t)
    }

    /// Vale perguntar ao servidor por esta música (mesmo já tendo a local).
    fn wants_remote(&self, job: &AnalysisJob) -> bool {
        job.remote.is_some()
            && !self.is_from_server(&job.key)
            && self.remote_tries.lock().get(&job.key).copied().unwrap_or(0) < REMOTE_TRIES
            && self.server_up()
    }

    fn needs_work(&self, job: &AnalysisJob) -> bool {
        let have = self.get(&job.key).is_some() || self.has_failed(&job.key);
        !have || self.wants_remote(job)
    }

    /// Enfileira (ou sobe a prioridade, se já estiver na fila).
    pub fn request(&self, job: AnalysisJob) {
        if !self.needs_work(&job) {
            return;
        }
        if let Some((_, w)) = self.waiting.lock().iter_mut().find(|(_, j)| j.key == job.key) {
            w.priority = w.priority.min(job.priority);
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
        let jobs: Vec<AnalysisJob> = jobs.into_iter().filter(|j| self.needs_work(j)).collect();
        let mut q = self.queue.lock();
        for j in q.iter_mut().filter(|j| j.priority == 0) {
            j.priority = 1;
        }
        q.retain(|j| !jobs.iter().any(|n| n.key == j.key));
        for mut job in jobs.into_iter().rev() {
            if let Some((_, w)) = self.waiting.lock().iter_mut().find(|(_, j)| j.key == job.key) {
                w.priority = 0;
                continue;
            }
            job.priority = 0;
            q.push_front(job);
        }
        self.cond.notify_one();
    }

    /// Esquece resultados em memória (ex.: trocou o modelo).
    pub fn clear_memory(&self) {
        self.results.lock().clear();
        self.failed.lock().clear();
        self.from_server.lock().clear();
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
            // As que esperavam o servidor e já deram a hora voltam para a fila.
            let now = Instant::now();
            {
                let mut w = self.waiting.lock();
                let mut i = 0;
                while i < w.len() {
                    if w[i].0 <= now {
                        let (_, job) = w.swap_remove(i);
                        if !q.iter().any(|j| j.key == job.key) {
                            q.push_back(job);
                        }
                    } else {
                        i += 1;
                    }
                }
            }
            if let Some(i) = q.iter().enumerate().min_by_key(|(_, j)| j.priority).map(|(i, _)| i) {
                return q.remove(i);
            }
            self.cond.wait_for(&mut q, Duration::from_secs(1));
        }
    }

    /// Pergunta ao servidor. Fora do ar ou login recusado: para de perguntar
    /// por um tempo (fora de casa, sem o servidor, não atrasa nada).
    fn fetch_remote(&self, url: &str) -> Remote {
        let down = |secs: u64| *self.server_down_until.lock() = Some(Instant::now() + Duration::from_secs(secs));
        let mut resp = match self.agent.get(url).call() {
            Ok(r) => r,
            Err(e) => {
                log::info!("servidor de análise fora do alcance: {e}");
                down(120);
                return Remote::No;
            }
        };
        match resp.status().as_u16() {
            200 => {
                let parsed = resp
                    .body_mut()
                    .with_config()
                    .limit(16 << 20)
                    .read_to_vec()
                    .ok()
                    .and_then(|b| serde_json::from_slice::<TrackAnalysis>(&b).ok());
                match parsed {
                    Some(a) if a.version == ANALYSIS_VERSION && a.is_sane() => Remote::Ready(Box::new(a)),
                    Some(a) if a.version == ANALYSIS_VERSION => {
                        log::warn!("servidor de análise mandou valores fora do possível; ignorada");
                        Remote::No
                    }
                    _ => Remote::No,
                }
            }
            404 => {
                let body = resp.body_mut().read_to_string().unwrap_or_default();
                let soon = serde_json::from_str::<serde_json::Value>(&body).is_ok_and(|v| v["soon"] == true);
                if soon {
                    Remote::Soon
                } else {
                    Remote::No
                }
            }
            401 | 403 => {
                log::warn!("servidor de análise recusou o login");
                down(600);
                Remote::No
            }
            _ => {
                down(60);
                Remote::No
            }
        }
    }

    fn run(&self, downloads: Arc<DownloadManager>, on_ready: ReadyCallback) {
        while let Some(job) = self.next_job() {
            if self.wants_remote(&job) {
                let tries = {
                    let mut t = self.remote_tries.lock();
                    let n = t.entry(job.key.clone()).or_insert(0);
                    *n += 1;
                    *n
                };
                match self.fetch_remote(job.remote.as_deref().unwrap_or_default()) {
                    Remote::Ready(a) => {
                        self.analyzer.store_remote(&job.key, &a);
                        let a = Arc::new(*a);
                        self.results.lock().insert(job.key.clone(), a.clone());
                        self.from_server.lock().insert(job.key.clone());
                        self.failed.lock().remove(&job.key);
                        on_ready(&job.key, Some(&a));
                        continue;
                    }
                    Remote::Soon if tries < REMOTE_TRIES => {
                        // Espera o servidor; enquanto isso, a local (se houver) vale.
                        self.waiting.lock().push((Instant::now() + REMOTE_WAIT, job));
                        continue;
                    }
                    Remote::Soon | Remote::No => {
                        self.remote_tries.lock().insert(job.key.clone(), REMOTE_TRIES);
                    }
                }
            }
            // Já tinha a local (quem pediu já usa ela): nada a fazer.
            if self.get(&job.key).is_some() || self.has_failed(&job.key) {
                continue;
            }
            if !self.analyzer.models_available() {
                self.failed.lock().insert(job.key.clone());
                on_ready(&job.key, None);
                continue;
            }
            let cancel = Arc::new(AtomicBool::new(false));
            // Um pânico numa música (arquivo estranho, bug) não pode parar as
            // análises da sessão inteira: vira falha só dessa música.
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                downloads
                    .open(job.cache_key.as_deref(), &job.url, cancel)
                    .and_then(|opened| self.analyzer.analyze(&job.key, opened.source, job.ext.as_deref()))
            }))
            .unwrap_or_else(|_| Err(anyhow::anyhow!("pânico na análise")));
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
    // SAFETY: gettid e setpriority só leem inteiros; mexem só nesta thread.
    unsafe {
        let tid = libc::syscall(libc::SYS_gettid) as libc::id_t;
        libc::setpriority(libc::PRIO_PROCESS, tid, 10);
    }
}
