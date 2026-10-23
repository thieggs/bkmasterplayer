//! Formatos que o symphonia sozinho não lia: cada arquivo de
//! `tests/fixtures` (varreduras de frequência de 0,6 s, geradas com o ffmpeg)
//! decodifica inteiro, com a taxa e os canais certos, e o seek cai
//! exatamente onde a decodificação contínua cairia. Como o sinal varre a
//! frequência, um seek fora do lugar dá diferença grande.

use std::fs::File;
use std::path::PathBuf;

use player_engine::engine::decoder::Decoder;

fn open(name: &str) -> Decoder {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures").join(name);
    let ext = path.extension().map(|e| e.to_string_lossy().to_string());
    Decoder::open(Box::new(File::open(&path).unwrap()), ext.as_deref(), None).unwrap()
}

fn rest(d: &mut Decoder) -> Vec<f32> {
    let (mut all, mut buf) = (Vec::new(), Vec::new());
    while d.next_chunk(&mut buf).unwrap().is_some() {
        all.extend_from_slice(&buf);
    }
    all
}

/// Decodifica inteiro, confere formato e duração, e compara um seek para
/// `seek_ms` com a decodificação contínua (diferença máxima `tolerance`).
fn check(name: &str, codec: &str, rate: u32, channels: usize, seek_ms: u64, tolerance: f32) {
    let mut d = open(name);
    assert_eq!((d.codec.as_str(), d.sample_rate, d.channels), (codec, rate, channels), "{name}");
    let all = rest(&mut d);
    let ms = all.len() as u64 / channels as u64 * 1000 / rate as u64;
    assert!((590..=620).contains(&ms), "{name}: {ms} ms");

    let mut d = open(name);
    let at = d.seek(seek_ms).unwrap() as usize;
    assert_eq!(at as u64, seek_ms * rate as u64 / 1000, "{name}");
    let tail = rest(&mut d);
    assert_eq!(tail.len(), all.len() - at * channels, "{name}: frames depois do seek");
    let diff = tail.iter().zip(&all[at * channels..]).map(|(a, b)| (a - b).abs()).fold(0f32, f32::max);
    assert!(diff <= tolerance, "{name}: diferença {diff} depois do seek");
}

#[test]
fn opus_in_ogg() {
    // O Opus depende do que veio antes: mesmo com os 400 ms de pré-rolagem,
    // depois do seek sobra ~−45 dB de diferença em taxa baixa (este arquivo é
    // de 24 kbps). Uma amostra fora do lugar já daria ~0,06.
    check("varredura.opus", "opus", 48_000, 2, 450, 1e-2);
}

#[test]
fn opus_in_webm() {
    // O WebM conta o tempo em milissegundos: o seek pode cair até ~1 ms fora,
    // mas não mais (antes do conserto, caía 5 ms fora).
    let mut d = open("varredura.webm");
    let all = rest(&mut d);
    let mut d = open("varredura.webm");
    let at = d.seek(450).unwrap() as usize;
    let tail = rest(&mut d);
    let lag = (-480i64..=480)
        .min_by(|&a, &b| {
            let err = |k: i64| -> f32 {
                (0..2000).map(|i| (tail[i * 2] - all[((at as i64 + k) as usize + i) * 2]).abs()).sum()
            };
            err(a).total_cmp(&err(b))
        })
        .unwrap();
    assert!(lag.abs() <= 48, "seek no WebM {lag} amostras fora");
}

#[test]
fn wavpack() {
    check("varredura.wv", "wavpack", 8_000, 1, 400, 0.0);
}

#[test]
fn mp2() {
    check("varredura.mp2", "mp2", 32_000, 2, 400, 0.0);
}
