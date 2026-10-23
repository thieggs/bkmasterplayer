//! Decodifica um arquivo com o motor e grava o PCM (f32 little-endian,
//! intercalado), para comparar com outra decodificação, como a do ffmpeg:
//!   ffmpeg -i <arquivo> -f f32le -ar <taxa> -ac <canais> ref.f32
//! Uso: decode <arquivo> <saída.f32> [seek_ms]
use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::Path;

use player_engine::engine::decoder::Decoder;

fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let (Some(path), Some(out)) = (args.next(), args.next()) else {
        anyhow::bail!("uso: decode <arquivo> <saída.f32> [seek_ms]");
    };
    let seek: Option<u64> = args.next().map(|s| s.parse()).transpose()?;
    let ext = Path::new(&path).extension().map(|e| e.to_string_lossy().to_string());
    let mut d = Decoder::open_file(Box::new(File::open(&path)?), ext.as_deref(), None, Some(Path::new(&path)))?;
    let start = seek.map(|ms| d.seek(ms)).transpose()?;
    let mut w = BufWriter::new(File::create(&out)?);
    let (mut buf, mut frames) = (Vec::new(), 0u64);
    while let Some(n) = d.next_chunk(&mut buf)? {
        frames += n as u64;
        for s in &buf {
            w.write_all(&s.to_le_bytes())?;
        }
    }
    w.flush()?;
    println!(
        "{path}: {} | {} Hz {} canais {:?} bits | total {:?} | decodificados {frames} | seek {start:?}",
        d.codec, d.sample_rate, d.channels, d.bits_per_sample, d.total_frames
    );
    Ok(())
}
