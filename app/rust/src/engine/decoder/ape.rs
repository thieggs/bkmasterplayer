//! Monkey's Audio (`.ape`), pelo `ape-decoder` (Rust puro, versões 3.95 em
//! diante). Cada quadro do APE (alguns segundos de áudio) decodifica sozinho:
//! o seek vai direto ao quadro certo pela tabela do cabeçalho.

use anyhow::Result;
use ape_decoder::{ApeDecoder, ApeError};
use symphonia::core::io::MediaSource;

use super::{frame_at, unsupported, Backend, Decoder};

struct Ape {
    dec: ApeDecoder<Box<dyn MediaSource>>,
    /// Próximo quadro do APE.
    frame: u32,
    frames: u32,
    /// Amostras a descartar do próximo quadro (seek no meio dele).
    skip: usize,
    channels: usize,
    rate: u32,
    total: u64,
    sample: Sample,
}

/// Como vêm as amostras do PCM que o decodificador entrega: sempre na forma
/// interna do APE, a do WAV (little-endian, 8 bits sem sinal). As marcas de
/// "veio de AIFF" (big-endian, 8 bits com sinal) só dizem como restaurar o
/// arquivo original byte a byte, e o `ape-decoder` não as aplica.
#[derive(Clone, Copy)]
enum Sample {
    U8,
    I16,
    I24,
    I32,
    /// Float de 32 bits, na codificação inteira do APE.
    F32,
}

impl Sample {
    fn bytes(self) -> usize {
        match self {
            Self::U8 => 1,
            Self::I16 => 2,
            Self::I24 => 3,
            Self::I32 | Self::F32 => 4,
        }
    }

    fn to_f32(self, b: &[u8]) -> f32 {
        match self {
            Self::U8 => (b[0] as f32 - 128.0) / 128.0,
            Self::I16 => i16::from_le_bytes([b[0], b[1]]) as f32 / 32_768.0,
            Self::I24 => (i32::from_le_bytes([0, b[0], b[1], b[2]]) >> 8) as f32 / 8_388_608.0,
            Self::I32 => i32::from_le_bytes([b[0], b[1], b[2], b[3]]) as f32 / 2_147_483_648.0,
            Self::F32 => f32::from_bits(float_transform(u32::from_le_bytes([b[0], b[1], b[2], b[3]]))),
        }
    }
}

/// O `FloatTransform` do SDK do Monkey's Audio: inteiro do APE ↔ bits do
/// IEEE 754 (a transformação é a inversa dela mesma).
fn float_transform(s: u32) -> u32 {
    let mut out = s & 0xc3ff_ffff;
    out |= !(s & 0x3c00_0000) ^ 0xc3ff_ffff;
    if out & 0x8000_0000 != 0 {
        out = !out | 0x8000_0000;
    }
    out
}

/// Arquivo que o decodificador recusa (versão antiga, cabeçalho estranho) é
/// formato não suportado; erro de leitura continua erro de leitura.
fn ape_error(e: ApeError) -> anyhow::Error {
    match e {
        ApeError::Io(e) => e.into(),
        e => unsupported(format!("Monkey's Audio ({e})")),
    }
}

pub fn open(src: Box<dyn MediaSource>) -> Result<Decoder> {
    let dec = ApeDecoder::new(src).map_err(ape_error)?;
    let info = dec.info();
    let sample = match (info.bits_per_sample, info.is_floating_point) {
        (8, _) => Sample::U8,
        (16, _) => Sample::I16,
        (24, _) => Sample::I24,
        (32, true) => Sample::F32,
        (32, false) => Sample::I32,
        (bits, _) => return Err(unsupported(format!("Monkey's Audio de {bits} bits"))),
    };
    let channels = info.channels as usize;
    if channels == 0 || info.block_align as usize != sample.bytes() * channels {
        return Err(unsupported("Monkey's Audio com cabeçalho estranho"));
    }
    let (rate, total, frames, bits) = (info.sample_rate, info.total_samples, info.total_frames, info.bits_per_sample as u32);
    let backend = Ape { dec, frame: 0, frames, skip: 0, channels, rate, total, sample };
    Decoder::new(Box::new(backend), rate, Some(total), Some(bits), "ape")
}

impl Backend for Ape {
    fn channels(&self) -> usize {
        self.channels
    }

    fn next_chunk(&mut self, out: &mut Vec<f32>) -> Result<Option<usize>> {
        while self.frame < self.frames {
            let pcm = self.dec.decode_frame(self.frame).map_err(ape_error)?;
            self.frame += 1;
            let width = self.sample.bytes();
            let frame_bytes = width * self.channels;
            let skip = (self.skip * frame_bytes).min(pcm.len());
            self.skip = 0;
            out.clear();
            out.extend(pcm[skip..].chunks_exact(width).map(|b| self.sample.to_f32(b)));
            let frames = out.len() / self.channels;
            out.truncate(frames * self.channels);
            if frames > 0 {
                return Ok(Some(frames));
            }
        }
        Ok(None)
    }

    fn seek(&mut self, position_ms: u64) -> Result<u64> {
        let target = frame_at(position_ms, self.rate, Some(self.total));
        if target >= self.total {
            self.frame = self.frames;
            return Ok(self.total);
        }
        let pos = self.dec.seek(target).map_err(ape_error)?;
        self.frame = pos.frame_index;
        self.skip = pos.skip_samples as usize;
        Ok(pos.actual_sample)
    }
}
