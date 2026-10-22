//! As N mais parecidas com uma música em cada método, com a nota (para
//! conferir à mão o que a rádio vai sugerir).
//! Uso: cargo run --release --example parecidas -- <arquivo.bkvec> <id> [N]
use std::path::PathBuf;

use player_engine::engine::recommend::{Recommender, Style};

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let r = Recommender::load(&PathBuf::from(&args[0]))?;
    let n: usize = args.get(2).and_then(|x| x.parse().ok()).unwrap_or(20);
    for style in ["sound", "mood", "genre", "era", "lyrics", "mix", "server"] {
        for h in r.similar(&args[1], Style::parse(style).unwrap(), n, None) {
            println!("{style}\t{}\t{:.3}", h.id, h.score);
        }
    }
    Ok(())
}
