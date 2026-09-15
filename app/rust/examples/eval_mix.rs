//! Mixa faixas reais em sequência com o planejador e o mixer do app e mede o
//! alinhamento das batidas de B com as de A durante a transição (correlação
//! cruzada dos ataques, que independe do tipo de bumbo).
//! Uso: cargo run --release --example eval_mix -- [--models <pasta>] [--full] [--sort-bpm]
//!      [--cache <pasta do exemplo tune>] <faixas...>
use std::fs::File;
use std::path::{Path, PathBuf};
use std::time::Duration;

use player_engine::engine::analysis::{build_analysis, decode_all, Analyzer, BeatModel, BeatRegion, TrackAnalysis};
use player_engine::engine::automix::{plan, AutomixSettings, TempoMap};
use player_engine::engine::deck::{spawn_deck, DeckSource, ProducerParams};
use player_engine::engine::decoder::Decoder;
use player_engine::engine::mixer::{AutomixExec, Mixer, MixerCmd, MixerEvent, Transition};
use rustfft::{num_complex::Complex, FftPlanner};

fn ext(p: &Path) -> Option<String> {
    p.extension().map(|e| e.to_string_lossy().to_string())
}

fn deck(token: u64, path: PathBuf, rate: u32, start_ms: u64, tempo: Option<TempoMap>) -> Box<DeckSource> {
    let e = ext(&path);
    let params = ProducerParams { device_rate: rate, handoff_in: None, start_ms, duration_hint_ms: None, ring_seconds: 2.0, tempo };
    Box::new(spawn_deck(token, 1.0, params, move |_| Decoder::open(Box::new(File::open(&path)?), e.as_deref(), None)))
}

/// Fluxo espectral (ataques), passo de 1 ms; o quadro i é o instante i ms.
fn flux(mono: &[f32], rate: f64) -> Vec<f32> {
    const N: usize = 1024;
    let fft = FftPlanner::<f32>::new().plan_fft_forward(N);
    let win: Vec<f32> = (0..N).map(|i| 0.5 - 0.5 * (2.0 * std::f32::consts::PI * i as f32 / N as f32).cos()).collect();
    let mut prev = vec![0.0f32; N / 2];
    let mut buf = vec![Complex::new(0.0f32, 0.0); N];
    let mut out = Vec::new();
    // Centro da janela no ms exato (passo inteiro de amostras acumularia erro).
    for c in (0..).map(|i: usize| (i as f64 * rate / 1000.0).round() as usize).take_while(|c| *c < mono.len()) {
        for i in 0..N {
            let j = (c + i).checked_sub(N / 2);
            buf[i] = Complex::new(j.and_then(|j| mono.get(j)).copied().unwrap_or(0.0) * win[i], 0.0);
        }
        fft.process(&mut buf);
        let mut f = 0.0f32;
        for k in 1..N / 2 {
            let m = (1.0 + 1000.0 * buf[k].norm()).ln();
            f += (m - prev[k]).max(0.0);
            prev[k] = m;
        }
        out.push(f);
    }
    out
}

/// Envelope da banda do bumbo (passa-baixas de fase zero em 150 Hz, RMS
/// centrado de 5 ms), um valor por ms.
fn low_env(mono: &[f32], rate: f64) -> Vec<f32> {
    let w = 2.0 * std::f64::consts::PI * 150.0 / rate;
    let alpha = w.sin() / (2.0 * 0.7071);
    let a0 = 1.0 + alpha;
    let (b0, b1, a1, a2) = (((1.0 - w.cos()) / 2.0) / a0, (1.0 - w.cos()) / a0, (-2.0 * w.cos()) / a0, (1.0 - alpha) / a0);
    let run = |x: &mut Vec<f64>| {
        let (mut x1, mut x2, mut y1, mut y2) = (0.0, 0.0, 0.0, 0.0);
        for v in x.iter_mut() {
            let y = b0 * *v + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2;
            (x2, x1, y2, y1) = (x1, *v, y1, y);
            *v = y;
        }
    };
    let mut y: Vec<f64> = mono.iter().map(|v| *v as f64).collect();
    run(&mut y);
    y.reverse();
    run(&mut y);
    y.reverse();
    let mut cum = vec![0.0f64; y.len() + 1];
    for (i, v) in y.iter().enumerate() {
        cum[i + 1] = cum[i] + v * v;
    }
    let half = (0.0025 * rate) as usize;
    (0..)
        .map(|k: usize| (k as f64 * rate / 1000.0).round() as usize)
        .take_while(|i| *i < y.len())
        .map(|i| {
            let (a, b) = (i.saturating_sub(half), (i + half).min(y.len()));
            ((cum[b] - cum[a]) / (b - a).max(1) as f64).sqrt() as f32
        })
        .collect()
}

