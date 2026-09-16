//! Portal: um endereço só para o servidor de música, que continua valendo
//! quando o túnel muda de nome.
//!
//! O túnel grátis da Cloudflare sorteia um endereço novo a cada reinício, o
//! que quebraria o servidor guardado no aparelho. O portal resolve com duas
//! peças:
//!
//! - o **anúncio** (este módulo): um papelzinho assinado dizendo "hoje a
//!   música está em tal endereço". Fica num lugar fixo (o Funnel do
//!   Tailscale), é pequeno, e o app só o lê quando o endereço guardado falha.
//! - o **proxy** ([`proxy`]): põe o Navidrome e o BK Analyzer atrás de um
//!   endereço só, para o anúncio ter um link único a divulgar.
//!
//! A assinatura é o que separa isso de um redirecionamento cego: sem ela,
//! quem escrevesse no anúncio mandaria o app — e a senha de quem o usa —
//! para o servidor que quisesse. A chave particular nunca sai da máquina de
//! casa; o app guarda a pública na primeira vez que vê (como o SSH faz) e
//! daí em diante recusa qualquer anúncio que não venha dela.

use std::time::{SystemTime, UNIX_EPOCH};

use ed25519_dalek::{Signature, Signer as _, SigningKey, VerifyingKey, SECRET_KEY_LENGTH};
use serde::{Deserialize, Serialize};

#[cfg(feature = "portal-server")]
pub mod proxy;
#[cfg(feature = "portal-server")]
pub mod tunnel;

/// Caminho do anúncio dentro do portal e do Funnel.
pub const NOTICE_PATH: &str = "/bk/portal.json";
/// Prefixo do BK Analyzer dentro do portal (o resto vai para o Navidrome).
pub const ANALYSIS_PREFIX: &str = "/bk/analise";

const APP: &str = "bkmasterplayer";
const VERSION: u32 = 1;
/// Um anúncio velho apontando para um endereço sorteado que já passou para
/// outra pessoa seria um jeito de desviar o app; por isso ele vence.
pub const VALID_FOR: u64 = 12 * 3600;
/// Folga para relógios desencontrados entre o servidor e o aparelho.
const CLOCK_SLACK: u64 = 6 * 3600;
/// Anúncio maior que isso nem é lido.
pub const MAX_BYTES: usize = 8 * 1024;
const MAX_URL: usize = 512;
const MAX_NAME: usize = 80;

/// O papelzinho assinado: onde está a música agora.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Notice {
    pub app: String,
    pub v: u32,
    /// Nome que o app mostra ("Servidor do Thiago").
    pub name: String,
    /// Endereço do Navidrome (raiz do portal).
    pub music: String,
    /// Endereço do BK Analyzer, quando o portal o serve.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub analysis: Option<String>,
    /// Quando foi escrito e até quando vale (segundos desde 1970).
    pub issued: u64,
    pub expires: u64,
    /// Chave pública de quem assinou, em hexadecimal.
    pub key: String,
    /// A assinatura, em hexadecimal.
    pub sig: String,
}

#[derive(Debug, PartialEq, Eq)]
pub enum NoticeError {
    /// Não é um anúncio do BKmasterplayer (ou é de uma versão mais nova).
    NotANotice,
    /// A assinatura não confere: alguém mexeu no anúncio.
    BadSignature,
    /// Está assinado, mas por uma chave diferente da que o app já conhecia.
    WrongKey,
    /// Venceu (ou foi escrito no futuro).
    Expired,
    /// Endereço malformado, longo demais ou sem https.
    BadAddress(&'static str),
}

impl std::fmt::Display for NoticeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotANotice => write!(f, "esse endereço não é um portal do BKmasterplayer"),
            Self::BadSignature => write!(f, "a assinatura do anúncio não confere"),
            Self::WrongKey => write!(f, "o anúncio veio de outra chave: não é mais o mesmo servidor"),
            Self::Expired => write!(f, "o anúncio venceu; o servidor de casa pode estar fora do ar"),
            Self::BadAddress(why) => write!(f, "endereço inválido no anúncio ({why})"),
        }
    }
}

impl std::error::Error for NoticeError {}

