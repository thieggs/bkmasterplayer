//! DSD, o áudio de 1 bit do SACD (2,8 MHz no DSD64; o DSD128 e acima dobram
//! a taxa), nos contêineres DSF (Sony) e DSDIFF (`.dff`, Philips). Vira PCM
//! a 88,2 kHz (96 kHz nas taxas da família de 48 kHz).
//!
//! A conversão é um passa-baixas de fase linear (seno cardinal com janela de
//! Kaiser) em dois estágios:
//! 1. direto nos bits, dizimando para 352,8 kHz. Cada byte (8 bits) entra
//!    numa tabela de 256 somas prontas: 8 multiplicações viram uma consulta;
//! 2. em ponto flutuante, de 352,8 para 88,2 kHz, já cortando o ruído que o
//!    DSD empurra para cima da faixa audível (cresce a partir de ~25 kHz).
//!
//! Nível: bit 1 = +1 e bit 0 = −1, sem ganho extra. O "0 dB" do SACD (50% de
//! modulação) fica em −6 dBFS, como no modo padrão de outros conversores, e
//! nenhum pico do SACD (até ~70%) estoura.

use std::f64::consts::PI;
use std::io::{Read, Seek, SeekFrom};

use anyhow::{anyhow, Result};
use symphonia::core::io::MediaSource;

use super::{frame_at, read_up_to, unsupported, Backend, Decoder};

/// Saídas do estágio 1 por amostra final (352,8 → 88,2 kHz).
const MID_PER_OUT: usize = 4;
/// Faixa que passa intacta, e onde o estágio 2 já cortou tudo (Hz).
const PASS_HZ: f64 = 20_000.0;
const STOP_HZ: f64 = 30_000.0;
/// Bytes por canal lidos de cada vez no DFF (o DSF lê um bloco do arquivo).
const DFF_CHUNK: usize = 4096;
/// Padrão de "silêncio" do DSD (média zero): enche a memória do filtro no
/// começo, para a primeira amostra não sair com um degrau.
const DSD_SILENCE: u8 = 0x69;

/// Bytes com os bits na ordem inversa (o DSF guarda o bit mais antigo no LSB).
fn reverse_table() -> [u8; 256] {
    let mut t = [0u8; 256];
    for (i, v) in t.iter_mut().enumerate() {
        *v = (i as u8).reverse_bits();
    }
    t
}

fn bessel_i0(x: f64) -> f64 {
    let (mut sum, mut term, mut k) = (1.0, 1.0, 1.0);
    loop {
        term *= (x / (2.0 * k)) * (x / (2.0 * k));
        sum += term;
        if term < sum * 1e-15 {
            return sum;
        }
        k += 1.0;
    }
}

/// Passa-baixas de fase linear com ganho 1 em DC: passa até `pass` e atenua
/// `atten_db` a partir de `stop` (Hz, numa taxa `rate`). O tamanho sai da
/// fórmula de Kaiser, arredondado para cima até múltiplo de `multiple`.
fn lowpass(rate: f64, pass: f64, stop: f64, atten_db: f64, multiple: usize) -> Vec<f64> {
    let width = (stop - pass) / rate;
    let n = ((atten_db - 7.95) / (14.36 * width)).ceil() as usize + 1;
    let len = n.div_ceil(multiple) * multiple;
    let cutoff = (pass + stop) / 2.0 / rate;
    let beta = 0.1102 * (atten_db - 8.7);
    let m = (len - 1) as f64 / 2.0;
    let mut h: Vec<f64> = (0..len)
        .map(|i| {
            let x = i as f64 - m;
            let sinc = if x == 0.0 { 2.0 * cutoff } else { (2.0 * PI * cutoff * x).sin() / (PI * x) };
            let r = if m > 0.0 { x / m } else { 0.0 };
            sinc * bessel_i0(beta * (1.0 - r * r).max(0.0).sqrt()) / bessel_i0(beta)
        })
        .collect();
    let sum: f64 = h.iter().sum();
    for v in &mut h {
        *v /= sum;
    }
    h
}

/// Produto escalar com 8 acumuladores (o compilador vetoriza).
fn dot(a: &[f32], b: &[f32]) -> f32 {
    let mut acc = [0f32; 8];
    let (ca, cb) = (a.chunks_exact(8), b.chunks_exact(8));
    let (ra, rb) = (ca.remainder(), cb.remainder());
    for (x, y) in ca.zip(cb) {
        for i in 0..8 {
            acc[i] += x[i] * y[i];
        }
    }
    let tail: f32 = ra.iter().zip(rb).map(|(x, y)| x * y).sum();
    acc.iter().sum::<f32>() + tail
}

