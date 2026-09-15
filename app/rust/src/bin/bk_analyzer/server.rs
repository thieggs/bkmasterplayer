//! Coordenador: servidor HTTP com o painel, a API dos players (análises
//! prontas, com o login do Navidrome) e a dos trabalhadores (token próprio).

use std::collections::HashMap;
use std::io::{Cursor, Read, Write};
use std::net::IpAddr;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{anyhow, Result};
use parking_lot::Mutex;
use player_engine::engine::analysis::{TrackAnalysis, ANALYSIS_VERSION};
use serde::Deserialize;
use serde_json::{json, Value};
use tiny_http::{Header, Method, Request, Response, StatusCode};

use crate::navidrome::{self, Login, Navidrome};
use crate::store::{Outcome, Store, WorkerInfo};

const DASHBOARD: &str = include_str!("dashboard.html");
const SYNC_EVERY: Duration = Duration::from_secs(3600);
const COOKIE: &str = "bka";
/// Pedidos atendidos ao mesmo tempo (cada um numa thread): acima disso, 503.
const MAX_IN_FLIGHT: usize = 256;
/// Logins de player errados por endereço em 5 min antes de parar de perguntar
/// ao Navidrome (sem isso, o coordenador serviria para chutar senhas).
const MAX_PLAYER_FAILURES: u32 = 20;

type Resp = Response<Box<dyn Read + Send>>;
/// Login de player (u, t, s) → (vale?, quando foi conferido).
type PlayerAuthCache = HashMap<(String, String, String), (bool, Instant)>;

static STOP: AtomicBool = AtomicBool::new(false);
static IN_FLIGHT: AtomicUsize = AtomicUsize::new(0);

extern "C" fn on_signal(_: libc::c_int) {
    STOP.store(true, Ordering::SeqCst);
}

struct App {
    store: Store,
    /// Logins de players já conferidos no Navidrome: (u, t, s) → (vale?, quando).
    player_auth: Mutex<PlayerAuthCache>,
    /// Senhas erradas por endereço (contra chute de senha).
    failures: Mutex<HashMap<IpAddr, (u32, Instant)>>,
    /// Logins de player errados por endereço.
    player_failures: Mutex<HashMap<IpAddr, (u32, Instant)>>,
}

pub fn serve(dir: &Path, listen: &str) -> Result<()> {
    let app = Arc::new(App {
        store: Store::open(dir)?,
        player_auth: Mutex::new(HashMap::new()),
        failures: Mutex::new(HashMap::new()),
        player_failures: Mutex::new(HashMap::new()),
    });
    let http = tiny_http::Server::http(listen).map_err(|e| anyhow!("não deu para abrir {listen}: {e}"))?;
    eprintln!("BK Analyzer v{} no ar em http://{listen} (dados em {})", env!("CARGO_PKG_VERSION"), dir.display());
    // SAFETY: o tratador só grava num AtomicBool (seguro dentro de um sinal).
    unsafe {
        libc::signal(libc::SIGTERM, on_signal as extern "C" fn(libc::c_int) as libc::sighandler_t);
        libc::signal(libc::SIGINT, on_signal as extern "C" fn(libc::c_int) as libc::sighandler_t);
    }
    {
        let app = app.clone();
        std::thread::spawn(move || loop {
            std::thread::sleep(Duration::from_secs(5));
            if let Err(e) = app.store.save() {
                eprintln!("não deu para gravar o estado: {e:#}");
            }
        });
    }
    {
        let app = app.clone();
        std::thread::spawn(move || loop {
            if app.store.sync_due(SYNC_EVERY) {
                app.sync();
            }
            std::thread::sleep(Duration::from_secs(3));
        });
    }
    while !STOP.load(Ordering::SeqCst) {
        match http.recv_timeout(Duration::from_millis(500)) {
            Ok(Some(req)) => {
                if IN_FLIGHT.fetch_add(1, Ordering::SeqCst) >= MAX_IN_FLIGHT {
                    IN_FLIGHT.fetch_sub(1, Ordering::SeqCst);
                    let _ = req.respond(err(503, "ocupado; tente de novo"));
                    continue;
                }
                let app = app.clone();
                std::thread::spawn(move || {
                    app.handle(req);
                    IN_FLIGHT.fetch_sub(1, Ordering::SeqCst);
                });
            }
            Ok(None) => {}
            Err(e) => eprintln!("conexão: {e}"),
        }
    }
    eprintln!("saindo");
    app.store.save()
}

