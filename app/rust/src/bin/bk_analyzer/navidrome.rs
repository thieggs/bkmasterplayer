//! Cliente mínimo da API Subsonic, só de leitura: login, a lista de músicas e
//! o arquivo original de cada uma (para os trabalhadores).

use std::io::Read;
use std::time::Duration;

use anyhow::{anyhow, bail, Context, Result};
use md5::{Digest, Md5};
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Login no Navidrome. Guarda só o token Subsonic, md5(senha + salt), nunca a senha.
#[derive(Clone, Serialize, Deserialize)]
pub struct Login {
    pub url: String,
    pub username: String,
    pub token: String,
    pub salt: String,
}

impl Login {
    pub fn from_password(url: &str, username: &str, password: &str) -> Self {
        let salt = random_hex(8);
        Self { url: normalize_url(url), username: username.trim().into(), token: md5_hex(&format!("{password}{salt}")), salt }
    }
}

pub fn md5_hex(s: &str) -> String {
    format!("{:x}", Md5::digest(s.as_bytes()))
}

pub fn normalize_url(url: &str) -> String {
    let u = url.trim().trim_end_matches('/');
    let u = u.strip_suffix("/rest").unwrap_or(u);
    if u.starts_with("http://") || u.starts_with("https://") {
        u.to_string()
    } else {
        format!("http://{u}")
    }
}

pub fn random_hex(bytes: usize) -> String {
    let mut buf = vec![0u8; bytes];
    std::fs::File::open("/dev/urandom").and_then(|mut f| f.read_exact(&mut buf)).expect("sem /dev/urandom");
    buf.iter().map(|b| format!("{b:02x}")).collect()
}

/// Codifica um valor para a query da URL.
pub fn enc(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// Música como vem do servidor.
#[derive(Clone, Debug)]
pub struct RemoteSong {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: u32,
    pub suffix: String,
    pub size: u64,
    pub plays: u32,
    pub starred: bool,
}

impl RemoteSong {
    fn from_json(v: &Value) -> Option<Self> {
        if v["isVideo"].as_bool() == Some(true) {
            return None;
        }
        let s = |k: &str| v[k].as_str().unwrap_or("").to_string();
        Some(Self {
            id: v["id"].as_str()?.to_string(),
            title: s("title"),
            artist: s("artist"),
            album: s("album"),
            duration: v["duration"].as_u64().unwrap_or(0) as u32,
            suffix: s("suffix").to_lowercase(),
            size: v["size"].as_u64().unwrap_or(0),
            plays: v["playCount"].as_u64().unwrap_or(0) as u32,
            starred: v.get("starred").is_some_and(|x| !x.is_null()),
        })
    }
}

pub struct Navidrome {
    login: Login,
    agent: ureq::Agent,
}

/// Erro da API Subsonic (código 40 = usuário ou senha errados).
#[derive(Debug)]
pub struct ApiError {
    pub code: i64,
    pub message: String,
}

impl std::fmt::Display for ApiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self.code {
            40 => write!(f, "usuário ou senha incorretos"),
            41 => write!(f, "o servidor não aceita login por token"),
            _ => write!(f, "{} (código {})", self.message, self.code),
        }
    }
}

impl std::error::Error for ApiError {}

impl Navidrome {
    pub fn new(login: Login) -> Self {
        let agent = ureq::Agent::config_builder()
            .timeout_connect(Some(Duration::from_secs(10)))
            .timeout_recv_response(Some(Duration::from_secs(60)))
            .http_status_as_error(false)
            .user_agent(concat!("BKmasterplayer-analyzer/", env!("CARGO_PKG_VERSION")))
            .build()
            .into();
        Self { login, agent }
    }

    fn url(&self, endpoint: &str, params: &[(&str, &str)]) -> String {
        let l = &self.login;
        let mut u = format!(
            "{}/rest/{endpoint}?u={}&t={}&s={}&v=1.16.1&c=bk-analyzer&f=json",
            l.url,
            enc(&l.username),
            enc(&l.token),
            enc(&l.salt)
        );
        for (k, v) in params {
            u.push_str(&format!("&{k}={}", enc(v)));
        }
        u
    }

