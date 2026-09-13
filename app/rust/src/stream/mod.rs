//! Streaming HTTP com cache em disco.
//!
//! Cada faixa remota vira um [`Download`]: uma thread baixa o arquivo para
//! `<cache>/<hash>.part` enquanto um ou mais leitores ([`HttpSource`]) leem dele.
//! O leitor bloqueia até os bytes que precisa chegarem. Se ele pular para uma
//! região distante (seek, ou o symphonia lendo tags no fim do arquivo), o
//! downloader reconecta com `Range:` a partir dali, então o seek é imediato
//! mesmo com o download pela metade. Quando termina, o arquivo vira
//! `<hash>.audio` e as próximas reproduções saem do disco.

mod rangeset;

pub use rangeset::RangeSet;

use std::collections::HashMap;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, SystemTime};

use anyhow::{anyhow, Result};
use parking_lot::{Condvar, Mutex};
use symphonia::core::io::MediaSource;

/// Se o leitor pedir um byte além disto à frente do downloader, reconecta ali.
const REDIRECT_WINDOW: u64 = 512 * 1024;
const CHUNK: usize = 64 * 1024;

pub fn fnv1a64(s: &str) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in s.as_bytes() {
        h ^= *b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

#[derive(Debug, Default)]
struct DlState {
    ranges: RangeSet,
    total_len: Option<u64>,
    headers_known: bool,
    supports_ranges: bool,
    complete: bool,
    error: Option<String>,
    want_pos: u64,
    content_type: Option<String>,
}

pub struct Download {
    pub key: String,
    url: String,
    part_path: PathBuf,
    final_path: PathBuf,
    state: Mutex<DlState>,
    cond: Condvar,
    cancel: AtomicBool,
}

impl Download {
    /// Fração baixada (0..1), se o tamanho é conhecido.
    pub fn progress(&self) -> Option<f32> {
        let st = self.state.lock();
        if st.complete {
            return Some(1.0);
        }
        st.total_len
            .filter(|t| *t > 0)
            .map(|t| (st.ranges.covered() as f64 / t as f64) as f32)
    }

    pub fn is_complete(&self) -> bool {
        self.state.lock().complete
    }

    pub fn error(&self) -> Option<String> {
        self.state.lock().error.clone()
    }

    pub fn content_type(&self) -> Option<String> {
        self.state.lock().content_type.clone()
    }

    pub fn cancel(&self) {
        self.cancel.store(true, Ordering::Relaxed);
        self.cond.notify_all();
    }

    fn set_error(&self, msg: String) {
        let mut st = self.state.lock();
        st.error = Some(msg);
        st.headers_known = true;
        self.cond.notify_all();
    }

    fn run(self: Arc<Self>, agent: ureq::Agent) {
        let mut file = match OpenOptions::new().write(true).open(&self.part_path)
        {
            Ok(f) => f,
            Err(e) => return self.set_error(format!("cache: {e}")),
        };
        let mut failures = 0u32;

        loop {
            if self.cancel.load(Ordering::Relaxed) {
                return;
            }
            // Escolhe de onde baixar: primeiro o que o leitor está esperando,
            // depois qualquer buraco que sobrou desde o início.
            let start = {
                let st = self.state.lock();
                match st.total_len {
                    Some(t) => {
                        match st
                            .ranges
                            .first_missing_from(st.want_pos, t)
                            .or_else(|| st.ranges.first_missing_from(0, t))
                        {
                            Some(s) => s,
                            None => {
                                drop(st);
                                self.finish(&mut file);
                                return;
                            }
                        }
                    }
                    None => st.ranges.contiguous_end(0).unwrap_or(0),
                }
            };

            let mut req = agent.get(&self.url);
            if start > 0 {
                req = req.header("Range", format!("bytes={start}-"));
            }
            let resp = match req.call() {
                Ok(r) => r,
                Err(ureq::Error::StatusCode(code)) => {
                    return self.set_error(format!("HTTP {code}"));
                }
                Err(e) => {
                    failures += 1;
                    if failures > 5 {
                        return self.set_error(format!("rede: {e}"));
                    }
                    std::thread::sleep(Duration::from_millis(300 * failures as u64));
                    continue;
                }
            };

            let status = resp.status().as_u16();
            let header = |name: &str| {
                resp.headers()
                    .get(name)
                    .and_then(|v| v.to_str().ok())
                    .map(|s| s.to_string())
            };
            let content_type = header("content-type");
            let content_length = header("content-length").and_then(|v| v.parse::<u64>().ok());
            let (write_pos, total, ranged) = if status == 206 {
                let total = header("content-range")
                    .and_then(|cr| cr.rsplit('/').next().and_then(|t| t.trim().parse::<u64>().ok()));
                (start, total, true)
            } else {
                let ranged = header("accept-ranges").is_some_and(|v| v.contains("bytes"));
                (0, content_length, ranged)
            };
            {
                let mut st = self.state.lock();
                if total.is_some() {
                    st.total_len = total;
                }
                st.supports_ranges = ranged;
                st.content_type = content_type;
                st.headers_known = true;
                self.cond.notify_all();
            }

            let mut reader = resp.into_body().into_reader();
            let mut pos = write_pos;
            if let Err(e) = file.seek(SeekFrom::Start(pos)) {
                return self.set_error(format!("cache: {e}"));
            }
            let mut buf = vec![0u8; CHUNK];
            let mut conn_eof = false;
            loop {
                if self.cancel.load(Ordering::Relaxed) {
                    return;
                }
                let n = match reader.read(&mut buf) {
                    Ok(0) => {
                        conn_eof = true;
                        break;
                    }
                    Ok(n) => n,
                    Err(_) => {
                        failures += 1;
                        break;
                    }
                };
                if let Err(e) = file.write_all(&buf[..n]) {
                    return self.set_error(format!("cache: {e}"));
                }
                let chunk_start = pos;
                pos += n as u64;
                failures = 0;

                let mut st = self.state.lock();
                st.ranges.insert(chunk_start, pos);
                self.cond.notify_all();
                let want = st.want_pos;
                let want_missing = st.total_len.is_none_or(|t| want < t) && !st.ranges.contains(want);
                // Só dá pra pular numa conexão com Range (206); sem isso, lê até o fim.
                if status == 206 {
                    let redirect = want_missing && (want < write_pos || want > pos + REDIRECT_WINDOW);
                    if redirect || st.ranges.contiguous_end(pos).is_some() {
                        break;
                    }
                }
            }

            if conn_eof {
                let mut st = self.state.lock();
                if st.total_len.is_none() {
                    st.total_len = Some(pos);
                }
                self.cond.notify_all();
            }
            if failures > 5 {
                return self.set_error("rede: conexão caiu várias vezes".into());
            }
            if failures > 0 {
                std::thread::sleep(Duration::from_millis(300 * failures as u64));
            }
        }
    }

    fn finish(&self, file: &mut File) {
        let _ = file.flush();
        let renamed = fs::rename(&self.part_path, &self.final_path).is_ok();
        let mut st = self.state.lock();
        st.complete = true;
        if !renamed {
            log::warn!("não consegui renomear {:?}", self.part_path);
        }
        self.cond.notify_all();
    }
}

/// Leitor bloqueante de um [`Download`] em andamento. Implementa `MediaSource`.
pub struct HttpSource {
    dl: Arc<Download>,
    file: File,
    pos: u64,
    cancel: Arc<AtomicBool>,
}

impl HttpSource {
    fn wait_headers(&self) -> io::Result<()> {
        let mut st = self.dl.state.lock();
        while !st.headers_known {
            if self.cancel.load(Ordering::Relaxed) {
                return Err(io::Error::new(io::ErrorKind::Interrupted, "cancelado"));
            }
            self.dl.cond.wait_for(&mut st, Duration::from_millis(100));
        }
        match &st.error {
            Some(e) if st.total_len.is_none() => Err(io::Error::other(e.clone())),
            _ => Ok(()),
        }
    }
}

impl Read for HttpSource {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        if buf.is_empty() {
            return Ok(0);
        }
        let mut st = self.dl.state.lock();
        loop {
            if let Some(end) = st.ranges.contiguous_end(self.pos) {
                let n = (buf.len() as u64).min(end - self.pos) as usize;
                drop(st);
                self.file.seek(SeekFrom::Start(self.pos))?;
                self.file.read_exact(&mut buf[..n])?;
                self.pos += n as u64;
                return Ok(n);
            }
            if st.total_len.is_some_and(|t| self.pos >= t) || (st.complete && st.total_len.is_none()) {
                return Ok(0);
            }
            if let Some(e) = &st.error {
                return Err(io::Error::other(e.clone()));
            }
            if self.cancel.load(Ordering::Relaxed) || self.dl.cancel.load(Ordering::Relaxed) {
                return Err(io::Error::new(io::ErrorKind::Interrupted, "cancelado"));
            }
            if st.want_pos != self.pos {
                st.want_pos = self.pos;
                self.dl.cond.notify_all();
            }
            self.dl.cond.wait_for(&mut st, Duration::from_millis(100));
        }
    }
}

