//! Confere análises gravadas (cache do app ou pasta `analyses/` do BK
//! Analyzer) com `TrackAnalysis::is_sane`: nenhuma análise de verdade pode ser
//! recusada pela validação.
//!
//! Uso: check_analyses <pasta ou arquivos .json...>
use player_engine::engine::analysis::TrackAnalysis;

fn main() -> anyhow::Result<()> {
    let mut files = Vec::new();
    for a in std::env::args().skip(1) {
        let p = std::path::PathBuf::from(a);
        if p.is_dir() {
            for e in std::fs::read_dir(&p)? {
                let e = e?.path();
                if e.extension().is_some_and(|x| x == "json") {
                    files.push(e);
                }
            }
        } else {
            files.push(p);
        }
    }
    let (mut ok, mut bad, mut unreadable) = (0, 0, 0);
    for f in &files {
        match serde_json::from_slice::<TrackAnalysis>(&std::fs::read(f)?) {
            Ok(a) if a.is_sane() => ok += 1,
            Ok(_) => {
                bad += 1;
                if bad <= 20 {
                    println!("recusada: {}", f.display());
                }
            }
            Err(_) => unreadable += 1,
        }
    }
    println!("{ok} aceitas, {bad} recusadas, {unreadable} ilegíveis (de {})", files.len());
    anyhow::ensure!(bad == 0, "a validação recusou análise de verdade");
    Ok(())
}