struct ChannelState {
    /// Últimos bytes, em anel com cópia dupla: a janela fica contígua.
    hist1: Vec<u8>,
    pos1: usize,
    /// Bytes desde a última amostra do estágio 1.
    count1: usize,
    hist2: Vec<f32>,
    pos2: usize,
    /// Amostras do estágio 1 desde a última saída.
    count2: usize,
}

/// Converte bytes de DSD (bit mais antigo no MSB) em PCM, canal a canal.
struct Converter {
    /// Bytes de DSD por amostra do estágio 1.
    bytes_per_mid: usize,
    /// Estágio 1: uma tabela por byte da janela, do mais antigo ao mais novo.
    tables: Vec<[f32; 256]>,
    taps2: Vec<f32>,
    state: Vec<ChannelState>,
}

impl Converter {
    /// Para DSD a `dsd_rate` Hz. Devolve também a taxa do PCM.
    fn new(dsd_rate: u32, channels: usize) -> Result<(Self, u32)> {
        let (mid, out) = if dsd_rate % 44_100 == 0 {
            (352_800, 88_200)
        } else if dsd_rate % 48_000 == 0 {
            (384_000, 96_000)
        } else {
            return Err(unsupported(format!("DSD a {dsd_rate} Hz")));
        };
        let ratio = dsd_rate / mid;
        if dsd_rate % mid != 0 || !matches!(ratio, 8 | 16 | 32 | 64 | 128) {
            return Err(unsupported(format!("DSD a {dsd_rate} Hz")));
        }
        // Estágio 1: o que dobraria para dentro de 0–30 kHz ao dizimar (perto
        // de múltiplos de 352,8 kHz) tem de sumir.
        let h1 = lowpass(dsd_rate as f64, PASS_HZ, mid as f64 - STOP_HZ, 110.0, 8);
        let k = h1.len() / 8;
        let tables = (0..k)
            .map(|j| {
                let mut t = [0f32; 256];
                for (b, v) in t.iter_mut().enumerate() {
                    // Bit p do byte j: idade (k-1-j)*8 + p (o LSB é o mais novo do byte).
                    *v = (0..8)
                        .map(|p| {
                            let c = h1[(k - 1 - j) * 8 + p];
                            if b >> p & 1 == 1 { c } else { -c }
                        })
                        .sum::<f64>() as f32;
                }
                t
            })
            .collect();
        // Estágio 2 (simétrico: a ordem da janela não importa).
        let taps2: Vec<f32> = lowpass(mid as f64, PASS_HZ, STOP_HZ, 100.0, 1).into_iter().map(|v| v as f32).collect();
        let mut c = Self { bytes_per_mid: ratio as usize / 8, tables, taps2, state: Vec::new() };
        c.state = (0..channels).map(|_| c.fresh_state()).collect();
        Ok((c, out))
    }

    fn fresh_state(&self) -> ChannelState {
        let (k, n2) = (self.tables.len(), self.taps2.len());
        ChannelState { hist1: vec![DSD_SILENCE; 2 * k], pos1: 0, count1: 0, hist2: vec![0.0; 2 * n2], pos2: 0, count2: 0 }
    }

    fn reset(&mut self) {
        for i in 0..self.state.len() {
            self.state[i] = self.fresh_state();
        }
    }

    /// Bytes de DSD por amostra de saída.
    fn bytes_per_out(&self) -> u64 {
        (self.bytes_per_mid * MID_PER_OUT) as u64
    }

    /// Bytes que enchem a memória dos dois estágios (aquecimento após seek),
    /// em múltiplo de `bytes_per_out`.
    fn warmup_bytes(&self) -> u64 {
        let b = (self.tables.len() + self.taps2.len() * self.bytes_per_mid) as u64;
        b.div_ceil(self.bytes_per_out()) * self.bytes_per_out()
    }

