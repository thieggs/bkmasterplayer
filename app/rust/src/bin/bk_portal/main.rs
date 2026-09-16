//! BK Portal: um endereço só para o servidor de música de casa.
//!
//! Junta o Navidrome e o BK Analyzer atrás de um link, cuida do túnel da
//! Cloudflare (que sorteia um nome novo a cada reinício) e publica um
//! anúncio assinado dizendo onde o túnel está agora. O app guarda o link
//! fixo do anúncio; quando o endereço rápido muda, ele descobre o novo
//! sozinho.
//!
//!   bk-portal serve
//!   bk-portal link
//!
//! O link fixo vem do Funnel do Tailscale, que é lento mas nunca muda; o
//! endereço que o anúncio aponta é o túnel da Cloudflare, que é rápido.
//! Cada um faz o que faz bem.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{anyhow, bail, Context, Result};
use player_engine::portal::{fingerprint, proxy, tunnel, Signer, NOTICE_PATH};

const USAGE: &str = "BK Portal — um endereço só para o servidor de música

  bk-portal serve [--listen 127.0.0.1:4530] [--navidrome http://127.0.0.1:4533]
                  [--analyzer http://127.0.0.1:4540] [--no-analyzer]
                  [--cloudflared <programa>] [--url <endereço fixo>]
                  [--nome \"Servidor do Fulano\"] [--url-file <arquivo>]
      põe o Navidrome e a análise atrás de um link, cuida do túnel e
      assina o anúncio

  bk-portal link [--funnel <endereço>]
      mostra o link para mandar aos amigos e a impressão digital da chave";

fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("."))
}

fn data_dir(o: &HashMap<String, String>) -> PathBuf {
    o.get("data").map(PathBuf::from).unwrap_or_else(|| {
        std::env::var_os("XDG_DATA_HOME").map(PathBuf::from).unwrap_or_else(|| home().join(".local/share")).join("bk-portal")
    })
}

/// `--chave valor` e `--flag` (sem valor).
fn parse(args: &[String], flags: &[&str]) -> Result<HashMap<String, String>> {
    let mut out = HashMap::new();
    let mut it = args.iter();
    while let Some(a) = it.next() {
        let Some(k) = a.strip_prefix("--") else { bail!("argumento inesperado: {a}\n\n{USAGE}") };
        if flags.contains(&k) {
            out.insert(k.to_string(), "1".into());
        } else {
            let v = it.next().ok_or_else(|| anyhow!("falta o valor de --{k}"))?;
            out.insert(k.to_string(), v.clone());
        }
    }
    Ok(out)
}

/// Abre a chave do portal, criando-a na primeira vez.
///
/// É ela que prova ao app que o anúncio é seu. Fica só para o dono do
/// arquivo: quem a tiver pode mandar os aparelhos para onde quiser.
fn signer(dir: &PathBuf) -> Result<Signer> {
    std::fs::create_dir_all(dir).with_context(|| format!("criando {}", dir.display()))?;
    let path = dir.join("chave");
    if let Ok(s) = std::fs::read_to_string(&path) {
        if let Some(k) = Signer::from_hex(&s) {
            return Ok(k);
        }
        bail!("a chave em {} está ilegível; apague o arquivo para criar outra (os aparelhos vão precisar aceitar a nova)", path.display());
    }
    let k = Signer::generate().context("sorteando a chave")?;
    std::fs::write(&path, k.secret_hex()).with_context(|| format!("gravando {}", path.display()))?;
    restrict(&path)?;
    eprintln!("chave nova criada em {}", path.display());
    Ok(k)
}

#[cfg(unix)]
fn restrict(path: &PathBuf) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600)).with_context(|| format!("fechando {}", path.display()))
}

#[cfg(not(unix))]
fn restrict(_path: &PathBuf) -> Result<()> {
    Ok(())
}

fn serve(o: HashMap<String, String>) -> Result<()> {
    let dir = data_dir(&o);
    let key = signer(&dir)?;
    let listen = o.get("listen").cloned().unwrap_or_else(|| "127.0.0.1:4530".into());
    let port: u16 = listen.rsplit(':').next().and_then(|p| p.parse().ok()).ok_or_else(|| anyhow!("--listen precisa ser endereço:porta"))?;
    let navidrome = o.get("navidrome").cloned().unwrap_or_else(|| "http://127.0.0.1:4533".into());
    let analyzer = if o.contains_key("no-analyzer") {
        None
    } else {
        Some(o.get("analyzer").cloned().unwrap_or_else(|| "http://127.0.0.1:4540".into()))
    };
    let name = o.get("nome").cloned().unwrap_or_else(|| "Servidor de música".into());
    let cloudflared = o.get("cloudflared").map(PathBuf::from).or_else(|| {
        let guess = home().join("cloudflared/cloudflared");
        guess.exists().then_some(guess)
    });
    let board = Arc::new(proxy::Board::default());
    let args = tunnel::Args {
        signer: key,
        board: board.clone(),
        name,
        port,
        serves_analysis: analyzer.is_some(),
        cloudflared,
        public_url: o.get("url").cloned(),
        url_file: o.get("url-file").map(PathBuf::from).or_else(|| Some(dir.join("endereco-de-fora"))),
    };
    let tunnel_thread = std::thread::spawn(move || {
        if let Err(e) = tunnel::run(args) {
            eprintln!("o túnel desistiu: {e:#}");
            // Sem endereço de fora o portal não serve para o que foi feito.
            proxy::stop();
        }
    });
    let result = proxy::serve(proxy::Config { listen, navidrome, analyzer }, board);
    proxy::stop();
    let _ = tunnel_thread.join();
    result
}

fn link(o: HashMap<String, String>) -> Result<()> {
    let key = signer(&data_dir(&o))?;
    let funnel = o.get("funnel").cloned().or_else(tailscale_funnel);
    println!("Impressão digital da chave:\n  {}\n", fingerprint(&key.public_hex()));
    match funnel {
        Some(f) => {
            println!("Link para mandar aos amigos (é só colar na tela de entrar do app):\n  {f}\n");
            println!("O anúncio em si fica em {f}{NOTICE_PATH}");
        }
        None => {
            println!("Não achei o endereço do Funnel do Tailscale.");
            println!("Ligue-o com:  tailscale funnel --bg 4530");
            println!("e rode de novo, ou passe --funnel https://sua-maquina.ts.net");
        }
    }
    println!("\nQuem receber o link vê essa mesma impressão digital no app,");
    println!("em Ajustes → Conta e servidor. Confira por voz na primeira vez: é o");
    println!("que garante que o servidor é o seu, e não o de outra pessoa.");
    Ok(())
}

/// Pergunta ao Tailscale qual é o endereço público desta máquina.
fn tailscale_funnel() -> Option<String> {
    let out = std::process::Command::new("tailscale").args(["status", "--json"]).output().ok()?;
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).ok()?;
    let name = v["Self"]["DNSName"].as_str()?.trim_end_matches('.');
    (!name.is_empty()).then(|| format!("https://{name}"))
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("serve") => parse(&args[1..], &["no-analyzer"]).and_then(serve),
        Some("link") => parse(&args[1..], &[]).and_then(link),
        _ => {
            eprintln!("{USAGE}");
            std::process::exit(2);
        }
    };
    if let Err(e) = result {
        eprintln!("erro: {e:#}");
        std::process::exit(1);
    }
}
