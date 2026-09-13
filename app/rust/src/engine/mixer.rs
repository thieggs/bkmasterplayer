//! Mixer: roda dentro do callback de áudio (tempo real — sem alocação, sem trava).
//!
//! Mantém a faixa atual, a próxima (pré-carregada) e, durante uma transição, a
//! que está saindo. Transições:
//! - **Gapless:** sobrepõe a cauda do filtro de conversão da faixa que sai com o
//!   pré-eco da que entra, ambas em ganho 1 (overlap-add), de modo que a soma é
//!   o sinal contínuo original.
//! - **Crossfade:** curvas equal-power (cos/sen) pela duração pedida.
//! - **Corte:** troca seca quando a atual termina.

use std::f32::consts::FRAC_PI_2;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use super::deck::DeckSource;

const BLOCK: usize = 512;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Transition {
    Gapless,
    Crossfade { frames: u64 },
    Cut,
}

pub enum MixerCmd {
    /// Toca agora (troca rápida com fade curto). Descarta a próxima.
    Play(Box<DeckSource>),
    /// Mesma faixa em outra posição (seek). Mantém a próxima.
    ReplaceCurrent(Box<DeckSource>),
    SetNext(Option<Box<DeckSource>>, Transition),
    Pause,
    Resume,
    Stop,
    SetVolume(f32),
}

pub enum MixerEvent {
    Started(u64),
    Replaced(u64),
    Finished(u64),
    Stopped,
    Buffering(bool),
    Garbage(Box<DeckSource>),
}

#[derive(Default)]
pub struct MixerShared {
    pub current: AtomicU64,
    pub playing: AtomicBool,
    pub buffering: AtomicBool,
    pub transitioning: AtomicBool,
}

#[derive(Clone, Copy, Debug)]
struct Ramp {
    v: f32,
    target: f32,
    step: f32,
}

impl Ramp {
    fn new(v: f32) -> Self {
        Self { v, target: v, step: 0.0 }
    }

    fn set(&mut self, target: f32, frames: u32) {
        self.target = target;
        if frames == 0 || (target - self.v).abs() < f32::EPSILON {
            self.v = target;
            self.step = 0.0;
        } else {
            self.step = (target - self.v) / frames as f32;
        }
    }

    #[inline]
    fn tick(&mut self) -> f32 {
        if self.step != 0.0 {
            self.v += self.step;
            if (self.step > 0.0 && self.v >= self.target) || (self.step < 0.0 && self.v <= self.target) {
                self.v = self.target;
                self.step = 0.0;
            }
        }
        self.v
    }

    fn settled_at(&self, value: f32) -> bool {
        self.step == 0.0 && (self.v - value).abs() < f32::EPSILON
    }
}

struct Slot {
    src: Box<DeckSource>,
    skip_lead: bool,
    fade: Ramp,
}

impl Slot {
    fn new(src: Box<DeckSource>, skip_lead: bool, fade_in: u32) -> Self {
        let mut fade = Ramp::new(if fade_in > 0 { 0.0 } else { 1.0 });
        fade.set(1.0, fade_in);
        Self { src, skip_lead, fade }
    }

    fn token(&self) -> u64 {
        self.src.shared.token
    }

    /// Lê até `n` frames no `buf` (zera o que faltar). Retorna frames lidos.
    fn pull(&mut self, buf: &mut [f32], n: usize) -> usize {
        let sh = &self.src.shared;
        if self.skip_lead {
            let lead = sh.lead_in.load(Ordering::Relaxed);
            let mut consumed = sh.consumed.load(Ordering::Relaxed);
            while consumed < lead {
                let want = (((lead - consumed) as usize) * 2).min(buf.len());
                let (got, _) = self.src.ring.pop_partial_slice(&mut buf[..want]);
                let frames = got.len() / 2;
                if frames == 0 {
                    break;
                }
                consumed += frames as u64;
            }
            sh.consumed.store(consumed, Ordering::Relaxed);
            if consumed >= lead {
                self.skip_lead = false;
            }
        }
        let want = n * 2;
        let (got, _) = self.src.ring.pop_partial_slice(&mut buf[..want]);
        let got = got.len();
        buf[got..want].fill(0.0);
        let frames = got / 2;
        sh.consumed.fetch_add(frames as u64, Ordering::Relaxed);
        frames
    }
}