/// Média do envelope (1 valor/ms) em torno de cada batida, de -100 a +150 ms.
fn beat_profile(env: &[f32], beats_ms: &[i64]) -> Vec<f32> {
    let mut acc = vec![0.0f32; 251];
    for &b in beats_ms {
        for (j, v) in acc.iter_mut().enumerate() {
            let i = b + j as i64 - 100;
            if i >= 0 {
                *v += env.get(i as usize).copied().unwrap_or(0.0);
            }
        }
    }
    acc
}

/// Nitidez do perfil: pico perto da batida (±50 ms) sobre a mediana.
fn clarity(p: &[f32]) -> f32 {
    let mut s = p.to_vec();
    s.sort_by(|a, b| a.partial_cmp(b).unwrap());
    p[50..151].iter().cloned().fold(f32::MIN, f32::max) / s[s.len() / 2].max(1e-9)
}

/// Pico do perfil (ms relativos à batida).
fn peak_ms(p: &[f32]) -> i64 {
    p[50..180].iter().enumerate().fold((0, f32::MIN), |m, (i, v)| if *v > m.1 { (i, *v) } else { m }).0 as i64 - 50
}

/// Ataque do perfil: 50% entre o vale antes do pico e o pico (ms relativos).
fn attack_ms(p: &[f32]) -> i64 {
    let ip = 50 + p[50..180].iter().enumerate().fold((0, f32::MIN), |m, (i, v)| if *v > m.1 { (i, *v) } else { m }).0;
    let (im, low) = p[20..=ip].iter().enumerate().fold((0, f32::MAX), |m, (i, v)| if *v < m.1 { (i, *v) } else { m });
    let thr = low + 0.5 * (p[ip] - low);
    (20 + im..=ip).find(|&i| p[i] >= thr).unwrap_or(ip) as i64 - 100
}

fn from_cache(dir: &Path, p: &Path) -> TrackAnalysis {
    let raw: serde_json::Value =
        serde_json::from_slice(&std::fs::read(dir.join(format!("{}.json", p.file_name().unwrap().to_string_lossy()))).expect("sem cache da faixa")).unwrap();
    let list = |r: &serde_json::Value, k: &str| r[k].as_array().map(|v| v.iter().filter_map(|x| x.as_f64()).collect()).unwrap_or_default();
    let regions: Vec<BeatRegion> = raw["regions"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| BeatRegion { start: r["start"].as_f64().unwrap(), end: r["end"].as_f64().unwrap(), beats: list(r, "beats"), downbeats: list(r, "downbeats") })
        .collect();
    let audio = decode_all(Box::new(File::open(p).unwrap()), ext(p).as_deref()).unwrap();
    build_analysis(&audio, &regions)
}

