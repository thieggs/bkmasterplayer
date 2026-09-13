//! Testes de ponta a ponta do mixer, sem placa de som: renderiza mais rápido
//! que o tempo real a partir dos arquivos de dev/music (gerados por
//! dev/tools/gen_test_music.py) e confere continuidade, duração e crossfade.

use std::fs::File;
use std::path::PathBuf;
use std::time::Duration;

use std::sync::Arc;

use player_engine::engine::deck::{spawn_deck, DeckShared, DeckSource, Handoff, ProducerParams};
use player_engine::engine::decoder::Decoder;
use player_engine::engine::mixer::{Mixer, MixerCmd, MixerEvent, Transition};

fn music_dir() -> Option<PathBuf> {
    let d = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../dev/music");
    d.join("ground_truth.json").exists().then_some(d)
}

fn deck(token: u64, path: PathBuf, rate: u32) -> Box<DeckSource> {
    deck_with(token, path, rate, None)
}

fn deck_with(token: u64, path: PathBuf, rate: u32, handoff: Option<Arc<Handoff>>) -> Box<DeckSource> {
    let ext = path.extension().map(|e| e.to_string_lossy().to_string());
    let params = ProducerParams { device_rate: rate, handoff_in: handoff, start_ms: 0, duration_hint_ms: None, ring_seconds: 2.0 };
    Box::new(spawn_deck(token, 1.0, params, move |_| {
        Decoder::open(Box::new(File::open(&path)?), ext.as_deref(), None)
    }))
}

struct Harness {
    mixer: Mixer,
    cmd: rtrb::Producer<MixerCmd>,
    ev: rtrb::Consumer<MixerEvent>,
    events: Vec<String>,
    underruns: usize,
}

impl Harness {
    fn new(rate: u32) -> Self {
        let (cmd, cmd_rx) = rtrb::RingBuffer::new(64);
        let (ev_tx, ev) = rtrb::RingBuffer::new(1024);
        Self { mixer: Mixer::new(rate, cmd_rx, ev_tx), cmd, ev, events: vec![], underruns: 0 }
    }

    fn send(&mut self, c: MixerCmd) {
        assert!(self.cmd.push(c).is_ok());
    }

    /// Renderiza até parar (evento Stopped). Retorna estéreo intercalado.
    fn render_all(&mut self, max_seconds: u32) -> Vec<f32> {
        let rate = self.mixer.rate() as usize;
        let mut out = Vec::new();
        let mut block = vec![0.0f32; 1024];
        // Espera a primeira faixa ficar pronta antes de começar.
        std::thread::sleep(Duration::from_millis(300));
        while out.len() < max_seconds as usize * rate * 2 {
            self.mixer.render(&mut block);
            out.extend_from_slice(&block);
            let mut stopped = false;
            while let Ok(e) = self.ev.pop() {
                match e {
                    MixerEvent::Started(t) => self.events.push(format!("start {t}")),
                    MixerEvent::Finished(t) => self.events.push(format!("end {t}")),
                    MixerEvent::Stopped => stopped = true,
                    MixerEvent::Buffering(true) => self.underruns += 1,
                    _ => {}
                }
            }
            if stopped {
                break;
            }
            // ~20x mais rápido que o tempo real; as produtoras decodificam bem mais rápido.
            std::thread::sleep(Duration::from_micros(500));
        }
        out
    }
}

fn second_difference_peak(x: &[f32], from: usize, to: usize) -> (f32, usize) {
    let mut peak = 0.0f32;
    let mut at = 0;
    for i in (from.max(2))..to.min(x.len() / 2) {
        let y = |k: usize| x[k * 2];
        let e = (y(i) - 2.0 * y(i - 1) + y(i - 2)).abs();
        if e > peak {
            peak = e;
            at = i;
        }
    }
    (peak, at)
}

