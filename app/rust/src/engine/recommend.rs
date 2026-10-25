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

use std::collections::{HashMap, HashSet};
use std::path::Path;

use anyhow::{bail, Context, Result};

const MAGIC_V2: &[u8; 8] = b"BKVEC\x02\x00\x00";
/// v3: + o vetor CLAP de cada música (8 bits), que é o que sabe "estilo".
const MAGIC_V3: &[u8; 8] = b"BKVEC\x03\x00\x00";
const OTHER_DIMS: usize = 6;

/// Distância de som abaixo da qual é a mesma gravação (o
/// `DUPLICATE_DISTANCE_THRESHOLD_COSINE` do AudioMuse).
const SAME_SONG_DISTANCE: f32 = 0.01;

// Réguas do aleatório smart, em distância de estilo (1 − nota de
// [`Style::Genre`]). Medidas na biblioteca do usuário em 24/10/2026, 7.272
// músicas: a 20ª mais parecida de uma música fica a ~0,05, a 350ª a ~0,10, e
// duas músicas quaisquer a ~0,29.

/// Gêmea de uma música pulada: some junto com ela. Umas vinte por música.
const TWIN: f32 = 0.045;

/// Raio de uma zona evitada: o estilo em volta das puladas, umas 350 músicas
/// (5% da biblioteca), não a biblioteca inteira.
const ZONE: f32 = 0.10;

/// Duas puladas a menos que isto uma da outra são do mesmo estilo e formam
/// zona; mais longe, cada uma leva só as gêmeas.
const ZONE_LINK: f32 = 0.15;

/// Quantas sorteadas a exploração compara para achar uma longe de tudo.
const SAMPLE: usize = 150;

/// De que jeito "parecida" é medido.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Style {
    /// Parecida no som: o timbre e o arranjo (o padrão).
    Sound,
    /// Mesmo clima: dançante, agressiva, feliz, festa, relaxada, triste.
    Mood,
    /// Mesmo estilo musical: o CLAP do AudioMuse (áudio + texto), com o som
    /// desempatando. Sem o CLAP no arquivo (v2), os rótulos de estilo.
    Genre,
    /// Mesma época, sem fugir do som.
    Era,
    /// Mesmo assunto, pela letra.
    Lyrics,
    /// Combina para emendar: andamento próximo e tom que casa.
    Mix,
    /// Imita a conta do "parecidas" do AudioMuse no servidor
    /// (`/api/similar_tracks`): só o vetor de som, pelo cosseno.
    ///
    /// Antes isto era 0,75 letra + 0,25 som, que é a busca por letra do
    /// AudioMuse (`sem_grove`), não o "parecidas" que a rádio usa — conferido
    /// no código dele (`tasks/ivf_manager.py`, v3.3.0).
    ///
    /// No app, "deixar o servidor escolher" pergunta ao servidor mesmo; isto
    /// aqui é o último recurso de quando ele não responde (offline, ou
    /// biblioteca local sem Last.fm) — ver `data/similar.dart`.
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
    /// CLAP em 8 bits (vazio no arquivo v2 ou sem análise CLAP).
    clap: Vec<i8>,
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

