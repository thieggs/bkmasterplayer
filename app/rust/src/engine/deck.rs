//! Deck: uma faixa carregada. Uma thread "produtora" decodifica e converte a
//! taxa, e enche um ring buffer sem trava. O mixer (thread de áudio) consome.

use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{anyhow, Result};
use parking_lot::{Condvar, Mutex};

use super::automix::TempoMap;
use super::decoder::Decoder;
use super::resample::{to_stereo, Resampler};

pub const UNKNOWN: u64 = u64::MAX;

/// Passagem do conversor de taxa de uma faixa para a seguinte (gapless).
///
/// Com conversão de taxa, cada faixa com seu próprio conversor começa numa
/// grade de amostras deslocada (até meia amostra) em relação ao fim da anterior,
/// e a emenda fica audível. Passando o MESMO conversor (com o estado interno) da
/// faixa A para a B, a conversão continua sem emenda, como se fosse um arquivo só.
pub struct Handoff {
    state: Mutex<HandoffState>,
    /// Taxa de origem da próxima faixa (0 = ainda não sabe).
    next_rate: AtomicU32,
    cond: Condvar,
}

enum HandoffState {
    Waiting,
    Offered(Box<Resampler>),
    Declined,
    Taken,
}

impl Handoff {
    pub fn new() -> Arc<Self> {
        Arc::new(Self { state: Mutex::new(HandoffState::Waiting), next_rate: AtomicU32::new(0), cond: Condvar::new() })
    }

    fn publish_rate(&self, rate: u32) {
        self.next_rate.store(rate, Ordering::Release);
    }

    fn next_rate(&self) -> Option<u32> {
        Some(self.next_rate.load(Ordering::Acquire)).filter(|r| *r != 0)
    }

    fn offer(&self, rs: Resampler) {
        *self.state.lock() = HandoffState::Offered(Box::new(rs));
        self.cond.notify_all();
    }

    pub fn decline(&self) {
        let mut st = self.state.lock();
        if matches!(*st, HandoffState::Waiting) {
            *st = HandoffState::Declined;
        }
        self.cond.notify_all();
    }

    /// Espera a faixa anterior decidir. `None` = recusado/cancelado.
    fn wait(&self, cancel: &AtomicBool) -> Option<Resampler> {
        let mut st = self.state.lock();
        loop {
            match std::mem::replace(&mut *st, HandoffState::Taken) {
                HandoffState::Offered(rs) => return Some(*rs),
                HandoffState::Waiting => *st = HandoffState::Waiting,
                other => {
                    *st = other;
                    return None;
                }
            }
            if cancel.load(Ordering::Relaxed) {
                return None;
            }
            self.cond.wait_for(&mut st, Duration::from_millis(50));
        }
    }
}

#[derive(Default)]
pub struct Successor {
    handoff: Option<Arc<Handoff>>,
    decoding_done: bool,
}

/// Estado compartilhado entre a produtora, o mixer e a thread de eventos.
pub struct DeckShared {
    pub token: u64,
    /// Frames (taxa do dispositivo) já consumidos pelo mixer, incluindo o pré-eco.
    pub consumed: AtomicU64,
    pub produced: AtomicU64,
    /// Total de frames que a produtora vai entregar (estimado; exato após `eof`).
    pub total_frames: AtomicU64,
    pub lead_in: AtomicU64,
    pub tail: AtomicU64,
    /// Posição de início (frames na taxa do dispositivo) — diferente de 0 após seek.
    pub start_frame: AtomicU64,
    pub eof: AtomicBool,
    pub ready: AtomicBool,
    pub failed: AtomicBool,
    pub cancel: Arc<AtomicBool>,
    pub error: Mutex<Option<String>>,
    pub device_rate: u32,
    pub successor: Mutex<Successor>,
    /// Time-stretch (AutoMix): mapeia frames tocados → posição original.
    pub tempo: Option<TempoMap>,
}

impl DeckShared {
    pub fn new(token: u64, device_rate: u32) -> Arc<Self> {
        Self::with_tempo(token, device_rate, None)
    }