fn gapless_album(ext: &str, album: &str, rate: u32, max_peak: f32) -> Option<Vec<f32>> {
    let Some(dir) = music_dir() else {
        eprintln!("dev/music ausente — rode dev/tools/gen_test_music.py");
        return None;
    };
    let base = dir.join("Teste Gapless").join(album);
    let paths: Vec<PathBuf> = (1..=3).map(|i| base.join(format!("{i:02} - Parte {i}.{ext}"))).collect();
    let mut h = Harness::new(rate);
    // Como o motor faz: a atual ganha um "sucessor" e a próxima herda o conversor dela.
    let mut shareds: Vec<Arc<DeckShared>> = Vec::new();
    let mut gapless_next = |cur: &Arc<DeckShared>, token: u64, p: PathBuf| {
        let hd = Handoff::new();
        cur.set_successor(Some(hd.clone()));
        deck_with(token, p, rate, Some(hd))
    };
    let first = deck(1, paths[0].clone(), rate);
    shareds.push(first.shared.clone());
    h.send(MixerCmd::Play(first));
    let second = gapless_next(&shareds[0], 2, paths[1].clone());
    shareds.push(second.shared.clone());
    h.send(MixerCmd::SetNext(Some(second), Transition::Gapless));
    let mut out = Vec::new();
    let mut next_token = 3;
    let mut queued = 2;
    let rate_us = rate as usize;
    std::thread::sleep(Duration::from_millis(300));
    let mut block = vec![0.0f32; 1024];
    loop {
        h.mixer.render(&mut block);
        out.extend_from_slice(&block);
        let mut stopped = false;
        while let Ok(e) = h.ev.pop() {
            match e {
                MixerEvent::Started(t) => {
                    h.events.push(format!("start {t}"));
                    // Como o app faz: ao começar uma faixa, agenda a seguinte.
                    if t >= 2 && queued < 3 {
                        queued += 1;
                        let p = paths[queued - 1].clone();
                        let cur = shareds.last().unwrap().clone();
                        let d = gapless_next(&cur, next_token, p);
                        shareds.push(d.shared.clone());
                        h.send(MixerCmd::SetNext(Some(d), Transition::Gapless));
                        next_token += 1;
                    }
                }
                MixerEvent::Finished(t) => h.events.push(format!("end {t}")),
                MixerEvent::Stopped => stopped = true,
                MixerEvent::Buffering(true) => h.underruns += 1,
                _ => {}
            }
        }
        if stopped || out.len() > 90 * rate_us * 2 {
            break;
        }
        std::thread::sleep(Duration::from_micros(300));
    }

    // Tira o silêncio final do último bloco.
    while out.len() >= 2 && out[out.len() - 1] == 0.0 && out[out.len() - 2] == 0.0 {
        out.truncate(out.len() - 2);
    }
    let frames = out.len() / 2;
    let expected = 75 * rate_us;
    if let Ok(dir) = std::env::var("DUMP_DIR") {
        let bytes: Vec<u8> = out.iter().flat_map(|s| s.to_le_bytes()).collect();
        std::fs::write(format!("{dir}/gapless_{ext}_{rate}.f32"), bytes).unwrap();
    }
    eprintln!("{album} @ {rate}: {frames} frames (esperado ~{expected}), eventos {:?}", h.events);
    assert_eq!(h.underruns, 0, "houve underrun no teste");
    assert!(
        (frames as i64 - expected as i64).abs() < (rate_us / 50) as i64,
        "duração errada: {frames} vs {expected}"
    );
    // Sinal suave: a segunda diferença de uma senoide até 880 Hz é pequena.
    // Um buraco/clique nas emendas gera picos muito maiores.
    let (peak, at) = second_difference_peak(&out, rate_us / 100, frames - rate_us / 100);
    eprintln!("pico da 2ª diferença: {peak:.4} em {:.3}s", at as f32 / rate as f32);
    assert!(peak < max_peak, "descontinuidade em {:.3}s (pico {peak})", at as f32 / rate as f32);
    Some(out)
}

