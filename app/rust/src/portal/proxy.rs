//! O proxy do portal: Navidrome e BK Analyzer atrás de um endereço só.
//!
//! ```text
//!   /bk/portal.json   →  o anúncio assinado (não sai daqui)
//!   /bk/analise/...   →  BK Analyzer, e só o que o player precisa
//!   /...              →  Navidrome
//! ```
//!
//! O Navidrome fica na raiz de propósito: a interface web dele usa caminhos
//! absolutos (`/app`, `/rest`), então pendurá-lo num prefixo exigiria mexer
//! na configuração do Navidrome — que é do usuário e não se toca.

use std::io::Read;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{anyhow, Result};
use parking_lot::RwLock;
use tiny_http::{Header, Method, Request, Response, StatusCode};
use ureq::config::AutoHeaderValue;

use super::{Notice, ANALYSIS_PREFIX, NOTICE_PATH};

type Resp = Response<Box<dyn Read + Send>>;

/// Pedidos ao mesmo tempo. O streaming de uma música segura a thread pelo
/// tempo da faixa, então o teto é mais alto que o do coordenador.
const MAX_IN_FLIGHT: usize = 512;
/// Só isto do BK Analyzer sai para a internet. O painel, a API dos
/// trabalhadores (que baixa áudio com o login do dono) e o resto ficam de
/// fora: quem quiser mexer neles entra pela rede de casa.
const ANALYSIS_PUBLIC: [&str; 3] = ["/api/hello", "/api/summary", "/api/analysis/"];
/// Cabeçalhos que morrem em cada salto e não podem ser repassados.
const HOP_BY_HOP: [&str; 8] =
    ["connection", "keep-alive", "transfer-encoding", "te", "trailer", "upgrade", "proxy-authenticate", "proxy-authorization"];
/// Cabeçalhos de "quem é você" que um proxy reverso confiaria. Vindos da
/// internet são uma tentativa de entrar como outra pessoa: somem na entrada.
const IDENTITY_SPOOF: [&str; 5] = ["remote-user", "remote-email", "remote-name", "x-forwarded-user", "x-authenticated-user"];

static STOP: AtomicBool = AtomicBool::new(false);
static IN_FLIGHT: AtomicUsize = AtomicUsize::new(0);

extern "C" fn on_signal(_: libc::c_int) {
    STOP.store(true, Ordering::SeqCst);
}

pub struct Config {
    pub listen: String,
    pub navidrome: String,
    pub analyzer: Option<String>,
}

/// O anúncio de agora, trocado pela thread que cuida do túnel.
#[derive(Default)]
pub struct Board(RwLock<Option<Vec<u8>>>);

impl Board {
    pub fn post(&self, n: &Notice) {
        *self.0.write() = serde_json::to_vec(n).ok();
    }

    fn read(&self) -> Option<Vec<u8>> {
        self.0.read().clone()
    }
}

struct App {
    cfg: Config,
    board: Arc<Board>,
    agent: ureq::Agent,
}