    fn get_json(&self, endpoint: &str, params: &[(&str, &str)]) -> Result<Value> {
        let mut resp = self
            .agent
            .get(&self.url(endpoint, params))
            .call()
            .with_context(|| format!("sem conexão com o Navidrome em {}", self.login.url))?;
        let status = resp.status().as_u16();
        if status != 200 {
            bail!("o Navidrome respondeu HTTP {status}");
        }
        let raw = resp.body_mut().with_config().limit(256 << 20).read_to_vec().context("resposta do Navidrome")?;
        let v: Value = serde_json::from_slice(&raw).context("resposta inválida do Navidrome")?;
        let r = v.get("subsonic-response").ok_or_else(|| anyhow!("isso não parece um servidor Subsonic"))?;
        if r["status"] != "ok" {
            return Err(ApiError {
                code: r["error"]["code"].as_i64().unwrap_or(0),
                message: r["error"]["message"].as_str().unwrap_or("erro").to_string(),
            }
            .into());
        }
        Ok(r.clone())
    }

    pub fn ping(&self) -> Result<()> {
        self.get_json("ping", &[]).map(|_| ())
    }

    pub fn is_admin(&self) -> Result<bool> {
        let r = self.get_json("getUser", &[("username", &self.login.username)])?;
        Ok(r["user"]["adminRole"].as_bool().unwrap_or(false))
    }

    /// Todas as músicas (busca vazia, em páginas de 500).
    pub fn songs(&self) -> Result<Vec<RemoteSong>> {
        const PAGE: usize = 500;
        let mut out = Vec::new();
        let mut offset = 0;
        loop {
            let off = offset.to_string();
            let r = self.get_json(
                "search3",
                &[("query", ""), ("artistCount", "0"), ("albumCount", "0"), ("songCount", "500"), ("songOffset", &off)],
            )?;
            let page = r["searchResult3"]["song"].as_array().cloned().unwrap_or_default();
            offset += page.len();
            out.extend(page.iter().filter_map(RemoteSong::from_json));
            if page.len() < PAGE {
                return Ok(out);
            }
        }
    }

    /// Arquivo de uma música, original ou convertido para `format`, do mesmo
    /// jeito que o player pede: (tamanho, tipo, conteúdo).
    pub fn stream(&self, id: &str, format: Option<&str>) -> Result<(Option<u64>, String, Box<dyn Read + Send>)> {
        let resp = self
            .agent
            .get(&self.url("stream", &[("id", id), ("format", format.unwrap_or("raw"))]))
            .call()
            .context("sem conexão com o Navidrome")?;
        let status = resp.status().as_u16();
        let header = |n: &str| resp.headers().get(n).and_then(|v| v.to_str().ok()).map(str::to_string);
        let ctype = header("content-type").unwrap_or_else(|| "application/octet-stream".into());
        if status != 200 {
            bail!("o Navidrome respondeu HTTP {status} ao arquivo");
        }
        // Erro da API vem como JSON/XML com status 200.
        if ctype.contains("json") || ctype.contains("xml") {
            bail!("o Navidrome não entregou o arquivo (ele sumiu da biblioteca?)");
        }
        let len = header("content-length").and_then(|v| v.parse().ok());
        Ok((len, ctype, Box::new(resp.into_body().into_reader())))
    }
}

/// Confere uma API key (OpenSubsonic) de player no servidor configurado.
pub fn check_key(url: &str, key: &str) -> Result<()> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_connect(Some(Duration::from_secs(10)))
        .timeout_recv_response(Some(Duration::from_secs(30)))
        .http_status_as_error(false)
        .build()
        .into();
    let raw = agent
        .get(&format!("{url}/rest/ping?apiKey={}&v=1.16.1&c=bk-analyzer&f=json", enc(key)))
        .call()?
        .body_mut()
        .read_to_vec()?;
    let v: Value = serde_json::from_slice(&raw)?;
    if v["subsonic-response"]["status"] != "ok" {
        bail!("API key recusada");
    }
    Ok(())
}

/// Confere um login de player (u/t/s da API Subsonic) no servidor configurado.
pub fn check(url: &str, username: &str, token: &str, salt: &str) -> Result<()> {
    Navidrome::new(Login { url: url.into(), username: username.into(), token: token.into(), salt: salt.into() }).ping()
}
