//! Saída de áudio via cpal. O callback só chama o mixer e converte o formato.
//!
//! No Linux usa o PulseAudio nativo quando existe (o PipeWire atende nesse
//! protocolo): assim o app segue a saída padrão do sistema (Bluetooth, HDMI…),
//! aparece no mixer do desktop e lista os dispositivos com nomes legíveis.
//! Sem servidor de som, cai no ALSA.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use anyhow::{anyhow, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{BufferSize, ErrorKind, FromSample, SampleFormat, SizedSample, SupportedBufferSize};
use parking_lot::Mutex;

use super::mixer::Mixer;

pub struct Output {
    stream: cpal::Stream,
    suspended: bool,
    pub sample_rate: u32,
    pub channels: u16,
    pub device_name: String,
    /// Id do dispositivo aberto (para detectar mudança da saída padrão).
    pub device_id: Option<String>,
}

impl Output {
    /// Para o stream (pausado há um tempo): o sistema deixa de manter o áudio
    /// e a CPU acordados só para tocar silêncio (bateria, no celular).
    pub fn suspend(&mut self) {
        if !self.suspended && self.stream.pause().is_ok() {
            self.suspended = true;
        }
    }

    /// Volta a rodar o stream (o mixer só processa comandos dentro do callback).
    /// false = não voltou (ex.: o servidor de som reiniciou): reabrir a saída.
    pub fn wake(&mut self) -> bool {
        if self.suspended {
            self.suspended = false;
            if let Err(e) = self.stream.play() {
                eprintln!("[áudio] retomando stream: {e}");
                return false;
            }
        }
        true
    }

    pub fn is_suspended(&self) -> bool {
        self.suspended
    }
}

