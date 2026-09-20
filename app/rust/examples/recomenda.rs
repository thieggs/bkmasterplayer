//! Confere o arquivo de vetores com a biblioteca de verdade e mede o tempo.
//! Uso: cargo run --release --example recomenda -- <arquivo.bkvec> [id]
use std::path::PathBuf;
use std::time::Instant;

use player_engine::engine::recommend::{Recommender, Style};

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let path = PathBuf::from(args.first().expect("passe o arquivo .bkvec"));
    let t0 = Instant::now();
    let r = Recommender::load(&path)?;
    println!("carregou {} músicas em {:?} ({} estilos)", r.len(), t0.elapsed(), r.styles.len());

    let seed = args.get(1).cloned().unwrap_or_default();
    let seed = if seed.is_empty() { first_id(&path)? } else { seed };
    println!("semente: {seed}\n");
    println!("{:8} {:>7} {:>7} {:>7} {:>7} {:>8}", "estilo", "tempo", "topo", "mediana", "pior", "empates");
    for style in ["sound", "mood", "genre", "era", "lyrics", "mix", "server"] {
        let s = Style::parse(style).unwrap();
        let t = Instant::now();
        // Pede tudo para ver a distribuição, não só o topo.
        let hits = r.similar(&seed, s, usize::MAX, None);
        let dt = t.elapsed();
        let topo = hits.first().map(|h| h.score).unwrap_or(0.0);
        let meio = hits[hits.len() / 2].score;
        let pior = hits.last().map(|h| h.score).unwrap_or(0.0);
        // Quantas ficam coladas no topo: muitas = a nota não separa nada.
        let empates = hits.iter().filter(|h| h.score > topo - 0.01).count();
        println!("{style:8} {dt:>7.2?} {topo:>7.3} {meio:>7.3} {pior:>7.3} {empates:>8}");
    }
    Ok(())
}

/// Primeiro id do arquivo, só para ter uma semente qualquer.
fn first_id(path: &PathBuf) -> anyhow::Result<String> {
    let raw = std::fs::read(path)?;
    let vocab = u32::from_le_bytes([raw[32], raw[33], raw[34], raw[35]]) as usize;
    let at = 36 + vocab;
    Ok(String::from_utf8_lossy(&raw[at..at + 32]).trim_end_matches('\0').to_string())
}
