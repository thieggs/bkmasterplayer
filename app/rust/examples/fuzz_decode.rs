//! Fuzzing do decodificador: corrompe arquivos de áudio de verdade (bits
//! trocados, pedaços apagados/repetidos, bytes "perigosos", arquivo cortado) e
//! decodifica cada variação como o player faz (abrir, tocar, pular). Tudo que
//! entrar em pânico ou travar é gravado para reproduzir.
//!
//! Uso: fuzz_decode [--secs 120] [--seed 1] [--out <pasta>] <arquivos...>
//! Reproduzir um caso: fuzz_decode --replay <arquivo.bin> <extensão> <semente>
//! (a semente vem no nome do arquivo gravado)
use std::collections::HashMap;
use std::io::Cursor;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use player_engine::engine::decoder::Decoder;

/// xorshift64*: reproduzível pela semente.
struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n.max(1) as u64) as usize
    }
}

const INTERESTING: [u8; 8] = [0x00, 0xFF, 0x7F, 0x80, 0x01, 0xFE, 0x40, 0x10];

fn mutate(rng: &mut Rng, data: &mut Vec<u8>) {
    let rounds = 1 + rng.below(8);
    for _ in 0..rounds {
        if data.is_empty() {
            return;
        }
        // Metade das mudanças perto do começo: é onde ficam os cabeçalhos.
        let at = if rng.below(2) == 0 { rng.below(data.len().min(4096)) } else { rng.below(data.len()) };
        match rng.below(7) {
            0 => data[at] ^= 1 << rng.below(8),
            1 => data[at] = INTERESTING[rng.below(INTERESTING.len())],
            2 => data[at] = rng.next() as u8,
            3 => {
                // Inteiro de 32 bits "extremo" (tamanhos, contagens, offsets).
                let v: u32 = [0, u32::MAX, 0x7FFF_FFFF, 0x8000_0000, 1, 0xFFFF][rng.below(6)];
                for (i, b) in v.to_be_bytes().iter().enumerate() {
                    if at + i < data.len() {
                        data[at + i] = *b;
                    }
                }
            }
            4 => {
                let n = rng.below(512).min(data.len() - at);
                data.drain(at..at + n);
            }
            5 => {
                let n = rng.below(256).min(data.len() - at);
                let chunk = data[at..at + n].to_vec();
                let to = rng.below(data.len());
                data.splice(to..to, chunk);
            }
            _ => data.truncate(at.max(16)),
        }
    }
}

/// Decodifica como o player: abre, lê um pouco, pula para o meio e para perto
/// do fim, lê de novo. Limitado para não demorar em arquivos grandes.
fn exercise(data: Vec<u8>, ext: &str, rng_seed: u64) {
    let Ok(mut dec) = Decoder::open(Box::new(Cursor::new(data)), Some(ext), None) else { return };
    let mut out = Vec::new();
    let mut rng = Rng(rng_seed | 1);
    for _ in 0..200 {
        match dec.next_chunk(&mut out) {
            Ok(Some(_)) => {}
            _ => break,
        }
    }
    for _ in 0..3 {
        let _ = dec.seek(rng.next() % 400_000);
        for _ in 0..50 {
            match dec.next_chunk(&mut out) {
                Ok(Some(_)) => {}
                _ => break,
            }
        }
    }
}

fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let (mut secs, mut seed, mut out) = (120u64, 1u64, PathBuf::from("fuzz-out"));
    let mut files = Vec::new();
    let mut replay = None;
    while let Some(a) = args.next() {
        match a.as_str() {
            "--secs" => secs = args.next().expect("segundos").parse()?,
            "--seed" => seed = args.next().expect("semente").parse()?,
            "--out" => out = PathBuf::from(args.next().expect("pasta")),
            "--replay" => {
                let f = PathBuf::from(args.next().expect("arquivo"));
                let ext = args.next().expect("extensão");
                replay = Some((f, ext, args.next().and_then(|s| s.parse().ok()).unwrap_or(7)));
            }
            _ => files.push(PathBuf::from(a)),
        }
    }
    if let Some((f, ext, seed)) = replay {
        exercise(std::fs::read(f)?, &ext, seed);
        println!("sem pânico");
        return Ok(());
    }
    anyhow::ensure!(!files.is_empty(), "passe arquivos de áudio de exemplo");
    let corpus: Vec<(Vec<u8>, String)> = files
        .iter()
        .map(|f| Ok((std::fs::read(f)?, f.extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase())))
        .collect::<anyhow::Result<_>>()?;
    std::fs::create_dir_all(&out)?;

    // Onde foi o pânico (arquivo:linha) → mensagem; o gancho só anota.
    let last_panic: Arc<Mutex<Option<String>>> = Arc::new(Mutex::new(None));
    {
        let last = last_panic.clone();
        std::panic::set_hook(Box::new(move |info| {
            let loc = info.location().map(|l| format!("{}:{}", l.file(), l.line())).unwrap_or_default();
            let msg = info
                .payload()
                .downcast_ref::<&str>()
                .map(|s| s.to_string())
                .or_else(|| info.payload().downcast_ref::<String>().cloned())
                .unwrap_or_default();
            *last.lock().unwrap() = Some(format!("{loc} — {msg}"));
        }));
    }

    // Vigia: caso que passa de 10 s é travamento (laço infinito no decodificador).
    let case_started = Arc::new(AtomicU64::new(0));
    type Case = Option<(Vec<u8>, String, u64)>;
    let current: Arc<Mutex<Case>> = Arc::new(Mutex::new(None));
    {
        let (started, current, out) = (case_started.clone(), current.clone(), out.clone());
        let t0 = Instant::now();
        std::thread::spawn(move || loop {
            std::thread::sleep(Duration::from_secs(1));
            let s = started.load(Ordering::Relaxed);
            if s > 0 && (t0.elapsed().as_millis() as u64).saturating_sub(s) > 10_000 {
                if let Some((data, ext, seed)) = current.lock().unwrap().clone() {
                    let p = out.join(format!("trava-{seed}.{ext}.bin"));
                    let _ = std::fs::write(&p, &data);
                    eprintln!("TRAVOU (>10 s): caso gravado em {}", p.display());
                }
                std::process::exit(2);
            }
        });
    }

    let t0 = Instant::now();
    let mut rng = Rng(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1);
    let mut crashes: HashMap<String, usize> = HashMap::new();
    let mut cases = 0u64;
    while t0.elapsed() < Duration::from_secs(secs) {
        let (base, ext) = &corpus[rng.below(corpus.len())];
        let mut data = base.clone();
        mutate(&mut rng, &mut data);
        let case_seed = rng.next();
        *current.lock().unwrap() = Some((data.clone(), ext.clone(), case_seed));
        case_started.store(t0.elapsed().as_millis() as u64 + 1, Ordering::Relaxed);
        let d = data.clone();
        let e = ext.clone();
        let r = std::panic::catch_unwind(move || exercise(d, &e, case_seed));
        case_started.store(0, Ordering::Relaxed);
        cases += 1;
        if r.is_err() {
            let what = last_panic.lock().unwrap().take().unwrap_or_else(|| "?".into());
            if !crashes.contains_key(&what) {
                let p = out.join(format!("panico-{}-{case_seed}.{ext}.bin", crashes.len() + 1));
                std::fs::write(&p, &data)?;
                println!("PÂNICO novo ({ext}): {what}\n  caso: {}", p.display());
            }
            *crashes.entry(what).or_insert(0) += 1;
        }
    }
    println!("\n{cases} casos em {} s; {} pânicos diferentes", t0.elapsed().as_secs(), crashes.len());
    let mut list: Vec<_> = crashes.into_iter().collect();
    list.sort_by_key(|(_, n)| std::cmp::Reverse(*n));
    for (what, n) in list {
        println!("  {n:>6}×  {what}");
    }
    Ok(())
}
