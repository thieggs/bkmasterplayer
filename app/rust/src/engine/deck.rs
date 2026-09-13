//! Deck: uma faixa carregada. Uma thread "produtora" decodifica e converte a
//! taxa, e enche um ring buffer sem trava. O mixer (thread de áudio) consome.

use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use parking_lot::{Condvar, Mutex};

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
    Offered(Resampler),
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
        *self.state.lock() = HandoffState::Offered(rs);
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
                HandoffState::Offered(rs) => return Some(rs),
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
}

impl DeckShared {
    pub fn new(token: u64, device_rate: u32) -> Arc<Self> {
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
        })
    }

    /// Posição de reprodução em ms (linha do tempo original da faixa).
    pub fn position_ms(&self) -> u64 {
        let consumed = self.consumed.load(Ordering::Relaxed);
        let lead = self.lead_in.load(Ordering::Relaxed);
        let frames = self.start_frame.load(Ordering::Relaxed) + consumed.saturating_sub(lead);
        frames * 1000 / self.device_rate as u64
    }

    /// Duração nominal em ms (sem pré-eco/cauda), se conhecida.
    pub fn duration_ms(&self) -> Option<u64> {
        let total = self.total_frames.load(Ordering::Relaxed);
        if total == UNKNOWN {
            return None;
        }
        let lead = self.lead_in.load(Ordering::Relaxed);
        let tail = self.tail.load(Ordering::Relaxed);
        let frames = self.start_frame.load(Ordering::Relaxed) + total.saturating_sub(lead + tail);
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
}

/// Cria o deck e dispara a thread produtora. `open` roda dentro da thread
/// (pode bloquear na rede sem travar quem chamou).
pub fn spawn_deck<F>(token: u64, gain: f32, params: ProducerParams, open: F) -> DeckSource
where
    F: FnOnce(Arc<AtomicBool>) -> Result<Decoder> + Send + 'static,
{
    let shared = DeckShared::new(token, params.device_rate);
    let capacity = (params.device_rate as f32 * params.ring_seconds) as usize * 2;
    let (producer, consumer) = rtrb::RingBuffer::<f32>::new(capacity.max(8192));
    let sh = shared.clone();
    let spawned = std::thread::Builder::new()
        .name(format!("deck-{token}"))
        .spawn(move || {
            if let Err(e) = produce(&sh, producer, params, open) {
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
    sh.lead_in.store(lead, Ordering::Relaxed);
    sh.tail.store(delay, Ordering::Relaxed);
    sh.start_frame
        .store((start_src_frame as f64 * ratio).round() as u64, Ordering::Relaxed);

    let total_src = dec.total_frames.or_else(|| {
        p.duration_hint_ms.map(|ms| ms * src_rate as u64 / 1000)
    });
    if let Some(n) = total_src {
        let remaining = n.saturating_sub(start_src_frame);
        sh.total_frames
            .store((remaining as f64 * ratio).round() as u64 + lead + delay, Ordering::Relaxed);
    }

    let ready_after = (p.device_rate as u64) / 4; // 250 ms
    let mut decoded = Vec::with_capacity(8192);
    let mut stereo = Vec::with_capacity(8192);
    let mut out = Vec::with_capacity(16384);
    let mut produced: u64 = 0;

    loop {
        if sh.cancel.load(Ordering::Relaxed) {
            return Ok(());
        }
        out.clear();
        let eof = match dec.next_chunk(&mut decoded)? {
            Some(_) => {
                to_stereo(&decoded, dec.channels, &mut stereo);
                rs.process(&stereo, &mut out)?;
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
                        rs.flush(&mut out)?;
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