fn main() -> anyhow::Result<()> {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let mut models = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../assets/models");
    let mut full = false;
    if let Some(i) = args.iter().position(|a| a == "--models") {
        models = PathBuf::from(args.remove(i + 1));
        args.remove(i);
    }
    if let Some(i) = args.iter().position(|a| a == "--full") {
        full = true;
        args.remove(i);
    }
    let sort_bpm = args.iter().position(|a| a == "--sort-bpm").map(|i| args.remove(i)).is_some();
    // Batidas da rede já guardadas pelo exemplo `tune` (<pasta>/<modelo>/<arquivo>.json):
    // refaz só o resto da análise, com o código atual.
    let mut tune_cache: Option<PathBuf> = None;
    if let Some(i) = args.iter().position(|a| a == "--cache") {
        tune_cache = Some(PathBuf::from(args.remove(i + 1)));
        args.remove(i);
    }
    let cache = std::env::temp_dir().join(format!("eval-mix-{}", std::process::id()));
    let analyzer = Analyzer::new(&models, &cache);
    if full {
        analyzer.set_model(BeatModel::Full);
    }
    println!("modelo: {}", analyzer.model().name());
    let mut tracks: Vec<(PathBuf, TrackAnalysis)> = args
        .iter()
        .map(PathBuf::from)
        .map(|p| {
            let a = match &tune_cache {
                Some(dir) => from_cache(&dir.join(if full { "full" } else { "small" }), &p),
                None => analyzer.analyze_uncached(Box::new(File::open(&p).unwrap()), ext(&p).as_deref()).unwrap(),
            };
            (p, a)
        })
        .collect();
    if sort_bpm {
        // Ordem de DJ: BPMs vizinhos (a maioria das transições cabe em ±8%).
        tracks.sort_by(|x, y| x.1.bpm.unwrap_or(0.0).partial_cmp(&y.1.bpm.unwrap_or(0.0)).unwrap());
    }
    let (paths, analyses): (Vec<PathBuf>, Vec<TrackAnalysis>) = tracks.into_iter().unzip();
    let settings = AutomixSettings::default();
    let (mut total, mut synced, mut good) = (0, 0, 0);
    let mut lags = Vec::new();
    for i in 0..paths.len().saturating_sub(1) {
        let (a_path, b_path) = (&paths[i], &paths[i + 1]);
        let (aa, ab) = (&analyses[i], &analyses[i + 1]);
        let name = |p: &PathBuf| p.file_stem().unwrap().to_string_lossy().to_string();
        total += 1;
        let p = plan(aa, ab, &settings, 0.0);
        println!("\n{} → {}: {} [{:?}{}]", name(a_path), name(b_path), p.summary, p.style, if p.beatmatched { "" } else { ", SEM SINCRONIA" });
        if !p.beatmatched || p.duration < 1.0 {
            continue;
        }
        synced += 1;

        let audio_a = decode_all(Box::new(File::open(a_path)?), ext(a_path).as_deref())?;
        let rate = audio_a.rate;
        let rf = rate as f64;
        let a_start_ms = ((p.from_start - 3.0).max(0.0) * 1000.0).round() as u64;
        let a_start = a_start_ms as f64 / 1000.0;
        let (cmd_tx, cmd_rx) = rtrb::RingBuffer::new(64);
        let (ev_tx, mut ev_rx) = rtrb::RingBuffer::new(1024);
        let mut mixer = Mixer::new(rate, cmd_rx, ev_tx);
        let mut cmd_tx = cmd_tx;
        let len = (p.duration * rf).round() as u64;
        let tempo = TempoMap { speed: p.speed, hold: len as f64, ramp: p.ramp * rf };
        let _ = cmd_tx.push(MixerCmd::Play(deck(1, a_path.clone(), rate, a_start_ms, None)));
        let exec = AutomixExec {
            style: p.style,
            start_native: (p.from_start * rf).round() as u64,
            len,
            swap_at: (p.swap_at * len as f64) as u64,
            beat: (p.beat * rf) as u64,
            echo_buf: vec![0.0; rate as usize * 4],
            mute_from: true,
        };
        let _ = cmd_tx.push(MixerCmd::SetNext(
            Some(deck(2, b_path.clone(), rate, (p.to_start * 1000.0).round() as u64, Some(tempo))),
            Transition::Automix(Box::new(exec)),
        ));
        std::thread::sleep(Duration::from_millis(500));
        let frames = ((p.from_start - a_start + p.duration + 1.0) * rf) as usize;
        let mut out = Vec::with_capacity(frames * 2);
        let mut block = vec![0.0f32; 1024];
        let mut underruns = 0;
        while out.len() < frames * 2 {
            mixer.render(&mut block);
            out.extend_from_slice(&block);
            while let Ok(e) = ev_rx.pop() {
                if let MixerEvent::Buffering(true) = e {
                    underruns += 1;
                }
            }
            std::thread::sleep(Duration::from_micros(300));
        }
        let b_out: Vec<f32> = out.chunks(2).map(|f| (f[0] + f[1]) * 0.5).collect();
        // Batidas de A (grade do fim) na parte da sobreposição depois da troca
        // de grave, em ms: na saída (só B) e no arquivo de A (tempo nativo).
        let ga = aa.grid_at(p.from_start).unwrap();
        // Ataques (banda larga): do primeiro quarto da sobreposição em diante
        // (B já audível). Grave: só depois da troca de grave.
        let beats_from = |t: f64| -> Vec<f64> {
            let first = ((t - ga.t0) / ga.period).ceil() as i64 + 1;
            let last = ((p.from_start + p.duration - ga.t0) / ga.period).floor() as i64 - 1;
            (first..=last).map(|k| ga.beat_time(k as f64)).collect()
        };
        let beats_a = beats_from(p.from_start + 0.25 * p.duration);
        let beats_low = beats_from(p.from_start + p.swap_at * p.duration);
        let ms = |v: f64| (v * 1000.0).round() as i64;
        let at = |v: &[f64]| -> (Vec<i64>, Vec<i64>) { (v.iter().map(|t| ms(*t)).collect(), v.iter().map(|t| ms(t - a_start)).collect()) };
        let ((at_a, at_out), (low_a, low_out)) = (at(&beats_a), at(&beats_low));
        let (fa, fb) = (flux(&audio_a.mono, rf), flux(&b_out, rf));
        let (la, lb) = (low_env(&audio_a.mono, rf), low_env(&b_out, rf));
        let (pfa, pfb) = (beat_profile(&fa, &at_a), beat_profile(&fb, &at_out));
        let (pla, plb) = (beat_profile(&la, &low_a), beat_profile(&lb, &low_out));
        let (xa, xb, ka, kb) = (peak_ms(&pfa), peak_ms(&pfb), attack_ms(&pla), attack_ms(&plb));
        let lag = xb - xa;
        let (ca, cb) = (clarity(&pfa), clarity(&pfb));
        if std::env::var_os("PROFILE").is_some() {
            // Uma coluna a cada 5 ms, de -100 a +150 ms; '|' é a batida.
            let show = |p: &[f32]| -> String {
                let max = p.iter().cloned().fold(1e-9f32, f32::max);
                let min = p.iter().cloned().fold(f32::MAX, f32::min);
                p.iter()
                    .step_by(5)
                    .enumerate()
                    .map(|(j, v)| if j == 20 { '|' } else { " .:-=+*#%@".chars().nth((((v - min) / (max - min).max(1e-9)) * 9.0).round() as usize).unwrap() })
                    .collect()
            };
            println!("   A fluxo [{}]  B fluxo [{}]", show(&pfa), show(&pfb));
            println!("   A grave [{}]  B grave [{}]", show(&pla), show(&plb));
        }
        println!(
            "   mix {:.1}s a {:.4}x, {} batidas medidas | ataque (fluxo): A {xa:+} ms, B {xb:+} ms → Δ {:+} ms | grave: A {ka:+} ms, B {kb:+} ms → Δ {:+} ms | underruns {underruns}",
            p.duration,
            p.speed,
            beats_a.len(),
            xb - xa,
            kb - ka
        );
        if ca < 1.5 || cb < 1.5 {
            println!("   (sem batida clara para medir: nitidez A {ca:.1}, B {cb:.1})");
            continue;
        }
        lags.push(lag);
        if lag.abs() <= 10 {
            good += 1;
        }
    }
    let mut abs: Vec<i64> = lags.iter().map(|l| l.abs()).collect();
    abs.sort();
    let med = abs.get(abs.len() / 2).copied().unwrap_or(0);
    println!(
        "\n{total} transições: {synced} sincronizadas; medidas {}: {good} com |atraso| ≤ 10 ms, mediana {med} ms; atrasos {lags:?}",
        lags.len()
    );
    let _ = std::fs::remove_dir_all(cache);
    Ok(())
}
