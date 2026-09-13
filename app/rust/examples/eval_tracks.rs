//! Avalia a análise em faixas reais: grade, confiança e precisão contra os
//! bumbos do próprio áudio (e se as grades do começo e do fim concordam).
//! Uso: cargo run --release --example eval_tracks -- [--models <pasta>] [--full] <arquivos...>
use std::fs::File;
use std::path::PathBuf;

use player_engine::engine::analysis::{decode_all, Analyzer, BeatGrid, BeatModel};

/// Envelope da banda do bumbo (passa-baixas de fase zero em 150 Hz, RMS
/// centrado de 5 ms), amostrado a cada 0,5 ms.
struct KickEnv {
    step: f64,
    env: Vec<f32>,
}

impl KickEnv {
    fn new(mono: &[f32], rate: f64) -> Self {
        // Biquad passa-baixas (RBJ), ida e volta = fase zero.
        let w = 2.0 * std::f64::consts::PI * 150.0 / rate;
        let alpha = w.sin() / (2.0 * 0.7071);
        let a0 = 1.0 + alpha;
        let b0 = ((1.0 - w.cos()) / 2.0) / a0;
        let b1 = (1.0 - w.cos()) / a0;
        let a1 = (-2.0 * w.cos()) / a0;
        let a2 = (1.0 - alpha) / a0;
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
        let hop = (0.0005 * rate).max(1.0) as usize;
        let env = (0..y.len())
            .step_by(hop)
            .map(|i| {
                let (a, b) = (i.saturating_sub(half), (i + half).min(y.len()));
                ((cum[b] - cum[a]) / (b - a).max(1) as f64).sqrt() as f32
            })
            .collect();
        Self { step: hop as f64 / rate, env }
    }

    /// Ataque do bumbo perto de `t` (±50 ms): cruzamento de 50% entre o vale
    /// antes do pico e o pico (o baixo contínuo do psytrance fica no vale).
    fn onset(&self, t: f64) -> Option<f64> {
        let i0 = ((t - 0.05) / self.step).max(0.0) as usize;
        let i1 = (((t + 0.05) / self.step) as usize).min(self.env.len());
        if i1 <= i0 + 4 {
            return None;
        }
        let w = &self.env[i0..i1];
        let (ip, peak) = w.iter().enumerate().fold((0, 0.0f32), |m, (i, v)| if *v > m.1 { (i, *v) } else { m });
        let (im, low) = w[..=ip].iter().enumerate().fold((0, f32::MAX), |m, (i, v)| if *v < m.1 { (i, *v) } else { m });
        if peak < 0.01 || peak < 2.0 * low {
            return None; // sem bumbo claro
        }
        let thr = low + 0.5 * (peak - low);
        let i = (im..=ip).find(|&i| w[i] >= thr)?;
        Some((i0 + i) as f64 * self.step)
    }
}

/// Envelope médio da banda grave alinhado pela grade, de -150 a +300 ms em
/// passos de 5 ms. Grade certa = ataque nítido sempre no mesmo lugar.
fn profile(kicks: &KickEnv, g: &BeatGrid) -> Vec<f32> {
    let offs: Vec<f64> = (-30..=60).map(|i| i as f64 * 0.005).collect();
    let mut acc = vec![0.0f32; offs.len()];
    let first = ((g.start - g.t0) / g.period).ceil() as i64 + 1;
    let last = ((g.end - g.t0) / g.period).floor() as i64 - 1;
    let mut n = 0;
    for k in first..=last {
        let t = g.beat_time(k as f64);
        for (j, o) in offs.iter().enumerate() {
            let i = ((t + o) / kicks.step) as usize;
            acc[j] += kicks.env.get(i).copied().unwrap_or(0.0);
        }
        n += 1;
    }
    let max = acc.iter().cloned().fold(1e-9, f32::max);
    acc.iter().map(|v| v / max.max(1e-9) * (n as f32 / n.max(1) as f32)).collect()
}

