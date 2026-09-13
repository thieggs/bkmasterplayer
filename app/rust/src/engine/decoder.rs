//! Decodificação com symphonia: qualquer formato suportado → f32 intercalado.

use anyhow::{anyhow, bail, Context, Result};
use symphonia::core::codecs::audio::{AudioDecoder, AudioDecoderOptions};
use symphonia::core::errors::Error as SymError;
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, FormatReader, SeekMode, SeekTo, TrackType};
use symphonia::core::io::{MediaSource, MediaSourceStream, MediaSourceStreamOptions};
use symphonia::core::meta::MetadataOptions;
use symphonia::core::units::{Time, TimeBase, Timestamp};

pub struct Decoder {
    format: Box<dyn FormatReader + 'static>,
    decoder: Box<dyn AudioDecoder>,
    track_id: u32,
    time_base: Option<TimeBase>,
    pub sample_rate: u32,
    pub channels: usize,
    /// Frames tocáveis (sem delay/padding do encoder) na taxa original, se conhecido.
    pub total_frames: Option<u64>,
    /// Frames a descartar do próximo bloco decodificado (seek preciso).
    skip_frames: u64,
}

fn ts_to_frames(ts: Timestamp, tb: Option<TimeBase>, sample_rate: u32) -> u64 {
    let v = ts.get().max(0) as u128;
    match tb {
        Some(tb) => (v * tb.numer.get() as u128 * sample_rate as u128 / tb.denom.get() as u128) as u64,
        None => v as u64,
    }
}

impl Decoder {
    pub fn open(source: Box<dyn MediaSource>, ext_hint: Option<&str>, mime_hint: Option<&str>) -> Result<Self> {
        let mss = MediaSourceStream::new(source, MediaSourceStreamOptions::default());
        let mut hint = Hint::new();
        if let Some(ext) = ext_hint {
            hint.with_extension(ext);
        }
        if let Some(mime) = mime_hint {
            hint.mime_type(mime);
        }
        let format = symphonia::default::get_probe()
            .probe(&hint, mss, FormatOptions::default(), MetadataOptions::default())
            .context("formato não reconhecido")?;

        let track = format
            .default_track(TrackType::Audio)
            .or_else(|| format.first_track_known_codec(TrackType::Audio))
            .ok_or_else(|| anyhow!("nenhuma faixa de áudio"))?;
        let params = track
            .codec_params
            .as_ref()
            .and_then(|p| p.audio())
            .ok_or_else(|| anyhow!("faixa sem parâmetros de áudio"))?
            .clone();
        let track_id = track.id;
        let time_base = track.time_base;
        let total_frames = track.num_frames;

        let decoder = symphonia::default::get_codecs()
            .make_audio_decoder(&params, &AudioDecoderOptions::default())
            .context("codec não suportado")?;
        let sample_rate = params.sample_rate.ok_or_else(|| anyhow!("taxa de amostragem desconhecida"))?;
        let channels = params.channels.as_ref().map(|c| c.count()).unwrap_or(2).max(1);

        Ok(Self {
            format,
            decoder,
            track_id,
            time_base,
            sample_rate,
            channels,
            total_frames,
            skip_frames: 0,
        })
    }

    /// Decodifica o próximo pacote em `out` (intercalado, `self.channels` canais).
    /// Retorna `Ok(None)` no fim do arquivo.
    pub fn next_chunk(&mut self, out: &mut Vec<f32>) -> Result<Option<usize>> {
        loop {
            let packet = match self.format.next_packet() {
                Ok(Some(p)) => p,
                Ok(None) => return Ok(None),
                Err(SymError::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
                Err(SymError::ResetRequired) => {
                    self.decoder.reset();
                    continue;
                }
                Err(e) => return Err(e.into()),
            };
            if packet.track_id != self.track_id {
                continue;
            }
            match self.decoder.decode(&packet) {
                Ok(buf) => {
                    let spec_channels = buf.spec().channels().count().max(1);
                    buf.copy_to_vec_interleaved::<f32>(out);
                    if spec_channels != self.channels {
                        self.channels = spec_channels;
                    }
                    let mut frames = out.len() / self.channels;
                    if self.skip_frames > 0 {
                        let skip = (self.skip_frames as usize).min(frames);
                        out.drain(..skip * self.channels);
                        self.skip_frames -= skip as u64;
                        frames -= skip;
                        if frames == 0 {
                            continue;
                        }
                    }
                    return Ok(Some(frames));
                }
                // Pacote corrompido: pula e segue.
                Err(SymError::DecodeError(msg)) => {
                    log::debug!("pacote inválido ignorado: {msg}");
                    continue;
                }
                Err(SymError::IoError(e)) if e.kind() != std::io::ErrorKind::Interrupted => {
                    log::debug!("erro de IO no pacote ignorado: {e}");
                    continue;
                }
                Err(SymError::ResetRequired) => {
                    self.decoder.reset();
                    continue;
                }
                Err(e) => return Err(e.into()),
            }
        }
    }

    /// Seek preciso. Retorna a posição real em frames (taxa original).
    pub fn seek(&mut self, position_ms: u64) -> Result<u64> {
        let seeked = self
            .format
            .seek(
                SeekMode::Accurate,
                SeekTo::Time { time: Time::from_millis_u64(position_ms), track_id: Some(self.track_id) },
            )
            .map_err(|e| anyhow!("seek falhou: {e}"))?;
        self.decoder.reset();
        let required = ts_to_frames(seeked.required_ts, self.time_base, self.sample_rate);
        let actual = ts_to_frames(seeked.actual_ts, self.time_base, self.sample_rate);
        self.skip_frames = required.saturating_sub(actual);
        if required < actual {
            bail!("seek retornou posição depois da pedida");
        }
        Ok(required)
    }
}