/// Uma candidata do aleatório smart: a música, quanto combina com o ímã que a
/// trouxe e qual ímã foi (a posição dele na lista pedida).
pub struct SmartHit {
    pub id: String,
    pub score: f32,
    pub anchor: u32,
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

/// Cosseno entre dois vetores de 8 bits (a escala de cada um não importa).
fn cosine_i8(a: &[i8], b: &[i8]) -> Option<f32> {
    if a.is_empty() || a.len() != b.len() {
        return None;
    }
    let (mut dot, mut na, mut nb) = (0i64, 0i64, 0i64);
    for (x, y) in a.iter().zip(b) {
        let (x, y) = (*x as i64, *y as i64);
        dot += x * y;
        na += x * x;
        nb += y * y;
    }
    if na == 0 || nb == 0 {
        return None;
    }
    Some((dot as f64 / ((na as f64).sqrt() * (nb as f64).sqrt())) as f32)
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

/// Mesmo estilo musical, de 0 a 1.
///
/// O CLAP é quem sabe estilo (corrido com corrido, samba com samba); o som
/// desempata. Medido contra o gênero das tags do Navidrome, 400 sementes:
/// acerta 53%, contra 46% da conta antiga — que usava os rótulos de estilo do
/// AudioMuse, um classificador de 45 gêneros ocidentais que põe corrido
/// mexicano como "electronic, rock, indie". Sem CLAP de uma das duas, a antiga.
fn genre_match(a: &Track, b: &Track) -> f32 {
    match cosine_i8(&a.clap, &b.clap) {
        Some(c) => 0.7 * unit(c) + 0.3 * unit(cosine(&a.audio, &b.audio)),
        None => 0.8 * cosine(&a.style, &b.style) + 0.2 * unit(cosine(&a.audio, &b.audio)),
    }
}

/// Quão longe no estilo (0 = igual). É a régua das zonas e da exploração do
/// aleatório smart, seja qual for o jeito de recomendar escolhido.
fn style_distance(a: &Track, b: &Track) -> f32 {
    1.0 - genre_match(a, b)
}

/// O que o aleatório smart aprendeu a evitar (ver `player/smart_session.dart`).
///
/// Uma música pulada sozinha leva junto só as gêmeas dela ([`TWIN`]): um pulo
/// pode ser "essa eu não aguento mais", e não "odeio o estilo". Duas ou mais
/// puladas perto uma da outra ([`ZONE_LINK`]) já dizem o estilo, e aí a região
/// em volta delas ([`ZONE`]) fica de fora — a não ser que ali também haja uma
/// música aprovada (`liked`).
///
/// Essa ressalva veio da simulação (24/10/2026, `test/smart_sim_test.dart`):
/// quem gosta de samba pula as vizinhas não-samba dos ímãs de samba, duas
/// dessas puladas fechavam uma zona em volta do próprio ímã, e ele parava de
/// trazer as vizinhas boas — metade da sessão virava amostra sorteada.
struct Avoid<'a> {
    skipped: Vec<&'a Track>,
    zone: Vec<bool>,
}

impl<'a> Avoid<'a> {
    fn new(r: &'a Recommender, ids: &[String], liked: &[String]) -> Self {
        let mut seen = HashSet::new();
        let skipped: Vec<&Track> = ids
            .iter()
            .filter_map(|id| r.by_id.get(id))
            .filter(|&&i| seen.insert(i))
            .map(|&i| &r.tracks[i as usize])
            .collect();
        let liked: Vec<&Track> = liked.iter().filter_map(|id| r.by_id.get(id)).map(|&i| &r.tracks[i as usize]).collect();
        let zone = (0..skipped.len())
            .map(|i| {
                (0..skipped.len()).any(|j| j != i && style_distance(skipped[i], skipped[j]) < ZONE_LINK)
                    && !liked.iter().any(|l| style_distance(skipped[i], l) < ZONE)
            })
            .collect();
        Self { skipped, zone }
    }