    pub fn with_tempo(token: u64, device_rate: u32, tempo: Option<TempoMap>) -> Arc<Self> {
        Arc::new(Self {
            token,
            consumed: AtomicU64::new(0),
            produced: AtomicU64::new(0),
            total_frames: AtomicU64::new(UNKNOWN),
            lead_in: AtomicU64::new(0),
            tail: AtomicU64::new(0),
            start_frame: AtomicU64::new(0),
            eof: AtomicBool::new(false),
            ready: AtomicBool::new(false),
            failed: AtomicBool::new(false),
            cancel: Arc::new(AtomicBool::new(false)),
            error: Mutex::new(None),
            device_rate,
            successor: Mutex::new(Successor::default()),
            tempo,
        })
    }

    /// Frames tocados (sem o pré-eco) → frames da faixa original desde o início do deck.
    pub fn played_to_native(&self, played: u64) -> u64 {
        match &self.tempo {
            Some(m) => m.input_at(played as f64).round().max(0.0) as u64,
            None => played,
        }
    }

    /// Inverso: quantos frames tocados até chegar num frame original (desde o início do deck).
    pub fn native_to_played(&self, native: u64) -> u64 {
        match &self.tempo {
            Some(m) => m.output_at(native as f64).round().max(0.0) as u64,
            None => native,
        }
    }

    /// Posição na linha do tempo original da faixa, em frames do dispositivo.
    pub fn native_position(&self) -> u64 {
        let consumed = self.consumed.load(Ordering::Relaxed);
        let lead = self.lead_in.load(Ordering::Relaxed);
        self.start_frame.load(Ordering::Relaxed) + self.played_to_native(consumed.saturating_sub(lead))
    }

    /// Posição de reprodução em ms (linha do tempo original da faixa).
    pub fn position_ms(&self) -> u64 {
        self.native_position() * 1000 / self.device_rate as u64
    }

    /// Duração nominal em ms (sem pré-eco/cauda), se conhecida.
    pub fn duration_ms(&self) -> Option<u64> {
        let total = self.total_frames.load(Ordering::Relaxed);
        if total == UNKNOWN {
            return None;
        }
        let lead = self.lead_in.load(Ordering::Relaxed);
        let tail = self.tail.load(Ordering::Relaxed);
        let frames = self.start_frame.load(Ordering::Relaxed) + self.played_to_native(total.saturating_sub(lead + tail));
        Some(frames * 1000 / self.device_rate as u64)
    }

    /// Liga esta faixa (a atual) à próxima para gapless com passagem do conversor.
    /// Se a decodificação desta já terminou, recusa na hora.
    pub fn set_successor(&self, handoff: Option<Arc<Handoff>>) {
        let mut s = self.successor.lock();
        if let Some(old) = s.handoff.take() {
            old.decline();
        }
        match handoff {
            Some(h) if s.decoding_done => h.decline(),
            h => s.handoff = h,
        }
    }

    /// Transfere o vínculo de sucessora para outra instância desta faixa (após seek).
    pub fn move_successor_to(&self, other: &DeckShared) {
        let h = self.successor.lock().handoff.take();
        other.set_successor(h);
    }

    pub fn set_error(&self, msg: String) {
        *self.error.lock() = Some(msg);
        self.failed.store(true, Ordering::Release);
        self.eof.store(true, Ordering::Release);
        self.ready.store(true, Ordering::Release);
    }
}

/// O que o mixer recebe: o lado consumidor do ring + estado.
pub struct DeckSource {
    pub shared: Arc<DeckShared>,
    pub ring: rtrb::Consumer<f32>,
    /// Ganho linear (ReplayGain já resolvido).
    pub gain: f32,
}

impl DeckSource {
    /// Frames que ainda faltam (estimativa até `eof`).
    pub fn remaining(&self) -> Option<u64> {
        let total = self.shared.total_frames.load(Ordering::Relaxed);
        if total == UNKNOWN {
            return None;
        }
        Some(total.saturating_sub(self.shared.consumed.load(Ordering::Relaxed)))
    }

    pub fn exhausted(&self) -> bool {
        self.shared.eof.load(Ordering::Acquire) && self.ring.slots() == 0
    }
}

impl Drop for DeckSource {
    fn drop(&mut self) {
        self.shared.cancel.store(true, Ordering::Relaxed);
    }
}

pub struct ProducerParams {
    pub device_rate: u32,
    /// Gapless: recebe o conversor da faixa anterior (se as taxas baterem).
    pub handoff_in: Option<Arc<Handoff>>,
    pub start_ms: u64,
    /// Duração em ms informada pelo servidor (usada se o arquivo não disser).
    pub duration_hint_ms: Option<u64>,
    pub ring_seconds: f32,
    /// Time-stretch do AutoMix (velocidade na sobreposição + rampa de volta).
    pub tempo: Option<TempoMap>,
}

