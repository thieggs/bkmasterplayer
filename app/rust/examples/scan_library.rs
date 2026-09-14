//! Varre uma pasta com o leitor da biblioteca local e mostra o resultado.
//! Uso: cargo run --release --example scan_library -- <pasta> [índice]
use std::path::PathBuf;
fn main() {
    let dir = std::env::args().nth(1).expect("pasta");
    let tmp = std::env::temp_dir().join("bk-scan");
    let index = std::env::args().nth(2).map(PathBuf::from).unwrap_or_else(|| tmp.join("index.json"));
    let t0 = std::time::Instant::now();
    let tracks = player_engine::library::scan(&[dir], &index, &tmp.join("covers")).unwrap();
    println!("{} faixas em {:.1?}", tracks.len(), t0.elapsed());
    for t in tracks.iter().take(6) {
        println!(
            "{:>2} {} — {} [{}] {:?} ms {:?} kbps ano {:?} gênero {:?} rg {:?} capa {}",
            t.track.unwrap_or(0), t.title, t.artist.as_deref().unwrap_or("?"), t.album.as_deref().unwrap_or("?"),
            t.duration_ms, t.bitrate_kbps, t.year, t.genre, t.rg_track_gain, t.cover.is_some()
        );
    }
    let no_dur = tracks.iter().filter(|t| t.duration_ms.is_none()).count();
    let no_cover = tracks.iter().filter(|t| t.cover.is_none()).count();
    let no_artist = tracks.iter().filter(|t| t.artist.is_none()).count();
    println!("sem duração: {no_dur}, sem capa: {no_cover}, sem artista: {no_artist}");
}