impl Seek for HttpSource {
    fn seek(&mut self, pos: SeekFrom) -> io::Result<u64> {
        let new = match pos {
            SeekFrom::Start(p) => p as i128,
            SeekFrom::Current(d) => self.pos as i128 + d as i128,
            SeekFrom::End(d) => {
                self.wait_headers()?;
                let total = self.dl.state.lock().total_len.ok_or_else(|| {
                    io::Error::new(io::ErrorKind::Unsupported, "tamanho desconhecido")
                })?;
                total as i128 + d as i128
            }
        };
        if new < 0 {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "seek negativo"));
        }
        self.pos = new as u64;
        Ok(self.pos)
    }
}

impl MediaSource for HttpSource {
    fn is_seekable(&self) -> bool {
        self.wait_headers().is_ok() && self.dl.state.lock().total_len.is_some()
    }

    fn byte_len(&self) -> Option<u64> {
        self.wait_headers().ok()?;
        self.dl.state.lock().total_len
    }
}

/// Uma fonte aberta para tocar: o `MediaSource` + o download (se remoto).
pub struct OpenedSource {
    pub source: Box<dyn MediaSource>,
    pub download: Option<Arc<Download>>,
    pub content_type: Option<String>,
}

pub struct DownloadManager {
    cache_dir: PathBuf,
    agent: ureq::Agent,
    active: Mutex<HashMap<String, Arc<Download>>>,
    limit_bytes: AtomicU64,
    /// Faixas baixadas para ouvir offline: nunca saem do cache.
    pinned: Mutex<std::collections::HashSet<String>>,
    /// Fila de downloads offline (um de cada vez).
    offline_queue: Mutex<std::collections::VecDeque<(String, String)>>,
    offline_cond: Condvar,
}