impl App {
    fn sync(&self) {
        let Some(login) = self.store.config().navidrome else { return };
        self.store.sync_started();
        match Navidrome::new(login).songs() {
            Ok(list) if list.is_empty() => {
                // Navidrome reindexando ou pasta desmontada: não apaga nada.
                self.store.sync_failed("o Navidrome devolveu a biblioteca vazia; a lista anterior foi mantida".into())
            }
            Ok(list) => self.store.sync(list),
            Err(e) => {
                eprintln!("sincronização falhou: {e:#}");
                self.store.sync_failed(format!("{e:#}"));
            }
        }
    }

    fn handle(&self, mut req: Request) {
        let url = req.url().to_string();
        let (path, query) = url.split_once('?').unwrap_or((&url, ""));
        let q = parse_query(query);
        let method = req.method().clone();
        let resp = match (&method, path) {
            (Method::Get, "/") | (Method::Get, "/index.html") => page(),
            (Method::Get, "/favicon.svg") | (Method::Get, "/favicon.ico") => bytes(200, "image/svg+xml", FAVICON.as_bytes().to_vec()),
            (Method::Get, "/api/hello") => json_resp(
                200,
                &json!({"app": "bk-analyzer", "version": env!("CARGO_PKG_VERSION"), "analysis_version": ANALYSIS_VERSION,
                        "configured": self.store.config().navidrome.is_some()}),
            ),
            (Method::Post, "/api/login") => self.login(&mut req),
            (Method::Post, "/api/logout") => {
                if let Some(t) = cookie(&req) {
                    self.store.end_session(&t);
                }
                json_resp(200, &json!({})).with_header(hdr("Set-Cookie", &format!("{COOKIE}=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict")))
            }
            (_, p) if p.starts_with("/api/worker/") => self.worker_api(&mut req, &method, &p["/api/worker/".len()..]),
            (Method::Get, p) if p.starts_with("/api/analysis/") => self.analysis(&req, &pct_decode(&p["/api/analysis/".len()..]), &q),
            (Method::Get, "/api/summary") if self.player_ok(&req, &q) => {
                let s = self.store.status();
                json_resp(200, &json!({"total": s["total"], "counts": s["counts"], "analysis_version": ANALYSIS_VERSION,
                    "workers_online": s["workers"].as_array().map(|w| w.iter().filter(|x| x["online"] == true).count()).unwrap_or(0)}))
            }
            (_, p) if p.starts_with("/api/") => match self.session(&req) {
                Some(user) => self.panel_api(&mut req, &method, p, &q, &user),
                None => err(401, "entre com a sua conta do Navidrome"),
            },
            _ => err(404, "não existe"),
        };
        let _ = req.respond(resp);
    }

    fn session(&self, req: &Request) -> Option<String> {
        self.store.session_user(&cookie(req)?)
    }

    // ---------- painel ----------

