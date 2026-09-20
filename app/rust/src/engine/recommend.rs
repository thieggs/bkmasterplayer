//! Recomendação offline: acha músicas parecidas sem internet e sem pesar.
//!
//! O AudioMuse faz a parte cara no servidor (rede neural por música) e
//! `dev/exporta_audiomuse.py` empacota os vetores num arquivo. Aqui só se
//! compara: uma música contra as outras cinco mil são poucos milissegundos,
//! milhares de vezes mais barato que acordar o rádio do celular para
//! perguntar ao servidor.
//!
//! A mesma faixa costuma existir em vários arquivos (single, álbum,
//! coletânea). O arquivo guarda o vetor uma vez e aponta todos os ids para
//! ele, senão "parecidas" viria com a mesma música repetida.

use std::collections::HashMap;
use std::path::Path;

use anyhow::{bail, Context, Result};

const MAGIC: &[u8; 8] = b"BKVEC\x02\x00\x00";
const OTHER_DIMS: usize = 6;

/// De que jeito "parecida" é medido.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Style {
    /// Parecida no som: o timbre e o arranjo (o padrão).
    Sound,
    /// Mesmo clima: dançante, agressiva, feliz, festa, relaxada, triste.
    Mood,
    /// Mesmo estilo musical (os gêneros que a análise reconheceu).
    Genre,
    /// Mesma época, sem fugir do som.
    Era,
    /// Mesmo assunto, pela letra.
    Lyrics,
    /// Combina para emendar: andamento próximo e tom que casa.
    Mix,
    /// A conta que o AudioMuse usa no servidor (0,75 letra + 0,25 som).
    Server,
}

impl Style {
    pub fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "sound" => Self::Sound,
            "mood" => Self::Mood,
            "genre" => Self::Genre,
            "era" => Self::Era,
            "lyrics" => Self::Lyrics,
            "mix" => Self::Mix,
            "server" => Self::Server,
            _ => return None,
        })
    }
}

/// Uma música do arquivo, já pronta para comparar.
struct Track {
    tempo: f32,
    year: u16,
    /// 0..11; 255 = desconhecido.
    key: u8,
    /// 0 maior, 1 menor; 255 = desconhecido.
    scale: u8,
    /// Clima (dançante, agressiva, feliz, festa, relaxada, triste, energia),
    /// já medido como distância da média da biblioteca — ver [`center`].
    mood: Vec<f32>,
    /// Estilos: só uns quatro dos quarenta e dois por música, o resto zero.
    /// Fica cru de propósito — centrar um vetor esparso faz as dimensões
    /// ausentes (todas iguais) dominarem e tudo virar parecido.
    style: Vec<f32>,
    audio: Vec<f32>,
    lyrics: Vec<f32>,
}

pub struct Recommender {
    /// Id do arquivo na biblioteca → qual vetor.
    by_id: HashMap<String, u32>,
    /// Um id de volta por vetor, para responder algo quando o pedido não
    /// trouxe lista de permitidos.
    first_id: Vec<String>,
    tracks: Vec<Track>,
    pub styles: Vec<String>,
}

pub struct Hit {
    pub id: String,
    pub score: f32,
}

fn f32s(b: &[u8], n: usize) -> Vec<f32> {
    (0..n).map(|i| f32::from_le_bytes([b[i * 4], b[i * 4 + 1], b[i * 4 + 2], b[i * 4 + 3]])).collect()
}

fn u32le(b: &[u8]) -> u32 {
    u32::from_le_bytes([b[0], b[1], b[2], b[3]])
}

/// Cosseno entre dois vetores. Vetor todo zero não combina com nada.
fn cosine(a: &[f32], b: &[f32]) -> f32 {
    let (mut dot, mut na, mut nb) = (0.0f32, 0.0f32, 0.0f32);
    for i in 0..a.len().min(b.len()) {
        dot += a[i] * b[i];
        na += a[i] * a[i];
        nb += b[i] * b[i];
    }
    if na <= 0.0 || nb <= 0.0 {
        return 0.0;
    }
    (dot / (na.sqrt() * nb.sqrt())).clamp(-1.0, 1.0)
}

