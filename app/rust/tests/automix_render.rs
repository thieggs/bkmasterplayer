//! AutoMix de ponta a ponta sem placa de som: analisa duas faixas sintéticas
//! (120 e 124 BPM), planeja, executa a transição no mixer com a faixa A
//! silenciada e mede se cada bumbo de B cai em cima da batida de A.

use std::fs::File;
use std::path::PathBuf;
use std::time::Duration;

use player_engine::engine::analysis::Analyzer;
use player_engine::engine::automix::{plan, AutomixSettings, TempoMap};
use player_engine::engine::deck::{spawn_deck, DeckSource, ProducerParams};
use player_engine::engine::decoder::Decoder;
use player_engine::engine::mixer::{AutomixExec, Mixer, MixerCmd, MixerEvent, Transition};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn deck(token: u64, path: PathBuf, rate: u32, start_ms: u64, tempo: Option<TempoMap>) -> Box<DeckSource> {
    let ext = path.extension().map(|e| e.to_string_lossy().to_string());
    let params = ProducerParams { device_rate: rate, handoff_in: None, start_ms, duration_hint_ms: None, ring_seconds: 2.0, tempo };
    Box::new(spawn_deck(token, 1.0, params, move |_| {
        Decoder::open(Box::new(File::open(&path)?), ext.as_deref(), None)
    }))
}

/// Instante (s) em que o bumbo começa perto de `expected` (±40 ms): primeira
/// amostra da banda grave acima de 30% do pico local.
fn kick_onset(mono: &[f32], rate: f64, expected: f64) -> Option<f64> {
    let a = ((expected - 0.04) * rate).max(0.0) as usize;
    let b = (((expected + 0.06) * rate) as usize).min(mono.len());
    if b <= a {
        return None;
    }
    // Passa-baixas de 1 polo em 200 Hz.
    let alpha = 1.0 - (-2.0 * std::f64::consts::PI * 200.0 / rate).exp() as f32;
    let mut y = 0.0f32;
    let lp: Vec<f32> = mono[a.saturating_sub(2000)..b]
        .iter()
        .map(|x| {
            y += alpha * (x - y);
            y.abs()
        })
        .collect();
    let lp = &lp[a.min(2000)..];
    let peak = lp.iter().cloned().fold(0.0f32, f32::max);
    if peak < 0.02 {
        return None;
    }
    let i = lp.iter().position(|v| *v >= 0.3 * peak)?;
    Some((a + i) as f64 / rate)
}

#[test]
fn automix_beats_align_with_stretch() {
    // 120 → 124 BPM: B é desacelerada 3,2% para casar com A.
    let music = root().join("../../dev/music/Sintético Beats/Pista Um");
    check_pair(music.join("01 - Abertura.flac"), music.join("03 - Terceira Via.flac"), 120.0, 124.0);
}

#[test]
fn automix_beats_align_same_tempo() {
    // 125 → 125 BPM (Ogg → AAC): sem time-stretch.
    let music = root().join("../../dev/music/Coletivo Ritmo/Formatos");
    check_pair(music.join("01 - Em Ogg.ogg"), music.join("02 - Em AAC.m4a"), 125.0, 125.0);
}

fn check_pair(a_path: PathBuf, b_path: PathBuf, bpm_a: f64, bpm_b: f64) {
    let models = root().join("../assets/models");
    if !a_path.exists() || !b_path.exists() {
        eprintln!("sem dev/music — pulando");
        return;
    }
    let ext = |p: &PathBuf| p.extension().map(|e| e.to_string_lossy().to_string());
    let cache = std::env::temp_dir().join(format!("player-automix-{}", std::process::id()));
    let analyzer = Analyzer::new(&models, &cache);
    let aa = analyzer.analyze_uncached(Box::new(File::open(&a_path).unwrap()), ext(&a_path).as_deref()).unwrap();
    let ab = analyzer.analyze_uncached(Box::new(File::open(&b_path).unwrap()), ext(&b_path).as_deref()).unwrap();
    let settings = AutomixSettings { preferred_bars: 8, ..Default::default() };
    let p = plan(&aa, &ab, &settings, 0.0);
    eprintln!("plano: {p:?}");
    assert!(p.beatmatched, "deveria sincronizar");
    assert!((p.speed - bpm_a / bpm_b).abs() < 0.002);
    let period = 60.0 / bpm_a;

    let rate = 48000u32;
    let rf = rate as f64;
    // Começa A 3 s antes do ponto de mixagem (poupa tempo de teste).
    let a_start = (p.from_start - 3.0).max(0.0);
    let (cmd_tx, cmd_rx) = rtrb::RingBuffer::new(64);
    let (ev_tx, mut ev_rx) = rtrb::RingBuffer::new(1024);
    let mut mixer = Mixer::new(rate, cmd_rx, ev_tx);
    let mut cmd_tx = cmd_tx;
    let len = (p.duration * rf).round() as u64;
    let tempo = TempoMap { speed: p.speed, hold: len as f64, ramp: p.ramp * rf };
    let _ = cmd_tx.push(MixerCmd::Play(deck(1, a_path, rate, (a_start * 1000.0).round() as u64, None)));
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
        Some(deck(2, b_path, rate, (p.to_start * 1000.0).round() as u64, Some(tempo))),
        Transition::Automix(Box::new(exec)),
    ));
    std::thread::sleep(Duration::from_millis(500));

    let total = ((3.0 + p.duration + 2.0) * rf) as usize;
    let mut out = Vec::with_capacity(total * 2);
    let mut block = vec![0.0f32; 1024];
    let mut underruns = 0;
    while out.len() < total * 2 {
        mixer.render(&mut block);
        out.extend_from_slice(&block);
        while let Ok(e) = ev_rx.pop() {
            if let MixerEvent::Buffering(true) = e {
                underruns += 1;
            }
        }
        std::thread::sleep(Duration::from_micros(300));
    }
    assert_eq!(underruns, 0);
    let mono: Vec<f32> = out.chunks(2).map(|f| (f[0] + f[1]) * 0.5).collect();

    // A (silenciada) tem bumbos exatamente em k·período (gabarito); na saída,
    // o instante de A é (tempo de A − a_start). Os bumbos de B devem cair ali.
    // O primeiro fica de fora: B ainda está com volume zero no início.
    let first_k = (p.from_start / period).ceil() as i64 + 1;
    let last_k = ((p.from_start + p.duration) / period).floor() as i64 - 1;
    let mut errs = Vec::new();
    for k in first_k..=last_k {
        let expected = k as f64 * period - a_start;
        if let Some(t) = kick_onset(&mono, rf, expected) {
            errs.push((t - expected) * 1000.0);
        }
    }
    let n = errs.len();
    let mean = errs.iter().sum::<f64>() / n.max(1) as f64;
    let worst = errs.iter().map(|e| e.abs()).fold(0.0, f64::max);
    let spread = errs.iter().map(|e| (e - mean).abs()).fold(0.0, f64::max);
    eprintln!("bumbos de B medidos: {n}, erro médio {mean:+.1} ms, pior {worst:.1} ms, variação {spread:.1} ms");
    eprintln!("erros (ms): {:?}", errs.iter().map(|e| (e * 10.0).round() / 10.0).collect::<Vec<_>>());
    assert!(n >= 12, "poucos bumbos detectados");
    // Deriva ao longo da transição: praticamente zero (tempo casado).
    assert!(spread < 4.0, "batidas de B derivam em relação às de A");
    // Alinhamento absoluto (inclui o viés da detecção): dentro de 10 ms.
    assert!(worst < 10.0, "batidas de B desalinhadas");
}