    fn process(&mut self, ch: usize, bytes: &[u8], out: &mut Vec<f32>) {
        let Self { bytes_per_mid, tables, taps2, state } = self;
        let (k, n2) = (tables.len(), taps2.len());
        let st = &mut state[ch];
        for &b in bytes {
            st.hist1[st.pos1] = b;
            st.hist1[st.pos1 + k] = b;
            st.pos1 = if st.pos1 + 1 == k { 0 } else { st.pos1 + 1 };
            st.count1 += 1;
            if st.count1 < *bytes_per_mid {
                continue;
            }
            st.count1 = 0;
            // Janela do mais antigo ao mais novo.
            let mut acc = 0f32;
            for (t, &x) in tables.iter().zip(&st.hist1[st.pos1..st.pos1 + k]) {
                acc += t[x as usize];
            }
            st.hist2[st.pos2] = acc;
            st.hist2[st.pos2 + n2] = acc;
            st.pos2 = if st.pos2 + 1 == n2 { 0 } else { st.pos2 + 1 };
            st.count2 += 1;
            if st.count2 < MID_PER_OUT {
                continue;
            }
            st.count2 = 0;
            out.push(dot(taps2, &st.hist2[st.pos2..st.pos2 + n2]));
        }
    }
}

/// Junta os canais (cada um em `planar`) em `out`, intercalado, descartando
/// os primeiros `skip` frames. Devolve os frames que ficaram.
fn interleave(planar: &mut [Vec<f32>], out: &mut Vec<f32>, skip: &mut u64) -> usize {
    let frames = planar.iter().map(Vec::len).min().unwrap_or(0);
    let drop = (*skip).min(frames as u64) as usize;
    *skip -= drop as u64;
    out.clear();
    out.reserve((frames - drop) * planar.len());
    for i in drop..frames {
        for ch in planar.iter() {
            out.push(ch[i]);
        }
    }
    for ch in planar.iter_mut() {
        ch.clear();
    }
    frames - drop
}

fn le32(b: &[u8], o: usize) -> u32 {
    u32::from_le_bytes(b[o..o + 4].try_into().unwrap())
}

fn le64(b: &[u8], o: usize) -> u64 {
    u64::from_le_bytes(b[o..o + 8].try_into().unwrap())
}

fn be16(b: &[u8], o: usize) -> u16 {
    u16::from_be_bytes(b[o..o + 2].try_into().unwrap())
}

fn be32(b: &[u8], o: usize) -> u32 {
    u32::from_be_bytes(b[o..o + 4].try_into().unwrap())
}

fn be64(b: &[u8], o: usize) -> u64 {
    u64::from_be_bytes(b[o..o + 8].try_into().unwrap())
}

/// "dsd64", "dsd128"... (múltiplo de 44,1 ou 48 kHz).
fn dsd_name(rate: u32) -> String {
    let base = if rate % 44_100 == 0 { 44_100 } else { 48_000 };
    format!("dsd{}", rate / base)
}

fn bad(what: &str) -> anyhow::Error {
    anyhow!("DSD inválido: {what}")
}

/// Posição (frame de saída) de um seek e onde começar a ler para aquecer o
/// filtro: (frame pedido, byte por canal de onde ler, saídas a descartar).
fn seek_plan(conv: &Converter, position_ms: u64, rate: u32, total: u64) -> (u64, u64, u64) {
    let target = frame_at(position_ms, rate, Some(total));
    let per_out = conv.bytes_per_out();
    let byte = target * per_out;
    let start = byte.saturating_sub(conv.warmup_bytes());
    (target, start, (byte - start) / per_out)
}

/// DSF: cabeçalho fixo e, no chunk `data`, blocos de 4096 bytes por canal
/// (todos os canais de um trecho, um depois do outro).
struct Dsf {
    src: Box<dyn MediaSource>,
    conv: Converter,
    channels: usize,
    rate: u32,
    total: u64,
    data_start: u64,
    block: usize,
    /// Bit mais antigo no LSB (o normal no DSF): inverte cada byte.
    lsb_first: Option<[u8; 256]>,
    /// Bytes com áudio por canal (sem o enchimento do último bloco).
    bytes_per_channel: u64,
    /// Próximo byte (por canal) a decodificar.
    next: u64,
    skip: u64,
    group: Vec<u8>,
    scratch: Vec<u8>,
    planar: Vec<Vec<f32>>,
}

