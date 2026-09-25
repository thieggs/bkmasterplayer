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

use super::automix::MixStyle;
use super::deck::DeckSource;

const BLOCK: usize = 512;

#[derive(Debug)]
pub enum Transition {
    Gapless,
    Crossfade { frames: u64 },
    Cut,
    /// Transição DJ planejada (AutoMix): começa num frame exato de A.
    Automix(Box<AutomixExec>),
}

impl Transition {
    fn is_gapless(&self) -> bool {
        matches!(self, Transition::Gapless)
    }
}

/// Parâmetros de execução de uma transição AutoMix (em frames do dispositivo).
#[derive(Debug)]
pub struct AutomixExec {
    pub style: MixStyle,
    /// Frame da linha do tempo ORIGINAL de A em que a transição começa.
    pub start_native: u64,
    pub len: u64,
    /// Deslocamento (frames) da troca de grave / corte do eco.
    pub swap_at: u64,
    /// Duração de uma batida (frames): rampa da troca de grave e tempo do eco.
    pub beat: u64,
    /// Linha de atraso pré-alocada para o eco (estéreo intercalado). O mixer
    /// já vai gravando a faixa atual nela antes da transição começar, para a
    /// primeira repetição sair no lugar da música, sem buraco.
    pub echo_buf: Vec<f32>,
    /// Posição de escrita na linha de atraso.
    #[doc(hidden)]
    pub echo_pos: usize,
    /// Só para testes: silencia A para medir o alinhamento de B.
    pub mute_from: bool,
}

/// Equalizador gráfico de 10 bandas (oitavas de 31 Hz a 16 kHz).
#[derive(Debug, Clone, Copy)]
pub struct EqSettings {
    pub enabled: bool,
    pub preamp_db: f32,
    pub gains_db: [f32; 10],
}

pub const EQ_FREQS: [f32; 10] = [31.25, 62.5, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0];

/// Biquad peaking (RBJ), forma direta II transposta, estéreo.
#[derive(Clone, Copy, Default)]
struct PeakBand {
    b0: f32,
    b1: f32,
    b2: f32,
    a1: f32,
    a2: f32,
    z1: [f32; 2],
    z2: [f32; 2],
    active: bool,
}

impl PeakBand {
    fn set(&mut self, freq: f32, gain_db: f32, rate: u32) {
        self.active = gain_db.abs() > 0.05 && freq < rate as f32 * 0.45;
        if !self.active {
            return;
        }
        let a = 10f32.powf(gain_db / 40.0);
        let w0 = 2.0 * std::f32::consts::PI * freq / rate as f32;
        let (sn, cs) = w0.sin_cos();
        let alpha = sn / (2.0 * 1.41);
        let a0 = 1.0 + alpha / a;
        self.b0 = (1.0 + alpha * a) / a0;
        self.b1 = -2.0 * cs / a0;
        self.b2 = (1.0 - alpha * a) / a0;
        self.a1 = -2.0 * cs / a0;
        self.a2 = (1.0 - alpha / a) / a0;
    }

    #[inline]
    fn run(&mut self, x: f32, ch: usize) -> f32 {
        let y = self.b0 * x + self.z1[ch];
        self.z1[ch] = self.b1 * x - self.a1 * y + self.z2[ch];
        self.z2[ch] = self.b2 * x - self.a2 * y;
        y
    }
}

struct Equalizer {
    settings: EqSettings,
    bands: [PeakBand; 10],
    preamp: f32,
}

impl Equalizer {
    fn new() -> Self {
        Self {
            settings: EqSettings { enabled: false, preamp_db: 0.0, gains_db: [0.0; 10] },
            bands: [PeakBand::default(); 10],
            preamp: 1.0,
        }
    }

    fn configure(&mut self, s: EqSettings, rate: u32) {
        self.settings = s;
        self.preamp = 10f32.powf(s.preamp_db / 20.0);
        for (i, b) in self.bands.iter_mut().enumerate() {
            b.set(EQ_FREQS[i], s.gains_db[i], rate);
        }
    }