/// Fluxo espectral (ataques), um valor por ms exato.
fn flux(mono: &[f32], rate: f64) -> Vec<f32> {
    use rustfft::{num_complex::Complex, FftPlanner};
    const N: usize = 1024;
    let fft = FftPlanner::<f32>::new().plan_fft_forward(N);
    let win: Vec<f32> = (0..N).map(|i| 0.5 - 0.5 * (2.0 * std::f32::consts::PI * i as f32 / N as f32).cos()).collect();
    let mut prev = vec![0.0f32; N / 2];
    let mut buf = vec![Complex::new(0.0f32, 0.0); N];
    let mut out = Vec::new();
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

/// Deslocamento local (ms) que põe a grade em cima dos ataques, a cada 8
/// compassos: argmax de Σ fluxo(batida + δ), δ em ±40 ms. '?' = sem pico claro.
fn local_offsets(fl: &[f32], g: &BeatGrid) -> String {
    let first = ((g.start - g.t0) / g.period).ceil() as i64;
    let last = ((g.end - g.t0) / g.period).floor() as i64;
    let win = 8 * g.beats_per_bar as i64;
    let mut out = Vec::new();
    let mut k0 = first;
    while k0 + win <= last + 1 {
        let score = |d: i64| -> f32 {
            (k0..k0 + win)
                .map(|k| {
                    let i = (g.beat_time(k as f64) * 1000.0).round() as i64 + d;
                    fl.get(i.max(0) as usize).copied().unwrap_or(0.0)
                })
                .sum()
        };
        let scores: Vec<(i64, f32)> = (-40..=40).map(|d| (d, score(d))).collect();
        let best = scores.iter().cloned().fold((0, f32::MIN), |m, x| if x.1 > m.1 { x } else { m });
        let mut s: Vec<f32> = scores.iter().map(|x| x.1).collect();
        s.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let med = s[s.len() / 2];
        out.push(if best.1 > 1.3 * med { format!("{:+}", best.0) } else { "?".into() });
        k0 += win;
    }
    out.join(" ")
}

/// (viés mediano em ms, desvio p90 em ms, fração de batidas com bumbo).
fn kick_fit(kicks: &KickEnv, g: &BeatGrid) -> (f64, f64, f64) {
    let mut offs = Vec::new();
    let mut total = 0;
    let first = ((g.start - g.t0) / g.period).ceil() as i64;
    let last = ((g.end - g.t0) / g.period).floor() as i64;
    for k in first..=last {
        let t = g.beat_time(k as f64);
        total += 1;
        if let Some(o) = kicks.onset(t) {
            offs.push((o - t) * 1000.0);
        }
    }
    if offs.is_empty() {
        return (f64::NAN, f64::NAN, 0.0);
    }
    let mut s = offs.clone();
    s.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let med = s[s.len() / 2];
    let mut dev: Vec<f64> = offs.iter().map(|o| (o - med).abs()).collect();
    dev.sort_by(|a, b| a.partial_cmp(b).unwrap());
    (med, dev[dev.len() * 9 / 10], offs.len() as f64 / total.max(1) as f64)
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
    let cache = std::env::temp_dir().join(format!("eval-tracks-{}", std::process::id()));
    let analyzer = Analyzer::new(&models, &cache);
    if full {
        analyzer.set_model(BeatModel::Full);
    }
    println!("modelo: {}", analyzer.model().name());
    let (mut n, mut has_beat, mut steady_both) = (0, 0, 0);
    for path in &args {
        let ext = std::path::Path::new(path).extension().map(|e| e.to_string_lossy().to_string());
        let a = analyzer.analyze_uncached(Box::new(File::open(path)?), ext.as_deref())?;
        let audio = decode_all(Box::new(File::open(path)?), ext.as_deref())?;
        let kicks = KickEnv::new(&audio.mono, audio.rate as f64);
        let fl = flux(&audio.mono, audio.rate as f64);
        n += 1;
        has_beat += a.has_beat() as usize;
        let name = std::path::Path::new(path).file_stem().unwrap().to_string_lossy();
        println!(
            "\n{name}  ({:.0} s) bpm {:?} conf {:.2} has_beat {} | tom {:?} | intro {:?} outro {:?} | som {:.2}..{:.2}",
            a.duration,
            a.bpm,
            a.bpm_confidence,
            a.has_beat(),
            a.camelot,
            a.intro_end.map(|x| (x * 10.0).round() / 10.0),
            a.outro_start.map(|x| (x * 10.0).round() / 10.0),
            a.first_sound,
            a.last_sound
        );
        for g in &a.grids {
            let (bias, jit, frac) = kick_fit(&kicks, g);
            println!(
                "   grade {:>5.0}-{:<5.0} {:>7.3} bpm  resid {:>4.1} ms  cob {:.2} n {:>3} lock {:.2}/{} val {}  conf {:.2} estável {:<5} | bumbo: viés {:>5.1} ms  p90 {:>4.1} ms  ({:.0}% c/ bumbo)  fase {}",
                g.start, g.end, g.bpm(), g.residual * 1000.0, g.coverage, g.inliers, g.lock, g.windows.len(), g.validated, g.confidence(), g.is_steady(), bias, jit, frac * 100.0, g.phase
            );
            println!("   fase local a cada 8 compassos (ms): {}", local_offsets(&fl, g));
            if std::env::var_os("PROFILE").is_some() {
                // Uma coluna por 5 ms, de -150 a +300 ms; '|' marca a batida da grade.
                let bars = " .:-=+*#%@";
                let line: String = profile(&kicks, g)
                    .iter()
                    .enumerate()
                    .map(|(j, v)| if j == 30 { '|' } else { bars.chars().nth(((v * 9.0).round() as usize).min(9)).unwrap() })
                    .collect();
                println!("   perfil -150ms [{line}] +300ms");
            }
        }
        if a.grids.len() == 2 {
            let (g1, g2) = (&a.grids[0], &a.grids[1]);
            steady_both += (g1.is_steady() && g2.is_steady()) as usize;
            // Primeiro compasso da grade do fim, visto pela grade do começo.
            let b2 = g2.bar_at_or_after(g2.start + 1.0);
            let p = (g1.period + g2.period) / 2.0;
            let k = (b2 - g1.t0) / p;
            let beat_err = (k - k.round()) * p * 1000.0;
            let bar_off = (k.round() as i64 - g1.phase as i64).rem_euclid(g1.beats_per_bar as i64);
            println!("   começo×fim: batida {beat_err:>+6.1} ms, compasso deslocado {bar_off} batida(s)");
        }
    }
    println!("\n{n} faixas: has_beat {has_beat}, duas grades estáveis {steady_both}");
    let _ = std::fs::remove_dir_all(cache);
    Ok(())
}
