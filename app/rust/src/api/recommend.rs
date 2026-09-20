//! Recomendação offline para o Dart. Ver [`crate::engine::recommend`].

use std::path::PathBuf;

use parking_lot::Mutex;

use crate::engine::recommend::{Recommender, Style};

static LOADED: Mutex<Option<Recommender>> = Mutex::new(None);

pub struct SimilarSong {
    pub id: String,
    pub score: f32,
}

/// Carrega o arquivo de vetores do AudioMuse e o deixa pronto na memória.
/// Devolve quantas músicas ele conhece.
pub fn recommend_load(path: String) -> Result<u32, String> {
    let r = Recommender::load(&PathBuf::from(path)).map_err(|e| format!("{e:#}"))?;
    let n = r.len() as u32;
    *LOADED.lock() = Some(r);
    Ok(n)
}

/// Solta a memória (uns 20 MB) quando não se vai recomendar nada.
pub fn recommend_unload() {
    *LOADED.lock() = None;
}

/// Quantas músicas o arquivo carregado conhece (0 = nenhum carregado).
pub fn recommend_count() -> u32 {
    LOADED.lock().as_ref().map(|r| r.len() as u32).unwrap_or(0)
}

/// Esta música tem vetor? (Sem ele não dá para recomendar a partir dela.)
pub fn recommend_knows(id: String) -> bool {
    LOADED.lock().as_ref().is_some_and(|r| r.knows(&id))
}

/// As mais parecidas com [seed].
///
/// [style]: sound, mood, genre, era, lyrics, mix, server.
/// [allowed] limita o que pode ser sugerido (offline, só o que está baixado);
/// vazio = a biblioteca toda.
pub fn recommend_similar(seed: String, style: String, limit: u32, allowed: Vec<String>) -> Vec<SimilarSong> {
    let guard = LOADED.lock();
    let Some(r) = guard.as_ref() else { return Vec::new() };
    let Some(s) = Style::parse(&style) else { return Vec::new() };
    let lista = (!allowed.is_empty()).then_some(allowed);
    r.similar(&seed, s, limit as usize, lista.as_deref())
        .into_iter()
        .map(|h| SimilarSong { id: h.id, score: h.score })
        .collect()
}