    #[inline]
    fn process(&mut self, block: &mut [f32]) {
        if !self.settings.enabled {
            return;
        }
        for f in block.chunks_exact_mut(2) {
            let (mut l, mut r) = (f[0] * self.preamp, f[1] * self.preamp);
            for b in self.bands.iter_mut().filter(|b| b.active) {
                l = b.run(l, 0);
                r = b.run(r, 1);
            }
            f[0] = l;
            f[1] = r;
        }
    }
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
    SetEq(EqSettings),
    /// Girar o disco de vinil: velocidade da agulha (`None` = soltou o disco).
    Vinyl(Option<f32>),
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

/// Filtro de estado variável (TPT, Andrew Simper): passa-baixas/altas estáveis
/// mesmo com a frequência de corte variando.
#[derive(Clone, Copy, Default)]
struct Svf {
    a1: f32,
    a2: f32,
    a3: f32,
    k: f32,
    ic1: [f32; 2],
    ic2: [f32; 2],
}

impl Svf {
    fn set(&mut self, cutoff: f32, rate: u32) {
        let fc = cutoff.clamp(10.0, rate as f32 * 0.45);
        let g = (std::f32::consts::PI * fc / rate as f32).tan();
        self.k = std::f32::consts::SQRT_2;
        self.a1 = 1.0 / (1.0 + g * (g + self.k));
        self.a2 = g * self.a1;
        self.a3 = g * self.a2;
    }

    /// Retorna (passa-baixas, passa-altas) para o canal `ch`.
    #[inline]
    fn run(&mut self, x: f32, ch: usize) -> (f32, f32) {
        let v3 = x - self.ic2[ch];
        let v1 = self.a1 * self.ic1[ch] + self.a2 * v3;
        let v2 = self.ic2[ch] + self.a2 * self.ic1[ch] + self.a3 * v3;
        self.ic1[ch] = 2.0 * v1 - self.ic1[ch];
        self.ic2[ch] = 2.0 * v2 - self.ic2[ch];
        (v2, x - self.k * v1 - v2)
    }
}

/// Efeitos de DJ de um deck durante a transição.
#[derive(Clone, Copy, Default)]
struct SlotFx {
    bass: Svf,
    bass_ready: bool,
    sweep: Svf,
}

struct Slot {
    src: Box<DeckSource>,
    skip_lead: bool,
    fade: Ramp,
    fx: SlotFx,
}

impl Slot {
    fn new(src: Box<DeckSource>, skip_lead: bool, fade_in: u32) -> Self {
        let mut fade = Ramp::new(if fade_in > 0 { 0.0 } else { 1.0 });
        fade.set(1.0, fade_in);
        Self { src, skip_lead, fade, fx: SlotFx::default() }
    }

    fn token(&self) -> u64 {
        self.src.shared.token
    }

    /// Lê até `n` frames no `buf` (zera o que faltar). Retorna frames lidos.
    fn pull(&mut self, buf: &mut [f32], n: usize) -> usize {
        let frames = self.pull_raw(buf, n);
        self.src.shared.consumed.fetch_add(frames as u64, Ordering::Relaxed);
        frames
    }

