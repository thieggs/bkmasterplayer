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
        echo_pos: 0,
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
        // 8× o tempo real (512 frames por bloco): rápido, mas sem exigir do
        // time-stretch um ritmo que a placa de som nunca pede (no build de
        // debug, a ~70× ele não acompanhava e o teste acusava cortes falsos).
        std::thread::sleep(Duration::from_secs_f64(512.0 / rate as f64 / 8.0));
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

/// Transição por eco (BPMs longe demais para casar): ao cortar A, a linha do
/// eco tem que repetir a última batida dela no lugar da música. A linha
/// começava vazia, então a primeira repetição só vinha uma batida depois e
/// ficava um buraco — a "travadinha" que só aparecia no modo eco.
#[test]
fn echo_repeats_the_last_beat_without_a_hole() {
    let a_path = root().join("../../dev/music/Sintético Beats/Pista Um/01 - Abertura.flac");
    if !a_path.exists() {
        eprintln!("sem dev/music — pulando");
        return;
    }
    let rate = 48000u32;
    let rf = rate as f64;
    let (beat, bar) = (0.5, 2.0); // A: 120 BPM, 4/4
    let cut = 4.0;
    // B em silêncio: o que sair depois do corte é só o eco de A.
    let silence = std::env::temp_dir().join(format!("bk-echo-silence-{}.wav", std::process::id()));
    {
        let spec = hound::WavSpec { channels: 2, sample_rate: rate, bits_per_sample: 16, sample_format: hound::SampleFormat::Int };
        let mut w = hound::WavWriter::create(&silence, spec).unwrap();
        for _ in 0..(rate as usize * 10 * 2) {
            w.write_sample(0i16).unwrap();
        }
        w.finalize().unwrap();
    }
    let (cmd_tx, cmd_rx) = rtrb::RingBuffer::new(64);
    let (ev_tx, _ev_rx) = rtrb::RingBuffer::new(1024);
    let mut mixer = Mixer::new(rate, cmd_rx, ev_tx);
    let mut cmd_tx = cmd_tx;
    let _ = cmd_tx.push(MixerCmd::Play(deck(1, a_path, rate, 0, None)));
    let exec = AutomixExec {
        style: player_engine::engine::automix::MixStyle::Echo,
        start_native: (cut * rf) as u64,
        len: (2.0 * bar * rf) as u64,
        swap_at: 0,
        beat: (beat * rf) as u64,
        echo_buf: vec![0.0; rate as usize * 4],
        echo_pos: 0,
        mute_from: false,
    };
    let _ = cmd_tx.push(MixerCmd::SetNext(Some(deck(2, silence.clone(), rate, 0, None)), Transition::Automix(Box::new(exec))));
    std::thread::sleep(Duration::from_millis(500));

    let total = ((cut + 2.0 * bar) * rf) as usize;
    let mut out = Vec::with_capacity(total * 2);
    let mut block = vec![0.0f32; 1024];
    while out.len() < total * 2 {
        mixer.render(&mut block);
        out.extend_from_slice(&block);
        std::thread::sleep(Duration::from_secs_f64(512.0 / rf / 8.0));
    }
    let _ = std::fs::remove_file(&silence);
    let mono: Vec<f32> = out.chunks(2).map(|f| (f[0] + f[1]) * 0.5).collect();
    let energy = |from: f64, to: f64| -> f32 {
        let (a, b) = ((from * rf) as usize, ((to * rf) as usize).min(mono.len()));
        (mono[a..b].iter().map(|x| x * x).sum::<f32>() / (b - a).max(1) as f32).sqrt()
    };
    // Última batida de A antes do corte e as duas repetições do eco.
    let ultima = energy(cut - beat, cut);
    let eco1 = energy(cut, cut + beat);
    let eco2 = energy(cut + beat, cut + 2.0 * beat);
    eprintln!("última batida {ultima:.4} → eco {eco1:.4} → {eco2:.4}");
    assert!(ultima > 0.01, "A não estava tocando antes do corte");
    assert!(eco1 > ultima * 0.4, "sem eco na primeira batida depois do corte ({eco1:.4} vs {ultima:.4}): buraco");
    assert!(eco2 > ultima * 0.1, "o eco não continuou na segunda batida ({eco2:.4})");
    assert!(eco2 < eco1, "o eco tem que ir sumindo ({eco1:.4} → {eco2:.4})");
}