    fn login(&self, req: &mut Request) -> Resp {
        let ip = req.remote_addr().map(|a| a.ip());
        if let Some(ip) = ip {
            let mut f = self.failures.lock();
            f.retain(|_, (_, at)| at.elapsed() < Duration::from_secs(300));
            if f.get(&ip).is_some_and(|(n, _)| *n >= 8) {
                return err(429, "muitas tentativas; espere uns minutos");
            }
        }
        let Ok(body) = body_json(req) else { return err(400, "pedido inválido") };
        let user = body["username"].as_str().unwrap_or("").trim().to_string();
        let pass = body["password"].as_str().unwrap_or("");
        if user.is_empty() || pass.is_empty() {
            return err(400, "preencha usuário e senha");
        }
        let current = self.store.config().navidrome;
        let change = body["url"].as_str().filter(|u| !u.trim().is_empty());
        // Primeira vez (ou trocando de servidor, já logado): o servidor vem do formulário.
        let first = current.is_none();
        if first && !ip.is_some_and(is_local) {
            return err(403, "a primeira configuração só pode ser feita da rede de casa");
        }
        if !first && change.is_some_and(|u| navidrome::normalize_url(u) != current.as_ref().unwrap().url) && self.session(req).is_none() {
            return err(403, "entre primeiro para trocar de servidor");
        }
        let url = match (change, &current) {
            (Some(u), _) => navidrome::normalize_url(u),
            (None, Some(l)) => l.url.clone(),
            (None, None) => "http://127.0.0.1:4533".into(),
        };
        let login = Login::from_password(&url, &user, pass);
        let nd = Navidrome::new(login.clone());
        if let Err(e) = nd.ping() {
            if let Some(ip) = ip {
                let mut f = self.failures.lock();
                let e = f.entry(ip).or_insert((0, Instant::now()));
                e.0 += 1;
                e.1 = Instant::now();
            }
            return err(401, &format!("{e:#}"));
        }
        let same_server = current.as_ref().is_some_and(|l| l.url == url);
        let owner = current.as_ref().is_some_and(|l| l.username == user);
        if same_server && !owner && !nd.is_admin().unwrap_or(false) {
            return err(403, "só o dono da biblioteca ou um administrador do Navidrome entra aqui");
        }
        // Dono (ou servidor novo): guarda o token novo (a senha pode ter mudado).
        if !same_server || owner {
            if let Err(e) = self.store.set_login(login) {
                return err(500, &format!("{e:#}"));
            }
        }
        let token = self.store.new_session(&user);
        json_resp(200, &json!({"user": user}))
            .with_header(hdr("Set-Cookie", &format!("{COOKIE}={token}; Path=/; Max-Age=2592000; HttpOnly; SameSite=Strict")))
    }

