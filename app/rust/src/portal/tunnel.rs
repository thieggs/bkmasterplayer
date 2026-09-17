//! Cuida do túnel da Cloudflare e mantém o anúncio em dia.
//!
//! O túnel grátis sorteia um nome novo a cada vez que sobe. Quem toma conta
//! dele aqui é o próprio portal: assim que a Cloudflare diz o endereço, o
//! anúncio é assinado de novo e quem tiver o app já acha o caminho sozinho
//! na próxima tentativa — ninguém precisa reconfigurar nada.

use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{anyhow, Result};

use super::proxy::{stopping, Board};
use super::{now, Signer, ANALYSIS_PREFIX, VALID_FOR};

/// De quanto em quanto tempo o anúncio é reescrito, para nunca vencer
/// enquanto o portal está no ar.
const RESIGN_EVERY: Duration = Duration::from_secs(VALID_FOR / 4);
/// Espera entre tentativas quando a Cloudflare recusa (vai dobrando).
const FIRST_BACKOFF: Duration = Duration::from_secs(5);
const MAX_BACKOFF: Duration = Duration::from_secs(300);
/// Quanto esperar o endereço aparecer na saída do cloudflared.
const URL_TIMEOUT: Duration = Duration::from_secs(90);

pub struct Args {
    pub signer: Signer,
    pub board: Arc<Board>,
    pub name: String,
    pub port: u16,
    pub serves_analysis: bool,
    /// O programa cloudflared; `None` quando o endereço é fixo.
    pub cloudflared: Option<PathBuf>,
    /// Endereço público fixo (domínio próprio): dispensa o cloudflared.
    pub public_url: Option<String>,
    /// Arquivo onde o endereço de fora é escrito a cada troca, para os
    /// scripts de quem usa (o supervisor do Minecraft faz isso hoje).
    pub url_file: Option<PathBuf>,
}

/// Assina e publica o anúncio de agora.
fn announce(a: &Args, url: &str) {
    let analysis = a.serves_analysis.then(|| format!("{url}{ANALYSIS_PREFIX}"));
    let notice = a.signer.announce(&a.name, url, analysis.as_deref(), now());
    a.board.post(&notice);
    if let Some(f) = &a.url_file {
        if let Err(e) = write_atomic(f, url.as_bytes()) {
            eprintln!("não deu para gravar {}: {e:#}", f.display());
        }
    }
}

/// Grava num arquivo temporário e troca: quem estiver lendo nunca pega o
/// arquivo pela metade.
fn write_atomic(path: &Path, data: &[u8]) -> std::io::Result<()> {
    let tmp = path.with_extension("tmp");
    std::fs::write(&tmp, data)?;
    std::fs::rename(&tmp, path)
}

pub fn run(a: Args) -> Result<()> {
    // Endereço fixo: nada de cloudflared, só reassinar de vez em quando.
    if let Some(url) = a.public_url.clone() {
        eprintln!("endereço de fora (fixo): {url}");
        while !stopping() {
            announce(&a, &url);
            sleep_until_stop(RESIGN_EVERY);
        }
        return Ok(());
    }
    let bin = a.cloudflared.clone().ok_or_else(|| anyhow!("falta --cloudflared <programa> ou --url <endereço fixo>"))?;
    let mut backoff = FIRST_BACKOFF;
    while !stopping() {
        match open_tunnel(&bin, a.port) {
            Ok((mut child, url)) => {
                backoff = FIRST_BACKOFF;
                eprintln!("endereço de fora: {url}");
                announce(&a, &url);
                // Enquanto o túnel vive, só reassina de tempos em tempos.
                let mut left = RESIGN_EVERY;
                loop {
                    if stopping() {
                        let _ = child.kill();
                        return Ok(());
                    }
                    match child.try_wait() {
                        Ok(Some(status)) => {
                            eprintln!("o túnel caiu ({status}); subindo outro");
                            break;
                        }
                        Ok(None) => {}
                        Err(e) => {
                            eprintln!("não deu para acompanhar o túnel: {e}");
                            let _ = child.kill();
                            break;
                        }
                    }
                    let step = Duration::from_secs(2).min(left);
                    std::thread::sleep(step);
                    left = left.saturating_sub(step);
                    if left.is_zero() {
                        announce(&a, &url);
                        left = RESIGN_EVERY;
                    }
                }
                let _ = child.wait();
            }
            Err(e) => {
                eprintln!("não deu para abrir o túnel: {e:#}; tentando de novo em {}s", backoff.as_secs());
                sleep_until_stop(backoff);
                backoff = (backoff * 2).min(MAX_BACKOFF);
            }
        }
    }
    Ok(())
}