#[derive(Debug, Clone)]
pub struct DeviceInfo {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

/// Host preferido: PulseAudio/PipeWire no Linux, senão o padrão da plataforma.
/// Fica em cache (cada host PulseAudio é uma conexão com o servidor de som).
static HOST: Mutex<Option<cpal::Host>> = Mutex::new(None);

fn with_host<R>(f: impl FnOnce(&cpal::Host) -> R) -> R {
    let mut guard = HOST.lock();
    let host = guard.get_or_insert_with(make_host);
    f(host)
}

/// Descarta o host em cache (ex.: o servidor de som reiniciou); recria na próxima chamada.
pub fn reset_host() {
    *HOST.lock() = None;
}

fn make_host() -> cpal::Host {
    #[cfg(target_os = "linux")]
    {
        if let Ok(h) = cpal::host_from_id(cpal::HostId::PulseAudio) {
            if h.default_output_device().is_some() {
                return h;
            }
        }
    }
    cpal::default_host()
}

fn device_name(d: &cpal::Device) -> String {
    d.description().map(|x| x.name().to_string()).unwrap_or_else(|_| "?".into())
}

fn id_of(d: &cpal::Device) -> Option<String> {
    d.id().ok().map(|i| i.to_string())
}

pub fn list_devices() -> Result<Vec<DeviceInfo>> {
    let (default_id, devices) = with_host(|h| -> Result<_> {
        Ok((h.default_output_device().and_then(|d| id_of(&d)), h.output_devices()?.collect::<Vec<_>>()))
    })?;
    let mut out = Vec::new();
    for d in devices {
        let Some(id) = id_of(&d) else { continue };
        // No ALSA puro há dezenas de "plugins" confusos; mostra só os úteis.
        if id.starts_with("alsa:") && !(id == "alsa:default" || id.starts_with("alsa:plughw:") || id == "alsa:pipewire" || id == "alsa:pulse") {
            continue;
        }
        out.push(DeviceInfo { is_default: Some(&id) == default_id.as_ref(), name: device_name(&d), id });
    }
    Ok(out)
}

/// Id da saída padrão atual do sistema.
pub fn default_device_id() -> Option<String> {
    with_host(|h| h.default_output_device()).and_then(|d| id_of(&d))
}

/// Taxa padrão do dispositivo (para montar o mixer antes de abrir o stream).
pub fn device_rate(device_id: Option<&str>) -> Result<u32> {
    let device = find_device(device_id)?;
    Ok(device.default_output_config()?.sample_rate())
}

fn find_device(device_id: Option<&str>) -> Result<cpal::Device> {
    if let Some(id) = device_id {
        let parsed = id.parse::<cpal::DeviceId>().map_err(|_| anyhow!("id de dispositivo inválido: {id}"))?;
        return with_host(|h| h.device_by_id(&parsed)).ok_or_else(|| anyhow!("dispositivo de áudio não encontrado: {id}"));
    }
    with_host(|h| h.default_output_device()).ok_or_else(|| anyhow!("nenhum dispositivo de saída de áudio"))
}

pub fn open(device_id: Option<&str>, mixer: Arc<Mutex<Mixer>>, failed: Arc<AtomicBool>) -> Result<Output> {
    let device = find_device(device_id)?;
    let default = device.default_output_config()?;
    // Prefere float 32 (o servidor de som converte com mais qualidade que truncar aqui).
    let supported = device
        .supported_output_configs()
        .ok()
        .and_then(|mut it| {
            it.find(|c| {
                c.sample_format() == SampleFormat::F32
                    && c.channels() == default.channels()
                    && c.min_sample_rate() <= default.sample_rate()
                    && c.max_sample_rate() >= default.sample_rate()
            })
        })
        .map(|c| c.with_sample_rate(default.sample_rate()))
        .unwrap_or(default);
    let format = supported.sample_format();
    let sample_rate = supported.sample_rate();
    // Música não precisa de latência baixa: ~50 ms por período (≈100 ms no
    // total no PulseAudio) evita travadas com Bluetooth e CPU ocupada.
    let wanted = (sample_rate / 20).max(256);
    let buffer_size = match supported.buffer_size() {
        SupportedBufferSize::Range { min, max } if wanted >= *min && wanted <= *max => BufferSize::Fixed(wanted),
        _ => BufferSize::Default,
    };
    let config = cpal::StreamConfig { channels: supported.channels().max(1), sample_rate, buffer_size };
    let channels = config.channels;
    mixer.lock().set_rate(sample_rate);

    let stream = match format {
        SampleFormat::F32 => build::<f32>(&device, config, mixer, failed)?,
        SampleFormat::I16 => build::<i16>(&device, config, mixer, failed)?,
        SampleFormat::I32 => build::<i32>(&device, config, mixer, failed)?,
        SampleFormat::U16 => build::<u16>(&device, config, mixer, failed)?,
        SampleFormat::F64 => build::<f64>(&device, config, mixer, failed)?,
        SampleFormat::I24 => build::<cpal::I24>(&device, config, mixer, failed)?,
        other => return Err(anyhow!("formato de saída não suportado: {other}")),
    };
    Ok(Output {
        stream,
        suspended: false,
        sample_rate,
        channels,
        device_name: device_name(&device),
        device_id: id_of(&device),
    })
}

fn build<T>(
    device: &cpal::Device,
    config: cpal::StreamConfig,
    mixer: Arc<Mutex<Mixer>>,
    failed: Arc<AtomicBool>,
) -> Result<cpal::Stream>
where
    T: SizedSample + FromSample<f32>,
{
    let channels = config.channels as usize;
    let mut stereo = vec![0.0f32; 16384];
    let stream = device.build_output_stream(
        config,
        move |data: &mut [T], _: &cpal::OutputCallbackInfo| {
            let frames = data.len() / channels;
            if stereo.len() < frames * 2 {
                stereo.resize(frames * 2, 0.0);
            }
            let buf = &mut stereo[..frames * 2];
            match mixer.try_lock() {
                Some(mut m) => m.render(buf),
                None => buf.fill(0.0),
            }
            for (i, frame) in data.chunks_mut(channels).enumerate() {
                let (l, r) = (buf[i * 2], buf[i * 2 + 1]);
                if channels == 1 {
                    frame[0] = T::from_sample((l + r) * 0.5);
                } else {
                    frame[0] = T::from_sample(l);
                    frame[1] = T::from_sample(r);
                    for s in frame.iter_mut().skip(2) {
                        *s = T::from_sample(0.0f32);
                    }
                }
            }
        },
        move |err: cpal::Error| match err.kind() {
            ErrorKind::Xrun => eprintln!("[áudio] xrun (o callback atrasou)"),
            ErrorKind::RealtimeDenied | ErrorKind::DeviceChanged => log::debug!("áudio: {err}"),
            _ => {
                eprintln!("[áudio] stream falhou: {err}");
                failed.store(true, Ordering::Relaxed);
            }
        },
        None,
    )?;
    stream.play()?;
    Ok(stream)
}