struct ActiveTransition {
    from: Slot,
    kind: Transition,
    pos: u64,
    len: u64,
}

pub struct Mixer {
    cmd_rx: rtrb::Consumer<MixerCmd>,
    ev_tx: rtrb::Producer<MixerEvent>,
    pub shared: Arc<MixerShared>,
    rate: u32,
    current: Option<Slot>,
    next: Option<(Slot, Transition)>,
    transition: Option<ActiveTransition>,
    fading: [Option<Slot>; 4],
    paused: bool,
    run_gain: Ramp,
    volume: Ramp,
    buffering: bool,
    scratch: Vec<f32>,
}

impl Mixer {
    pub fn new(rate: u32, cmd_rx: rtrb::Consumer<MixerCmd>, ev_tx: rtrb::Producer<MixerEvent>) -> Self {
        Self {
            cmd_rx,
            ev_tx,
            shared: Arc::new(MixerShared::default()),
            rate,
            current: None,
            next: None,
            transition: None,
            fading: [None, None, None, None],
            paused: false,
            run_gain: Ramp::new(1.0),
            volume: Ramp::new(1.0),
            buffering: false,
            scratch: vec![0.0; BLOCK * 2],
        }
    }

    pub fn rate(&self) -> u32 {
        self.rate
    }

    pub fn set_rate(&mut self, rate: u32) {
        self.rate = rate;
    }

    fn ms(&self, ms: u32) -> u32 {
        self.rate * ms / 1000
    }

    fn emit(&mut self, ev: MixerEvent) {
        // Se a fila encher, o evento se perde (e um Garbage é destruído aqui mesmo).
        let _ = self.ev_tx.push(ev);
    }

    fn trash(&mut self, slot: Slot) {
        self.emit(MixerEvent::Garbage(slot.src));
    }

    fn fade_out(&mut self, mut slot: Slot) {
        slot.fade.set(0.0, self.ms(25));
        if let Some(free) = self.fading.iter_mut().find(|f| f.is_none()) {
            *free = Some(slot);
        } else {
            self.trash(slot);
        }
    }

    fn drain_commands(&mut self) {
        while let Ok(cmd) = self.cmd_rx.pop() {
            match cmd {
                MixerCmd::Play(src) => {
                    let token = src.shared.token;
                    if let Some(tr) = self.transition.take() {
                        self.fade_out(tr.from);
                    }
                    if let Some(cur) = self.current.take() {
                        self.fade_out(cur);
                    }
                    if let Some((n, _)) = self.next.take() {
                        self.trash(n);
                    }
                    self.current = Some(Slot::new(src, true, self.ms(5)));
                    self.paused = false;
                    self.run_gain.set(1.0, self.ms(5));
                    self.shared.current.store(token, Ordering::Relaxed);
                    self.shared.playing.store(true, Ordering::Relaxed);
                    self.emit(MixerEvent::Started(token));
                }
                MixerCmd::ReplaceCurrent(src) => {
                    let token = src.shared.token;
                    if let Some(tr) = self.transition.take() {
                        self.fade_out(tr.from);
                    }
                    if let Some(cur) = self.current.take() {
                        self.fade_out(cur);
                    }
                    self.current = Some(Slot::new(src, true, self.ms(10)));
                    self.shared.current.store(token, Ordering::Relaxed);
                    self.emit(MixerEvent::Replaced(token));
                }
                MixerCmd::SetNext(src, kind) => {
                    if let Some((n, _)) = self.next.take() {
                        self.trash(n);
                    }
                    self.next = src.map(|s| (Slot::new(s, false, 0), kind));
                }
                MixerCmd::Pause => {
                    self.paused = true;
                    self.run_gain.set(0.0, self.ms(12));
                    self.shared.playing.store(false, Ordering::Relaxed);
                }
                MixerCmd::Resume => {
                    if self.current.is_some() {
                        self.paused = false;
                        self.run_gain.set(1.0, self.ms(12));
                        self.shared.playing.store(true, Ordering::Relaxed);
                    }
                }
                MixerCmd::Stop => {
                    if let Some(tr) = self.transition.take() {
                        self.fade_out(tr.from);
                    }
                    if let Some(cur) = self.current.take() {
                        self.fade_out(cur);
                    }
                    if let Some((n, _)) = self.next.take() {
                        self.trash(n);
                    }
                    self.paused = false;
                    self.run_gain.set(1.0, 0);
                    self.shared.current.store(0, Ordering::Relaxed);
                    self.shared.playing.store(false, Ordering::Relaxed);
                    self.emit(MixerEvent::Stopped);
                }
                MixerCmd::SetVolume(v) => {
                    let frames = self.ms(30);
                    self.volume.set(v.clamp(0.0, 2.0), frames);
                }
            }
        }
    }