pub fn serve(cfg: Config, board: Arc<Board>) -> Result<()> {
    let listen = cfg.listen.clone();
    let http = tiny_http::Server::http(&listen).map_err(|e| anyhow!("não deu para abrir {listen}: {e}"))?;
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_connect(Some(Duration::from_secs(10)))
        .timeout_recv_response(Some(Duration::from_secs(60)))
        // A resposta é repassada inteira: um 404 do Navidrome é um 404 aqui.
        .http_status_as_error(false)
        // Quem segue redirecionamento é o app; segui-los aqui esconderia
        // dele para onde foi mandado.
        .max_redirects(0)
        // Sem compressão entre o portal e a máquina de casa: o ureq
        // descompactaria a resposta e o cabeçalho repassado passaria a
        // mentir. Na saída quem compacta é a Cloudflare.
        .accept_encoding(AutoHeaderValue::None)
        .user_agent(concat!("BKmasterplayer-portal/", env!("CARGO_PKG_VERSION")))
        .build()
        .into();
    let app = Arc::new(App { cfg, board, agent });
    eprintln!("portal no ar em http://{listen}");
    // SAFETY: o tratador só grava num AtomicBool (seguro dentro de um sinal).
    unsafe {
        libc::signal(libc::SIGTERM, on_signal as extern "C" fn(libc::c_int) as libc::sighandler_t);
        libc::signal(libc::SIGINT, on_signal as extern "C" fn(libc::c_int) as libc::sighandler_t);
    }
    while !STOP.load(Ordering::SeqCst) {
        match http.recv_timeout(Duration::from_millis(500)) {
            Ok(Some(req)) => {
                if IN_FLIGHT.fetch_add(1, Ordering::SeqCst) >= MAX_IN_FLIGHT {
                    IN_FLIGHT.fetch_sub(1, Ordering::SeqCst);
                    let _ = req.respond(text(503, "ocupado; tente de novo"));
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
    eprintln!("portal saindo");
    Ok(())
}

pub fn stop() {
    STOP.store(true, Ordering::SeqCst);
}

pub fn stopping() -> bool {
    STOP.load(Ordering::SeqCst)
}

impl App {
    fn handle(&self, mut req: Request) {
        let raw = req.url().to_string();
        let path = raw.split('?').next().unwrap_or("/").to_string();
        if path == NOTICE_PATH {
            let r = match self.board.read() {
                Some(b) => Response::from_data(b).with_header(json_header()).with_header(no_store()).boxed(),
                // O portal subiu mas o túnel ainda não: o app tenta de novo.
                None => text(503, "o portal ainda não sabe o endereço de fora").boxed(),
            };
            let _ = req.respond(r);
            return;
        }
        let target = match path.strip_prefix(ANALYSIS_PREFIX) {
            Some(rest) => {
                let rest = if rest.is_empty() { "/" } else { rest };
                match (&self.cfg.analyzer, plain_path(rest) && ANALYSIS_PUBLIC.iter().any(|p| rest.starts_with(p))) {
                    (Some(base), true) => format!("{base}{}", with_query(&raw, rest)),
                    (Some(_), false) => {
                        let _ = req.respond(text(404, "essa parte da análise não sai de casa"));
                        return;
                    }
                    (None, _) => {
                        let _ = req.respond(text(404, "esse portal não serve análise"));
                        return;
                    }
                }
            }
            None => format!("{}{}", self.cfg.navidrome, raw),
        };
        match self.forward(&mut req, &target) {
            Ok(resp) => {
                // A conexão cai no meio de uma música o tempo todo (pular
                // faixa, tela desligada): é rotina, não erro.
                let _ = req.respond(resp);
            }
            Err(e) => {
                eprintln!("{path}: {e:#}");
                let _ = req.respond(text(502, "o servidor de casa não respondeu"));
            }
        }
    }

    fn forward(&self, req: &mut Request, target: &str) -> Result<Resp> {
        let method = req.method().clone();
        let mut out = ureq::http::Request::builder().method(method.as_str()).uri(target);
        for h in req.headers() {
            let name = h.field.as_str().as_str().to_ascii_lowercase();
            // O Host é o do portal; quem responde é a máquina de casa.
            if name == "host" || name == "accept-encoding" || HOP_BY_HOP.contains(&name.as_str()) || IDENTITY_SPOOF.contains(&name.as_str()) {
                continue;
            }
            out = out.header(h.field.as_str().as_str(), h.value.as_str());
        }
        let has_body = !matches!(method, Method::Get | Method::Head | Method::Delete) && req.body_length().unwrap_or(0) > 0;
        let resp = if has_body {
            // O corpo vai direto do soquete de entrada para o de saída.
            let mut reader = req.as_reader();
            self.agent.run(out.body(ureq::SendBody::from_reader(&mut reader))?)?
        } else {
            self.agent.run(out.body(ureq::SendBody::none())?)?
        };
        let status = resp.status().as_u16();
        let mut headers = Vec::new();
        let mut length = None;
        for (name, value) in resp.headers() {
            let lower = name.as_str().to_ascii_lowercase();
            if HOP_BY_HOP.contains(&lower.as_str()) {
                continue;
            }
            // O tiny_http escreve o tamanho sozinho a partir do que recebe.
            if lower == "content-length" {
                length = value.to_str().ok().and_then(|v| v.parse::<usize>().ok());
                continue;
            }
            if let (Ok(v), Ok(h)) = (value.to_str(), Header::from_bytes(name.as_str().as_bytes(), value.as_bytes())) {
                let _ = v;
                headers.push(h);
            }
        }
        let reader: Box<dyn Read + Send> = Box::new(resp.into_body().into_reader());
        Ok(Response::new(StatusCode(status), headers, reader, length, None))
    }
}

/// Caminho sem truque: nenhum trecho `.` ou `..`, nem contrabandeados em
/// `%2e%2e%2f`.
///
/// A lista do que pode sair da análise é por prefixo. Se um `..` chegasse
/// inteiro do outro lado e alguém o normalizasse,
/// `/api/analysis/../../api/worker/audio` viraria `/api/worker/audio` — e a
/// API dos trabalhadores, que baixa áudio com o login do dono, estaria na
/// internet. O coordenador de hoje não normaliza, mas a barreira não pode
/// depender disso.
fn plain_path(path: &str) -> bool {
    if path.contains('\\') {
        return false;
    }
    let decoded = unescape(path);
    !decoded.split('/').any(|seg| seg == "." || seg == "..")
}

/// Desfaz os `%XX` uma vez, para enxergar o caminho como o outro lado veria.
fn unescape(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = String::with_capacity(s.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            if let Ok(v) = u8::from_str_radix(&s[i + 1..i + 3], 16) {
                out.push(v as char);
                i += 3;
                continue;
            }
        }
        out.push(b[i] as char);
        i += 1;
    }
    out
}

/// Junta o que veio depois do `?` ao caminho já sem o prefixo.
fn with_query(full: &str, path: &str) -> String {
    match full.split_once('?') {
        Some((_, q)) => format!("{path}?{q}"),
        None => path.to_string(),
    }
}

fn json_header() -> Header {
    Header::from_bytes(&b"Content-Type"[..], &b"application/json; charset=utf-8"[..]).expect("cabeçalho fixo")
}

fn no_store() -> Header {
    Header::from_bytes(&b"Cache-Control"[..], &b"no-store"[..]).expect("cabeçalho fixo")
}

fn text(code: u16, msg: &str) -> Response<std::io::Cursor<Vec<u8>>> {
    Response::from_string(msg).with_status_code(StatusCode(code))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_player_part_of_the_analyzer_is_public() {
        for (path, public) in [
            ("/api/hello", true),
            ("/api/summary", true),
            ("/api/analysis/abc123", true),
            ("/api/worker/audio", false),
            ("/api/worker-setup", false),
            ("/api/state", false),
            ("/api/login", false),
            ("/", false),
        ] {
            assert_eq!(ANALYSIS_PUBLIC.iter().any(|p| path.starts_with(p)), public, "{path}");
        }
    }

    #[test]
    fn a_dot_dot_never_slips_past_the_list() {
        // Sem isto, quem normalizasse o caminho do outro lado chegaria na API
        // dos trabalhadores, que baixa áudio com o login do dono.
        for truque in [
            "/api/analysis/../../api/worker/audio",
            "/api/analysis/..%2f..%2fapi%2fworker%2faudio",
            "/api/analysis/%2e%2e/%2e%2e/api/worker/audio",
            "/api/analysis/x/../../api/worker-setup",
            "/api/hello/../worker/audio",
            "/api/analysis/./../api/state",
            "/api/analysis/..\\..\\api",
        ] {
            assert!(!plain_path(truque), "deixou passar: {truque}");
        }
    }

    #[test]
    fn ordinary_addresses_still_pass() {
        for ok in [
            "/api/hello",
            "/api/summary",
            "/api/analysis/KO2M9cOeJh2EO3NDPn13T7",
            // Id com caractere escapado é normal; só `.` e `..` incomodam.
            "/api/analysis/a%20b",
            "/api/analysis/musica.mp3",
        ] {
            assert!(plain_path(ok), "barrou à toa: {ok}");
        }
    }

    #[test]
    fn the_query_survives_the_prefix_being_cut() {
        assert_eq!(with_query("/bk/analise/api/summary?u=x&t=y", "/api/summary"), "/api/summary?u=x&t=y");
        assert_eq!(with_query("/bk/analise/api/hello", "/api/hello"), "/api/hello");
    }
}