    fn panel_api(&self, req: &mut Request, method: &Method, path: &str, q: &HashMap<String, String>, user: &str) -> Resp {
        // POST só com JSON: formulário de outro site não consegue mandar.
        if *method == Method::Post && !header(req, "Content-Type").is_some_and(|c| c.starts_with("application/json")) {
            return err(415, "use JSON");
        }
        match (method, path) {
            (Method::Get, "/api/state") => {
                let mut s = self.store.status();
                s["user"] = json!(user);
                json_resp(200, &s)
            }
            (Method::Get, "/api/songs") => {
                let num = |k: &str, d: usize| q.get(k).and_then(|v| v.parse().ok()).unwrap_or(d);
                let cat = q.get("cat").map(String::as_str).unwrap_or("problems");
                json_resp(200, &self.store.list(cat, q.get("q").map(String::as_str).unwrap_or(""), num("offset", 0), num("limit", 100).min(500)))
            }
            (Method::Post, "/api/retry") => {
                let Ok(body) = body_json(req) else { return err(400, "pedido inválido") };
                let ids: Vec<String> = body["ids"].as_array().map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect()).unwrap_or_default();
                let cat = body["category"].as_str();
                let n = self.store.retry(&ids, cat);
                json_resp(200, &json!({"queued": n}))
            }
            (Method::Post, "/api/sync") => {
                self.store.request_sync();
                json_resp(200, &json!({}))
            }
            (Method::Post, "/api/pause") => {
                let Ok(body) = body_json(req) else { return err(400, "pedido inválido") };
                match self.store.set_paused(body["paused"].as_bool().unwrap_or(true)) {
                    Ok(()) => json_resp(200, &json!({})),
                    Err(e) => err(500, &format!("{e:#}")),
                }
            }
            (Method::Post, "/api/worker-prefs") => {
                let Ok(body) = body_json(req) else { return err(400, "pedido inválido") };
                let Some(name) = body["name"].as_str() else { return err(400, "falta o nome do trabalhador") };
                let jobs = body.get("jobs").map(|j| j.as_u64().map(|n| n as u32));
                match self.store.set_worker(name, jobs, body["paused"].as_bool()) {
                    Ok(()) => json_resp(200, &json!({})),
                    Err(e) => err(500, &format!("{e:#}")),
                }
            }
            (Method::Get, "/api/worker-setup") => json_resp(200, &json!({"token": self.store.worker_token()})),
            _ => err(404, "não existe"),
        }
    }

    // ---------- players ----------

    /// Login de player (u/t/s da API Subsonic), conferido no Navidrome e
    /// lembrado por 10 min (errado: por 30 s).
    fn player_ok(&self, req: &Request, q: &HashMap<String, String>) -> bool {
        let key = match (q.get("u"), q.get("t"), q.get("s"), q.get("apiKey")) {
            (Some(u), Some(t), Some(s), _) => (u.clone(), t.clone(), s.clone()),
            (_, _, _, Some(k)) => (String::new(), String::new(), k.clone()),
            _ => return false,
        };
        if let Some((ok, at)) = self.player_auth.lock().get(&key) {
            if at.elapsed() < if *ok { Duration::from_secs(600) } else { Duration::from_secs(30) } {
                return *ok;
            }
        }
        let ip = req.remote_addr().map(|a| a.ip());
        if let Some(ip) = ip {
            let mut f = self.player_failures.lock();
            f.retain(|_, (_, at)| at.elapsed() < Duration::from_secs(300));
            if f.get(&ip).is_some_and(|(n, _)| *n >= MAX_PLAYER_FAILURES) {
                return false;
            }
        }
        let Some(login) = self.store.config().navidrome else { return false };
        let ok = if key.0.is_empty() { navidrome::check_key(&login.url, &key.2) } else { navidrome::check(&login.url, &key.0, &key.1, &key.2) }.is_ok();
        if let (false, Some(ip)) = (ok, ip) {
            let mut f = self.player_failures.lock();
            let e = f.entry(ip).or_insert((0, Instant::now()));
            e.0 += 1;
            e.1 = Instant::now();
        }
        let mut cache = self.player_auth.lock();
        if cache.len() > 1000 {
            cache.clear();
        }
        cache.insert(key, (ok, Instant::now()));
        ok
    }

    fn analysis(&self, req: &Request, id: &str, q: &HashMap<String, String>) -> Resp {
        if self.session(req).is_none() && !self.player_ok(req, q) {
            return err(401, "login do Navidrome inválido");
        }
        match self.store.analysis(id) {
            Some(data) => {
                let gzip = header(req, "Accept-Encoding").is_some_and(|a| a.contains("gzip"));
                if gzip {
                    let mut enc = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
                    if enc.write_all(&data).is_ok() {
                        if let Ok(z) = enc.finish() {
                            return bytes(200, "application/json", z).with_header(hdr("Content-Encoding", "gzip"));
                        }
                    }
                }
                bytes(200, "application/json", data)
            }
            None => {
                let state = self.store.bump(id);
                let s = match state {
                    Some(crate::store::State::Pending) => "pending",
                    Some(crate::store::State::Failed) => "failed",
                    Some(crate::store::State::Done) => "old",
                    None => "unknown",
                };
                // Na frente da fila e com trabalhador ligado: sai em segundos.
                let soon = s == "pending" && self.store.worker_ready();
                json_resp(404, &json!({"state": s, "soon": soon}))
            }
        }
    }

    // ---------- trabalhadores ----------

    fn worker_api(&self, req: &mut Request, method: &Method, rest: &str) -> Resp {
        let expected = format!("Bearer {}", self.store.worker_token());
        if !header(req, "Authorization").is_some_and(|h| const_eq(h.as_bytes(), expected.as_bytes())) {
            return err(401, "token de trabalhador inválido");
        }
        let (action, id) = rest.split_once('/').map(|(a, b)| (a, pct_decode(b))).unwrap_or((rest, String::new()));
        match (method, action) {
            (Method::Post, "claim") => {
                let Ok(b) = body_json(req) else { return err(400, "pedido inválido") };
                if b["analysis_version"].as_u64() != Some(ANALYSIS_VERSION as u64) {
                    return err(409, &format!("versão da análise diferente do coordenador ({ANALYSIS_VERSION}): atualize o trabalhador"));
                }
                let name = b["name"].as_str().unwrap_or("?").chars().take(40).collect::<String>();
                let info = WorkerInfo {
                    name: name.clone(),
                    model: b["model"].as_str().unwrap_or("").chars().take(20).collect(),
                    cpu: b["cpu"].as_str().unwrap_or("").chars().take(80).collect(),
                    jobs: b["jobs"].as_u64().unwrap_or(1) as u32,
                    slots: b["slots"].as_u64().unwrap_or(0) as u32,
                    last_seen: 0,
                    done: 0,
                    failed: 0,
                    secs_total: 0.0,
                    paused: b["paused"].as_str().map(|s| s.chars().take(60).collect()),
                    session: b["session"].as_str().unwrap_or("").chars().take(40).collect(),
                };
                match self.store.claim(&name, info) {
                    Ok(s) => json_resp(
                        200,
                        &json!({"id": s.id, "suffix": s.stream_format().unwrap_or(&s.suffix), "size": s.size, "title": s.title, "artist": s.artist, "duration": s.duration}),
                    ),
                    // Nada agora: diz quando perguntar de novo.
                    Err(wait) => bytes(204, "text/plain", Vec::new()).with_header(hdr("Retry-After", &wait.to_string())),
                }
            }
            (Method::Get, "audio") => {
                let Some(song) = self.store.song(&id) else { return err(404, "música fora da biblioteca") };
                let Some(login) = self.store.config().navidrome else { return err(503, "sem Navidrome configurado") };
                match Navidrome::new(login).stream(&id, song.stream_format()) {
                    Ok((len, ctype, body)) => {
                        let ctype = if ctype.is_ascii() && !ctype.contains(['\r', '\n']) { ctype.as_str() } else { "application/octet-stream" };
                        Response::new(StatusCode(200), vec![hdr("Content-Type", ctype)], body, len.map(|l| l as usize), None)
                    }
                    Err(e) => err(502, &format!("{e:#}")),
                }
            }
            (Method::Post, "beat") => {
                let Ok(b) = body_json(req) else { return err(400, "pedido inválido") };
                let mine = self.store.heartbeat(&id, b["name"].as_str().unwrap_or("?"));
                json_resp(if mine { 200 } else { 410 }, &json!({}))
            }
            (Method::Post, "done") => {
                #[derive(Deserialize)]
                struct Done {
                    name: String,
                    secs: f32,
                    model: String,
                    analysis: Option<TrackAnalysis>,
                    error: Option<String>,
                }
                let mut raw = Vec::new();
                if req.as_reader().take(32 << 20).read_to_end(&mut raw).is_err() {
                    return err(400, "pedido inválido");
                }
                let d: Done = match serde_json::from_slice(&raw) {
                    Ok(d) => d,
                    Err(e) => return err(400, &format!("resultado inválido: {e}")),
                };
                let outcome = match (d.analysis, d.error) {
                    (Some(a), _) if a.version == ANALYSIS_VERSION && a.is_sane() => Outcome::Ok(Box::new(a)),
                    (Some(a), _) if a.version == ANALYSIS_VERSION => Outcome::Err("análise com valores fora do possível".into()),
                    (Some(a), _) => Outcome::Err(format!("versão da análise {} (esperada {ANALYSIS_VERSION})", a.version)),
                    (None, e) => Outcome::Err(e.unwrap_or_else(|| "erro desconhecido".into())),
                };
                match self.store.finish(&id, &d.name, d.secs, &d.model, outcome) {
                    Ok(()) => json_resp(200, &json!({})),
                    Err(e) => err(500, &format!("{e:#}")),
                }
            }
            _ => err(404, "não existe"),
        }
    }
}