/// Cria o deck e dispara a thread produtora. `open` roda dentro da thread
/// (pode bloquear na rede sem travar quem chamou).
pub fn spawn_deck<F>(token: u64, gain: f32, params: ProducerParams, open: F) -> DeckSource
where
    F: FnOnce(Arc<AtomicBool>) -> Result<Decoder> + Send + 'static,
{
    let tempo = params.tempo.filter(|t| !t.is_identity());
    let shared = DeckShared::with_tempo(token, params.device_rate, tempo);
    let capacity = (params.device_rate as f32 * params.ring_seconds) as usize * 2;
    let (producer, consumer) = rtrb::RingBuffer::<f32>::new(capacity.max(8192));
    let sh = shared.clone();
    let spawned = std::thread::Builder::new()
        .name(format!("deck-{token}"))
        .spawn(move || {
            // Pânico ao decodificar (arquivo estranho) vira erro do deck: o
            // player pula a música em vez de ficar mudo esperando o som.
            let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| produce(&sh, producer, params, open)))
                .unwrap_or_else(|_| Err(anyhow!("pânico ao decodificar")));
            if let Err(e) = r {
                if !sh.cancel.load(Ordering::Relaxed) {
                    log::warn!("deck {}: {e:#}", sh.token);
                    sh.set_error(format!("{e:#}"));
                }
            }
        });
    if let Err(e) = spawned {
        shared.set_error(format!("thread: {e}"));
    }
    DeckSource { shared, ring: consumer, gain }
}

fn produce<F>(sh: &DeckShared, mut ring: rtrb::Producer<f32>, p: ProducerParams, open: F) -> Result<()>
where
    F: FnOnce(Arc<AtomicBool>) -> Result<Decoder>,
{
    let mut dec = open(sh.cancel.clone())?;
    let src_rate = dec.sample_rate;
    let mut start_src_frame = 0u64;
    if p.start_ms > 0 {
        start_src_frame = dec.seek(p.start_ms)?;
    }
    // Gapless: avisa a anterior qual é a nossa taxa e espera o conversor dela.
    let inherited = match (&p.handoff_in, p.start_ms) {
        (Some(h), 0) => {
            h.publish_rate(src_rate);
            h.wait(&sh.cancel)
        }
        (Some(h), _) => {
            h.decline();
            None
        }
        _ => None,
    };
    let (mut rs, lead) = match inherited {
        Some(rs) => (rs, 0),
        None => {
            let rs = Resampler::new(src_rate, p.device_rate)?;
            let d = rs.delay() as u64;
            (rs, d)
        }
    };
    let ratio = rs.ratio();
    let delay = rs.delay() as u64;
    // Com time-stretch, o pré-eco do resampler é descartado aqui (a saída do
    // deck começa exatamente no ponto de entrada) e não há sobreposição gapless.
    let mut stretcher = sh.tempo.map(|m| TempoStretcher::new(m, p.device_rate, lead as usize));
    let lead = if stretcher.is_some() { 0 } else { lead };
    sh.lead_in.store(lead, Ordering::Relaxed);
    sh.tail.store(if stretcher.is_some() { 0 } else { delay }, Ordering::Relaxed);
    sh.start_frame
        .store((start_src_frame as f64 * ratio).round() as u64, Ordering::Relaxed);

    let total_src = dec.total_frames.or_else(|| {
        p.duration_hint_ms.map(|ms| ms * src_rate as u64 / 1000)
    });
    if let Some(n) = total_src {
        let remaining = n.saturating_sub(start_src_frame);
        let native = (remaining as f64 * ratio).round() as u64;
        let played = match &sh.tempo {
            Some(m) => m.output_at(native as f64).round() as u64,
            None => native + lead + delay,
        };
        sh.total_frames.store(played, Ordering::Relaxed);
    }

    let ready_after = (p.device_rate as u64) / 4; // 250 ms
    let mut decoded = Vec::with_capacity(8192);
    let mut stereo = Vec::with_capacity(8192);
    let mut out = Vec::with_capacity(16384);
    let mut resampled = Vec::with_capacity(16384);
    let mut produced: u64 = 0;

    loop {
        if sh.cancel.load(Ordering::Relaxed) {
            return Ok(());
        }
        out.clear();
        let eof = match dec.next_chunk(&mut decoded)? {
            Some(_) => {
                to_stereo(&decoded, dec.channels, &mut stereo);
                match stretcher.as_mut() {
                    Some(st) => {
                        resampled.clear();
                        rs.process(&stereo, &mut resampled)?;
                        st.push(&resampled, &mut out);
                    }
                    None => rs.process(&stereo, &mut out)?,
                }
                false
            }
            None => {
                // Fim do arquivo: passa o conversor pra próxima (se ela tiver a
                // mesma taxa) ou esvazia a cauda normalmente.
                let succ = {
                    let mut s = sh.successor.lock();
                    s.decoding_done = true;
                    s.handoff.take()
                };
                match succ {
                    Some(h) if h.next_rate() == Some(src_rate) => {
                        // Troca por um conversor "passa-direto" (barato) e entrega o real.
                        let passthrough = Resampler::new(src_rate, src_rate)?;
                        h.offer(std::mem::replace(&mut rs, passthrough));
                        sh.tail.store(0, Ordering::Relaxed);
                    }
                    other => {
                        if let Some(h) = other {
                            h.decline();
                        }
                        match stretcher.as_mut() {
                            Some(st) => {
                                resampled.clear();
                                rs.flush(&mut resampled)?;
                                st.push(&resampled, &mut out);
                                st.finish(&mut out);
                            }
                            None => rs.flush(&mut out)?,
                        }
                    }
                }
                true
            }
        };
        if !push_all(&mut ring, &out, sh) {
            return Ok(());
        }
        produced += (out.len() / 2) as u64;
        sh.produced.store(produced, Ordering::Relaxed);
        if eof {
            sh.total_frames.store(produced, Ordering::Relaxed);
            sh.eof.store(true, Ordering::Release);
            sh.ready.store(true, Ordering::Release);
            return Ok(());
        }
        if produced >= ready_after {
            sh.ready.store(true, Ordering::Release);
        }
    }
}