/// Decodifica e concatena as partes (canal esquerdo), na taxa original.
fn concat_parts(ext: &str, album: &str) -> Vec<f32> {
    let base = music_dir().unwrap().join("Teste Gapless").join(album);
    let mut all = Vec::new();
    for i in 1..=3 {
        let p = base.join(format!("{i:02} - Parte {i}.{ext}"));
        let mut d = Decoder::open(Box::new(File::open(&p).unwrap()), Some(ext), None).unwrap();
        let mut buf = Vec::new();
        while d.next_chunk(&mut buf).unwrap().is_some() {
            all.extend(buf.chunks(d.channels).map(|f| f[0]));
        }
    }
    all
}

/// Na mesma taxa, o gapless tem que ser idêntico amostra por amostra à concatenação.
fn assert_bit_exact(ext: &str, album: &str) {
    let Some(out) = gapless_album(ext, album, 44100, 10.0) else { return };
    let reference = concat_parts(ext, album);
    let ours: Vec<f32> = out.chunks(2).map(|f| f[0]).collect();
    assert_eq!(ours.len(), reference.len(), "número de amostras difere");
    let skip = 44100 / 100; // fade-in de 5 ms no início
    let max_diff = ours[skip..]
        .iter()
        .zip(&reference[skip..])
        .map(|(a, b)| (a - b).abs())
        .fold(0.0f32, f32::max);
    eprintln!("{album}: diferença máxima vs concatenação = {max_diff:e}");
    assert!(max_diff < 1e-6, "saída difere da concatenação: {max_diff}");
}

#[test]
fn gapless_flac_same_rate_bit_exact() {
    assert_bit_exact("flac", "Contínuo (FLAC)");
}

#[test]
fn gapless_mp3_same_rate_bit_exact() {
    assert_bit_exact("mp3", "Contínuo (MP3)");
}

#[test]
fn gapless_flac_resampled() {
    gapless_album("flac", "Contínuo (FLAC)", 48000, 0.02);
}

#[test]
fn gapless_mp3_resampled_no_worse_than_source() {
    if music_dir().is_none() {
        return;
    }
    // O MP3 tem artefato próprio nas bordas (cada parte codificada separada).
    let src = concat_parts("mp3", "Contínuo (MP3)");
    let stereo: Vec<f32> = src.iter().flat_map(|s| [*s, *s]).collect();
    let (baseline, _) = second_difference_peak(&stereo, 441, src.len() - 441);
    eprintln!("MP3: pico intrínseco dos arquivos = {baseline:.4}");
    gapless_album("mp3", "Contínuo (MP3)", 48000, baseline * 1.3 + 0.02);
}

#[test]
fn crossfade_overlaps_tracks() {
    let Some(dir) = music_dir() else { return };
    let rate = 48000;
    let a = dir.join("Onda Calma/Ambiente/01 - Névoa.flac");
    let b = dir.join("Onda Calma/Ambiente/02 - Maré.flac");
    let mut h = Harness::new(rate);
    h.send(MixerCmd::Play(deck(1, a.clone(), rate)));
    let xfade = 4 * rate as u64;
    h.send(MixerCmd::SetNext(Some(deck(2, b.clone(), rate)), Transition::Crossfade { frames: xfade }));
    let out = h.render_all(200);
    let dur = |p: &PathBuf| {
        let d = Decoder::open(Box::new(File::open(p).unwrap()), Some("flac"), None).unwrap();
        d.total_frames.unwrap() as f64 / d.sample_rate as f64
    };
    let expected = (dur(&a) + dur(&b) - 4.0) * rate as f64;
    let frames = out.len() as f64 / 2.0;
    eprintln!("crossfade: {frames} frames, esperado ~{expected}, eventos {:?}", h.events);
    assert_eq!(h.underruns, 0);
    assert!((frames - expected).abs() < rate as f64 * 0.1, "duração com crossfade errada");
    assert_eq!(h.events.first().map(String::as_str), Some("start 1"));
    assert!(h.events.contains(&"start 2".to_string()));
    // A faixa 2 começa (Started) antes da 1 terminar (Finished): houve sobreposição.
    let s2 = h.events.iter().position(|e| e == "start 2").unwrap();
    let e1 = h.events.iter().position(|e| e == "end 1").unwrap();
    assert!(s2 < e1);
}
