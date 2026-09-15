//! Diagnóstico da análise do AutoMix, igual à do app (começo e fim da faixa):
//! por faixa e por grade, os números que decidem se a batida é confiável, e
//! as batidas detectadas num JSON (para comparar aparelhos/processadores).
//!
//! Uso: diag [--models <pasta>] [--full] [--out <pasta>] <arquivos...>
//! (no PC: cargo run --release --example diag -- …; no celular: binário
//! aarch64-linux-android rodado por adb shell).
use std::fs::File;
use std::path::{Path, PathBuf};
use std::time::Instant;

use player_engine::engine::analysis::{Analyzer, BeatModel};

fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1).peekable();
    let mut models = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../assets/models");
    let mut out: Option<PathBuf> = None;
    let mut model = BeatModel::Small;
    let mut files = Vec::new();
    while let Some(a) = args.next() {
        match a.as_str() {
            "--models" => models = PathBuf::from(args.next().expect("pasta")),
            "--out" => out = Some(PathBuf::from(args.next().expect("pasta"))),
            "--full" => model = BeatModel::Full,
            _ => files.push(a),
        }
    }
    let cache = std::env::temp_dir().join(format!("bk-diag-{}", std::process::id()));
    let analyzer = Analyzer::new(&models, &cache);
    let chosen = analyzer.set_model(model);
    println!("# arch={} modelo={}", std::env::consts::ARCH, chosen.name());
    let (mut ok, mut total) = (0, 0);
    for f in &files {
        total += 1;
        let path = Path::new(f);
        let ext = path.extension().map(|e| e.to_string_lossy().to_string());
        let t = Instant::now();
        let a = match analyzer.analyze_uncached(Box::new(File::open(path)?), ext.as_deref()) {
            Ok(a) => a,
            Err(e) => {
                println!("{} ERRO {e:#}", name(path));
                continue;
            }
        };
        let secs = t.elapsed().as_secs_f64();
        if a.has_beat() {
            ok += 1;
        }
        println!(
            "{} | {:.1}s | bpm {:?} | confiável {} | batidas {} | {:.0} s de áudio",
            name(path),
            secs,
            a.bpm,
            if a.has_beat() { "SIM" } else { "não" },
            a.beats.len(),
            a.duration
        );
        for g in &a.grids {
            println!(
                "    grade {:>5.1}–{:>5.1}s  {:.2} BPM  lock {:.2} ({} janelas)  resíduo {:.1} ms  cobertura {:.2}  inliers {}  validada {}  → {}",
                g.start,
                g.end,
                g.bpm(),
                g.lock,
                g.windows.len(),
                g.residual * 1000.0,
                g.coverage,
                g.inliers,
                g.validated,
                if g.is_steady() { "ESTÁVEL" } else { "instável" }
            );
        }
        if let Some(dir) = &out {
            std::fs::create_dir_all(dir)?;
            let j = serde_json::json!({ "beats": a.beats, "downbeats": a.downbeats, "bpm": a.bpm });
            std::fs::write(dir.join(format!("{}.{}.json", name(path), chosen.name())), j.to_string())?;
        }
    }
    println!("# confiáveis: {ok} de {total}");
    let _ = std::fs::remove_dir_all(&cache);
    Ok(())
}

fn name(p: &Path) -> String {
    p.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default()
}
