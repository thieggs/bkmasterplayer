//! Analisa um arquivo e mostra tempos por etapa. Uso: cargo run --release --example analyze -- <arquivo>
use std::fs::File;
use std::time::Instant;
use beat_this::{BeatThis, RtenRuntime};
use player_engine::engine::analysis::{build_analysis, decode_all, BeatRegion};

fn main() -> anyhow::Result<()> {
    let path = std::env::args().nth(1).expect("arquivo");
    // MODELS=<pasta> e MODEL=beat_this.onnx para testar o modelo completo.
    let models = std::env::var("MODELS").map(std::path::PathBuf::from).unwrap_or_else(|_| std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../assets/models"));
    let model = std::env::var("MODEL").unwrap_or_else(|_| "beat_this_small.onnx".into());
    let t = Instant::now();
    let ext = std::path::Path::new(&path).extension().map(|e| e.to_string_lossy().to_string());
    let audio = decode_all(Box::new(File::open(&path)?), ext.as_deref())?;
    println!("decodificar: {:?} ({} s de áudio)", t.elapsed(), audio.mono.len() / audio.rate as usize);
    let t = Instant::now();
    let mut bt = BeatThis::new(&RtenRuntime, &models.join("mel_spectrogram.onnx"), &models.join(&model))?;
    println!("carregar modelos: {:?}", t.elapsed());
    let t = Instant::now();
    let r = bt.analyze_audio_timed(&audio.mono, audio.rate)?;
    println!("beat-this total {:?} (mel {:?}, rede {:?}, pico {:?})", t.elapsed(), r.timing.mel, r.timing.predict, r.timing.decode);
    let t = Instant::now();
    let dur = audio.mono.len() as f64 / audio.rate as f64;
    let region = BeatRegion { start: 0.0, end: dur, beats: r.analysis.beats.iter().map(|b| *b as f64).collect(), downbeats: r.analysis.downbeats.iter().map(|b| *b as f64).collect() };
    let a = build_analysis(&audio, &[region]);
    println!("grades: {:?}", a.grids);
    let iv: Vec<String> = r.analysis.beats.windows(2).map(|w| format!("{:.2}", w[1]-w[0])).collect();
    println!("intervalos: {}", iv.join(" "));
    println!("resto (tom, loudness, estrutura): {:?}", t.elapsed());
    println!("bpm {:?} conf {} tom {:?} lufs {:?}", a.bpm, a.bpm_confidence, a.key, a.lufs);
    Ok(())
}
