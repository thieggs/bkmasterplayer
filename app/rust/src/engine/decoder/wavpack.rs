//! WavPack (`.wv`), pelo `wavicle` (Rust puro): sem perdas, mono ou estéreo,
//! inteiro de 16 a 32 bits ou float. Ficam de fora o modo híbrido (com perdas
//! + `.wvc`), mais de 2 canais e DSD dentro de WavPack: viram formato não
//! suportado (o servidor converte).
//!
//! O arquivo é uma sequência de blocos independentes (`wvpk` + cabeçalho de
//! 32 bytes com a posição da primeira amostra): decodifica bloco a bloco, sem
//! carregar o arquivo inteiro, e o seek acha o bloco por busca binária.

use std::io::{Read, Seek, SeekFrom};

use anyhow::Result;
use symphonia::core::io::MediaSource;
use wavicle::error::Error as WvError;
use wavicle::BlockHeader;

use super::{frame_at, read_up_to, unsupported, Backend, Decoder};

const HEADER: usize = wavicle::block::HEADER_LEN;
/// Até onde procurar o primeiro bloco (pode haver ID3v2 ou lixo na frente)
/// e, no seek, o próximo bloco a partir de um ponto qualquer.
const SCAN_LIMIT: u64 = 1 << 20;
/// Abaixo disto a busca binária para e o resto é andando bloco a bloco.
const LINEAR_SPAN: u64 = 256 * 1024;

struct WavPack {
    src: Box<dyn MediaSource>,
    /// Onde começa o próximo bloco.
    pos: u64,
    /// O primeiro bloco e a amostra em que ele começa.
    first: u64,
    base: u64,
    len: Option<u64>,
    rate: u32,
    channels: usize,
    float: bool,
    scale: f32,
    total: Option<u64>,
    skip: u64,
    block: Vec<u8>,
}

/// Bloco que o `wavicle` recusa por escolha (híbrido, multicanal, DSD) ou por
/// ainda não fazer (8 bits) é formato não suportado.
fn wv_error(e: WvError) -> anyhow::Error {
    match e {
        WvError::OutOfScope(scope) => unsupported(format!("WavPack ({scope:?})")),
        WvError::NotYetImplemented(what) | WvError::MissingSubBlock(what) => unsupported(format!("WavPack ({what})")),
        WvError::UnsupportedVersion(v) => unsupported(format!("WavPack versão {v:#x}")),
        e => anyhow::anyhow!("WavPack inválido: {e}"),
    }
}

/// Procura um cabeçalho de bloco válido a partir de `from` (até `limit`
/// bytes adiante). Devolve onde ele começa e o cabeçalho.
fn find_block(src: &mut (impl Read + Seek), from: u64, limit: u64) -> Result<Option<(u64, BlockHeader)>> {
    let mut buf = vec![0u8; 64 * 1024];
    let mut at = from;
    while at < from + limit {
        src.seek(SeekFrom::Start(at))?;
        let n = read_up_to(src, &mut buf)?;
        if n < HEADER {
            return Ok(None);
        }
        for i in 0..=n - HEADER {
            if &buf[i..i + 4] == b"wvpk" {
                match BlockHeader::parse(&buf[i..i + HEADER]) {
                    Ok(h) => return Ok(Some((at + i as u64, h))),
                    // Arquivo é WavPack, mas de um tipo que o wavicle não faz.
                    Err(e @ WvError::OutOfScope(_)) => return Err(wv_error(e)),
                    Err(_) => {}
                }
            }
        }
        // Sobreposição: um cabeçalho pode estar cortado entre duas leituras.
        at += (n - HEADER + 1) as u64;
    }
    Ok(None)
}