const FAVICON: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#6446c9"/><path d="M7 20v-4m4 8V12m4 10V8m4 12v-6m4 8V10m4 8v-2" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/></svg>"##;

fn page() -> Resp {
    bytes(200, "text/html; charset=utf-8", DASHBOARD.as_bytes().to_vec())
        .with_header(hdr(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'",
        ))
        .with_header(hdr("X-Content-Type-Options", "nosniff"))
}

fn hdr(k: &str, v: &str) -> Header {
    Header::from_bytes(k.as_bytes(), v.as_bytes()).expect("cabeçalho")
}

fn bytes(status: u16, ctype: &str, body: Vec<u8>) -> Resp {
    let len = body.len();
    Response::new(
        StatusCode(status),
        vec![hdr("Content-Type", ctype), hdr("Cache-Control", "no-store")],
        Box::new(Cursor::new(body)) as Box<dyn Read + Send>,
        Some(len),
        None,
    )
}

fn json_resp(status: u16, v: &Value) -> Resp {
    bytes(status, "application/json", serde_json::to_vec(v).unwrap_or_default())
}

fn err(status: u16, msg: &str) -> Resp {
    json_resp(status, &json!({"error": msg}))
}

fn header(req: &Request, name: &str) -> Option<String> {
    req.headers().iter().find(|h| h.field.as_str().as_str().eq_ignore_ascii_case(name)).map(|h| h.value.as_str().to_string())
}

