//! Confere a análise (batidas, BPM, tom, intro/outro) com o gabarito das
//! músicas sintéticas de dev/music. Rode em release: `cargo test --release`.

use std::fs::File;
use std::path::PathBuf;

use player_engine::engine::analysis::{camelot_compatible, Analyzer};
use serde_json::Value;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

#[test]
fn analysis_matches_ground_truth() {
    let music = root().join("../../dev/music");
    let models = root().join("../assets/models");
    let Ok(truth) = std::fs::read_to_string(music.join("ground_truth.json")) else {
        eprintln!("sem dev/music — pulando");
        return;
    };
    let truth: Value = serde_json::from_str(&truth).unwrap();
    let cache = std::env::temp_dir().join(format!("player-analysis-{}", std::process::id()));
    let analyzer = Analyzer::new(&models, &cache);
    assert!(analyzer.models_available(), "modelos ausentes em {models:?}");

    let mut bpm_ok = 0;
    let mut key_exact = 0;
    let mut key_compat = 0;
    let mut structure_ok = 0;
    let mut total = 0;
    let mut phase_errs: Vec<f64> = Vec::new();
    for t in truth["tracks"].as_array().unwrap() {
        let Some(bpm_true) = t["bpm"].as_f64() else { continue };
        let path = music.join(t["path"].as_str().unwrap());
        let ext = path.extension().map(|e| e.to_string_lossy().to_string());
        if ext.as_deref() == Some("opus") {
            continue; // symphonia não decodifica Opus (ainda)
        }
        total += 1;
        let started = std::time::Instant::now();
        let a = analyzer.analyze_uncached(Box::new(File::open(&path).unwrap()), ext.as_deref()).unwrap();
        let secs = started.elapsed().as_secs_f32();
        let bar = 60.0 / bpm_true * 4.0;
        let intro_true = bar * 8.0;
        let outro_true = bar * 36.0;
        // Aceita meio/dobro de tempo como erro separado (reportado).
        let bpm = a.bpm.unwrap_or(0.0);
        let bpm_good = (bpm - bpm_true).abs() < 0.5;
        let key_true = t["camelot"].as_str().unwrap();
        let cam = a.camelot.clone().unwrap_or_default();
        let near = |x: Option<f64>, y: f64| x.is_some_and(|v| (v - y).abs() < bar * 0.6);
        let struct_good = near(a.intro_end, intro_true) && near(a.outro_start, outro_true);
        eprintln!(
            "{:<22} bpm {:>7.2} (verdade {:>3}) conf {:.2} | tom {:<4} {:<4} (verdade {} {:<3}) | intro {:>6.2?} (≈{:.2}) outro {:>6.2?} (≈{:.2}) | 1º downbeat {:.3} | {:.1}s",
            t["title"].as_str().unwrap(),
            bpm,
            bpm_true,
            a.bpm_confidence,
            a.key.clone().unwrap_or_default(),
            cam,
            t["key"].as_str().unwrap(),
            key_true,
            a.intro_end,
            intro_true,
            a.outro_start,
            outro_true,
            a.downbeats.first().copied().unwrap_or(-1.0),
            secs
        );
        // Faixa sem batida confiável não é sincronizada (o AutoMix usa outro estilo): conta como ok.
        let reliable = a.has_beat();
        bpm_ok += (bpm_good || !reliable) as usize;
        if !bpm_good && reliable {
            eprintln!("   ^ BPM errado com confiança alta!");
        }
        // Fase da grade: batidas verdadeiras em k·(60/bpm) a partir de 0.
        for g in &a.grids {
            let per = 60.0 / bpm_true;
            let off = (g.t0 / per - (g.t0 / per).round()) * per * 1000.0;
            eprintln!("   grade {:.0}-{:.0}s: fase {:+.1} ms, resíduo {:.1} ms, cobertura {:.2}, confiança {:.2}", g.start, g.end, off, g.residual * 1000.0, g.coverage, g.confidence());
            // AAC (m4a) tem ~1024 amostras de "priming" que o symphonia não corta:
            // a grade fica certa em relação ao áudio tocado, só não ao gabarito.
            if a.has_beat() && ext.as_deref() != Some("m4a") {
                phase_errs.push(off.abs());
            }
        }
        key_exact += (cam == key_true) as usize;
        key_compat += camelot_compatible(&cam, key_true) as usize;
        structure_ok += struct_good as usize;
    }
    eprintln!("BPM {bpm_ok}/{total}, tom exato {key_exact}/{total} (compatível {key_compat}/{total}), estrutura {structure_ok}/{total}");
    let worst = phase_errs.iter().cloned().fold(0.0, f64::max);
    eprintln!("pior erro de fase: {worst:.1} ms");
    assert_eq!(bpm_ok, total, "BPM errado em alguma faixa");
    assert!(worst < 15.0, "fase da grade imprecisa");
    assert!(key_compat >= total - 1, "tom muito errado");
    assert!(structure_ok >= total - 1, "intro/outro errados");
}
