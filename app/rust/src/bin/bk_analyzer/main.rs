//! BK Analyzer: a análise do AutoMix feita no servidor, como a análise sônica
//! do AudioMuse. O coordenador (na máquina do Navidrome) lista a biblioteca
//! pela API Subsonic, reparte as músicas entre os trabalhadores (qualquer
//! máquina com CPU sobrando), guarda as análises e entrega para os players,
//! que só decidem a transição. Painel web com o andamento e as músicas que
//! não deram certo.
//!
//!   bk-analyzer serve  [--data <pasta>] [--listen 0.0.0.0:4540]
//!   bk-analyzer worker --server http://pc:4540 [--jobs N] [--models <pasta>]
//!                      [--model full|small] [--name <nome>] [--on-battery] [--nice N]
//!                      (token em BK_ANALYZER_TOKEN ou --token)
//!   bk-analyzer token  [--data <pasta>]

mod navidrome;
mod server;
mod store;
mod worker;

use std::collections::HashMap;
use std::path::PathBuf;

use anyhow::{anyhow, bail, Result};
use player_engine::engine::analysis::BeatModel;

const USAGE: &str = "BK Analyzer — análise do AutoMix no servidor

  bk-analyzer serve  [--data <pasta>] [--listen 0.0.0.0:4540]
      coordenador: painel em http://<máquina>:4540, fila e análises prontas

  bk-analyzer worker --server http://<coordenador>:4540 [--jobs N]
                     [--models <pasta>] [--model full|small] [--name <nome>]
                     [--on-battery] [--nice 0-19]
      trabalhador (token em BK_ANALYZER_TOKEN ou --token)

  bk-analyzer token  [--data <pasta>]
      mostra o token que os trabalhadores usam";

fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("."))
}

fn data_dir(opts: &HashMap<String, String>) -> PathBuf {
    opts.get("data").map(PathBuf::from).unwrap_or_else(|| {
        std::env::var_os("XDG_DATA_HOME").map(PathBuf::from).unwrap_or_else(|| home().join(".local/share")).join("bk-analyzer")
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

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("serve") => parse(&args[1..], &[]).and_then(|o| {
            let listen = o.get("listen").cloned().unwrap_or_else(|| "0.0.0.0:4540".into());
            server::serve(&data_dir(&o), &listen)
        }),
        Some("worker") => parse(&args[1..], &["on-battery"]).and_then(|o| worker::run(worker_args(&o)?)),
        Some("token") => parse(&args[1..], &[]).and_then(|o| {
            println!("{}", store::Store::open(&data_dir(&o))?.worker_token());
            Ok(())
        }),
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

fn worker_args(o: &HashMap<String, String>) -> Result<worker::Args> {
    let server = o
        .get("server")
        .cloned()
        .or_else(|| std::env::var("BK_ANALYZER_SERVER").ok())
        .ok_or_else(|| anyhow!("falta --server http://<coordenador>:4540"))?;
    let token = o
        .get("token")
        .cloned()
        .or_else(|| std::env::var("BK_ANALYZER_TOKEN").ok())
        .filter(|t| !t.is_empty())
        .ok_or_else(|| anyhow!("falta o token (BK_ANALYZER_TOKEN ou --token; veja no painel)"))?;
    let cores = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4);
    let jobs = match o.get("jobs") {
        Some(j) => j.parse().map_err(|_| anyhow!("--jobs precisa ser um número"))?,
        // A rede usa todos os núcleos numa análise, mas decodificar e o resto
        // da análise usam um só: umas poucas ao mesmo tempo aproveitam melhor.
        None => (cores / 4).clamp(1, 3),
    };
    let models = o.get("models").map(PathBuf::from).unwrap_or_else(|| home().join(".local/share/io.github.playermusica.player_musica/models"));
    let model = match o.get("model").map(String::as_str) {
        None => BeatModel::Full,
        Some(m) => BeatModel::parse(m).ok_or_else(|| anyhow!("--model precisa ser full ou small"))?,
    };
    let name = o.get("name").cloned().unwrap_or_else(|| {
        std::fs::read_to_string("/etc/hostname").map(|h| h.trim().to_string()).ok().filter(|h| !h.is_empty()).unwrap_or_else(|| "trabalhador".into())
    });
    let nice = o.get("nice").map(|n| n.parse::<i32>()).transpose().map_err(|_| anyhow!("--nice precisa ser 0-19"))?.unwrap_or(15).clamp(0, 19);
    Ok(worker::Args {
        server: navidrome::normalize_url(&server),
        token,
        jobs: jobs.max(1),
        models,
        model,
        name,
        on_battery: o.contains_key("on-battery"),
        nice,
    })
}