fn sleep_until_stop(total: Duration) {
    let mut left = total;
    while !left.is_zero() && !stopping() {
        let step = Duration::from_secs(1).min(left);
        std::thread::sleep(step);
        left = left.saturating_sub(step);
    }
}

/// Sobe o cloudflared e espera ele dizer o endereço sorteado.
fn open_tunnel(bin: &Path, port: u16) -> Result<(Child, String)> {
    let mut child = Command::new(bin)
        .args(["tunnel", "--no-autoupdate", "--url", &format!("http://127.0.0.1:{port}")])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        // O cloudflared anuncia o endereço na saída de erro.
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| anyhow!("{}: {e}", bin.display()))?;
    let stderr = child.stderr.take().ok_or_else(|| anyhow!("sem saída do cloudflared"))?;
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        for line in BufReader::new(stderr).lines().map_while(Result::ok) {
            if let Some(u) = find_url(&line) {
                let _ = tx.send(u);
            }
        }
    });
    match rx.recv_timeout(URL_TIMEOUT) {
        Ok(url) => Ok((child, url)),
        // A saída fechou antes de qualquer endereço: o cloudflared morreu.
        // Acontece no boot, quando ainda não há rede. A mensagem antiga dizia
        // "não disse o endereço em 90s" mesmo quando tinha morrido em 1 s.
        Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
            let status = child.wait().map(|s| s.to_string()).unwrap_or_else(|e| e.to_string());
            Err(anyhow!("o cloudflared saiu sem dar endereço ({status}); sem rede ainda?"))
        }
        Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
            let _ = child.kill();
            let _ = child.wait();
            Err(anyhow!("o cloudflared não disse o endereço em {}s", URL_TIMEOUT.as_secs()))
        }
    }
}

/// Acha `https://algo.trycloudflare.com` no meio da moldura que o
/// cloudflared desenha em volta do endereço.
fn find_url(line: &str) -> Option<String> {
    let start = line.find("https://")?;
    let rest = &line[start..];
    let end = rest.find(|c: char| !(c.is_ascii_alphanumeric() || "-._~:/".contains(c))).unwrap_or(rest.len());
    let url = rest[..end].trim_end_matches('/');
    url.strip_suffix(".trycloudflare.com").map(|_| url.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_address_is_picked_out_of_the_frame() {
        let line = "2026-09-16T02:11:04Z INF |  https://alpha-module-skip.trycloudflare.com    |";
        assert_eq!(find_url(line).as_deref(), Some("https://alpha-module-skip.trycloudflare.com"));
        assert_eq!(find_url("| https://fields-edmonton-announce-infant.trycloudflare.com |").as_deref(), Some("https://fields-edmonton-announce-infant.trycloudflare.com"));
    }

    #[test]
    fn other_addresses_in_the_log_are_ignored() {
        for line in [
            "INF Requesting new quick Tunnel on trycloudflare.com...",
            "INF See https://developers.cloudflare.com/argo-tunnel for help",
            "ERR failed to connect to https://region1.v2.argotunnel.com",
            "sem endereço nenhum",
        ] {
            assert_eq!(find_url(line), None, "{line}");
        }
    }
}