pub fn open_dsf(mut src: Box<dyn MediaSource>) -> Result<Decoder> {
    let mut head = [0u8; 28];
    src.read_exact(&mut head)?;
    if &head[0..4] != b"DSD " {
        return Err(bad("sem cabeçalho DSD"));
    }
    let fmt_pos = le64(&head, 4);
    src.seek(SeekFrom::Start(fmt_pos))?;
    let mut fmt = [0u8; 52];
    src.read_exact(&mut fmt)?;
    if &fmt[0..4] != b"fmt " {
        return Err(bad("sem chunk fmt"));
    }
    let (fmt_size, format_id, channels, rate, bits, samples, block) =
        (le64(&fmt, 4), le32(&fmt, 16), le32(&fmt, 24) as usize, le32(&fmt, 28), le32(&fmt, 32), le64(&fmt, 36), le32(&fmt, 44) as usize);
    if format_id != 0 {
        return Err(unsupported("DSF comprimido"));
    }
    if !(1..=8).contains(&channels) || !(1..=1 << 20).contains(&block) || !matches!(bits, 1 | 8) {
        return Err(bad("formato fora do padrão"));
    }
    let data_pos = fmt_pos.checked_add(fmt_size).ok_or_else(|| bad("chunk fmt grande demais"))?;
    src.seek(SeekFrom::Start(data_pos))?;
    let mut data = [0u8; 12];
    src.read_exact(&mut data)?;
    if &data[0..4] != b"data" {
        return Err(bad("sem chunk data"));
    }
    let data_len = le64(&data, 4).saturating_sub(12);
    let padded = data_len / channels as u64;
    let bytes_per_channel = (samples / 8).min(padded);
    let (conv, out_rate) = Converter::new(rate, channels)?;
    let total = bytes_per_channel / conv.bytes_per_out();
    let backend = Dsf {
        src,
        conv,
        channels,
        rate: out_rate,
        total,
        data_start: data_pos.saturating_add(12),
        block,
        lsb_first: (bits == 1).then(reverse_table),
        bytes_per_channel,
        next: 0,
        skip: 0,
        group: vec![0; block * channels],
        scratch: Vec::with_capacity(block),
        planar: vec![Vec::new(); channels],
    };
    Decoder::new(Box::new(backend), out_rate, Some(total), Some(1), dsd_name(rate))
}

impl Backend for Dsf {
    fn channels(&self) -> usize {
        self.channels
    }

    fn next_chunk(&mut self, out: &mut Vec<f32>) -> Result<Option<usize>> {
        while self.next < self.bytes_per_channel {
            let block = self.block as u64;
            let (g, off) = (self.next / block, (self.next % block) as usize);
            let avail = (block - off as u64).min(self.bytes_per_channel - self.next) as usize;
            let at = g.saturating_mul(block * self.channels as u64).saturating_add(self.data_start);
            self.src.seek(SeekFrom::Start(at))?;
            let n = read_up_to(&mut self.src, &mut self.group)?;
            if n == 0 {
                break;
            }
            // Arquivo cortado no meio do bloco: o resto vira silêncio.
            self.group[n..].fill(if self.lsb_first.is_some() { DSD_SILENCE.reverse_bits() } else { DSD_SILENCE });
            for ch in 0..self.channels {
                let bytes = &self.group[ch * self.block + off..ch * self.block + off + avail];
                match &self.lsb_first {
                    Some(rev) => {
                        self.scratch.clear();
                        self.scratch.extend(bytes.iter().map(|&b| rev[b as usize]));
                        self.conv.process(ch, &self.scratch, &mut self.planar[ch]);
                    }
                    None => self.conv.process(ch, bytes, &mut self.planar[ch]),
                }
            }
            self.next += avail as u64;
            let frames = interleave(&mut self.planar, out, &mut self.skip);
            if frames > 0 {
                return Ok(Some(frames));
            }
        }
        Ok(None)
    }

    fn seek(&mut self, position_ms: u64) -> Result<u64> {
        let (target, start, skip) = seek_plan(&self.conv, position_ms, self.rate, self.total);
        self.conv.reset();
        self.next = start;
        self.skip = skip;
        Ok(target)
    }
}

/// DSDIFF (`.dff`): chunks big-endian; no `DSD ` o áudio vem intercalado
/// byte a byte entre os canais, com o bit mais antigo no MSB.
struct Dff {
    src: Box<dyn MediaSource>,
    conv: Converter,
    channels: usize,
    rate: u32,
    total: u64,
    data_start: u64,
    bytes_per_channel: u64,
    next: u64,
    skip: u64,
    buf: Vec<u8>,
    split: Vec<Vec<u8>>,
    planar: Vec<Vec<f32>>,
}

