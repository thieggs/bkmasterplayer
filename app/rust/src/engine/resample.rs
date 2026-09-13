//! Conversão de taxa de amostragem (rubato), sempre em estéreo intercalado.
//!
//! A saída NÃO descarta o atraso do filtro: ela tem `delay` frames de "pré-eco"
//! antes do início nominal e `delay` frames de cauda depois do fim. O mixer usa
//! isso para somar (overlap-add) o fim de uma faixa com o começo da próxima e
//! manter o gapless perfeito mesmo quando há conversão de taxa. Numa reprodução
//! isolada, o mixer simplesmente pula o pré-eco.

use anyhow::Result;
use audioadapter_buffers::direct::InterleavedSlice;
use rubato::{Async, FixedAsync, Indexing, Resampler as _, SincInterpolationParameters, WindowFunction};

const CHUNK: usize = 1024;

pub struct Resampler {
    inner: Option<Async<f32>>,
    ratio: f64,
    pending: Vec<f32>,
    out_buf: Vec<f32>,
    delay: usize,
    input_total: u64,
    output_total: u64,
}

impl Resampler {
    pub fn new(from_rate: u32, to_rate: u32) -> Result<Self> {
        let ratio = to_rate as f64 / from_rate as f64;
        if from_rate == to_rate {
            return Ok(Self {
                inner: None,
                ratio,
                pending: Vec::new(),
                out_buf: Vec::new(),
                delay: 0,
                input_total: 0,
                output_total: 0,
            });
        }
        let params = SincInterpolationParameters::new(128, WindowFunction::BlackmanHarris2);
        let inner = Async::<f32>::new_sinc(ratio, 1.0, &params, CHUNK, 2, FixedAsync::Input)?;
        let delay = inner.output_delay();
        let out_buf = vec![0.0; inner.output_frames_max() * 2];
        Ok(Self {
            inner: Some(inner),
            ratio,
            pending: Vec::with_capacity(CHUNK * 4),
            out_buf,
            delay,
            input_total: 0,
            output_total: 0,
        })
    }

    pub fn delay(&self) -> usize {
        self.delay
    }

    pub fn ratio(&self) -> f64 {
        self.ratio
    }

    /// Recebe estéreo intercalado e anexa a saída convertida em `out`.
    pub fn process(&mut self, input: &[f32], out: &mut Vec<f32>) -> Result<()> {
        self.input_total += (input.len() / 2) as u64;
        let Some(inner) = self.inner.as_mut() else {
            out.extend_from_slice(input);
            self.output_total += (input.len() / 2) as u64;
            return Ok(());
        };
        self.pending.extend_from_slice(input);
        let mut consumed = 0;
        while self.pending.len() - consumed >= CHUNK * 2 {
            let chunk = &self.pending[consumed..consumed + CHUNK * 2];
            let written = run_chunk(inner, chunk, CHUNK, None, &mut self.out_buf)?;
            out.extend_from_slice(&self.out_buf[..written * 2]);
            self.output_total += written as u64;
            consumed += CHUNK * 2;
        }
        self.pending.drain(..consumed);
        Ok(())
    }

    /// Fim da faixa: esvazia o resto e a cauda do filtro.
    pub fn flush(&mut self, out: &mut Vec<f32>) -> Result<()> {
        let Some(inner) = self.inner.as_mut() else {
            return Ok(());
        };
        let expected = (self.input_total as f64 * self.ratio).round() as u64 + 2 * self.delay as u64;
        let zeros = vec![0.0f32; CHUNK * 2];
        let mut first = true;
        while self.output_total < expected {
            let (data, partial) = if first && !self.pending.is_empty() {
                let mut d = self.pending.clone();
                let n = d.len() / 2;
                d.resize(CHUNK * 2, 0.0);
                (d, n)
            } else {
                (zeros.clone(), 0)
            };
            first = false;
            let written = run_chunk(inner, &data, CHUNK, Some(partial), &mut self.out_buf)?;
            let take = (written as u64).min(expected - self.output_total) as usize;
            out.extend_from_slice(&self.out_buf[..take * 2]);
            self.output_total += take as u64;
            if written == 0 {
                break;
            }
        }
        self.pending.clear();
        Ok(())
    }
}

fn run_chunk(
    inner: &mut Async<f32>,
    data: &[f32],
    frames: usize,
    partial: Option<usize>,
    out_buf: &mut [f32],
) -> Result<usize> {
    let input = InterleavedSlice::new(data, 2, frames)?;
    let capacity = out_buf.len() / 2;
    let mut output = InterleavedSlice::new_mut(out_buf, 2, capacity)?;
    let indexing = Indexing { input_offset: 0, output_offset: 0, partial_len: partial, active_channels_mask: None };
    let (_, written) = inner.process_into_buffer(&input, &mut output, Some(&indexing))?;
    Ok(written)
}

/// Converte `channels` canais intercalados para estéreo.
pub fn to_stereo(input: &[f32], channels: usize, out: &mut Vec<f32>) {
    out.clear();
    match channels {
        1 => {
            out.reserve(input.len() * 2);
            for &s in input {
                out.push(s);
                out.push(s);
            }
        }
        2 => out.extend_from_slice(input),
        n => {
            // Downmix simples: L/R + central e surrounds atenuados.
            out.reserve(input.len() / n * 2);
            for f in input.chunks_exact(n) {
                let c = if n >= 3 { f[2] * 0.707 } else { 0.0 };
                let (sl, sr) = if n >= 6 { (f[4] * 0.5, f[5] * 0.5) } else { (0.0, 0.0) };
                out.push((f[0] + c + sl).clamp(-1.0, 1.0));
                out.push((f[1] + c + sr).clamp(-1.0, 1.0));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn output_length_includes_both_delays() {
        let mut r = Resampler::new(44100, 48000).unwrap();
        let d = r.delay();
        assert!(d > 0);
        let input: Vec<f32> = (0..44100 * 2).map(|i| ((i / 2) as f32 * 0.01).sin()).collect();
        let mut out = Vec::new();
        r.process(&input, &mut out).unwrap();
        r.flush(&mut out).unwrap();
        assert_eq!(out.len() / 2, 48000 + 2 * d);
    }

    #[test]
    fn passthrough_when_same_rate() {
        let mut r = Resampler::new(48000, 48000).unwrap();
        assert_eq!(r.delay(), 0);
        let input = vec![0.5f32; 2000];
        let mut out = Vec::new();
        r.process(&input, &mut out).unwrap();
        r.flush(&mut out).unwrap();
        assert_eq!(out, input);
    }
}
