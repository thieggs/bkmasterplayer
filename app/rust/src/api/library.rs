//! Biblioteca local (músicas do aparelho) para o Dart.

use std::path::PathBuf;
use std::sync::atomic::Ordering;

use anyhow::Result;
use flutter_rust_bridge::frb;

pub use crate::library::LocalTrack;

#[frb(mirror(LocalTrack))]
pub struct _LocalTrack {
    pub path: String,
    pub size: i64,
    pub mtime: i64,
    pub title: String,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub track: Option<u32>,
    pub disc: Option<u32>,
    pub year: Option<i32>,
    pub genre: Option<String>,
    pub duration_ms: Option<i64>,
    pub sample_rate: Option<u32>,
    pub bit_depth: Option<u32>,
    pub channels: Option<u32>,
    pub bitrate_kbps: Option<u32>,
    pub bpm: Option<u32>,
    pub cover: Option<String>,
    pub rg_track_gain: Option<f32>,
    pub rg_album_gain: Option<f32>,
    pub rg_track_peak: Option<f32>,
    pub rg_album_peak: Option<f32>,
}

/// Varre as pastas (só relê o que mudou desde o índice) e devolve as faixas.
pub fn library_scan(folders: Vec<String>, index_path: String, covers_dir: String) -> Result<Vec<LocalTrack>> {
    crate::library::scan(&folders, &PathBuf::from(index_path), &PathBuf::from(covers_dir))
}

/// Índice salvo (sem varrer).
pub fn library_load(index_path: String) -> Vec<LocalTrack> {
    crate::library::load_index(&PathBuf::from(index_path))
}

/// Arquivos lidos na varredura em andamento.
#[frb(sync)]
pub fn library_scan_progress() -> u32 {
    crate::library::SCAN_PROGRESS.load(Ordering::Relaxed)
}

/// Tags de um arquivo avulso (null se não for áudio conhecido).
pub fn library_read_file(path: String, covers_dir: String) -> Option<LocalTrack> {
    crate::library::read_file(&PathBuf::from(path), &PathBuf::from(covers_dir))
}