impl DownloadManager {
    pub fn new(cache_dir: impl Into<PathBuf>, limit_bytes: u64) -> Result<Self> {
        let cache_dir = cache_dir.into();
        fs::create_dir_all(&cache_dir)?;
        // Downloads parciais de sessões anteriores não têm mapa de intervalos: descarta.
        if let Ok(rd) = fs::read_dir(&cache_dir) {
            for e in rd.flatten() {
                if e.path().extension().is_some_and(|x| x == "part") {
                    let _ = fs::remove_file(e.path());
                }
            }
        }
        let config = ureq::Agent::config_builder()
            .timeout_connect(Some(Duration::from_secs(10)))
            .timeout_recv_response(Some(Duration::from_secs(30)))
            .user_agent(concat!("BKplayer/", env!("CARGO_PKG_VERSION")))
            .build();
        let pinned: std::collections::HashSet<String> = fs::read(cache_dir.join("pinned.json"))
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or_default();
        Ok(Self {
            cache_dir,
            agent: config.into(),
            active: Mutex::new(HashMap::new()),
            limit_bytes: AtomicU64::new(limit_bytes),
            pinned: Mutex::new(pinned),
            offline_queue: Mutex::new(std::collections::VecDeque::new()),
            offline_cond: Condvar::new(),
        })
    }

    fn save_pinned(&self) {
        let list: Vec<String> = self.pinned.lock().iter().cloned().collect();
        if let Ok(json) = serde_json::to_vec(&list) {
            let _ = fs::write(self.cache_dir.join("pinned.json"), json);
        }
    }