/// Leva o cosseno (-1 a 1) para 0 a 1, para somar com os outros termos.
fn unit(c: f32) -> f32 {
    (c + 1.0) / 2.0
}

/// Andamentos que emendam: perto, ou no dobro/metade (90 com 180 casa).
fn tempo_match(a: f32, b: f32) -> f32 {
    if a <= 0.0 || b <= 0.0 {
        return 0.0;
    }
    [1.0f32, 2.0, 0.5]
        .iter()
        .map(|m| {
            let d = ((a * m - b) / b).abs();
            (1.0 - d / 0.12).clamp(0.0, 1.0)
        })
        .fold(0.0f32, f32::max)
}

/// Tons que casam, como a roda dos DJs: o mesmo, o vizinho, ou o
/// relativo maior/menor.
fn key_match(ka: u8, sa: u8, kb: u8, sb: u8) -> f32 {
    if ka > 11 || kb > 11 || sa > 1 || sb > 1 {
        return 0.5; // sem informação: não ajuda nem atrapalha
    }
    if ka == kb && sa == sb {
        return 1.0;
    }
    // Relativo (dó maior ↔ lá menor): três semitons abaixo do maior.
    let relativo = if sa == 0 { (ka + 9) % 12 == kb && sb == 1 } else { (ka + 3) % 12 == kb && sb == 0 };
    if relativo {
        return 0.9;
    }
    let passo = (ka as i32 - kb as i32).rem_euclid(12);
    if sa == sb && (passo == 7 || passo == 5) {
        return 0.8; // quinta acima ou abaixo
    }
    0.2
}

/// Quanto a época pesa: cai devagar, alguns anos ainda contam como "a mesma".
fn era_match(a: u16, b: u16) -> f32 {
    if a == 0 || b == 0 {
        return 0.5;
    }
    let d = (a as f32 - b as f32).abs();
    (-d / 8.0).exp()
}

/// Tira de cada dimensão a média da biblioteca.
fn center(tracks: &mut [Track], pick: fn(&mut Track) -> &mut Vec<f32>) {
    if tracks.is_empty() {
        return;
    }
    let n = pick(&mut tracks[0]).len();
    let mut soma = vec![0.0f64; n];
    for t in tracks.iter_mut() {
        for (i, v) in pick(t).iter().enumerate().take(n) {
            soma[i] += *v as f64;
        }
    }
    let media: Vec<f32> = soma.iter().map(|s| (s / tracks.len() as f64) as f32).collect();
    for t in tracks.iter_mut() {
        for (i, v) in pick(t).iter_mut().enumerate().take(n) {
            *v -= media[i];
        }
    }
}

