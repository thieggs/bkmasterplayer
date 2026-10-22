//! Pico de memória de cada etapa da análise do AutoMix (decodificar, carregar
//! os modelos, rede de batidas, montar o resultado). Linux: zera o pico entre
//! as etapas por `/proc/self/clear_refs`.
//!
//! Uso: cargo run --release --example memprof -- <arquivo>
use std::fs::File;
use std::path::{Path, PathBuf};
use std::time::Instant;

use beat_this::{BeatThis, RtenRuntime};
use player_engine::engine::analysis::{analysis_regions, build_analysis, decode_all, BeatRegion};

fn status(field: &str) -> u64 {
    std::fs::read_to_string("/proc/self/status")
        .unwrap_or_default()
        .lines()
        .find(|l| l.starts_with(field))
        .and_then(|l| l.split_whitespace().nth(1)?.parse().ok())
        .unwrap_or(0)
        / 1024
}

fn step(name: &str, t: Instant) {
    if std::env::var_os("TRIM").is_some() {
        // SAFETY: só pede ao alocador do glibc para devolver o que está livre.
        unsafe { libc::malloc_trim(0) };
    }
    println!("{name:<28} pico {:>5} MB  agora {:>5} MB  {:>6.2} s", status("VmHWM:"), status("VmRSS:"), t.elapsed().as_secs_f64());
    let _ = std::fs::write("/proc/self/clear_refs", "5");
}

fn main() -> anyhow::Result<()> {
    let path = std::env::args().nth(1).expect("arquivo");
    let models = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../assets/models");
    let path = Path::new(&path);
    let ext = path.extension().map(|e| e.to_string_lossy().to_string());
    step("início", Instant::now());

    let t = Instant::now();
    let audio = decode_all(Box::new(File::open(path)?), ext.as_deref())?;
    step("decodificar", t);

    let t = Instant::now();
    let mut tracker = BeatThis::new(&RtenRuntime, &models.join("mel_spectrogram.onnx"), &models.join("beat_this_small.onnx"))?;
    step("carregar modelos", t);

    let mut regions = Vec::new();
    for (a, b) in analysis_regions(audio.mono.len() as f64 / audio.rate as f64) {
        let t = Instant::now();
        let i0 = (a * audio.rate as f64) as usize;
        let i1 = ((b * audio.rate as f64) as usize).min(audio.mono.len());
        let r = tracker.analyze_audio_timed(&audio.mono[i0..i1], audio.rate)?;
        println!("  região {a:.0}–{b:.0} s: mel {:.2} s, rede {:.2} s", r.timing.mel.as_secs_f64(), r.timing.predict.as_secs_f64());
        step("rede de batidas", t);
        regions.push(BeatRegion {
            start: a,
            end: b,
            beats: r.analysis.beats.iter().map(|t| *t as f64 + a).collect(),
            downbeats: r.analysis.downbeats.iter().map(|t| *t as f64 + a).collect(),
        });
    }

    let t = Instant::now();
    let a = build_analysis(&audio, &regions);
    step("montar a análise", t);
    println!("bpm {:?}, {} batidas, {:.0} s", a.bpm, a.beats.len(), a.duration);
    Ok(())
}