    /// Marca faixas para ouvir offline e enfileira os downloads.
    pub fn pin(self: &Arc<Self>, tracks: Vec<(String, String)>) {
        {
            let mut pinned = self.pinned.lock();
            for (k, _) in &tracks {
                pinned.insert(k.clone());
            }
        }
        self.save_pinned();
        let mut q = self.offline_queue.lock();
        for t in tracks {
            if !self.is_cached(&t.0) && !q.iter().any(|(k, _)| *k == t.0) {
                q.push_back(t);
            }
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
        self.offline_queue.lock().retain(|(k, _)| !keys.contains(k));
        for k in keys {
            let _ = fs::remove_file(self.paths(k).1);
        }
    }

    pub fn is_pinned(&self, key: &str) -> bool {
        self.pinned.lock().contains(key)
    }

    /// Thread que baixa a fila offline, uma faixa por vez.
    pub fn start_offline_worker(self: &Arc<Self>) {
        let me = Arc::downgrade(self);
        let _ = std::thread::Builder::new().name("offline".into()).spawn(move || loop {
            let Some(mgr) = me.upgrade() else { return };
            let job = {
                let mut q = mgr.offline_queue.lock();
                if q.is_empty() {
                    mgr.offline_cond.wait_for(&mut q, Duration::from_secs(2));
                }
                q.pop_front()
            };
            let Some((key, url)) = job else { continue };
            if mgr.is_cached(&key) || !mgr.is_pinned(&key) {
                continue;
            }
            if let Some(dl) = mgr.ensure_download(&key, &url) {
                drop(mgr);
                // Espera terminar (ou falhar) antes do próximo.
                loop {
                    if dl.is_complete() || dl.error().is_some() {
                        break;
                    }
                    std::thread::sleep(Duration::from_millis(300));
                }
            }
        });
    }

    pub fn set_limit(&self, bytes: u64) {
        self.limit_bytes.store(bytes, Ordering::Relaxed);
    }

    fn paths(&self, key: &str) -> (PathBuf, PathBuf) {
        let h = format!("{:016x}", fnv1a64(key));
        (
            self.cache_dir.join(format!("{h}.part")),
            self.cache_dir.join(format!("{h}.audio")),
        )
    }

    pub fn is_cached(&self, key: &str) -> bool {
        self.paths(key).1.exists()
    }

    fn is_local(url: &str) -> Option<PathBuf> {
        if let Some(p) = url.strip_prefix("file://") {
            return Some(PathBuf::from(p));
        }
        if !url.contains("://") {
            return Some(PathBuf::from(url));
        }
        None
    }

    /// Garante que o download existe (ou já está em cache). Retorna `None` se é arquivo local ou já em cache.
    fn ensure_download(&self, key: &str, url: &str) -> Option<Arc<Download>> {
        let (part, fin) = self.paths(key);
        let mut active = self.active.lock();
        if let Some(dl) = active.get(key) {
            if dl.error().is_none() {
                return Some(dl.clone());
            }
            active.remove(key);
        }
        if fin.exists() {
            return None;
        }
        // Cria o .part antes da thread, para leitores poderem abrir na hora.
        if let Err(e) = File::create(&part) {
            log::warn!("cache: {e}");
            return None;
        }
        let dl = Arc::new(Download {
            key: key.to_string(),
            url: url.to_string(),
            part_path: part,
            final_path: fin,
            state: Mutex::new(DlState::default()),
            cond: Condvar::new(),
            cancel: AtomicBool::new(false),
        });
        active.insert(key.to_string(), dl.clone());
        let agent = self.agent.clone();
        let runner = dl.clone();
        std::thread::Builder::new()
            .name("download".into())
            .spawn(move || runner.run(agent))
            .ok()?;
        Some(dl)
    }

    /// Abre uma fonte para leitura. `cancel` interrompe leituras bloqueadas.
    pub fn open(&self, key: Option<&str>, url: &str, cancel: Arc<AtomicBool>) -> Result<OpenedSource> {
        if let Some(path) = Self::is_local(url) {
            let f = File::open(&path).map_err(|e| anyhow!("abrir {path:?}: {e}"))?;
            return Ok(OpenedSource { source: Box::new(f), download: None, content_type: None });
        }
        let key = key.map(str::to_string).unwrap_or_else(|| format!("url:{url}"));
        match self.ensure_download(&key, url) {
            None => {
                let (_, fin) = self.paths(&key);
                let f = File::open(&fin)?;
                let _ = f.set_modified(SystemTime::now());
                Ok(OpenedSource { source: Box::new(f), download: None, content_type: None })
            }
            Some(dl) => {
                // Pode ter acabado de completar e renomear: tenta o .part e cai pro final.
                let file = File::open(&dl.part_path).or_else(|_| File::open(&dl.final_path))?;
                let content_type = dl.content_type();
                Ok(OpenedSource {
                    source: Box::new(HttpSource { dl: dl.clone(), file, pos: 0, cancel }),
                    download: Some(dl),
                    content_type,
                })
            }
        }
    }

    /// Começa a baixar em segundo plano (pré-carregamento da próxima faixa).
    pub fn prefetch(&self, key: &str, url: &str) {
        if Self::is_local(url).is_none() {
            self.ensure_download(key, url);
        }
    }

    pub fn cancel(&self, key: &str) {
        if let Some(dl) = self.active.lock().remove(key) {
            dl.cancel();
        }
    }

    /// Remove downloads terminados da lista ativa e aplica o limite do cache.
    pub fn gc(&self, keep: &[String]) {
        let finished: Vec<String> = {
            let active = self.active.lock();
            active
                .iter()
                .filter(|(k, d)| {
                    (d.is_complete() || d.error().is_some())
                        && Arc::strong_count(d) == 1
                        && !keep.contains(k)
                })
                .map(|(k, _)| k.clone())
                .collect()
        };
        if !finished.is_empty() {
            let mut active = self.active.lock();
            for k in &finished {
                active.remove(k);
            }
            drop(active);
            self.evict(keep);
        }
    }

    pub fn evict(&self, keep: &[String]) {
        let limit = self.limit_bytes.load(Ordering::Relaxed);
        let pinned: Vec<String> = self.pinned.lock().iter().cloned().collect();
        let protected: Vec<PathBuf> = keep
            .iter()
            .chain(self.active.lock().keys())
            .chain(pinned.iter())
            .map(|k| self.paths(k).1)
            .collect();
        let mut files: Vec<(PathBuf, u64, SystemTime)> = match fs::read_dir(&self.cache_dir) {
            Ok(rd) => rd
                .flatten()
                .filter(|e| e.path().extension().is_some_and(|x| x == "audio"))
                .filter_map(|e| {
                    let m = e.metadata().ok()?;
                    Some((e.path(), m.len(), m.modified().unwrap_or(SystemTime::UNIX_EPOCH)))
                })
                .collect(),
            Err(_) => return,
        };
        // O limite vale para o cache comum; as offline não contam.
        let mut total: u64 = files.iter().filter(|f| !protected.contains(&f.0)).map(|f| f.1).sum();
        if total <= limit {
            return;
        }
        files.sort_by_key(|f| f.2);
        let target = limit / 10 * 9;
        for (path, len, _) in files {
            if total <= target {
                break;
            }
            if protected.contains(&path) {
                continue;
            }
            if fs::remove_file(&path).is_ok() {
                total -= len;
            }
        }
    }

    pub fn cache_size(&self) -> u64 {
        dir_size(&self.cache_dir)
    }

    /// Limpa o cache comum (mantém downloads em andamento e as offline).
    pub fn clear(&self) {
        let mut keep: Vec<PathBuf> = self.active.lock().keys().map(|k| self.paths(k).0).collect();
        keep.extend(self.pinned.lock().iter().map(|k| self.paths(k).1));
        keep.push(self.cache_dir.join("pinned.json"));
        if let Ok(rd) = fs::read_dir(&self.cache_dir) {
            for e in rd.flatten() {
                if !keep.contains(&e.path()) {
                    let _ = fs::remove_file(e.path());
                }
            }
        }
    }
}

fn dir_size(p: &Path) -> u64 {
    fs::read_dir(p)
        .map(|rd| rd.flatten().filter_map(|e| e.metadata().ok()).map(|m| m.len()).sum())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufRead, BufReader};
    use std::net::TcpListener;