pub fn open(mut src: Box<dyn MediaSource>) -> Result<Decoder> {
    let len = src.byte_len();
    let Some((first, h)) = find_block(&mut src, 0, SCAN_LIMIT)? else {
        return Err(anyhow::anyhow!("WavPack inválido: nenhum bloco"));
    };
    if !(h.flags.initial_block() && h.flags.final_block()) {
        return Err(unsupported("WavPack com mais de 2 canais"));
    }
    let mut wv = WavPack {
        src,
        pos: first,
        first,
        base: h.block_index,
        len,
        rate: 0,
        channels: h.flags.output_channels() as usize,
        float: h.flags.is_float(),
        scale: 1.0,
        total: h.total_samples,
        skip: 0,
        block: Vec::new(),
    };
    // O primeiro bloco com áudio diz a taxa (pode ser fora do padrão) e
    // confirma que o wavicle decodifica este arquivo.
    let info = loop {
        let Some(h) = wv.read_block()? else {
            return Err(anyhow::anyhow!("WavPack sem áudio"));
        };
        if h.block_samples > 0 {
            break wavicle::decode::decode_stream(&wv.block).map_err(wv_error)?;
        }
    };
    wv.pos = first;
    wv.rate = info.sample_rate;
    wv.channels = info.channels as usize;
    wv.float = info.is_float;
    wv.scale = 1.0 / (1u64 << (info.bits_per_sample.clamp(8, 32) - 1)) as f32;
    let (rate, total, bits) = (wv.rate, wv.total, info.bits_per_sample);
    Decoder::new(Box::new(wv), rate, total, Some(bits), "wavpack")
}

impl WavPack {
    /// Lê o bloco em `pos` para `self.block` e avança. `None` no fim (ou na
    /// tag APE que costuma fechar o arquivo).
    fn read_block(&mut self) -> Result<Option<BlockHeader>> {
        self.src.seek(SeekFrom::Start(self.pos))?;
        let mut head = [0u8; HEADER];
        if read_up_to(&mut self.src, &mut head)? < HEADER {
            return Ok(None);
        }
        let Ok(h) = BlockHeader::parse(&head) else { return Ok(None) };
        let len = h.block_len();
        self.block.clear();
        self.block.extend_from_slice(&head);
        self.block.resize(len, 0);
        if read_up_to(&mut self.src, &mut self.block[HEADER..])? < len - HEADER {
            return Ok(None);
        }
        self.pos += len as u64;
        Ok(Some(h))
    }
}

impl Backend for WavPack {
    fn channels(&self) -> usize {
        self.channels
    }

    fn next_chunk(&mut self, out: &mut Vec<f32>) -> Result<Option<usize>> {
        loop {
            let Some(h) = self.read_block()? else { return Ok(None) };
            if h.block_samples == 0 {
                continue;
            }
            out.clear();
            match wavicle::decode::decode_stream(&self.block) {
                Ok(d) if d.channels as usize == self.channels => {
                    if self.float {
                        out.extend(d.samples.iter().map(|&s| f32::from_bits(s as u32)));
                    } else {
                        out.extend(d.samples.iter().map(|&s| s as f32 * self.scale));
                    }
                }
                // Bloco estragado: silêncio no lugar dele, como faz a
                // biblioteca de referência, em vez de parar a música.
                r => {
                    log::debug!("bloco WavPack ignorado: {:?}", r.err());
                    out.resize(h.block_samples as usize * self.channels, 0.0);
                }
            }
            let mut frames = out.len() / self.channels;
            if self.skip > 0 {
                let drop = (self.skip as usize).min(frames);
                out.drain(..drop * self.channels);
                self.skip -= drop as u64;
                frames -= drop;
            }
            if frames > 0 {
                return Ok(Some(frames));
            }
        }
    }

    fn seek(&mut self, position_ms: u64) -> Result<u64> {
        let target = frame_at(position_ms, self.rate, self.total);
        let want = self.base + target;
        // Busca binária pelo último bloco que começa antes da amostra pedida.
        let (mut lo, mut hi) = (self.first, self.len.unwrap_or(self.first));
        let mut best = self.first;
        while hi.saturating_sub(lo) > LINEAR_SPAN {
            let mid = lo + (hi - lo) / 2;
            match find_block(&mut self.src, mid, SCAN_LIMIT.min(hi - mid))? {
                Some((at, h)) if at < hi && h.block_index <= want => {
                    best = at;
                    lo = at + 1;
                }
                _ => hi = mid,
            }
        }
        // Daí em diante, bloco a bloco, até o que contém a amostra.
        self.pos = best;
        loop {
            let at = self.pos;
            let Some(h) = self.read_block()? else {
                self.pos = at;
                self.skip = 0;
                return Ok(target);
            };
            if h.block_samples > 0 && h.block_index + h.block_samples as u64 > want {
                self.pos = at;
                self.skip = want.saturating_sub(h.block_index);
                return Ok(target);
            }
        }
    }
}