    /// Duração da sobreposição para a transição pendente, se já dá pra decidir.
    fn pending_overlap(&self) -> Option<u64> {
        let cur = self.current.as_ref()?;
        let (next, kind) = self.next.as_ref()?;
        if !next.src.shared.ready.load(Ordering::Acquire) || next.src.shared.failed.load(Ordering::Acquire) {
            return None;
        }
        match *kind {
            Transition::Cut => None,
            Transition::Gapless => {
                // Só com o total exato (produtora terminou).
                if !cur.src.shared.eof.load(Ordering::Acquire) {
                    return None;
                }
                let tail = cur.src.shared.tail.load(Ordering::Relaxed);
                let lead = next.src.shared.lead_in.load(Ordering::Relaxed);
                Some(tail + lead).filter(|l| *l > 0)
            }
            Transition::Crossfade { frames } => {
                let mut len = frames;
                let next_total = next.src.shared.total_frames.load(Ordering::Relaxed);
                if next_total != super::deck::UNKNOWN {
                    len = len.min(next_total / 2);
                }
                Some(len).filter(|l| *l > 0)
            }
        }
    }

    fn frames_until_transition(&self) -> Option<(u64, u64)> {
        if self.transition.is_some() {
            return None;
        }
        let len = self.pending_overlap()?;
        let remaining = self.current.as_ref()?.src.remaining()?;
        let len = len.min(remaining);
        Some((remaining.saturating_sub(len), len))
    }

    fn start_transition(&mut self, len: u64) {
        let Some((mut next, kind)) = self.next.take() else { return };
        let Some(from) = self.current.take() else {
            self.next = Some((next, kind));
            return;
        };
        // No gapless o pré-eco da próxima é parte da soma; no crossfade entra já no início nominal.
        next.skip_lead = !matches!(kind, Transition::Gapless);
        let token = next.token();
        self.current = Some(next);
        self.transition = Some(ActiveTransition { from, kind, pos: 0, len });
        self.shared.current.store(token, Ordering::Relaxed);
        self.shared.transitioning.store(true, Ordering::Relaxed);
        self.emit(MixerEvent::Started(token));
    }

    /// Renderiza `out` (estéreo intercalado).
    pub fn render(&mut self, out: &mut [f32]) {
        self.drain_commands();
        out.fill(0.0);
        let frames = out.len() / 2;
        let mut done = 0;
        while done < frames {
            let mut n = (frames - done).min(BLOCK);
            if self.paused && self.run_gain.settled_at(0.0) {
                break;
            }
            if let Some((until, len)) = self.frames_until_transition() {
                if until == 0 {
                    self.start_transition(len);
                } else if (until as usize) < n {
                    n = until as usize;
                }
            }
            // Troca sem sobreposição: o bloco termina exatamente no fim da faixa,
            // pra próxima começar no frame seguinte (sem zeros no meio).
            if self.transition.is_none() {
                if let Some(cur) = self.current.as_ref() {
                    if cur.src.shared.eof.load(Ordering::Acquire) && !cur.skip_lead {
                        let left = cur.src.ring.slots() / 2;
                        if left > 0 && left < n {
                            n = left;
                        }
                    }
                }
            }
            self.render_block(&mut out[done * 2..(done + n) * 2], n);
            self.after_block();
            done += n;
        }
    }