    /// Igual, sem mexer na posição tocada: com o disco na mão quem manda na
    /// posição é a agulha do [`Vinyl`], não o que saiu do anel.
    fn pull_raw(&mut self, buf: &mut [f32], n: usize) -> usize {
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
        got / 2
    }
}

/// Quanto do que já tocou fica guardado, para dar para voltar girando o disco.
const VINYL_MEMORY_SECS: usize = 4;

/// Acima desta velocidade não é mais som de disco, é chiado: a agulha levanta.
const VINYL_MAX_SPEED: f32 = 4.0;
const VINYL_FADE_FROM: f32 = 3.0;

/// Abaixo disto o disco está parado na mão, e disco parado não faz som (a
/// interpolação seguraria uma amostra só, o que vira um estalo contínuo).
const VINYL_MIN_SPEED: f32 = 0.05;

/// A velocidade leva este tempo para chegar onde o dedo pediu (degrau estala).
const VINYL_RAMP_SECS: f32 = 0.015;

/// Leitura do deck com velocidade variável, para girar a capa como um vinil.
///
/// A agulha anda num índice **fracionário** e o áudio sai por interpolação
/// entre dois frames: acelerar sobe o tom, desacelerar desce, e velocidade
/// negativa toca de trás para frente — o som de um disco de verdade. É por isso
/// que o time-stretch do AutoMix não serve aqui: ele **segura** o tom, que é
/// justamente o que tem que se mexer.
///
/// O que já saiu do anel do deck fica guardado num anel próprio
/// ([`VINYL_MEMORY_SECS`]); sem essa memória não haveria como voltar.
struct Vinyl {
    /// O que já foi lido do deck (estéreo intercalado), em anel.
    memory: Vec<f32>,
    /// Frames válidos na memória.
    filled: usize,
    /// Primeiro frame ainda não lido do deck (na contagem do deck).
    head: u64,
    /// A agulha, fracionária: é dela que sai o tom.
    pos: f64,
    /// Velocidade que o dedo pediu e a que está valendo.
    target: f32,
    speed: f32,
    /// Passo da rampa de velocidade, por frame.
    step: f32,
    /// Passagem do anel do deck para a memória.
    tmp: Vec<f32>,
    active: bool,
}

impl Vinyl {
    fn new(rate: u32) -> Self {
        Self {
            memory: vec![0.0; rate as usize * VINYL_MEMORY_SECS * 2],
            filled: 0,
            head: 0,
            pos: 0.0,
            target: 1.0,
            speed: 1.0,
            step: 1.0 / (rate as f32 * VINYL_RAMP_SECS),
            tmp: vec![0.0; BLOCK * 2],
            active: false,
        }
    }

    fn frames(&self) -> usize {
        self.memory.len() / 2
    }

    /// Pega o disco no ponto em que a faixa está agora.
    fn grab(&mut self, at: u64) {
        self.active = true;
        self.head = at;
        self.pos = at as f64;
        self.filled = 0;
        self.speed = 1.0;
        self.target = 1.0;
    }

    /// O mais antigo que a memória ainda guarda.
    fn oldest(&self) -> f64 {
        self.head.saturating_sub(self.filled as u64) as f64
    }

    /// Ganho da agulha: some quando o disco está parado na mão ou girando
    /// rápido demais para o som querer dizer alguma coisa.
    fn needle(&self) -> f32 {
        let s = self.speed.abs();
        let slow = (s / VINYL_MIN_SPEED).clamp(0.0, 1.0);
        let fast = ((VINYL_MAX_SPEED - s) / (VINYL_MAX_SPEED - VINYL_FADE_FROM)).clamp(0.0, 1.0);
        slow * fast
    }

    /// Puxa do deck até ter o frame `upto` na memória. `false` = o deck secou
    /// (rede atrasada ou fim da faixa).
    fn fill_to(&mut self, slot: &mut Slot, upto: u64) -> bool {
        let cap = self.frames();
        while self.head <= upto {
            // Em pedaços, não frame a frame: isto roda dentro do callback de
            // áudio, e o que sobra vai para a memória de qualquer jeito.
            let want = ((upto + 1 - self.head) as usize).clamp(BLOCK / 4, BLOCK);
            let got = slot.pull_raw(&mut self.tmp, want);
            if got == 0 {
                return false;
            }
            for i in 0..got {
                let w = ((self.head as usize + i) % cap) * 2;
                self.memory[w] = self.tmp[i * 2];
                self.memory[w + 1] = self.tmp[i * 2 + 1];
            }
            self.head += got as u64;
            self.filled = (self.filled + got).min(cap);
        }
        true
    }