/// Onde estão as partes de um DFF que interessam.
#[derive(Default)]
pub(crate) struct DffLayout {
    rate: Option<u32>,
    channels: Option<usize>,
    dst: bool,
    /// Início e tamanho do áudio (chunk `DSD `).
    sound: Option<(u64, u64)>,
    /// Tag ID3v2 (chunk `ID3 `, fora do padrão mas comum): início e tamanho.
    pub id3: Option<(u64, u64)>,
    pub title: Option<String>,
    pub artist: Option<String>,
}

/// Lê os chunks do DFF. Com `all`, segue depois do áudio (as tags costumam
/// vir no fim); senão para no áudio, que é o que tocar precisa.
pub(crate) fn dff_layout(src: &mut (impl Read + Seek), all: bool) -> Result<DffLayout> {
    let mut head = [0u8; 16];
    src.seek(SeekFrom::Start(0))?;
    src.read_exact(&mut head)?;
    if &head[0..4] != b"FRM8" || &head[12..16] != b"DSD " {
        return Err(bad("sem cabeçalho FRM8"));
    }
    let end = be64(&head, 4).saturating_add(12);
    let mut layout = DffLayout::default();
    let mut pos = 16u64;
    while pos + 12 <= end {
        src.seek(SeekFrom::Start(pos))?;
        let mut ck = [0u8; 12];
        if read_up_to(src, &mut ck)? < 12 {
            break;
        }
        let (id, size, data) = (&ck[0..4], be64(&ck, 4), pos + 12);
        match id {
            b"PROP" => {
                let mut prop = vec![0u8; size.min(1 << 16) as usize];
                src.read_exact(&mut prop)?;
                parse_prop(&prop, &mut layout);
            }
            b"DSD " => {
                layout.sound = Some((data, size));
                if !all {
                    break;
                }
            }
            b"DST " => {
                layout.dst = true;
                if !all {
                    break;
                }
            }
            b"ID3 " => layout.id3 = Some((data, size)),
            b"DIIN" => {
                let mut diin = vec![0u8; size.min(1 << 16) as usize];
                src.read_exact(&mut diin)?;
                parse_diin(&diin, &mut layout);
            }
            _ => {}
        }
        pos = data.saturating_add(size).saturating_add(size & 1);
    }
    Ok(layout)
}

fn sub_chunks(data: &[u8]) -> impl Iterator<Item = (&[u8], &[u8])> {
    let mut rest = data;
    std::iter::from_fn(move || {
        if rest.len() < 12 {
            return None;
        }
        let id = &rest[0..4];
        let size = be64(rest, 4).min((rest.len() - 12) as u64) as usize;
        let body = &rest[12..12 + size];
        let next = (12 + size + (size & 1)).min(rest.len());
        rest = &rest[next..];
        Some((id, body))
    })
}

fn parse_prop(prop: &[u8], layout: &mut DffLayout) {
    if prop.len() < 4 || &prop[0..4] != b"SND " {
        return;
    }
    for (id, body) in sub_chunks(&prop[4..]) {
        match id {
            b"FS  " if body.len() >= 4 => layout.rate = Some(be32(body, 0)),
            b"CHNL" if body.len() >= 2 => layout.channels = Some(be16(body, 0) as usize),
            b"CMPR" if body.len() >= 4 => layout.dst = &body[0..4] == b"DST ",
            _ => {}
        }
    }
}

fn parse_diin(diin: &[u8], layout: &mut DffLayout) {
    let text = |body: &[u8]| {
        let n = (body.len() >= 4).then(|| be32(body, 0) as usize)?;
        let s = String::from_utf8_lossy(body.get(4..4 + n)?).trim().to_string();
        (!s.is_empty()).then_some(s)
    };
    for (id, body) in sub_chunks(diin) {
        match id {
            b"DITI" => layout.title = text(body),
            b"DIAR" => layout.artist = text(body),
            _ => {}
        }
    }
}