/// Time-stretch (Signalsmith Stretch) seguindo um [`TempoMap`]: velocidade
/// constante na sobreposição, rampa até 1.0 e depois 1.0 (continua passando
/// pelo stretch para não haver emenda). A saída começa exatamente no primeiro
/// frame de entrada: a latência de entrada é suprida com `seek` e a de saída
/// (pré-roll) é descartada.
pub struct TempoStretcher {
    st: signalsmith_stretch::Stretch,
    map: TempoMap,
    pending: Vec<f32>,
    skip_input: usize,
    started: bool,
    discard_out: usize,
    out_frames: u64,
    in_frames: f64,
    block: Vec<f32>,
}

const STRETCH_BLOCK: usize = 256;

impl TempoStretcher {
    pub fn new(map: TempoMap, rate: u32, skip_input: usize) -> Self {
        let st = signalsmith_stretch::Stretch::preset_default(2, rate);
        Self {
            st,
            map,
            pending: Vec::with_capacity(16384),
            skip_input,
            started: false,
            discard_out: 0,
            out_frames: 0,
            in_frames: 0.0,
            block: vec![0.0; STRETCH_BLOCK * 2],
        }
    }

    fn emit(&mut self, frames: usize, out: &mut Vec<f32>) {
        let mut data = &self.block[..frames * 2];
        if self.discard_out > 0 {
            let d = self.discard_out.min(frames);
            self.discard_out -= d;
            data = &data[d * 2..];
        }
        out.extend_from_slice(data);
    }

    /// Recebe estéreo intercalado (taxa do dispositivo) e anexa a saída esticada.
    pub fn push(&mut self, input: &[f32], out: &mut Vec<f32>) {
        let mut input = input;
        if self.skip_input > 0 {
            let n = (self.skip_input * 2).min(input.len());
            input = &input[n..];
            self.skip_input -= n / 2;
        }
        self.pending.extend_from_slice(input);
        if !self.started {
            let lat = self.st.input_latency();
            if self.pending.len() < lat * 2 {
                return;
            }
            let first: Vec<f32> = self.pending.drain(..lat * 2).collect();
            self.st.seek(&first, self.map.speed);
            self.discard_out = self.st.output_latency();
            self.started = true;
        }
        let mut consumed = 0usize;
        loop {
            let out_pos = self.out_frames as f64;
            let next_in = self.map.input_at(out_pos + STRETCH_BLOCK as f64);
            let need = (next_in - self.in_frames).round().max(0.0) as usize;
            if (self.pending.len() - consumed) / 2 < need {
                break;
            }
            let chunk = &self.pending[consumed..consumed + need * 2];
            self.st.process(chunk, &mut self.block[..]);
            consumed += need * 2;
            self.in_frames += need as f64;
            self.out_frames += STRETCH_BLOCK as u64;
            self.emit(STRETCH_BLOCK, out);
        }
        self.pending.drain(..consumed);
    }