    /// Escreve `n` frames girados em `out`.
    fn render(&mut self, slot: &mut Slot, out: &mut [f32], n: usize) {
        let cap = self.frames() as u64;
        for i in 0..n {
            self.speed += (self.target - self.speed).clamp(-self.step, self.step);
            let need = self.pos as u64 + 1;
            if self.head <= need && !self.fill_to(slot, need) {
                out[i * 2] = 0.0;
                out[i * 2 + 1] = 0.0;
                continue;
            }
            // Puxar do deck joga o mais antigo fora: a agulha não passa disso.
            self.pos = self.pos.max(self.oldest());
            let whole = self.pos as u64;
            let frac = (self.pos - whole as f64) as f32;
            let a = (whole % cap) as usize * 2;
            let b = ((whole + 1) % cap) as usize * 2;
            let g = self.needle();
            out[i * 2] = (self.memory[a] + (self.memory[b] - self.memory[a]) * frac) * g;
            out[i * 2 + 1] = (self.memory[a + 1] + (self.memory[b + 1] - self.memory[a + 1]) * frac) * g;
            self.pos = (self.pos + self.speed as f64).max(self.oldest());
        }
        // Com o disco na mão, a posição tocada é onde a agulha está.
        slot.src.shared.consumed.store(self.pos as u64, Ordering::Relaxed);
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
    vinyl: Vinyl,
    eq: Equalizer,
}

/// Áudio já decodificado que a próxima precisa ter para a transição começar
/// sem engasgo (a rede pode oscilar no meio da mixagem).
const CUSHION_SECS: f32 = 0.5;

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
            vinyl: Vinyl::new(rate),
            eq: Equalizer::new(),
        }
    }

    pub fn rate(&self) -> u32 {
        self.rate
    }

    pub fn set_rate(&mut self, rate: u32) {
        self.rate = rate;
        let s = self.eq.settings;
        self.eq.configure(s, rate);
        self.vinyl = Vinyl::new(rate);
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
                    self.vinyl.active = false;
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
                    self.vinyl.active = false;
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
                    self.vinyl.active = false;
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
                MixerCmd::SetEq(s) => {
                    let rate = self.rate;
                    self.eq.configure(s, rate);
                }
                MixerCmd::Vinyl(speed) => match speed {
                    Some(v) => {
                        if !self.vinyl.active {
                            // Pega o disco onde a faixa está (só depois do
                            // pré-eco: antes dele a posição ainda não vale).
                            match self.current.as_ref() {
                                Some(cur) if !cur.skip_lead => {
                                    let at = cur.src.shared.consumed.load(Ordering::Relaxed);
                                    self.vinyl.grab(at);
                                }
                                _ => {}
                            }
                        }
                        self.vinyl.target = v.clamp(-VINYL_MAX_SPEED, VINYL_MAX_SPEED);
                    }
                    None => self.vinyl.active = false,
                },
            }
        }
    }

    /// A próxima já tem áudio decodificado para aguentar o começo da
    /// transição? (ou terminou de decodificar: faixa curta)
    fn next_has_cushion(&self) -> bool {
        let Some((next, _)) = self.next.as_ref() else { return false };
        next.src.shared.eof.load(Ordering::Acquire) || next.src.ring.slots() >= (self.rate as f32 * CUSHION_SECS) as usize * 2
    }

    /// Duração da sobreposição para a transição pendente, se já dá pra decidir.
    fn pending_overlap(&self) -> Option<u64> {
        let cur = self.current.as_ref()?;
        let (next, kind) = self.next.as_ref()?;
        if !next.src.shared.ready.load(Ordering::Acquire) || next.src.shared.failed.load(Ordering::Acquire) {
            return None;
        }
        // Mixar com a próxima quase vazia engasga no meio: espera o fôlego.
        if matches!(kind, Transition::Automix(_) | Transition::Crossfade { .. }) && !self.next_has_cushion() {
            return None;
        }
        match kind {
            Transition::Cut => None,
            Transition::Automix(exec) => Some(exec.len.max(1)),
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
                let mut len = *frames;
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
        let cur = self.current.as_ref()?;
        if let Some((_, Transition::Automix(exec))) = self.next.as_ref() {
            // Começa quando A chega no frame planejado (na linha do tempo original).
            let sh = &cur.src.shared;
            let start_frame = sh.start_frame.load(Ordering::Relaxed);
            let lead = sh.lead_in.load(Ordering::Relaxed);
            let target = lead + sh.native_to_played(exec.start_native.saturating_sub(start_frame));
            let consumed = sh.consumed.load(Ordering::Relaxed);
            return Some((target.saturating_sub(consumed), len));
        }
        let remaining = cur.src.remaining()?;
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
        next.skip_lead = !kind.is_gapless();
        next.fx = SlotFx::default();
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
            // Com o disco na mão a faixa não troca nem acaba: a agulha está
            // onde o dedo deixou, e o anel do deck pode estar seco sem a
            // música ter terminado.
            if !self.vinyl.active {
                if let Some((until, len)) = self.frames_until_transition() {
                    if until == 0 {
                        self.start_transition(len);
                    } else if (until as usize) < n {
                        n = until as usize;
                    }
                }
                // Troca sem sobreposição: o bloco termina exatamente no fim da
                // faixa, pra próxima começar no frame seguinte (sem zeros no meio).
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
            }
            self.render_block(&mut out[done * 2..(done + n) * 2], n);
            self.after_block();
            done += n;
        }
    }

    fn render_block(&mut self, block: &mut [f32], n: usize) {
        let mut underrun = false;
        let rate = self.rate;
        let scratch = &mut self.scratch;

        if let Some(cur) = self.current.as_mut() {
            if self.vinyl.active {
                self.vinyl.render(cur, scratch, n);
            } else {
                let got = cur.pull(scratch, n);
                if got < n && !cur.src.shared.eof.load(Ordering::Acquire) {
                    underrun = true;
                }
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
                Some(tr) if matches!(tr.kind, Transition::Automix(_)) => {
                    let Transition::Automix(exec) = &tr.kind else { unreachable!() };
                    automix_incoming(cur, exec, tr.pos, tr.len, &mut scratch[..n * 2], rate);
                    for i in 0..n {
                        let g = gain * cur.fade.tick();
                        block[i * 2] += scratch[i * 2] * g;
                        block[i * 2 + 1] += scratch[i * 2 + 1] * g;
                    }
                }
                _ => {
                    // Transição de eco esperando: a linha de atraso já vai
                    // guardando a música, para a primeira repetição sair no
                    // lugar dela quando a troca chegar (senão fica um buraco).
                    if let Some((_, Transition::Automix(exec))) = self.next.as_mut() {
                        prime_echo(exec, &scratch[..n * 2]);
                    }
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
            match &mut tr.kind {
                Transition::Automix(exec) => {
                    let (pos, len) = (tr.pos, tr.len);
                    automix_outgoing(&mut tr.from, exec, pos, len, &mut scratch[..n * 2], rate);
                    for i in 0..n {
                        let g = gain * tr.from.fade.tick();
                        block[i * 2] += scratch[i * 2] * g;
                        block[i * 2 + 1] += scratch[i * 2 + 1] * g;
                    }
                }
                kind => {
                    let crossfade = matches!(kind, Transition::Crossfade { .. });
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
                }
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

        self.eq.process(block);
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
        if !self.vinyl.active {
            self.advance();
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

    /// Fecha a transição que terminou e passa para a próxima faixa.
    fn advance(&mut self) {
        let transition_done = self
            .transition
            .as_ref()
            .is_some_and(|tr| tr.pos >= tr.len || tr.from.src.exhausted());
        if transition_done {
            if let Some(tr) = self.transition.take() {
                // Terminou antes da hora (faixa mais curta que o estimado): evita salto de volume.
                if let (Transition::Crossfade { .. }, Some(cur)) = (&tr.kind, self.current.as_mut()) {
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
                next.skip_lead = !kind.is_gapless();
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
    }
}

/// Curvas de cada estilo (t de 0 a 1 ao longo da transição).
fn smooth_in(x: f32) -> f32 {
    (x.clamp(0.0, 1.0) * FRAC_PI_2).sin()
}

fn smooth_out(x: f32) -> f32 {
    (x.clamp(0.0, 1.0) * FRAC_PI_2).cos()
}

const FX_STEP: usize = 32;

/// Faixa que entra (B): volume, grave cortado até a troca, passa-baixas no filtro.
fn automix_incoming(slot: &mut Slot, e: &AutomixExec, pos: u64, len: u64, buf: &mut [f32], rate: u32) {
    let len_f = len.max(1) as f32;
    let s = e.swap_at as f32 / len_f;
    let b = (e.beat as f32 / len_f).max(1e-4);
    let frames = buf.len() / 2;
    if !slot.fx.bass_ready {
        slot.fx.bass.set(180.0, rate);
        slot.fx.bass_ready = true;
    }
    for i in 0..frames {
        let t = (pos + i as u64) as f32 / len_f;
        let (l, r) = (buf[i * 2], buf[i * 2 + 1]);
        let (mut l2, mut r2);
        let vol;
        match e.style {
            MixStyle::BassSwap | MixStyle::Auto => {
                vol = if t < 0.25 { smooth_in(t / 0.25) } else { 1.0 };
                let kill = if t < s { 1.0 } else { (1.0 - (t - s) / b).clamp(0.0, 1.0) };
                let (lo_l, _) = slot.fx.bass.run(l, 0);
                let (lo_r, _) = slot.fx.bass.run(r, 1);
                l2 = l - kill * lo_l;
                r2 = r - kill * lo_r;
            }
            MixStyle::Filter => {
                vol = if t < 0.3 { smooth_in(t / 0.3) } else { 1.0 };
                if i % FX_STEP == 0 {
                    let x = (t / 0.7).clamp(0.0, 1.0);
                    slot.fx.sweep.set(300.0 * (66.0f32).powf(x), rate);
                }
                l2 = slot.fx.sweep.run(l, 0).0;
                r2 = slot.fx.sweep.run(r, 1).0;
                if t >= 0.7 {
                    // Filtro já aberto: passa direto (sem mudar a cor no fim).
                    let w = ((t - 0.7) / 0.1).clamp(0.0, 1.0);
                    l2 = l2 * (1.0 - w) + l * w;
                    r2 = r2 * (1.0 - w) + r * w;
                }
            }
            MixStyle::Echo => {
                vol = if t < s { 0.0 } else { smooth_in((t - s) / b) };
                l2 = l;
                r2 = r;
            }
            MixStyle::Blend => {
                vol = smooth_in(t);
                l2 = l;
                r2 = r;
            }
            MixStyle::Cut => {
                vol = smooth_in(t);
                l2 = l;
                r2 = r;
            }
        }
        buf[i * 2] = l2 * vol;
        buf[i * 2 + 1] = r2 * vol;
    }
}

/// Faixa que sai (A): volume, grave cortado depois da troca, passa-altas, eco.
/// Guarda a música na linha de atraso do eco antes da transição começar.
fn prime_echo(e: &mut AutomixExec, buf: &[f32]) {
    if e.style != MixStyle::Echo || e.echo_buf.is_empty() {
        return;
    }
    let frames = e.echo_buf.len() / 2;
    for i in 0..buf.len() / 2 {
        let w = e.echo_pos % frames;
        e.echo_buf[w * 2] = buf[i * 2];
        e.echo_buf[w * 2 + 1] = buf[i * 2 + 1];
        e.echo_pos = w + 1;
    }
}

fn automix_outgoing(
    slot: &mut Slot,
    e: &mut AutomixExec,
    pos: u64,
    len: u64,
    buf: &mut [f32],
    rate: u32,
) {
    let len_f = len.max(1) as f32;
    let s = e.swap_at as f32 / len_f;
    let b = (e.beat as f32 / len_f).max(1e-4);
    let frames = buf.len() / 2;
    if !slot.fx.bass_ready {
        slot.fx.bass.set(180.0, rate);
        slot.fx.bass_ready = true;
    }
    let echo_frames = (e.echo_buf.len() / 2).max(1);
    let delay = (e.beat as usize).clamp(1, echo_frames - 1);
    for i in 0..frames {
        let t = (pos + i as u64) as f32 / len_f;
        let (l, r) = (buf[i * 2], buf[i * 2 + 1]);
        let (mut l2, mut r2) = (l, r);
        let vol;
        match e.style {
            MixStyle::BassSwap | MixStyle::Auto => {
                vol = if t < s { 1.0 } else { smooth_out((t - s) / (1.0 - s).max(1e-4)) };
                let kill = if t < s { 0.0 } else { ((t - s) / b).clamp(0.0, 1.0) };
                let (lo_l, _) = slot.fx.bass.run(l, 0);
                let (lo_r, _) = slot.fx.bass.run(r, 1);
                l2 = l - kill * lo_l;
                r2 = r - kill * lo_r;
            }
            MixStyle::Filter => {
                vol = if t < 0.7 { 1.0 } else { smooth_out((t - 0.7) / 0.3) };
                if i % FX_STEP == 0 {
                    slot.fx.sweep.set(20.0 * (100.0f32).powf(t.clamp(0.0, 1.0)), rate);
                }
                l2 = slot.fx.sweep.run(l, 0).1;
                r2 = slot.fx.sweep.run(r, 1).1;
            }
            MixStyle::Echo => {
                // Antes do corte (t < s): a música toca normal e vai enchendo a
                // linha de atraso. No corte: some em 20 ms e o que continua é a
                // linha, repetindo a última batida e sumindo (0,55 por
                // repetição). Sem esse "pré-rolo", a primeira repetição só
                // viria uma batida depois e ficava um buraco no meio da troca.
                let fade = (0.02 * rate as f32 / len_f).max(1e-6);
                let dry = if t < s { 1.0 } else { (1.0 - (t - s) / fade).clamp(0.0, 1.0) };
                let echoing = t >= s;
                if !e.echo_buf.is_empty() {
                    let w = e.echo_pos % echo_frames;
                    let rd = (w + echo_frames - delay) % echo_frames;
                    let (dl, dr) = (e.echo_buf[rd * 2], e.echo_buf[rd * 2 + 1]);
                    // Grava a música antes do corte; depois, só a realimentação.
                    let (wl, wr) = if echoing { (dl * 0.55, dr * 0.55) } else { (l, r) };
                    e.echo_buf[w * 2] = wl;
                    e.echo_buf[w * 2 + 1] = wr;
                    e.echo_pos = w + 1;
                    let wet = if echoing { 0.8 } else { 0.0 };
                    l2 = l * dry + dl * wet;
                    r2 = r * dry + dr * wet;
                } else {
                    l2 = l * dry;
                    r2 = r * dry;
                }
                vol = 1.0;
            }
            MixStyle::Blend | MixStyle::Cut => {
                vol = smooth_out(t);
            }
        }
        let m = if e.mute_from { 0.0 } else { vol };
        buf[i * 2] = l2 * m;
        buf[i * 2 + 1] = r2 * m;
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

#[cfg(test)]
mod eq_tests {
    use super::*;

    /// Resposta do equalizador a uma senoide (dB).
    fn gain_at(freq: f32, s: EqSettings) -> f32 {
        let rate = 48000;
        let mut eq = Equalizer::new();
        eq.configure(s, rate);
        let n = rate as usize;
        let mut buf: Vec<f32> = (0..n)
            .flat_map(|i| {
                let v = (2.0 * std::f32::consts::PI * freq * i as f32 / rate as f32).sin() * 0.1;
                [v, v]
            })
            .collect();
        eq.process(&mut buf);
        let tail = &buf[n..];
        let rms = (tail.iter().map(|x| x * x).sum::<f32>() / tail.len() as f32).sqrt();
        20.0 * (rms / (0.1 / std::f32::consts::SQRT_2)).log10()
    }

    #[test]
    fn bands_hit_their_gain() {
        let mut g = [0.0; 10];
        g[2] = 6.0; // 125 Hz
        g[7] = -6.0; // 4 kHz
        let s = EqSettings { enabled: true, preamp_db: 0.0, gains_db: g };
        assert!((gain_at(125.0, s) - 6.0).abs() < 0.7, "{}", gain_at(125.0, s));
        assert!((gain_at(4000.0, s) + 6.0).abs() < 0.7, "{}", gain_at(4000.0, s));
        assert!(gain_at(1000.0, s).abs() < 1.0);
        let off = EqSettings { enabled: false, ..s };
        assert!(gain_at(125.0, off).abs() < 0.01);
    }
}

#[cfg(test)]
mod vinyl_tests {
    use super::*;
    use crate::engine::deck::DeckShared;

    /// Deck de mentira com uma rampa (o frame `i` vale `i + 1`): como a
    /// interpolação é linear, dá para conferir a agulha na casa decimal.
    fn ramp_slot(frames: usize) -> (rtrb::Producer<f32>, Slot) {
        let (mut p, c) = rtrb::RingBuffer::<f32>::new(frames * 2);
        for i in 0..frames {
            p.push(i as f32 + 1.0).unwrap();
            p.push(-(i as f32 + 1.0)).unwrap();
        }
        let shared = DeckShared::new(1, 48000);
        (p, Slot::new(Box::new(DeckSource { shared, ring: c, gain: 1.0 }), false, 0))
    }

    fn play(v: &mut Vinyl, slot: &mut Slot, n: usize) -> Vec<f32> {
        let mut out = vec![0.0; n * 2];
        v.render(slot, &mut out, n);
        out
    }

    fn at(v: &Vinyl, slot: &Slot) -> u64 {
        let _ = v;
        slot.src.shared.consumed.load(Ordering::Relaxed)
    }

    #[test]
    fn na_velocidade_normal_sai_o_mesmo_audio() {
        let (_p, mut slot) = ramp_slot(2000);
        let mut v = Vinyl::new(48000);
        v.grab(0);
        let out = play(&mut v, &mut slot, 100);
        for i in 0..100 {
            assert!((out[i * 2] - (i as f32 + 1.0)).abs() < 1e-3, "frame {i}: {}", out[i * 2]);
            assert!((out[i * 2 + 1] + (i as f32 + 1.0)).abs() < 1e-3);
        }
        assert_eq!(at(&v, &slot), 100);
    }

    #[test]
    fn devagar_estica_o_som_e_anda_menos() {
        let (_p, mut slot) = ramp_slot(2000);
        let mut v = Vinyl::new(48000);
        v.grab(0);
        // Sem a rampa de velocidade, para medir só o passo da agulha.
        v.target = 0.5;
        v.speed = 0.5;
        let out = play(&mut v, &mut slot, 100);
        for i in 0..100 {
            assert!((out[i * 2] - (i as f32 * 0.5 + 1.0)).abs() < 1e-3, "frame {i}: {}", out[i * 2]);
        }
        assert_eq!(at(&v, &slot), 50);
    }

    #[test]
    fn para_tras_toca_de_tras_para_frente_e_a_posicao_volta() {
        let (_p, mut slot) = ramp_slot(2000);
        let mut v = Vinyl::new(48000);
        v.grab(0);
        play(&mut v, &mut slot, 200);
        assert_eq!(at(&v, &slot), 200);
        v.target = -1.0;
        v.speed = -1.0;
        let out = play(&mut v, &mut slot, 50);
        for i in 0..50 {
            assert!((out[i * 2] - (201.0 - i as f32)).abs() < 1e-3, "frame {i}: {}", out[i * 2]);
        }
        assert_eq!(at(&v, &slot), 150);
    }

    #[test]
    fn disco_parado_e_giro_rapido_demais_nao_fazem_som() {
        let (_p, mut slot) = ramp_slot(2000);
        let mut v = Vinyl::new(48000);
        v.grab(0);
        play(&mut v, &mut slot, 100);
        v.target = 0.0;
        v.speed = 0.0;
        assert!(play(&mut v, &mut slot, 20).iter().all(|x| *x == 0.0), "disco parado fez som");
        v.target = VINYL_MAX_SPEED;
        v.speed = VINYL_MAX_SPEED;
        assert!(play(&mut v, &mut slot, 20).iter().all(|x| *x == 0.0), "giro rápido demais fez som");
    }

    #[test]
    fn sem_audio_decodificado_a_agulha_cala_em_vez_de_repetir() {
        let (_p, mut slot) = ramp_slot(10);
        let mut v = Vinyl::new(48000);
        v.grab(0);
        let out = play(&mut v, &mut slot, 40);
        assert!(out[0] != 0.0 && out[2] != 0.0);
        assert!(out[30 * 2..].iter().all(|x| *x == 0.0), "repetiu o que não tinha");
    }

    #[test]
    fn nao_volta_alem_do_que_a_memoria_guarda() {
        let (_p, mut slot) = ramp_slot(2000);
        // Memória curta de propósito: 100 frames.
        let mut v = Vinyl::new(25);
        v.grab(0);
        play(&mut v, &mut slot, 300);
        v.target = -1.0;
        v.speed = -1.0;
        play(&mut v, &mut slot, 1000);
        // Parou no mais antigo que a memória ainda guardava — não voltou ao
        // começo da faixa nem foi ler lixo.
        assert_eq!(at(&v, &slot), v.head - v.frames() as u64);
        assert!(at(&v, &slot) > 300 - v.frames() as u64);
    }
}