pub fn open_dff(mut src: Box<dyn MediaSource>) -> Result<Decoder> {
    let layout = dff_layout(&mut src, false)?;
    if layout.dst {
        return Err(unsupported("DSD comprimido (DST)"));
    }
    let (Some(rate), Some(channels), Some((data_start, data_len))) = (layout.rate, layout.channels, layout.sound) else {
        return Err(bad("faltam propriedades"));
    };
    if !(1..=8).contains(&channels) {
        return Err(bad("canais fora do padrão"));
    }
    let (conv, out_rate) = Converter::new(rate, channels)?;
    let bytes_per_channel = data_len / channels as u64;
    let total = bytes_per_channel / conv.bytes_per_out();
    let backend = Dff {
        src,
        conv,
        channels,
        rate: out_rate,
        total,
        data_start,
        bytes_per_channel,
        next: 0,
        skip: 0,
        buf: vec![0; DFF_CHUNK * channels],
        split: vec![Vec::with_capacity(DFF_CHUNK); channels],
        planar: vec![Vec::new(); channels],
    };
    Decoder::new(Box::new(backend), out_rate, Some(total), Some(1), dsd_name(rate))
}

impl Backend for Dff {
    fn channels(&self) -> usize {
        self.channels
    }

    fn next_chunk(&mut self, out: &mut Vec<f32>) -> Result<Option<usize>> {
        while self.next < self.bytes_per_channel {
            let want = (DFF_CHUNK as u64).min(self.bytes_per_channel - self.next) as usize * self.channels;
            self.src.seek(SeekFrom::Start(self.next.saturating_mul(self.channels as u64).saturating_add(self.data_start)))?;
            let n = read_up_to(&mut self.src, &mut self.buf[..want])? / self.channels * self.channels;
            if n == 0 {
                break;
            }
            for s in self.split.iter_mut() {
                s.clear();
            }
            for frame in self.buf[..n].chunks_exact(self.channels) {
                for (ch, &b) in frame.iter().enumerate() {
                    self.split[ch].push(b);
                }
            }
            for ch in 0..self.channels {
                self.conv.process(ch, &self.split[ch], &mut self.planar[ch]);
            }
            self.next += (n / self.channels) as u64;
            let frames = interleave(&mut self.planar, out, &mut self.skip);
            if frames > 0 {
                return Ok(Some(frames));
            }
        }
        Ok(None)
    }

    fn seek(&mut self, position_ms: u64) -> Result<u64> {
        let (target, start, skip) = seek_plan(&self.conv, position_ms, self.rate, self.total);
        self.conv.reset();
        self.next = start;
        self.skip = skip;
        Ok(target)
    }
}