fn cookie(req: &Request) -> Option<String> {
    let c = header(req, "Cookie")?;
    c.split(';').filter_map(|p| p.trim().strip_prefix(&format!("{COOKIE}="))).map(str::to_string).find(|v| !v.is_empty())
}

fn body_json(req: &mut Request) -> Result<Value> {
    let mut buf = Vec::new();
    req.as_reader().take(1 << 20).read_to_end(&mut buf)?;
    Ok(serde_json::from_slice(&buf)?)
}

fn const_eq(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

/// Rede de casa: loopback, faixas privadas, link-local e a Tailscale (100.64/10).
fn is_local(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v) => {
            let o = v.octets();
            v.is_loopback() || v.is_private() || v.is_link_local() || (o[0] == 100 && (64..128).contains(&o[1]))
        }
        IpAddr::V6(v) => {
            v.is_loopback() || (v.segments()[0] & 0xfe00) == 0xfc00 || (v.segments()[0] & 0xffc0) == 0xfe80 || v.to_ipv4_mapped().is_some_and(|m| is_local(IpAddr::V4(m)))
        }
    }
}

/// Decodifica %XX (e `+` como espaço, se `plus`: só na query).
fn decode(s: &str, plus: bool) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        let c = b[i];
        if c == b'%' && i + 2 < b.len() && b[i + 1].is_ascii_hexdigit() && b[i + 2].is_ascii_hexdigit() {
            let h = |x: u8| (x as char).to_digit(16).unwrap_or(0) as u8;
            out.push(h(b[i + 1]) * 16 + h(b[i + 2]));
            i += 3;
            continue;
        }
        out.push(if plus && c == b'+' { b' ' } else { c });
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn pct_decode(s: &str) -> String {
    decode(s, false)
}

fn parse_query(q: &str) -> HashMap<String, String> {
    q.split('&')
        .filter(|p| !p.is_empty())
        .map(|p| {
            let (k, v) = p.split_once('=').unwrap_or((p, ""));
            (decode(k, true), decode(v, true))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_query() {
        let q = parse_query("u=thi%20ago&t=abc&s=x%2By&q=a+b");
        assert_eq!(q["u"], "thi ago");
        assert_eq!(q["s"], "x+y");
        assert_eq!(q["q"], "a b");
        assert_eq!(pct_decode("abc%"), "abc%");
        assert_eq!(pct_decode("%4"), "%4");
        assert_eq!(pct_decode("%41%2"), "A%2");
        assert_eq!(pct_decode("a+b"), "a+b");
    }

    #[test]
    fn local_addresses() {
        assert!(is_local("192.168.1.67".parse().unwrap()));
        assert!(is_local("100.101.1.2".parse().unwrap()));
        assert!(is_local("127.0.0.1".parse().unwrap()));
        assert!(!is_local("8.8.8.8".parse().unwrap()));
    }
}