impl Recommender {
    pub fn load(path: &Path) -> Result<Self> {
        let raw = std::fs::read(path).with_context(|| format!("lendo {}", path.display()))?;
        if raw.len() < 36 || &raw[..8] != MAGIC {
            bail!("não é um arquivo de vetores desta versão");
        }
        let ids_count = u32le(&raw[8..]) as usize;
        let vecs_count = u32le(&raw[12..]) as usize;
        let audio_dims = u32le(&raw[16..]) as usize;
        let lyrics_dims = u32le(&raw[20..]) as usize;
        let style_dims = u32le(&raw[24..]) as usize;
        let id_len = u32le(&raw[28..]) as usize;
        let vocab_len = u32le(&raw[32..]) as usize;
        let mut at = 36;
        let styles: Vec<String> =
            String::from_utf8_lossy(&raw[at..at + vocab_len]).lines().map(str::to_string).collect();
        at += vocab_len;

        let mut by_id = HashMap::with_capacity(ids_count);
        let mut first_id = vec![String::new(); vecs_count];
        for _ in 0..ids_count {
            if at + id_len + 4 > raw.len() {
                bail!("arquivo de vetores truncado na lista de músicas");
            }
            let id = String::from_utf8_lossy(&raw[at..at + id_len]).trim_end_matches('\0').to_string();
            let i = u32le(&raw[at + id_len..]);
            at += id_len + 4;
            if (i as usize) < vecs_count {
                if first_id[i as usize].is_empty() {
                    first_id[i as usize] = id.clone();
                }
                by_id.insert(id, i);
            }
        }

        let rec_len = 4 + 4 + 2 + 1 + 1 + OTHER_DIMS + style_dims + (audio_dims + lyrics_dims) * 4;
        let mut tracks = Vec::with_capacity(vecs_count);
        for _ in 0..vecs_count {
            if at + rec_len > raw.len() {
                bail!("arquivo de vetores truncado nos vetores");
            }
            let b = &raw[at..at + rec_len];
            let mut other = [0.0f32; OTHER_DIMS];
            for (i, v) in other.iter_mut().enumerate() {
                *v = b[12 + i] as f32 / 255.0;
            }
            let s0 = 12 + OTHER_DIMS;
            let a0 = s0 + style_dims;
            let energy = f32::from_le_bytes([b[4], b[5], b[6], b[7]]);
            tracks.push(Track {
                tempo: f32::from_le_bytes([b[0], b[1], b[2], b[3]]),
                year: u16::from_le_bytes([b[8], b[9]]),
                key: b[10],
                scale: b[11],
                mood: other.iter().copied().chain([energy]).collect(),
                style: b[s0..a0].iter().map(|&x| x as f32 / 255.0).collect(),
                audio: f32s(&b[a0..], audio_dims),
                lyrics: f32s(&b[a0 + audio_dims * 4..], lyrics_dims),
            });
            at += rec_len;
        }
        // O clima sai da análise quase constante (tudo entre 0,6 e 0,72):
        // comparado cru, o cosseno dá 1 para qualquer par. Duas contas
        // resolvem: tirar a média da biblioteca em cada medida, e depois o
        // nível geral de cada música — senão sobra um fator comum a todas
        // que domina o cosseno. O que fica é o perfil: esta é mais dançante
        // do que triste, aquela o contrário.
        center(&mut tracks, |t| &mut t.mood);
        for t in tracks.iter_mut() {
            let m = t.mood.iter().sum::<f32>() / t.mood.len().max(1) as f32;
            for v in t.mood.iter_mut() {
                *v -= m;
            }
        }
        Ok(Self { by_id, first_id, tracks, styles })
    }

    pub fn len(&self) -> usize {
        self.tracks.len()
    }

    pub fn is_empty(&self) -> bool {
        self.tracks.is_empty()
    }

    pub fn knows(&self, id: &str) -> bool {
        self.by_id.contains_key(id)
    }

    fn score(&self, a: &Track, b: &Track, style: Style) -> f32 {
        match style {
            Style::Sound => cosine(&a.audio, &b.audio),
            Style::Lyrics => cosine(&a.lyrics, &b.lyrics),
            // Muita música divide o mesmo punhado de estilos e empata em 1;
            // o som desempata entre elas.
            Style::Genre => 0.8 * cosine(&a.style, &b.style) + 0.2 * unit(cosine(&a.audio, &b.audio)),
            Style::Server => 0.75 * cosine(&a.lyrics, &b.lyrics) + 0.25 * cosine(&a.audio, &b.audio),
            Style::Mood => cosine(&a.mood, &b.mood),
            // Nas misturadas o som entra de 0 a 1, como os outros termos: o
            // cosseno vai de -1 a 1 e somar escalas diferentes desequilibra.
            // A época manda, e o som desempata — senão "mesma época" acabava
            // devolvendo o mais parecido de qualquer ano.
            Style::Era => 0.6 * era_match(a.year, b.year) + 0.4 * unit(cosine(&a.audio, &b.audio)),
            Style::Mix => {
                let casa = tempo_match(a.tempo, b.tempo) * key_match(a.key, a.scale, b.key, b.scale);
                0.7 * casa + 0.3 * unit(cosine(&a.audio, &b.audio))
            }
        }
    }