/// Onde começa a tag ID3v2 de um DSF (o cabeçalho aponta; 0 = sem tag).
pub(crate) fn dsf_id3_offset(src: &mut (impl Read + Seek)) -> Option<u64> {
    let mut head = [0u8; 28];
    src.seek(SeekFrom::Start(0)).ok()?;
    src.read_exact(&mut head).ok()?;
    (&head[0..4] == b"DSD ").then(|| le64(&head, 20)).filter(|&p| p > 0)
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::io::Cursor;

    /// Modulador sigma-delta de 2ª ordem: PCM (−1..1) → bits de DSD, MSB
    /// primeiro, um vetor de bytes por canal.
    pub(crate) fn modulate(signal: impl Fn(f64) -> f64, rate: u32, seconds: f64) -> Vec<u8> {
        let n = (rate as f64 * seconds) as usize / 8 * 8;
        let (mut i1, mut i2, mut y) = (0.0f64, 0.0f64, 0.0f64);
        let mut bytes = Vec::with_capacity(n / 8);
        let mut cur = 0u8;
        for i in 0..n {
            let x = signal(i as f64 / rate as f64);
            i1 += x - y;
            i2 += i1 - y;
            y = if i2 >= 0.0 { 1.0 } else { -1.0 };
            cur = cur << 1 | (y > 0.0) as u8;
            if i % 8 == 7 {
                bytes.push(cur);
                cur = 0;
            }
        }
        bytes
    }

    /// DSF em memória com os canais dados (bytes MSB primeiro).
    pub(crate) fn dsf_file(channels: &[Vec<u8>], rate: u32) -> Vec<u8> {
        dsf_file_with_tag(channels, rate, &[])
    }

    /// Idem, com uma tag ID3v2 no fim (o cabeçalho aponta para ela).
    pub(crate) fn dsf_file_with_tag(channels: &[Vec<u8>], rate: u32, id3: &[u8]) -> Vec<u8> {
        let block = 4096usize;
        let per = channels[0].len();
        let groups = per.div_ceil(block);
        let mut data = Vec::new();
        for g in 0..groups {
            for ch in channels {
                for i in 0..block {
                    // DSF: LSB primeiro.
                    data.push(ch.get(g * block + i).map_or(0, |b| b.reverse_bits()));
                }
            }
        }
        let mut f = Vec::new();
        let end = (28 + 52 + 12 + data.len()) as u64;
        f.extend_from_slice(b"DSD ");
        f.extend_from_slice(&28u64.to_le_bytes());
        f.extend_from_slice(&(end + id3.len() as u64).to_le_bytes());
        f.extend_from_slice(&(if id3.is_empty() { 0 } else { end }).to_le_bytes());
        f.extend_from_slice(b"fmt ");
        f.extend_from_slice(&52u64.to_le_bytes());
        for v in [1u32, 0, 2, channels.len() as u32, rate, 1] {
            f.extend_from_slice(&v.to_le_bytes());
        }
        f.extend_from_slice(&((per * 8) as u64).to_le_bytes());
        f.extend_from_slice(&(block as u32).to_le_bytes());
        f.extend_from_slice(&0u32.to_le_bytes());
        f.extend_from_slice(b"data");
        f.extend_from_slice(&((12 + data.len()) as u64).to_le_bytes());
        f.extend_from_slice(&data);
        f.extend_from_slice(id3);
        f
    }

    fn dff_file(channels: &[Vec<u8>], rate: u32) -> Vec<u8> {
        let chunk = |id: &[u8], body: &[u8]| {
            let mut c = id.to_vec();
            c.extend_from_slice(&(body.len() as u64).to_be_bytes());
            c.extend_from_slice(body);
            if body.len() % 2 == 1 {
                c.push(0);
            }
            c
        };
        let mut prop = b"SND ".to_vec();
        prop.extend(chunk(b"FS  ", &rate.to_be_bytes()));
        let mut chnl = (channels.len() as u16).to_be_bytes().to_vec();
        for _ in channels {
            chnl.extend_from_slice(b"SLFT");
        }
        prop.extend(chunk(b"CHNL", &chnl));
        prop.extend(chunk(b"CMPR", b"DSD \x0enot compressed\x00"));
        let mut sound = Vec::new();
        for i in 0..channels[0].len() {
            for ch in channels {
                sound.push(ch[i]);
            }
        }
        let mut diin = chunk(b"DITI", &[&4u32.to_be_bytes()[..], b"Tema"].concat());
        diin.extend(chunk(b"DIAR", &[&6u32.to_be_bytes()[..], b"Autora"].concat()));
        let mut body = b"DSD ".to_vec();
        body.extend(chunk(b"FVER", &0x0105_0000u32.to_be_bytes()));
        body.extend(chunk(b"PROP", &prop));
        body.extend(chunk(b"DSD ", &sound));
        body.extend(chunk(b"DIIN", &diin));
        chunk(b"FRM8", &body)
    }

    fn decode(mut d: Decoder) -> Vec<f32> {
        let mut all = Vec::new();
        let mut buf = Vec::new();
        while d.next_chunk(&mut buf).unwrap().is_some() {
            all.extend_from_slice(&buf);
        }
        all
    }

    /// Amplitude e frequência de um seno (canal `ch` de `ch_count`), longe das bordas.
    fn measure(pcm: &[f32], ch: usize, chs: usize, rate: f64, freq: f64) -> (f64, f64) {
        let x: Vec<f64> = pcm.iter().skip(ch).step_by(chs).map(|&v| v as f64).collect();
        let (a, b) = (x.len() / 4, x.len() * 3 / 4);
        // Projeção em seno e cosseno da frequência esperada + resíduo.
        let (mut s, mut c) = (0.0, 0.0);
        for (i, v) in x[a..b].iter().enumerate() {
            let t = 2.0 * PI * freq * (i + a) as f64 / rate;
            s += v * t.sin();
            c += v * t.cos();
        }
        let n = (b - a) as f64;
        let (s, c) = (2.0 * s / n, 2.0 * c / n);
        let amp = (s * s + c * c).sqrt();
        let mut err = 0.0;
        for (i, v) in x[a..b].iter().enumerate() {
            let t = 2.0 * PI * freq * (i + a) as f64 / rate;
            err += (v - s * t.sin() - c * t.cos()).powi(2);
        }
        let rms_err = (err / n).sqrt();
        (amp, 20.0 * (rms_err / (amp / 2f64.sqrt())).log10())
    }

    #[test]
    fn dsf_sine_comes_out_at_the_right_level_and_clean() {
        let rate = 2_822_400;
        let left = modulate(|t| 0.5 * (2.0 * PI * 1000.0 * t).sin(), rate, 0.3);
        let right = modulate(|t| 0.25 * (2.0 * PI * 3000.0 * t).sin(), rate, 0.3);
        let file = dsf_file(&[left.clone(), right], rate);
        let d = Decoder::open(Box::new(Cursor::new(file)), Some("dsf"), None).unwrap();
        assert_eq!((d.sample_rate, d.channels), (88_200, 2));
        assert_eq!(d.total_frames, Some(left.len() as u64 / 4));
        let pcm = decode(d);
        assert_eq!(pcm.len() / 2, left.len() / 4);
        let (amp_l, noise_l) = measure(&pcm, 0, 2, 88_200.0, 1000.0);
        let (amp_r, noise_r) = measure(&pcm, 1, 2, 88_200.0, 3000.0);
        assert!((amp_l - 0.5).abs() < 0.005, "nível esquerdo {amp_l}");
        assert!((amp_r - 0.25).abs() < 0.0025, "nível direito {amp_r}");
        // Ruído + distorção bem abaixo do sinal. O modulador de teste é de 2ª
        // ordem: o ruído dele até 30 kHz já fica perto de −60 dB.
        assert!(noise_l < -50.0 && noise_r < -45.0, "ruído {noise_l} / {noise_r} dB");
    }

    #[test]
    fn dsf_seek_matches_continuous_decode() {
        let rate = 2_822_400;
        let ch = modulate(|t| 0.4 * (2.0 * PI * 440.0 * t).sin(), rate, 0.25);
        let file = dsf_file(&[ch.clone(), ch], rate);
        let all = decode(Decoder::open(Box::new(Cursor::new(file.clone())), None, None).unwrap());
        let mut d = Decoder::open(Box::new(Cursor::new(file)), None, None).unwrap();
        let at = d.seek(150).unwrap() as usize;
        assert_eq!(at, 150 * 88_200 / 1000);
        let rest = decode(d);
        assert_eq!(rest.len(), all.len() - at * 2);
        let diff = rest.iter().zip(&all[at * 2..]).map(|(a, b)| (a - b).abs()).fold(0f32, f32::max);
        assert!(diff < 1e-6, "diferença {diff}");
    }

    #[test]
    fn dff_decodes_and_reads_the_title() {
        let rate = 2_822_400 * 2;
        let ch = modulate(|t| 0.5 * (2.0 * PI * 1000.0 * t).sin(), rate, 0.2);
        let file = dff_file(&[ch.clone(), ch.clone()], rate);
        let d = Decoder::open(Box::new(Cursor::new(file.clone())), Some("dff"), None).unwrap();
        assert_eq!((d.sample_rate, d.channels, d.codec.as_str()), (88_200, 2, "dsd128"));
        let pcm = decode(d);
        assert_eq!(pcm.len() / 2, ch.len() / 8);
        let (amp, noise) = measure(&pcm, 0, 2, 88_200.0, 1000.0);
        assert!((amp - 0.5).abs() < 0.005 && noise < -55.0, "{amp} {noise}");
        let layout = dff_layout(&mut Cursor::new(file), true).unwrap();
        assert_eq!((layout.title.as_deref(), layout.artist.as_deref()), (Some("Tema"), Some("Autora")));
    }

    #[test]
    fn dst_and_odd_rates_are_unsupported_not_errors() {
        let mut file = dff_file(&[vec![0x69; 64]], 2_822_400);
        let at = file.windows(5).position(|w| w == b"DSD \x0e").unwrap();
        file[at..at + 4].copy_from_slice(b"DST ");
        let e = Decoder::open(Box::new(Cursor::new(file)), None, None).err().unwrap();
        assert!(super::super::is_unsupported(&e), "{e:#}");
        let e = Decoder::open(Box::new(Cursor::new(dsf_file(&[vec![0x69; 64]], 1_000_000))), None, None).err().unwrap();
        assert!(super::super::is_unsupported(&e), "{e:#}");
    }
}
