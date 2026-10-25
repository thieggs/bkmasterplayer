//! Recomendação offline para o Dart. Ver [`crate::engine::recommend`].

use std::path::PathBuf;

use parking_lot::Mutex;

use crate::engine::recommend::{Recommender, Style};

static LOADED: Mutex<Option<Recommender>> = Mutex::new(None);

pub struct SimilarSong {
    pub id: String,
    pub score: f32,
}

/// Candidata do aleatório smart: qual ímã a trouxe (posição na lista pedida)
/// e quanto combina com ele.
pub struct SmartSong {
    pub id: String,
    pub score: f32,
    pub anchor: u32,
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

/// Aleatório smart: as parecidas com cada ímã ([anchors], músicas que a
/// pessoa aprovou), [per_anchor] por ímã, longe do que ela pulou ([avoid]) e
/// fora do que já tocou ([exclude]). Ver `Recommender::smart`.
pub fn recommend_smart(
    anchors: Vec<String>,
    avoid: Vec<String>,
    style: String,
    per_anchor: u32,
    exclude: Vec<String>,
    allowed: Vec<String>,
) -> Vec<SmartSong> {
    let guard = LOADED.lock();
    let Some(r) = guard.as_ref() else { return Vec::new() };
    let Some(s) = Style::parse(&style) else { return Vec::new() };
    let lista = (!allowed.is_empty()).then_some(allowed);
    r.smart(&anchors, &avoid, s, per_anchor as usize, &exclude, lista.as_deref())
        .into_iter()
        .map(|h| SmartSong { id: h.id, score: h.score, anchor: h.anchor })
        .collect()
}

/// Aleatório smart: [count] amostras sorteadas — com [spread], cada uma de um
/// canto diferente e longe do que a pessoa já ouviu ([known]). [liked] são os
/// ímãs: pulos perto deles não fecham a região. Ver `Recommender::explore`.
#[allow(clippy::too_many_arguments)]
pub fn recommend_explore(
    count: u32,
    known: Vec<String>,
    avoid: Vec<String>,
    liked: Vec<String>,
    exclude: Vec<String>,
    allowed: Vec<String>,
    spread: bool,
    seed: u32,
) -> Vec<String> {
    let guard = LOADED.lock();
    let Some(r) = guard.as_ref() else { return Vec::new() };
    let lista = (!allowed.is_empty()).then_some(allowed);
    r.explore(count as usize, &known, &avoid, &liked, &exclude, lista.as_deref(), spread, seed as u64)
}

/// Destas músicas, quais caíram no que a pessoa pulou (a própria, as gêmeas,
/// ou a zona de duas puladas perto uma da outra, longe de [liked])?
pub fn recommend_avoided(ids: Vec<String>, avoid: Vec<String>, liked: Vec<String>) -> Vec<String> {
    let guard = LOADED.lock();
    let Some(r) = guard.as_ref() else { return Vec::new() };
    r.avoided(&ids, &avoid, &liked)
}