    /// Fim da faixa: processa o resto + a latência de entrada em silêncio e esvazia.
    pub fn finish(&mut self, out: &mut Vec<f32>) {
        if !self.started {
            // Faixa curtíssima: sem stretch.
            out.extend_from_slice(&self.pending);
            self.pending.clear();
            return;
        }
        let lat = self.st.input_latency();
        let mut rest = std::mem::take(&mut self.pending);
        rest.resize(rest.len() + lat * 2, 0.0);
        let speed = self.map.speed_at(self.out_frames as f64).max(0.25);
        let out_len = ((rest.len() / 2) as f64 / speed).round() as usize;
        let mut buf = vec![0.0f32; out_len * 2];
        self.st.process(&rest, &mut buf);
        let mut data: &[f32] = &buf;
        if self.discard_out > 0 {
            let d = self.discard_out.min(out_len);
            self.discard_out -= d;
            data = &data[d * 2..];
        }
        out.extend_from_slice(data);
        let mut tail = vec![0.0f32; self.st.output_latency() * 2];
        self.st.flush(&mut tail);
        out.extend_from_slice(&tail);
    }
}

/// Empurra tudo no ring, esperando espaço. Retorna `false` se cancelado.
fn push_all(ring: &mut rtrb::Producer<f32>, mut data: &[f32], sh: &DeckShared) -> bool {
    while !data.is_empty() {
        if sh.cancel.load(Ordering::Relaxed) || ring.is_abandoned() {
            return false;
        }
        // Mantém a escrita alinhada em frames estéreo.
        let slots = ring.slots() & !1;
        if slots == 0 {
            std::thread::sleep(Duration::from_millis(5));
            continue;
        }
        let n = slots.min(data.len());
        let (pushed, _) = ring.push_partial_slice(&data[..n]);
        data = &data[pushed.len()..];
    }
    true
}

#[cfg(test)]
mod stretch_tests {
    use super::*;

    /// Cliques a cada 0,5 s: mede onde saem depois do stretch.
    fn click_offsets(speed: f64) -> Vec<f64> {
        let rate = 48000u32;
        let mut input = vec![0.0f32; rate as usize * 12 * 2];
        for k in 0..24 {
            let i = (k as f64 * 0.5 * rate as f64) as usize;
            for j in 0..48 {
                let v = (1.0 - j as f32 / 48.0) * 0.9;
                input[(i + j) * 2] = v;
                input[(i + j) * 2 + 1] = v;
            }
        }
        let map = TempoMap { speed, hold: rate as f64 * 20.0, ramp: 0.0 };
        let mut st = TempoStretcher::new(map, rate, 0);
        let mut out = Vec::new();
        for chunk in input.chunks(4096) {
            st.push(chunk, &mut out);
        }
        st.finish(&mut out);
        let mono: Vec<f32> = out.chunks(2).map(|f| f[0]).collect();
        // Primeiro ponto acima de 30% do pico perto de cada clique esperado.
        (2..20)
            .filter_map(|k| {
                let expected = k as f64 * 0.5 / speed;
                let a = ((expected - 0.05) * rate as f64) as usize;
                let b = ((expected + 0.05) * rate as f64) as usize;
                let seg = &mono[a..b.min(mono.len())];
                let peak = seg.iter().fold(0.0f32, |m, v| m.max(v.abs()));
                let i = seg.iter().position(|v| v.abs() >= 0.3 * peak)?;
                Some(((a + i) as f64 / rate as f64 - expected) * 1000.0)
            })
            .collect()
    }

    #[test]
    fn stretch_offset_by_speed() {
        for speed in [0.92, 0.95, 0.97, 1.0, 1.03, 1.05, 1.08] {
            let o = click_offsets(speed);
            let mean = o.iter().sum::<f64>() / o.len() as f64;
            let spread = o.iter().map(|x| (x - mean).abs()).fold(0.0, f64::max);
            eprintln!("velocidade {speed:.2}: desvio médio {mean:+.2} ms, variação {spread:.2} ms");
        }
    }
}
