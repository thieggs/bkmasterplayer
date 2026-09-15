//! Afinação da análise do AutoMix em muitas faixas: roda a rede de batidas
//! uma vez por faixa (guarda as batidas de cada região) e refaz só o resto
//! (grades, confiabilidade, estrutura) a cada mudança no código. Mostra, por
//! faixa, se sincroniza na entrada e na saída e, se não, por quê.
//!
//! Uso: tune [--models <pasta>] [--full] --cache <pasta> <arquivos...>
//! (a rede é o passo caro: rode a primeira vez numa máquina forte e copie o
//! cache; depois, cada rodada é só decodificar e ajustar)
use std::path::{Path, PathBuf};

use beat_this::{BeatThis, RtenRuntime};
use player_engine::engine::analysis::{analysis_regions, build_analysis, decode_all, BeatModel, BeatRegion};
use player_engine::engine::automix::{bar_entry, bar_exit, AutomixSettings};
use rayon::prelude::*;
use serde_json::json;

fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let mut models = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../assets/models");
    let mut model = BeatModel::Small;
    let mut cache = PathBuf::from("tune-cache");
    let mut files = Vec::new();
    while let Some(a) = args.next() {
        match a.as_str() {
            "--models" => models = PathBuf::from(args.next().expect("pasta")),
            "--full" => model = BeatModel::Full,
            "--cache" => cache = PathBuf::from(args.next().expect("pasta")),
            _ => files.push(PathBuf::from(a)),
        }
    }
    let cache = cache.join(model.name());
    std::fs::create_dir_all(&cache)?;
    let cache_of = |f: &Path| cache.join(format!("{}.json", f.file_name().unwrap().to_string_lossy()));

    // 1) Rede (só o que falta no cache), uma faixa por vez: ela já usa todos os núcleos.
    let missing: Vec<&PathBuf> = files.iter().filter(|f| !cache_of(f).exists()).collect();
    if !missing.is_empty() {
        let mut tracker =
            BeatThis::new(&RtenRuntime, &models.join("mel_spectrogram.onnx"), &models.join(model.file_name())).map_err(|e| anyhow::anyhow!("{e}"))?;
        for (i, f) in missing.iter().enumerate() {
            let t = std::time::Instant::now();
            let audio = match decode_all(Box::new(std::fs::File::open(f)?), ext(f).as_deref()) {
                Ok(a) => a,
                Err(e) => {
                    eprintln!("{}: {e:#}", f.display());
                    continue;
                }
            };
            let mut regions = Vec::new();
            for (a, b) in analysis_regions(audio.mono.len() as f64 / audio.rate as f64) {
                let i0 = (a * audio.rate as f64) as usize;
                let i1 = ((b * audio.rate as f64) as usize).min(audio.mono.len());
                let r = tracker.analyze_audio(&audio.mono[i0..i1], audio.rate).map_err(|e| anyhow::anyhow!("{e}"))?;
                regions.push(json!({
                    "start": a, "end": b,
                    "beats": r.beats.iter().map(|t| *t as f64 + a).collect::<Vec<_>>(),
                    "downbeats": r.downbeats.iter().map(|t| *t as f64 + a).collect::<Vec<_>>(),
                }));
            }
            std::fs::write(cache_of(f), json!({ "regions": regions }).to_string())?;
            eprintln!("rede {}/{}: {} ({:.1} s)", i + 1, missing.len(), name(f), t.elapsed().as_secs_f64());
        }
    }

    // 2) O resto da análise, em paralelo.
    let rows: Vec<(String, String, String)> = files
        .par_iter()
        .filter_map(|f| {
            let raw: serde_json::Value = serde_json::from_slice(&std::fs::read(cache_of(f)).ok()?).ok()?;
            let regions: Vec<BeatRegion> = raw["regions"]
                .as_array()?
                .iter()
                .map(|r| BeatRegion {
                    start: r["start"].as_f64().unwrap_or(0.0),
                    end: r["end"].as_f64().unwrap_or(0.0),
                    beats: r["beats"].as_array().map(|v| v.iter().filter_map(|x| x.as_f64()).collect()).unwrap_or_default(),
                    downbeats: r["downbeats"].as_array().map(|v| v.iter().filter_map(|x| x.as_f64()).collect()).unwrap_or_default(),
                })
                .collect();
            let audio = decode_all(Box::new(std::fs::File::open(f).ok()?), ext(f).as_deref()).ok()?;
            let a = build_analysis(&audio, &regions);
            // Mesmas categorias do painel do BK Analyzer.
            let (head, tail) = a.sync_ends();
            let (bin, bout) = (bar_entry(&a).is_some(), bar_exit(&a, &AutomixSettings::default(), 0.0).is_some());
            let cat = if head && tail {
                "ok"
            } else if (head || bin) && (tail || bout) {
                "bars"
            } else if head || bin || tail || bout {
                "partial"
            } else {
                "nobeat"
            };
            let why = a.beat_problem().unwrap_or_default();
            Some((cat.to_string(), name(f), format!("{why}\n{}", a.grid_summary())))
        })
        .collect();
    let mut rows = rows;
    rows.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
    let verbose = std::env::var_os("TUNE_VERBOSE").is_some();
    for (cat, n, detail) in &rows {
        let mut lines = detail.lines();
        println!("[{cat:7}] {n:<60.60} {}", lines.next().unwrap_or(""));
        if verbose && cat != "ok" {
            for l in lines {
                println!("            {l}");
            }
        }
    }
    let count = |c: &str| rows.iter().filter(|r| r.0 == c).count();
    println!(
        "# sincronizam: {} · no compasso: {} · só uma ponta: {} · sem batida: {} · de {}",
        count("ok"),
        count("bars"),
        count("partial"),
        count("nobeat"),
        rows.len()
    );
    Ok(())
}

fn ext(p: &Path) -> Option<String> {
    p.extension().map(|e| e.to_string_lossy().to_string())
}

fn name(p: &Path) -> String {
    p.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default()
}
