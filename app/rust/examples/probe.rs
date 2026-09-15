//! Decodifica um arquivo e mostra contagem de frames e amostras das bordas.
//! Uso: cargo run --example probe -- <arquivo>...
use player_engine::engine::decoder::Decoder;
use std::fs::File;

fn main() -> anyhow::Result<()> {
    for path in std::env::args().skip(1) {
        let ext = std::path::Path::new(&path).extension().map(|e| e.to_string_lossy().to_string());
        let mut d = Decoder::open(Box::new(File::open(&path)?), ext.as_deref(), None)?;
        let mut buf = Vec::new();
        let mut all = Vec::new();
        while d.next_chunk(&mut buf)?.is_some() {
            all.extend(buf.chunks(d.channels).map(|f| f[0]));
        }
        let n = all.len();
        println!(
            "{path}: rate {} ch {} num_frames {:?} decodificados {n} | início {:?} | fim {:?}",
            d.sample_rate, d.channels, d.total_frames,
            &all[..4.min(n)], &all[n.saturating_sub(4)..]
        );
    }
    Ok(())
}