    fn blocks(&self, t: &Track) -> bool {
        self.skipped.iter().zip(&self.zone).any(|(s, &zone)| {
            let d = style_distance(s, t);
            d < TWIN || (zone && d < ZONE)
        })
    }
}

/// Sorteio sem dependência nova (splitmix64). A semente vem de quem pede,
/// para os testes repetirem o mesmo sorteio.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    fn below(&mut self, n: usize) -> usize {
        (self.next() % n.max(1) as u64) as usize
    }
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
        let v3 = raw.len() >= 40 && &raw[..8] == MAGIC_V3;
        if !v3 && (raw.len() < 36 || &raw[..8] != MAGIC_V2) {
            bail!("não é um arquivo de vetores desta versão");
        }
        let ids_count = u32le(&raw[8..]) as usize;
        let vecs_count = u32le(&raw[12..]) as usize;
        let audio_dims = u32le(&raw[16..]) as usize;
        let lyrics_dims = u32le(&raw[20..]) as usize;
        let style_dims = u32le(&raw[24..]) as usize;
        let id_len = u32le(&raw[28..]) as usize;
        let clap_dims = if v3 { u32le(&raw[32..]) as usize } else { 0 };
        let mut at = if v3 { 36 } else { 32 };
        let vocab_len = u32le(&raw[at..]) as usize;
        at += 4;
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

        let rec_len = 4 + 4 + 2 + 1 + 1 + OTHER_DIMS + style_dims + (audio_dims + lyrics_dims) * 4 + clap_dims;
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
                clap: {
                    let c0 = a0 + (audio_dims + lyrics_dims) * 4;
                    let c = &b[c0..c0 + clap_dims];
                    // Tudo zero = sem análise CLAP dessa música.
                    if c.iter().all(|&x| x == 0) { Vec::new() } else { c.iter().map(|&x| x as i8).collect() }
                },
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
            Style::Genre => genre_match(a, b),
            Style::Server => cosine(&a.audio, &b.audio),
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
        let pick = self.pickable(allowed);
        let mut hits: Vec<Hit> = pick
            .iter()
            .enumerate()
            .filter(|(i, id)| *i != si as usize && id.is_some())
            // A mesma música noutro arquivo (outra codificação, a versão
            // trocada por uma melhor) sai com um vetor quase igual: o AudioMuse
            // descarta abaixo de 0,01 de distância, e aqui também.
            .filter(|(i, _)| 1.0 - cosine(&seed_track.audio, &self.tracks[*i].audio) >= SAME_SONG_DISTANCE)
            .map(|(i, id)| Hit { id: id.unwrap().to_string(), score: self.score(seed_track, &self.tracks[i], style) })
            .collect();
        hits.sort_by(|a, b| b.score.total_cmp(&a.score));
        hits.truncate(limit);
        hits
    }

    /// Qual id de cada vetor pode ser sugerido: cada vetor concorre uma vez
    /// só. `allowed` limita (offline, só o que está baixado); `None` = a
    /// biblioteca toda.
    fn pickable<'a>(&'a self, allowed: Option<&'a [String]>) -> Vec<Option<&'a str>> {
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
        pick
    }

    /// Vetores destes ids (a mesma gravação noutro arquivo cai junto).
    fn marked(&self, ids: &[String]) -> Vec<bool> {
        let mut out = vec![false; self.tracks.len()];
        for id in ids {
            if let Some(&i) = self.by_id.get(id) {
                out[i as usize] = true;
            }
        }
        out
    }

    /// Candidatas do aleatório smart: as mais parecidas com cada ímã (música
    /// que a pessoa aprovou), `per_anchor` por ímã, cada lista da melhor para a
    /// pior e marcada com o ímã que a trouxe. Nada do que é para evitar (ver
    /// [`Avoid`]) nem do que já tocou ou está na fila (`exclude`).
    ///
    /// A conta é por ímã, sem misturar: quem aprovou rock e samba quer rock e
    /// samba, e a média dos dois não é nenhum. Quantas vêm de cada um quem
    /// decide é o app, pelo peso de cada ímã.
    pub fn smart(
        &self,
        anchors: &[String],
        avoid: &[String],
        style: Style,
        per_anchor: usize,
        exclude: &[String],
        allowed: Option<&[String]>,
    ) -> Vec<SmartHit> {
        let pick = self.pickable(allowed);
        let mut out = self.marked(exclude);
        for id in anchors {
            if let Some(&i) = self.by_id.get(id) {
                out[i as usize] = true;
            }
        }
        let avoid = Avoid::new(self, avoid, anchors);
        // A mesma candidata aparece na lista de vários ímãs: a conta de evitar
        // é feita uma vez só.
        let mut blocked: Vec<Option<bool>> = vec![None; self.tracks.len()];
        let mut hits = Vec::new();
        for (n, anchor) in anchors.iter().enumerate() {
            let Some(&ai) = self.by_id.get(anchor) else { continue };
            let a = &self.tracks[ai as usize];
            let mut ranked: Vec<(usize, f32)> = (0..self.tracks.len())
                .filter(|&i| !out[i] && pick[i].is_some())
                .filter(|&i| 1.0 - cosine(&a.audio, &self.tracks[i].audio) >= SAME_SONG_DISTANCE)
                .map(|i| (i, self.score(a, &self.tracks[i], style)))
                .collect();
            ranked.sort_by(|x, y| y.1.total_cmp(&x.1));
            let mut taken = 0;
            for (i, score) in ranked {
                if taken >= per_anchor {
                    break;
                }
                if *blocked[i].get_or_insert_with(|| avoid.blocks(&self.tracks[i])) {
                    continue;
                }
                hits.push(SmartHit { id: pick[i].unwrap_or_default().to_string(), score, anchor: n as u32 });
                taken += 1;
            }
        }
        hits
    }

    /// Amostras para conhecer o gosto: `count` músicas sorteadas.
    ///
    /// Com `spread`, cada uma sai de um canto diferente: de umas cento e
    /// cinquenta sorteadas, fica uma das mais longe de tudo o que a pessoa já
    /// ouviu (`known`) e das que já saíram. Sem isso, numa biblioteca com 60% de
    /// funk, quatro amostras davam quatro funks e não se aprendia nada do
    /// resto. Sem `spread`, é sorteio puro. Nas duas, nada do que é para evitar
    /// nem do que já tocou (`exclude`).
    #[allow(clippy::too_many_arguments)]
    pub fn explore(
        &self,
        count: usize,
        known: &[String],
        avoid: &[String],
        liked: &[String],
        exclude: &[String],
        allowed: Option<&[String]>,
        spread: bool,
        seed: u64,
    ) -> Vec<String> {
        let pick = self.pickable(allowed);
        let out = self.marked(exclude);
        let mut pool: Vec<usize> = (0..self.tracks.len()).filter(|&i| !out[i] && pick[i].is_some()).collect();
        let avoid = Avoid::new(self, avoid, liked);
        let mut near: Vec<usize> = known.iter().filter_map(|id| self.by_id.get(id)).map(|&i| i as usize).collect();
        let mut rng = Rng(seed);
        let mut chosen = Vec::new();
        while chosen.len() < count && !pool.is_empty() {
            // Tira do monte; as que são para evitar não voltam.
            let mut sample = Vec::new();
            while sample.len() < SAMPLE && !pool.is_empty() {
                let i = pool.swap_remove(rng.below(pool.len()));
                if !avoid.blocks(&self.tracks[i]) {
                    sample.push(i);
                }
            }
            if sample.is_empty() {
                break;
            }
            let i = if spread && !near.is_empty() {
                let mut far: Vec<(usize, f32)> = sample
                    .iter()
                    .map(|&i| {
                        let d = near.iter().map(|&k| style_distance(&self.tracks[k], &self.tracks[i])).fold(f32::MAX, f32::min);
                        (i, d)
                    })
                    .collect();
                far.sort_by(|a, b| b.1.total_cmp(&a.1));
                // Uma do quarto mais longe, e não sempre a mais longe de
                // todas: a mais isolada da biblioteca costuma ser a esquisita.
                far[rng.below((far.len() / 4).max(1))].0
            } else {
                sample[rng.below(sample.len())]
            };
            pool.extend(sample.into_iter().filter(|&x| x != i));
            near.push(i);
            chosen.push(pick[i].unwrap_or_default().to_string());
        }
        chosen
    }

    /// Destas, quais caíram no que é para evitar? O app troca na hora as que
    /// ainda não tocaram.
    pub fn avoided(&self, ids: &[String], avoid: &[String], liked: &[String]) -> Vec<String> {
        let avoid = Avoid::new(self, avoid, liked);
        ids.iter()
            .filter(|id| self.by_id.get(*id).is_some_and(|&i| avoid.blocks(&self.tracks[i as usize])))
            .cloned()
            .collect()
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
            clap: Vec::new(),
        }
    }

    fn rec(tracks: Vec<Track>) -> Recommender {
        let ids: Vec<String> = (0..tracks.len()).map(|i| format!("s{i}")).collect();
        Recommender {
            by_id: ids.iter().enumerate().map(|(i, id)| (id.clone(), i as u32)).collect(),
            first_id: ids,
            tracks,
            styles: vec![],
        }
    }

    /// Música a `deg` graus do eixo `axis` (inclinada para o eixo seguinte),
    /// com o CLAP e o som apontando para o mesmo lado: a distância de estilo
    /// entre duas é 0,5·(1 − cos do ângulo). Mesmo eixo = mesmo estilo (até
    /// 30°); eixos diferentes ficam a 0,25 ou mais.
    fn at(axis: usize, deg: f32) -> Track {
        let (s, c) = deg.to_radians().sin_cos();
        let mut v = [0.0f32; 3];
        v[axis] = c;
        v[(axis + 1) % 3] = s;
        let mut x = t(&v, 120.0, 0, 0, 2000);
        x.clap = v.iter().map(|f| (f * 100.0).round() as i8).collect();
        x
    }

    fn ids<const N: usize>(x: [&str; N]) -> Vec<String> {
        x.iter().map(|s| s.to_string()).collect()
    }

    fn hit_ids(h: &[SmartHit]) -> Vec<&str> {
        h.iter().map(|h| h.id.as_str()).collect()
    }

    #[test]
    fn smart_keeps_each_liked_style_apart() {
        // s0–s3: estilo A; s4–s7: estilo B; s8, s9: estilo C, que ninguém aprovou.
        let r = rec(vec![
            at(0, 0.0),
            at(0, 10.0),
            at(0, 15.0),
            at(0, 20.0),
            at(1, 0.0),
            at(1, 10.0),
            at(1, 15.0),
            at(1, 20.0),
            at(2, 0.0),
            at(2, 10.0),
        ]);
        let hits = r.smart(&ids(["s0", "s4"]), &[], Style::Genre, 2, &[], None);
        let by: Vec<(&str, u32)> = hits.iter().map(|h| (h.id.as_str(), h.anchor)).collect();
        assert_eq!(by, [("s1", 0), ("s2", 0), ("s5", 1), ("s6", 1)], "cada ímã traz as dele, sem misturar");
    }

    #[test]
    fn one_skip_takes_only_its_twins() {
        // Ímã s0; pulada s1 (15°); s2 é gêmea dela (5° de distância); s3 é do
        // mesmo estilo, mas a 30° da pulada; s4 é de outro estilo.
        let r = rec(vec![at(0, 0.0), at(0, 15.0), at(0, 20.0), at(0, 45.0), at(1, 0.0)]);
        let hits = r.smart(&ids(["s0"]), &ids(["s1"]), Style::Genre, 10, &[], None);
        assert_eq!(hit_ids(&hits), ["s3", "s4"], "um pulo só pode ser enjoo da música, não do estilo");
    }

    #[test]
    fn two_skips_close_together_close_the_region() {
        // Ímã s0 noutro estilo. Puladas s1 (15°) e s2 (35°): perto uma da
        // outra, mesmo estilo, longe do ímã. s3, a 30° da s2, já não é gêmea,
        // mas está na zona; s4 é do estilo do ímã.
        let r = rec(vec![at(1, 0.0), at(0, 15.0), at(0, 35.0), at(0, 65.0), at(1, 30.0)]);
        let hits = r.smart(&ids(["s0"]), &ids(["s1", "s2"]), Style::Genre, 10, &[], None);
        assert_eq!(hit_ids(&hits), ["s4"]);
        assert_eq!(r.avoided(&ids(["s3", "s4", "nao-existe"]), &ids(["s1", "s2"]), &[]), ["s3"]);
        assert!(r.avoided(&ids(["s3"]), &ids(["s2"]), &[]).is_empty(), "com uma pulada só, s3 ficava");
    }

    #[test]
    fn skips_next_to_a_liked_song_do_not_close_the_region() {
        // Ímã s0; puladas s1 (20°) e s2 (35°), perto uma da outra e as duas a
        // menos de 0,10 do ímã: o estilo tem coisa que a pessoa gosta. s3
        // (65°, a 30° da s2) fica; a gêmea da s1 (s4, a 23°) sai.
        let r = rec(vec![at(0, 0.0), at(0, 20.0), at(0, 35.0), at(0, 65.0), at(0, 23.0)]);
        let hits = r.smart(&ids(["s0"]), &ids(["s1", "s2"]), Style::Genre, 10, &[], None);
        assert_eq!(hit_ids(&hits), ["s3"]);
        assert_eq!(r.avoided(&ids(["s3", "s4"]), &ids(["s1", "s2"]), &ids(["s0"])), ["s4"]);
        assert_eq!(r.avoided(&ids(["s3", "s4"]), &ids(["s1", "s2"]), &[]), ["s3", "s4"], "sem a aprovada, vira zona");
    }

    #[test]
    fn what_already_played_does_not_come_back() {
        let r = rec(vec![at(0, 0.0), at(0, 10.0), at(0, 15.0), at(0, 20.0)]);
        let hits = r.smart(&ids(["s0"]), &[], Style::Genre, 10, &ids(["s1"]), None);
        assert_eq!(hit_ids(&hits), ["s2", "s3"]);
        let offline = r.smart(&ids(["s0"]), &[], Style::Genre, 10, &[], Some(&ids(["s3"])));
        assert_eq!(hit_ids(&offline), ["s3"], "offline, só o que está baixado");
    }

    /// Três estilos com dez músicas cada: s0–s9, s10–s19, s20–s29.
    fn three_styles() -> Recommender {
        let mut tracks = Vec::new();
        for axis in 0..3 {
            for k in 0..10 {
                tracks.push(at(axis, k as f32 * 3.0));
            }
        }
        rec(tracks)
    }

    fn style_of(id: &str) -> usize {
        id[1..].parse::<usize>().unwrap() / 10
    }

    #[test]
    fn exploring_takes_each_sample_from_a_different_style() {
        let r = three_styles();
        for seed in 0..20 {
            let got = r.explore(3, &[], &[], &[], &[], None, true, seed);
            let styles: HashSet<usize> = got.iter().map(|id| style_of(id)).collect();
            assert_eq!(styles.len(), 3, "semente {seed}: {got:?}");
        }
        // Já ouviu os estilos A e B: a amostra vem do C.
        for seed in 0..10 {
            let got = r.explore(1, &ids(["s0", "s10"]), &[], &[], &[], None, true, seed);
            assert_eq!(style_of(&got[0]), 2, "semente {seed}: {got:?}");
        }
    }

    #[test]
    fn exploring_skips_what_was_avoided_and_what_already_played() {
        let r = three_styles();
        let avoid = ids(["s0", "s1"]); // duas puladas juntas: o estilo A inteiro sai
        let exclude = ids(["s10", "s11"]);
        for spread in [false, true] {
            let got = r.explore(12, &[], &avoid, &[], &exclude, None, spread, 3);
            assert_eq!(got.len(), 12);
            let unique: HashSet<&String> = got.iter().collect();
            assert_eq!(unique.len(), 12, "nada repetido");
            assert!(got.iter().all(|id| style_of(id) > 0 && id != "s10" && id != "s11"), "{got:?}");
        }
        let few = r.explore(50, &[], &avoid, &[], &exclude, None, true, 1);
        assert_eq!(few.len(), 18, "pede mais do que há: vem o que há");
    }
    #[test]
    fn the_same_song_in_another_file_is_not_a_suggestion() {
        let r = rec(vec![
            t(&[1.0, 0.0, 0.0], 120.0, 0, 0, 2000),
            // Mesma gravação noutra codificação: vetor quase igual.
            t(&[0.999, 0.01, 0.0], 120.0, 0, 0, 2000),
            t(&[0.8, 0.6, 0.0], 120.0, 0, 0, 2000),
            t(&[0.0, 0.0, 1.0], 120.0, 0, 0, 2000),
        ]);
        let ids: Vec<String> = r.similar("s0", Style::Sound, 10, None).into_iter().map(|h| h.id).collect();
        assert_eq!(ids, ["s2", "s3"], "a cópia (s1) não volta como sugestão");
    }

    #[test]
    fn imitating_the_server_follows_the_sound_only() {
        // Letra igual e som oposto não pode ganhar de som parecido e letra
        // diferente: o "parecidas" do AudioMuse é só o vetor de som.
        let mut seed = t(&[1.0, 0.0], 120.0, 0, 0, 2000);
        seed.lyrics = vec![1.0, 0.0];
        let mut letra = t(&[-1.0, 0.0], 120.0, 0, 0, 2000);
        letra.lyrics = vec![1.0, 0.0];
        let mut som = t(&[0.9, 0.3], 120.0, 0, 0, 2000);
        som.lyrics = vec![0.0, 1.0];
        let r = rec(vec![seed, letra, som]);
        let ids: Vec<String> = r.similar("s0", Style::Server, 2, None).into_iter().map(|h| h.id).collect();
        assert_eq!(ids[0], "s2");
    }

    #[test]
    fn genre_follows_clap_when_there_is_one() {
        // Rótulos de estilo iguais (o classificador não distingue) e CLAP
        // diferente: quem manda é o CLAP.
        let mut seed = t(&[1.0, 0.0], 120.0, 0, 0, 2000);
        seed.clap = vec![100, 0, 0];
        let mut corrido = t(&[0.9, 0.4], 120.0, 0, 0, 2000);
        corrido.clap = vec![90, 10, 0];
        let mut indie = t(&[0.95, 0.3], 120.0, 0, 0, 2000);
        indie.clap = vec![0, 0, 100];
        let r = rec(vec![seed, corrido, indie]);
        let ids: Vec<String> = r.similar("s0", Style::Genre, 2, None).into_iter().map(|h| h.id).collect();
        assert_eq!(ids, ["s1", "s2"]);
    }

    #[test]
    fn reads_the_v3_file_with_clap_and_still_the_v2() {
        let dir = std::env::temp_dir().join(format!("bkvec-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        for v3 in [false, true] {
            let (audio, lyrics, styles, id_len, clap) = (2usize, 2usize, 1usize, 32usize, if v3 { 3 } else { 0 });
            let mut f = Vec::new();
            f.extend_from_slice(if v3 { MAGIC_V3 } else { MAGIC_V2 });
            let mut head = vec![2u32, 2, audio as u32, lyrics as u32, styles as u32, id_len as u32];
            if v3 {
                head.push(clap as u32);
            }
            for x in head {
                f.extend_from_slice(&x.to_le_bytes());
            }
            f.extend_from_slice(&3u32.to_le_bytes());
            f.extend_from_slice(b"pop");
            for (i, id) in ["a", "b"].iter().enumerate() {
                let mut b = id.as_bytes().to_vec();
                b.resize(id_len, 0);
                f.extend_from_slice(&b);
                f.extend_from_slice(&(i as u32).to_le_bytes());
            }
            for i in 0..2 {
                f.extend_from_slice(&120f32.to_le_bytes());
                f.extend_from_slice(&0.5f32.to_le_bytes());
                f.extend_from_slice(&2000u16.to_le_bytes());
                f.extend_from_slice(&[0, 0]);
                f.extend_from_slice(&[128; OTHER_DIMS]);
                f.extend_from_slice(&[200]);
                for x in [1.0f32, i as f32, 1.0, 0.0] {
                    f.extend_from_slice(&x.to_le_bytes());
                }
                if v3 {
                    f.extend_from_slice(&[100u8, 0, if i == 0 { 0 } else { 5 }]);
                }
            }
            let p = dir.join(if v3 { "v3.bkvec" } else { "v2.bkvec" });
            std::fs::write(&p, &f).unwrap();
            let r = Recommender::load(&p).unwrap();
            assert_eq!(r.len(), 2);
            assert!(r.knows("a") && r.knows("b"));
            assert_eq!(r.tracks[1].clap.len(), clap, "v3 = {v3}");
            assert_eq!(r.similar("a", Style::Genre, 5, None).len(), 1);
        }
        let _ = std::fs::remove_dir_all(&dir);
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