    /// As mais parecidas com [seed], do jeito [style].
    ///
    /// `allowed` limita às músicas que a pessoa tem (offline, sugerir o que
    /// não dá para tocar não serve). `None` = a biblioteca toda.
    pub fn similar(&self, seed: &str, style: Style, limit: usize, allowed: Option<&[String]>) -> Vec<Hit> {
        let Some(&si) = self.by_id.get(seed) else { return Vec::new() };
        let seed_track = &self.tracks[si as usize];
        // Cada vetor concorre uma vez só; guarda qual id daquele vetor pode
        // ser tocado.
        let mut pick: Vec<Option<&str>> = vec![None; self.tracks.len()];
        match allowed {
            Some(list) => {
                for id in list {
                    if let Some(&i) = self.by_id.get(id.as_str()) {
                        let slot = &mut pick[i as usize];
                        if slot.is_none() {
                            *slot = Some(id.as_str());
                        }
                    }
                }
            }
            None => {
                for (i, id) in self.first_id.iter().enumerate() {
                    if !id.is_empty() {
                        pick[i] = Some(id.as_str());
                    }
                }
            }
        }
        let mut hits: Vec<Hit> = pick
            .iter()
            .enumerate()
            .filter(|(i, id)| *i != si as usize && id.is_some())
            .map(|(i, id)| Hit { id: id.unwrap().to_string(), score: self.score(seed_track, &self.tracks[i], style) })
            .collect();
        hits.sort_by(|a, b| b.score.total_cmp(&a.score));
        hits.truncate(limit);
        hits
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t(audio: &[f32], tempo: f32, key: u8, scale: u8, year: u16) -> Track {
        Track {
            tempo,
            year,
            key,
            scale,
            mood: vec![0.5; OTHER_DIMS + 1],
            style: vec![0.5; 4],
            audio: audio.to_vec(),
            lyrics: audio.to_vec(),
        }
    }

    #[test]
    fn the_cosine_knows_equal_from_opposite() {
        assert!((cosine(&[1.0, 0.0], &[1.0, 0.0]) - 1.0).abs() < 1e-6);
        assert!((cosine(&[1.0, 0.0], &[-1.0, 0.0]) + 1.0).abs() < 1e-6);
        assert!(cosine(&[1.0, 0.0], &[0.0, 1.0]).abs() < 1e-6);
        assert_eq!(cosine(&[0.0, 0.0], &[1.0, 1.0]), 0.0, "vetor vazio não combina com nada");
    }

    #[test]
    fn double_and_half_tempo_still_mix() {
        assert!(tempo_match(128.0, 128.0) > 0.99);
        assert!(tempo_match(90.0, 180.0) > 0.99, "dobro emenda");
        assert!(tempo_match(174.0, 87.0) > 0.99, "metade emenda");
        assert!(tempo_match(128.0, 130.0) > 0.8, "quase igual");
        assert_eq!(tempo_match(100.0, 145.0), 0.0, "longe demais");
    }

    #[test]
    fn keys_follow_the_dj_wheel() {
        assert_eq!(key_match(0, 0, 0, 0), 1.0, "mesmo tom");
        assert!(key_match(0, 0, 9, 1) > 0.85, "dó maior com lá menor");
        assert!(key_match(0, 0, 7, 0) > 0.75, "quinta acima");
        assert!(key_match(0, 0, 1, 0) < 0.3, "meio tom acima briga");
        assert_eq!(key_match(255, 255, 0, 0), 0.5, "sem tom não atrapalha");
    }

    #[test]
    fn the_era_fades_with_the_years() {
        assert_eq!(era_match(2000, 2000), 1.0);
        assert!(era_match(2000, 2003) > 0.6, "três anos ainda é a mesma época");
        assert!(era_match(1970, 2020) < 0.01, "cinquenta anos não");
        assert_eq!(era_match(0, 2000), 0.5, "sem ano não atrapalha");
    }

    #[test]
    fn each_style_ranks_by_what_it_promises() {
        let seed = t(&[1.0, 0.0], 128.0, 0, 0, 2000);
        // Som igual, época longe.
        let igual_som = t(&[1.0, 0.0], 60.0, 5, 1, 1965);
        // Som diferente, mesma época e emenda.
        let igual_resto = t(&[0.0, 1.0], 128.0, 0, 0, 2000);
        let r = Recommender { by_id: HashMap::new(), first_id: vec![], tracks: vec![], styles: vec![] };
        assert!(r.score(&seed, &igual_som, Style::Sound) > r.score(&seed, &igual_resto, Style::Sound));
        assert!(r.score(&seed, &igual_resto, Style::Mix) > r.score(&seed, &igual_som, Style::Mix));
        assert!(r.score(&seed, &igual_resto, Style::Era) > r.score(&seed, &igual_som, Style::Era));
    }
}