    fn render_block(&mut self, block: &mut [f32], n: usize) {
        let mut underrun = false;
        let scratch = &mut self.scratch;

        if let Some(cur) = self.current.as_mut() {
            let got = cur.pull(scratch, n);
            if got < n && !cur.src.shared.eof.load(Ordering::Acquire) {
                underrun = true;
            }
            let gain = cur.src.gain;
            match &self.transition {
                Some(tr) if matches!(tr.kind, Transition::Crossfade { .. }) => {
                    for i in 0..n {
                        let t = ((tr.pos + i as u64) as f32 / tr.len as f32).min(1.0);
                        let g = gain * cur.fade.tick() * (t * FRAC_PI_2).sin();
                        block[i * 2] += scratch[i * 2] * g;
                        block[i * 2 + 1] += scratch[i * 2 + 1] * g;
                    }
                }
                _ => {
                    for i in 0..n {
                        let g = gain * cur.fade.tick();
                        block[i * 2] += scratch[i * 2] * g;
                        block[i * 2 + 1] += scratch[i * 2 + 1] * g;
                    }
                }
            }
        }

        if let Some(tr) = self.transition.as_mut() {
            tr.from.pull(scratch, n);
            let gain = tr.from.src.gain;
            let crossfade = matches!(tr.kind, Transition::Crossfade { .. });
            for i in 0..n {
                let curve = if crossfade {
                    let t = ((tr.pos + i as u64) as f32 / tr.len as f32).min(1.0);
                    (t * FRAC_PI_2).cos()
                } else {
                    1.0
                };
                let g = gain * tr.from.fade.tick() * curve;
                block[i * 2] += scratch[i * 2] * g;
                block[i * 2 + 1] += scratch[i * 2 + 1] * g;
            }
            tr.pos += n as u64;
        }

        for slot in self.fading.iter_mut().flatten() {
            slot.pull(scratch, n);
            let gain = slot.src.gain;
            for i in 0..n {
                let g = gain * slot.fade.tick();
                block[i * 2] += scratch[i * 2] * g;
                block[i * 2 + 1] += scratch[i * 2 + 1] * g;
            }
        }

        for i in 0..n {
            let g = self.volume.tick() * self.run_gain.tick();
            block[i * 2] = soft_clip(block[i * 2] * g);
            block[i * 2 + 1] = soft_clip(block[i * 2 + 1] * g);
        }

        if underrun != self.buffering {
            self.buffering = underrun;
            self.shared.buffering.store(underrun, Ordering::Relaxed);
            self.emit(MixerEvent::Buffering(underrun));
        }
    }

    fn after_block(&mut self) {
        let transition_done = self
            .transition
            .as_ref()
            .is_some_and(|tr| tr.pos >= tr.len || tr.from.src.exhausted());
        if transition_done {
            if let Some(tr) = self.transition.take() {
                // Terminou antes da hora (faixa mais curta que o estimado): evita salto de volume.
                if let (Transition::Crossfade { .. }, Some(cur)) = (tr.kind, self.current.as_mut()) {
                    if tr.pos < tr.len {
                        let v = (tr.pos as f32 / tr.len as f32 * FRAC_PI_2).sin();
                        cur.fade = Ramp::new(v * cur.fade.v);
                        let frames = self.rate / 20;
                        cur.fade.set(1.0, frames);
                    }
                }
                let token = tr.from.token();
                self.emit(MixerEvent::Finished(token));
                self.trash(tr.from);
                self.shared.transitioning.store(false, Ordering::Relaxed);
            }
        }

        let exhausted = self.transition.is_none() && self.current.as_ref().is_some_and(|c| c.src.exhausted());
        if exhausted {
            if let Some(old) = self.current.take() {
                let token = old.token();
                self.emit(MixerEvent::Finished(token));
                self.trash(old);
            }
            if let Some((mut next, kind)) = self.next.take() {
                next.skip_lead = !matches!(kind, Transition::Gapless);
                let token = next.token();
                self.shared.current.store(token, Ordering::Relaxed);
                self.current = Some(next);
                self.emit(MixerEvent::Started(token));
            } else {
                self.shared.current.store(0, Ordering::Relaxed);
                self.shared.playing.store(false, Ordering::Relaxed);
                self.emit(MixerEvent::Stopped);
            }
        }

        for i in 0..self.fading.len() {
            let done = self.fading[i]
                .as_ref()
                .is_some_and(|s| s.fade.settled_at(0.0) || s.src.exhausted());
            if done {
                if let Some(s) = self.fading[i].take() {
                    self.trash(s);
                }
            }
        }
    }
}

#[inline]
fn soft_clip(x: f32) -> f32 {
    let a = x.abs();
    if a <= 0.9 {
        x
    } else {
        (0.9 + 0.1 * ((a - 0.9) / 0.1).tanh()).copysign(x)
    }
}