pub fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// Bytes que a assinatura cobre.
///
/// Não é o JSON: dois programas serializam o mesmo objeto de formas
/// diferentes (ordem das chaves, espaços) e a assinatura deixaria de bater.
/// Aqui cada campo entra com o tamanho na frente, então nenhuma combinação
/// de conteúdos produz a mesma sequência de outra.
fn signed_bytes(n: &Notice) -> Vec<u8> {
    let mut out = Vec::with_capacity(256);
    let mut field = |b: &[u8]| {
        out.extend_from_slice(&(b.len() as u64).to_be_bytes());
        out.extend_from_slice(b);
    };
    field(b"bk-portal-v1");
    field(n.app.as_bytes());
    field(n.v.to_string().as_bytes());
    field(n.name.as_bytes());
    field(n.music.as_bytes());
    field(n.analysis.as_deref().unwrap_or("").as_bytes());
    field(n.issued.to_string().as_bytes());
    field(n.expires.to_string().as_bytes());
    field(n.key.as_bytes());
    out
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn unhex(s: &str, want: usize) -> Option<Vec<u8>> {
    if s.len() != want * 2 || !s.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    (0..want).map(|i| u8::from_str_radix(&s[i * 2..i * 2 + 2], 16).ok()).collect()
}

/// Endereço aceitável para o app: https, ou http só dentro de casa.
///
/// Sem isso um anúncio poderia rebaixar a conexão para http e a senha de
/// quem usa sairia em texto puro pela internet.
fn check_url(url: &str) -> Result<(), NoticeError> {
    if url.len() > MAX_URL {
        return Err(NoticeError::BadAddress("longo demais"));
    }
    if url.contains(|c: char| c.is_whitespace() || c.is_control()) {
        return Err(NoticeError::BadAddress("tem espaço ou caractere de controle"));
    }
    let rest = if let Some(r) = url.strip_prefix("https://") {
        return host_ok(r).map(|_| ());
    } else if let Some(r) = url.strip_prefix("http://") {
        r
    } else {
        return Err(NoticeError::BadAddress("precisa começar com https://"));
    };
    let host = host_ok(rest)?;
    if is_private(host) {
        Ok(())
    } else {
        Err(NoticeError::BadAddress("http só vale para endereço de casa"))
    }
}

fn host_ok(rest: &str) -> Result<&str, NoticeError> {
    let host = rest.split(['/', '?', '#']).next().unwrap_or("");
    let host = host.rsplit_once(':').map(|(h, _)| h).unwrap_or(host);
    if host.is_empty() || host.contains('@') {
        return Err(NoticeError::BadAddress("sem servidor, ou com usuário embutido"));
    }
    Ok(host)
}

fn is_private(host: &str) -> bool {
    if host == "localhost" || host.ends_with(".local") {
        return true;
    }
    match host.parse::<std::net::IpAddr>() {
        Ok(std::net::IpAddr::V4(ip)) => {
            ip.is_loopback() || ip.is_private() || ip.is_link_local() || ip.octets()[0] == 100 && (64..128).contains(&ip.octets()[1])
        }
        Ok(std::net::IpAddr::V6(ip)) => ip.is_loopback() || (ip.segments()[0] & 0xfe00) == 0xfc00,
        Err(_) => false,
    }
}

/// Lê e confere um anúncio.
///
/// `pinned` é a chave que o app já viu antes (nenhuma na primeira vez).
pub fn verify(raw: &[u8], pinned: Option<&str>, at: u64) -> Result<Notice, NoticeError> {
    if raw.len() > MAX_BYTES {
        return Err(NoticeError::NotANotice);
    }
    let n: Notice = serde_json::from_slice(raw).map_err(|_| NoticeError::NotANotice)?;
    if n.app != APP || n.v != VERSION || n.name.len() > MAX_NAME {
        return Err(NoticeError::NotANotice);
    }
    // A chave primeiro: um anúncio de outro servidor não merece mais exame.
    if let Some(p) = pinned {
        if !p.eq_ignore_ascii_case(&n.key) {
            return Err(NoticeError::WrongKey);
        }
    }
    let key = unhex(&n.key, 32).ok_or(NoticeError::NotANotice)?;
    let sig = unhex(&n.sig, 64).ok_or(NoticeError::BadSignature)?;
    let verifying = VerifyingKey::from_bytes(&key.try_into().expect("32 bytes")).map_err(|_| NoticeError::BadSignature)?;
    let signature = Signature::from_bytes(&sig.try_into().expect("64 bytes"));
    verifying.verify_strict(&signed_bytes(&n), &signature).map_err(|_| NoticeError::BadSignature)?;
    // Só depois de assinado é que as datas e os endereços querem dizer algo.
    if at > n.expires.saturating_add(CLOCK_SLACK) || n.issued > at.saturating_add(CLOCK_SLACK) {
        return Err(NoticeError::Expired);
    }
    check_url(&n.music)?;
    if let Some(a) = &n.analysis {
        check_url(a)?;
    }
    Ok(n)
}

/// Impressão digital da chave, para a pessoa comparar de viva voz.
///
/// Oito grupos de quatro, como o Tailscale e o Signal mostram.
pub fn fingerprint(key_hex: &str) -> String {
    let short: String = key_hex.chars().take(32).collect();
    short.as_bytes().chunks(4).map(|c| String::from_utf8_lossy(c).to_uppercase()).collect::<Vec<_>>().join("-")
}

/// A chave particular do portal; fica só na máquina de casa.
pub struct Signer(SigningKey);

impl Signer {
    /// Cria uma chave nova a partir do sorteio do sistema.
    pub fn generate() -> std::io::Result<Self> {
        use std::io::Read;
        let mut seed = [0u8; SECRET_KEY_LENGTH];
        std::fs::File::open("/dev/urandom")?.read_exact(&mut seed)?;
        Ok(Self(SigningKey::from_bytes(&seed)))
    }

    pub fn from_hex(s: &str) -> Option<Self> {
        let b = unhex(s.trim(), SECRET_KEY_LENGTH)?;
        Some(Self(SigningKey::from_bytes(&b.try_into().expect("32 bytes"))))
    }

    pub fn secret_hex(&self) -> String {
        hex(&self.0.to_bytes())
    }

    pub fn public_hex(&self) -> String {
        hex(self.0.verifying_key().as_bytes())
    }

    /// Escreve e assina o anúncio de agora.
    pub fn announce(&self, name: &str, music: &str, analysis: Option<&str>, at: u64) -> Notice {
        let mut n = Notice {
            app: APP.into(),
            v: VERSION,
            name: name.chars().take(MAX_NAME).collect(),
            music: music.trim_end_matches('/').into(),
            analysis: analysis.map(|a| a.trim_end_matches('/').into()),
            issued: at,
            expires: at + VALID_FOR,
            key: self.public_hex(),
            sig: String::new(),
        };
        n.sig = hex(&self.0.sign(&signed_bytes(&n)).to_bytes());
        n
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn signer() -> Signer {
        Signer::from_hex(&"ab".repeat(32)).unwrap()
    }

    fn raw(n: &Notice) -> Vec<u8> {
        serde_json::to_vec(n).unwrap()
    }

    #[test]
    fn a_good_notice_is_accepted_and_pins_the_key() {
        let s = signer();
        let n = s.announce("Casa", "https://um.trycloudflare.com", Some("https://um.trycloudflare.com/bk/analise"), 1000);
        let got = verify(&raw(&n), None, 1000).unwrap();
        assert_eq!(got.music, "https://um.trycloudflare.com");
        // Na segunda vez o app já sabe a chave e continua aceitando.
        verify(&raw(&n), Some(&s.public_hex()), 1000).unwrap();
    }

    #[test]
    fn a_changed_address_breaks_the_signature() {
        let s = signer();
        let mut n = s.announce("Casa", "https://um.trycloudflare.com", None, 1000);
        n.music = "https://doatacante.com".into();
        assert_eq!(verify(&raw(&n), None, 1000), Err(NoticeError::BadSignature));
    }

    #[test]
    fn another_key_signing_correctly_is_still_refused() {
        // O ataque que importa: o atacante assina um anúncio perfeito, mas
        // com a chave dele. Sem fixar a chave isso passaria.
        let mine = signer();
        let theirs = Signer::from_hex(&"cd".repeat(32)).unwrap();
        let n = theirs.announce("Casa", "https://doatacante.com", None, 1000);
        assert_eq!(verify(&raw(&n), None, 1000).unwrap().music, "https://doatacante.com");
        assert_eq!(verify(&raw(&n), Some(&mine.public_hex()), 1000), Err(NoticeError::WrongKey));
    }

    #[test]
    fn an_old_notice_stops_working() {
        let s = signer();
        let n = s.announce("Casa", "https://um.trycloudflare.com", None, 1000);
        verify(&raw(&n), None, 1000 + VALID_FOR).unwrap();
        assert_eq!(verify(&raw(&n), None, 1000 + VALID_FOR + CLOCK_SLACK + 1), Err(NoticeError::Expired));
    }

    #[test]
    fn plain_http_is_only_allowed_at_home() {
        let s = signer();
        for (url, ok) in [
            ("https://um.trycloudflare.com", true),
            ("http://192.168.1.10:4533", true),
            ("http://100.64.180.93:4533", true),
            ("http://localhost:4533", true),
            ("http://servidor-de-fora.com", false),
            ("ftp://um.com", false),
            ("https://user@um.com", false),
        ] {
            let n = s.announce("Casa", url, None, 1000);
            assert_eq!(verify(&raw(&n), None, 1000).is_ok(), ok, "{url}");
        }
    }

    #[test]
    fn junk_is_refused_without_panicking() {
        for bad in [&b""[..], b"{}", b"nao e json", b"{\"app\":\"outro\",\"v\":1}", &[0xff; 64]] {
            assert!(verify(bad, None, 1000).is_err());
        }
        let s = signer();
        let n = s.announce("Casa", "https://um.trycloudflare.com", None, 1000);
        let big = vec![b' '; MAX_BYTES + 1];
        assert_eq!(verify(&big, None, 1000), Err(NoticeError::NotANotice));
        assert!(verify(&raw(&n), Some("nao e hexadecimal"), 1000).is_err());
    }

    #[test]
    fn the_fingerprint_is_readable_out_loud() {
        let f = fingerprint(&signer().public_hex());
        assert_eq!(f.len(), 32 + 7);
        assert!(f.chars().all(|c| c.is_ascii_hexdigit() && !c.is_lowercase() || c == '-'));
    }
}