    /// Servidor HTTP mínimo com suporte a Range, para testar sem rede.
    fn serve(data: Arc<Vec<u8>>, ranges: bool) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        std::thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                let data = data.clone();
                std::thread::spawn(move || {
                    let mut reader = BufReader::new(stream.try_clone().unwrap());
                    let mut range_start = None;
                    loop {
                        let mut line = String::new();
                        if reader.read_line(&mut line).unwrap_or(0) == 0 || line == "\r\n" {
                            break;
                        }
                        let lower = line.to_ascii_lowercase();
                        if let Some(r) = lower.strip_prefix("range: bytes=") {
                            range_start = r.trim().trim_end_matches('-').parse::<usize>().ok();
                        }
                    }
                    let mut s = stream;
                    let (status, body) = match (ranges, range_start) {
                        (true, Some(st)) => (
                            format!(
                                "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes {}-{}/{}\r\n",
                                st,
                                data.len() - 1,
                                data.len()
                            ),
                            &data[st..],
                        ),
                        _ => (
                            format!(
                                "HTTP/1.1 200 OK\r\n{}",
                                if ranges { "Accept-Ranges: bytes\r\n" } else { "" }
                            ),
                            &data[..],
                        ),
                    };
                    let head = format!(
                        "{status}Content-Length: {}\r\nContent-Type: audio/flac\r\nConnection: close\r\n\r\n",
                        body.len()
                    );
                    let _ = s.write_all(head.as_bytes());
                    for c in body.chunks(8192) {
                        if s.write_all(c).is_err() {
                            return;
                        }
                        std::thread::sleep(Duration::from_micros(200));
                    }
                });
            }
        });
        format!("http://{addr}/stream")
    }

    fn tmpdir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("player-test-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn data(n: usize) -> Arc<Vec<u8>> {
        Arc::new((0..n).map(|i| (i * 31 % 251) as u8).collect())
    }

    #[test]
    fn sequential_read_matches() {
        let d = data(3_000_000);
        let url = serve(d.clone(), true);
        let mgr = DownloadManager::new(tmpdir("seq"), u64::MAX).unwrap();
        let mut src = mgr.open(Some("k1"), &url, Arc::new(AtomicBool::new(false))).unwrap().source;
        assert_eq!(src.byte_len(), Some(d.len() as u64));
        let mut out = Vec::new();
        src.read_to_end(&mut out).unwrap();
        assert_eq!(out, *d);
    }

    #[test]
    fn seek_far_ahead_and_tail() {
        let d = data(4_000_000);
        let url = serve(d.clone(), true);
        let mgr = DownloadManager::new(tmpdir("seek"), u64::MAX).unwrap();
        let mut src = mgr.open(Some("k2"), &url, Arc::new(AtomicBool::new(false))).unwrap().source;
        // Lê o final (como o probe de tags do symphonia), depois o meio, depois o começo.
        src.seek(SeekFrom::End(-128)).unwrap();
        let mut tail = vec![0u8; 128];
        src.read_exact(&mut tail).unwrap();
        assert_eq!(&tail[..], &d[d.len() - 128..]);
        src.seek(SeekFrom::Start(2_500_000)).unwrap();
        let mut mid = vec![0u8; 1000];
        src.read_exact(&mut mid).unwrap();
        assert_eq!(&mid[..], &d[2_500_000..2_501_000]);
        src.seek(SeekFrom::Start(0)).unwrap();
        let mut all = Vec::new();
        src.read_to_end(&mut all).unwrap();
        assert_eq!(all, *d);
        // Espera completar e virar arquivo de cache.
        for _ in 0..100 {
            if mgr.is_cached("k2") {
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        assert!(mgr.is_cached("k2"));
    }

    #[test]
    fn server_without_ranges() {
        let d = data(1_000_000);
        let url = serve(d.clone(), false);
        let mgr = DownloadManager::new(tmpdir("norange"), u64::MAX).unwrap();
        let mut src = mgr.open(Some("k3"), &url, Arc::new(AtomicBool::new(false))).unwrap().source;
        src.seek(SeekFrom::Start(900_000)).unwrap();
        let mut buf = vec![0u8; 1000];
        src.read_exact(&mut buf).unwrap();
        assert_eq!(&buf[..], &d[900_000..901_000]);
    }
}
