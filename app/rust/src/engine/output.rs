//! Saída de áudio via cpal. O callback só chama o mixer e converte o formato.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use anyhow::{anyhow, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{ErrorKind, FromSample, SampleFormat, SizedSample};
use parking_lot::Mutex;

use super::mixer::Mixer;

pub struct Output {
    _stream: cpal::Stream,
    pub sample_rate: u32,
    pub channels: u16,
    pub device_name: String,
}

#[derive(Debug, Clone)]
pub struct DeviceInfo {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

fn device_name(d: &cpal::Device) -> String {
    d.description().map(|x| x.name().to_string()).unwrap_or_else(|_| "?".into())
}

pub fn list_devices() -> Result<Vec<DeviceInfo>> {
    let host = cpal::default_host();
    let default_id = host.default_output_device().and_then(|d| d.id().ok()).map(|i| i.to_string());
    let mut out = Vec::new();
    for d in host.output_devices()? {
        let Ok(id) = d.id() else { continue };
        let id = id.to_string();
        out.push(DeviceInfo { is_default: Some(&id) == default_id.as_ref(), name: device_name(&d), id });
    }
    Ok(out)
}

/// Taxa padrão do dispositivo (para montar o mixer antes de abrir o stream).
pub fn device_rate(device_id: Option<&str>) -> Result<u32> {
    let device = find_device(device_id)?;
    Ok(device.default_output_config()?.sample_rate())
}

fn find_device(device_id: Option<&str>) -> Result<cpal::Device> {
    let host = cpal::default_host();
    if let Some(id) = device_id {
        if let Ok(parsed) = id.parse::<cpal::DeviceId>() {
            if let Some(d) = host.device_by_id(&parsed) {
                return Ok(d);
            }
        }
        log::warn!("dispositivo {id} não encontrado, usando o padrão");
    }
    host.default_output_device().ok_or_else(|| anyhow!("nenhum dispositivo de saída de áudio"))
}

pub fn open(device_id: Option<&str>, mixer: Arc<Mutex<Mixer>>, failed: Arc<AtomicBool>) -> Result<Output> {
    let device = find_device(device_id)?;
    let supported = device.default_output_config()?;
    let format = supported.sample_format();
    let config: cpal::StreamConfig = supported.into();
    let sample_rate = config.sample_rate;
    let channels = config.channels;
    mixer.lock().set_rate(sample_rate);

    let stream = match format {
        SampleFormat::F32 => build::<f32>(&device, config, mixer, failed)?,
        SampleFormat::I16 => build::<i16>(&device, config, mixer, failed)?,
        SampleFormat::I32 => build::<i32>(&device, config, mixer, failed)?,
        SampleFormat::U16 => build::<u16>(&device, config, mixer, failed)?,
        SampleFormat::F64 => build::<f64>(&device, config, mixer, failed)?,
        other => return Err(anyhow!("formato de saída não suportado: {other}")),
    };
    Ok(Output { _stream: stream, sample_rate, channels, device_name: device_name(&device) })
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
            ErrorKind::Xrun | ErrorKind::RealtimeDenied | ErrorKind::DeviceChanged => {
                log::debug!("áudio: {err}")
            }
            _ => {
                log::warn!("stream de áudio falhou: {err}");
                failed.store(true, Ordering::Relaxed);
            }
        },
        None,
    )?;
    stream.play()?;
    Ok(stream)
}
