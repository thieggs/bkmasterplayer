//! Compara o tempo de análise dos modelos de batida numa faixa, do jeito que o
//! app faz (só nas regiões de começo e fim).
//! Uso: cargo run --release --example bench_models -- <arquivo> [pasta_dos_modelos]
use std::fs::File;
use std::time::Instant;

use beat_this::{BeatThis, RtenRuntime};
use player_engine::engine::analysis::{analysis_regions, decode_all, device_profile, BeatModel};

fn main() -> anyhow::Result<()> {
    let path = std::env::args().nth(1).expect("arquivo");
    let models = std::env::args()
        .nth(2)
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../assets/models"));
    let p = device_profile();
    println!("aparelho: {} núcleos, AVX2+FMA: {}, recomendado: {}", p.cores, p.avx2, p.recommended.name());

    let t = Instant::now();
    let ext = std::path::Path::new(&path).extension().map(|e| e.to_string_lossy().to_string());
    let audio = decode_all(Box::new(File::open(&path)?), ext.as_deref())?;
    let dur = audio.mono.len() as f64 / audio.rate as f64;
    let regions = analysis_regions(dur);
    let analyzed: f64 = regions.iter().map(|(a, b)| b - a).sum();
    println!("decodificar: {:.1?} ({dur:.0} s de áudio, rede roda em {analyzed:.0} s)", t.elapsed());

    for m in [BeatModel::Small, BeatModel::Full] {
        let file = models.join(m.file_name());
        if !file.exists() {
            println!("{}: modelo ausente em {file:?}", m.name());
            continue;
        }
        let t = Instant::now();
        let mut bt = BeatThis::new(&RtenRuntime, &models.join("mel_spectrogram.onnx"), &file)?;
        let load = t.elapsed();
        let t = Instant::now();
        let mut beats = 0;
        for (a, b) in &regions {
            let i0 = (a * audio.rate as f64) as usize;
            let i1 = ((b * audio.rate as f64) as usize).min(audio.mono.len());
            beats += bt.analyze_audio(&audio.mono[i0..i1], audio.rate)?.beats.len();
        }
        println!("{:<5}: carregar {load:.1?}, rede {:.1?} ({beats} batidas)", m.name(), t.elapsed());
    }
    Ok(())
}
