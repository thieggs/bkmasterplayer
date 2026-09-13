//! AutoMix: planejamento da transição DJ entre duas faixas analisadas.
//!
//! O plano diz ONDE a faixa A começa a sair (sempre no início de um compasso,
//! de preferência no começo da outro), ONDE a faixa B entra (no primeiro
//! compasso dela), por quantos compassos as duas tocam juntas, qual a
//! velocidade de B para as batidas baterem (time-stretch sem mudar o tom) e
//! qual o estilo (troca de grave, filtro, mistura, corte).

use serde::{Deserialize, Serialize};

use super::analysis::{camelot_compatible, BeatGrid, TrackAnalysis};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MixStyle {
    /// Escolhe sozinho pelo material.
    Auto,
    /// Mistura com troca de grave no meio (padrão de DJ para música com batida).
    BassSwap,
    /// Mistura simples de volume (equal-power), graves inteiros.
    Blend,
    /// A sai com filtro passa-altas subindo; B entra com passa-baixas abrindo.
    Filter,
    /// A sai com eco sincronizado na batida; B entra no compasso.
    Echo,
    /// Troca seca no início do compasso.
    Cut,
}

/// Configurações do AutoMix (todas ajustáveis pelo usuário; os padrões são o
/// "melhor jeito" para a maioria das bibliotecas).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomixSettings {
    pub style: MixStyle,
    /// Mudança máxima de velocidade para sincronizar (0.08 = ±8%).
    pub max_tempo_change: f64,
    /// Duração preferida da sobreposição, em compassos (4, 8, 16, 32).
    pub preferred_bars: u32,
    /// Menos que isso não vale sincronizar: vira transição simples.
    pub min_bars: u32,
    /// Teto da transição em segundos (mesmo quando a estrutura permite mais).
    pub max_seconds: f64,
    /// Duração da transição quando não há batida/estrutura clara.
    pub unclear_seconds: f64,
    /// Encurta a transição quando os tons não combinam (roda Camelot).
    pub harmonic: bool,
    /// Depois da transição, volta a velocidade de B ao original ao longo de N compassos (0 = mantém).
    pub tempo_ramp_bars: u32,
    /// Corta silêncio no fim de A e no começo de B.
    pub trim_silence: bool,
}

impl Default for AutomixSettings {
    fn default() -> Self {
        Self {
            style: MixStyle::Auto,
            max_tempo_change: 0.08,
            preferred_bars: 16,
            min_bars: 4,
            max_seconds: 40.0,
            unclear_seconds: 8.0,
            harmonic: true,
            tempo_ramp_bars: 16,
            trim_silence: true,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct MixPlan {
    pub style: MixStyle,
    /// Instante em A (s) em que a transição começa.
    pub from_start: f64,
    /// Posição em B (s) onde B começa a tocar.
    pub to_start: f64,
    /// Duração da sobreposição em tempo real (s).
    pub duration: f64,
    /// Velocidade de B durante a sobreposição (1.0 = original).
    pub speed: f64,
    /// Tempo real (s) para B voltar à velocidade original depois da sobreposição.
    pub ramp: f64,
    /// Fração da duração em que acontece a troca de grave (BassSwap).
    pub swap_at: f64,
    /// Duração de uma batida de A (s) — usada pelo eco.
    pub beat: f64,
    pub beatmatched: bool,
    pub bars: u32,
    pub summary: String,
}

fn snap_bars(bars: u32) -> u32 {
    [32, 16, 8, 4, 2, 1].into_iter().find(|b| *b <= bars).unwrap_or(1)
}

/// A emenda entre A e B é contínua (álbum ao vivo, mixado ou conceitual):
/// A soa até o fim do arquivo e B já começa soando.
pub fn seamless(a: &TrackAnalysis, b: &TrackAnalysis) -> bool {
    a.duration - a.last_sound < 0.4 && b.first_sound < 0.4
}

/// "Plano" de emenda sem pausa (nada a mixar).
pub fn gapless_plan(a: &TrackAnalysis) -> MixPlan {
    MixPlan {
        style: MixStyle::Cut,
        from_start: a.duration,
        to_start: 0.0,
        duration: 0.0,
        speed: 1.0,
        ramp: 0.0,
        swap_at: 0.5,
        beat: 0.5,
        beatmatched: false,
        bars: 0,
        summary: "sem pausa".into(),
    }
}

/// Transição simples (sem batida confiável ou estrutura clara).
fn unclear_plan(a: &TrackAnalysis, b: &TrackAnalysis, s: &AutomixSettings, a_now: f64, why: &str) -> MixPlan {
    let dur = s.unclear_seconds.min(s.max_seconds).max(0.5);
    let a_end = if s.trim_silence { a.last_sound.min(a.duration) } else { a.duration };
    let from = (a_end - dur).max(a_now + 1.0).min(a.duration);
    let to = if s.trim_silence { b.first_sound.max(0.0) } else { 0.0 };
    let style = match s.style {
        MixStyle::Auto | MixStyle::BassSwap => MixStyle::Blend,
        MixStyle::Cut => MixStyle::Cut,
        other => other,
    };
    MixPlan {
        style,
        from_start: from,
        to_start: to,
        duration: if style == MixStyle::Cut { 0.0 } else { (a_end - from).max(0.5) },
        speed: 1.0,
        ramp: 0.0,
        swap_at: 0.5,
        beat: a.bpm.map(|b| 60.0 / b).unwrap_or(0.5),
        beatmatched: false,
        bars: 0,
        summary: format!("transição simples de {:.0}s ({why})", dur),
    }
}

/// BPMs longe demais para casar: em vez de misturar dois tempos brigando, faz
/// como DJ — A ecoa (ou corta) num início de compasso perto do fim e B entra
/// no primeiro tempo dela no mesmo instante. Estilos "mistura"/"filtro"
/// escolhidos pelo usuário ficam com a transição simples.
fn tempo_jump_plan(a: &TrackAnalysis, b: &TrackAnalysis, ga: &BeatGrid, gb: &BeatGrid, s: &AutomixSettings, a_now: f64) -> MixPlan {
    let style = match s.style {
        MixStyle::Auto | MixStyle::BassSwap | MixStyle::Echo => MixStyle::Echo,
        MixStyle::Cut => MixStyle::Cut,
        MixStyle::Blend | MixStyle::Filter => return unclear_plan(a, b, s, a_now, "BPM muito diferente"),
    };
    let a_end = if s.trim_silence { a.last_sound } else { a.duration };
    let bar_a = ga.bar_seconds();
    let a_stop = ga.nearest_bar(a_end).min(a.duration);
    // Onde sair: começo da outro, se estiver nos últimos 16 compassos (a outro
    // de A não casa com B mesmo), senão 4 compassos antes do fim musical.
    let mut at = match a.outro_start {
        Some(o) if a_stop - o <= 16.0 * bar_a => ga.nearest_bar(o),
        _ => a_stop - 4.0 * bar_a,
    };
    at = at.max(ga.bar_at_or_after(a_now + 4.0));
    // O eco repete a batida de A por 2 compassos, sumindo (0,55 por repetição).
    let duration = if style == MixStyle::Cut { ga.period } else { 2.0 * bar_a };
    if at + duration > a.duration {
        return unclear_plan(a, b, s, a_now, "BPM muito diferente");
    }
    let b_bar = gb.bar_at_or_after(b.first_sound - 0.05);
    let off_a = ga.offset_near(at, at + bar_a).filter(|o| o.abs() <= 0.025).unwrap_or(0.0);
    let off_b = gb.offset_near(b_bar, b_bar + gb.bar_seconds()).filter(|o| o.abs() <= 0.025).unwrap_or(0.0);
    MixPlan {
        style,
        from_start: at + off_a,
        to_start: (b_bar + off_b).max(0.0),
        duration,
        speed: 1.0,
        ramp: 0.0,
        // Eco já no primeiro tempo: A para e ecoa, B entra ao longo de 1 batida.
        swap_at: 0.0,
        beat: ga.period,
        beatmatched: false,
        bars: 1,
        summary: format!(
            "{} no compasso, {:.1}→{:.1} BPM (diferença grande demais para casar)",
            if style == MixStyle::Cut { "corte" } else { "eco" },
            ga.bpm(),
            gb.bpm()
        ),
    }
}

/// Planeja a transição de A (tocando, na posição `a_now` s) para B.
pub fn plan(a: &TrackAnalysis, b: &TrackAnalysis, s: &AutomixSettings, a_now: f64) -> MixPlan {
    if !a.has_beat() || !b.has_beat() {
        return unclear_plan(a, b, s, a_now, "sem batida confiável");
    }
    let a_end = if s.trim_silence { a.last_sound } else { a.duration };
    let Some(ga) = a.grid_at(a_end - 20.0) else {
        return unclear_plan(a, b, s, a_now, "sem grade no fim da atual");
    };
    let Some(gb) = b.grid_at(b.first_sound + 5.0) else {
        return unclear_plan(a, b, s, a_now, "sem grade no começo da próxima");
    };
    if !ga.is_steady() {
        return unclear_plan(a, b, s, a_now, "batida irregular no fim da atual");
    }
    if !gb.is_steady() {
        return unclear_plan(a, b, s, a_now, "batida irregular no começo da próxima");
    }

    // Velocidade de B para as batidas baterem (aceita 2:1 e 1:2).
    let (speed, ratio) = [1.0, 2.0, 0.5]
        .into_iter()
        .map(|m| (m * ga.bpm() / gb.bpm(), m))
        .min_by(|x, y| (x.0 - 1.0).abs().partial_cmp(&(y.0 - 1.0).abs()).unwrap())
        .unwrap();
    if (speed - 1.0).abs() > s.max_tempo_change {
        return tempo_jump_plan(a, b, ga, gb, s, a_now);
    }

    let bar_a = ga.bar_seconds();
    let bar_b = gb.bar_seconds();
    // Ponto de entrada de B: primeiro compasso com som.
    let b_bar = gb.bar_at_or_after(b.first_sound - 0.05);
    let b_in = b_bar.max(0.0);
    let intro_bars = b
        .intro_end
        .map(|ie| ((ie - b_in) / bar_b).round().max(0.0) as u32)
        .unwrap_or(0);
    // Fim musical de A (compasso mais próximo do último som).
    let a_stop = ga.nearest_bar(a_end).min(a.duration);
    let outro_bars = a
        .outro_start
        .map(|o| ((a_stop - ga.nearest_bar(o)) / bar_a).round().max(0.0) as u32)
        .unwrap_or(0);
    let structure_clear = a.outro_start.is_some() && b.intro_end.is_some();

    let by_time = (s.max_seconds / bar_a).floor() as u32;
    let mut bars = s.preferred_bars.min(by_time.max(1));
    if outro_bars >= s.min_bars {
        bars = bars.min(outro_bars);
    }
    if intro_bars >= s.min_bars {
        bars = bars.min(intro_bars);
    }
    if !structure_clear {
        // Estrutura não clara: respeita a duração "sem estrutura" do usuário.
        let unclear_bars = (s.unclear_seconds / bar_a).round().max(1.0) as u32;
        bars = bars.min(unclear_bars.max(s.min_bars));
    }
    let key_clash = s.harmonic
        && matches!((&a.camelot, &b.camelot), (Some(x), Some(y)) if a.key_confidence > 0.1 && b.key_confidence > 0.1 && !camelot_compatible(x, y));
    if key_clash {
        bars = bars.min(8);
    }
    let mut bars = snap_bars(bars);
    if bars < s.min_bars {
        return unclear_plan(a, b, s, a_now, "pouco espaço para mixar");
    }

    // Início: começo da outro (se couber a transição inteira nela), senão
    // `bars` compassos antes do fim musical de A.
    let latest = a_stop - bars as f64 * bar_a;
    let mut from = match a.outro_start {
        Some(o) if outro_bars >= bars => ga.nearest_bar(o).min(latest),
        _ => latest,
    };
    // Precisa estar no futuro (tempo de preparar B), sempre num compasso.
    let earliest = ga.bar_at_or_after(a_now + 4.0);
    if from < earliest {
        from = earliest;
        let room = ((a_stop - from) / bar_a).floor().max(0.0) as u32;
        bars = snap_bars(bars.min(room));
        if bars < s.min_bars.min(2) {
            return unclear_plan(a, b, s, a_now, "tarde demais para sincronizar");
        }
    }
    let duration = bars as f64 * bar_a;

    // Fase medida nos ataques do áudio exatamente no trecho da mixagem: corrige
    // o que sobrou de erro da grade ali (poucos ms). Muito fora = não confia.
    let off_a = ga.offset_near(from, from + duration).unwrap_or(0.0);
    let off_b = gb.offset_near(b_bar, b_bar + bars as f64 * bar_b).unwrap_or(0.0);
    if off_a.abs() > 0.025 || off_b.abs() > 0.025 {
        return unclear_plan(a, b, s, a_now, "fase incerta no ponto da mixagem");
    }
    // B pode cair uns ms antes do começo do arquivo (batida em t≈0): aí B
    // começa em 0 e a transição atrasa esse mesmo tanto, para as batidas
    // continuarem casando.
    let b_true = b_bar + off_b;
    let b_in = b_true.max(0.0);
    let b_shift = (b_in - b_true) / speed;
    let from = from + off_a + b_shift;

    let style = match s.style {
        MixStyle::Auto => {
            if key_clash {
                MixStyle::Filter
            } else {
                MixStyle::BassSwap
            }
        }
        other => other,
    };
    let ramp = if (speed - 1.0).abs() < 1e-4 || s.tempo_ramp_bars == 0 {
        0.0
    } else {
        s.tempo_ramp_bars as f64 * bar_b / speed
    };
    // Troca de grave num compasso no meio.
    let swap_bar = (bars / 2).max(1);
    let pct = (speed - 1.0) * 100.0;
    let summary = format!(
        "{bars} compassos, {:.1}→{:.1} BPM ({:+.1}%{}){}{}",
        gb.bpm(),
        ga.bpm(),
        pct,
        if ratio != 1.0 { ", 2:1" } else { "" },
        match (&a.camelot, &b.camelot) {
            (Some(x), Some(y)) => format!(", {x}→{y}"),
            _ => String::new(),
        },
        if key_clash { " (tons não combinam: transição curta com filtro)" } else { "" },
    );
    MixPlan {
        style,
        from_start: from,
        to_start: b_in,
        duration,
        speed,
        ramp,
        swap_at: swap_bar as f64 / bars as f64,
        beat: ga.period,
        beatmatched: true,
        bars,
        summary,
    }
}

/// Mapa de tempo de um deck com time-stretch: sobreposição a `speed`, rampa
/// linear até 1.0 e depois velocidade normal. Em frames de saída (tempo real).
#[derive(Debug, Clone, Copy)]
pub struct TempoMap {
    pub speed: f64,
    pub hold: f64,
    pub ramp: f64,
}

impl TempoMap {
    pub fn identity() -> Self {
        Self { speed: 1.0, hold: 0.0, ramp: 0.0 }
    }

    pub fn is_identity(&self) -> bool {
        (self.speed - 1.0).abs() < 1e-9
    }

    /// Velocidade no frame de saída `out`.
    pub fn speed_at(&self, out: f64) -> f64 {
        if out <= self.hold {
            self.speed
        } else if self.ramp > 0.0 && out <= self.hold + self.ramp {
            self.speed + (1.0 - self.speed) * (out - self.hold) / self.ramp
        } else {
            1.0
        }
    }

    /// Frames de entrada (posição original) consumidos até o frame de saída `out`.
    pub fn input_at(&self, out: f64) -> f64 {
        let s = self.speed;
        if out <= self.hold {
            s * out
        } else if out <= self.hold + self.ramp {
            let x = out - self.hold;
            s * self.hold + s * x + (1.0 - s) * x * x / (2.0 * self.ramp)
        } else {
            s * self.hold + (s + 1.0) / 2.0 * self.ramp + (out - self.hold - self.ramp)
        }
    }

    /// Inverso de `input_at`.
    pub fn output_at(&self, input: f64) -> f64 {
        let s = self.speed;
        let a = s * self.hold;
        let b = a + (s + 1.0) / 2.0 * self.ramp;
        if input <= a {
            input / s
        } else if input <= b {
            // Resolve s·x + (1-s)x²/(2R) = input - a
            let c = input - a;
            let k = (1.0 - s) / (2.0 * self.ramp);
            let x = if k.abs() < 1e-12 { c / s } else { (-s + (s * s + 4.0 * k * c).sqrt()) / (2.0 * k) };
            self.hold + x
        } else {
            self.hold + self.ramp + (input - b)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fake(bpm: f64, duration: f64, intro_bars: f64, outro_bars: f64, camelot: &str) -> TrackAnalysis {
        let p = 60.0 / bpm;
        let bar = 4.0 * p;
        let grid = BeatGrid {
            start: 0.0,
            end: duration,
            t0: 0.0,
            period: p,
            phase: 0,
            beats_per_bar: 4,
            residual: 0.003,
            coverage: 0.95,
            inliers: (duration / p) as u32,
            windows: (0..(duration / (8.0 * bar)) as usize).map(|i| ((i as f64 + 0.5) * 8.0 * bar, 0.0)).collect(),
            lock: 1.0,
            validated: false,
        };
        TrackAnalysis {
            version: 1,
            duration,
            bpm: Some(bpm),
            bpm_confidence: 0.9,
            beats: vec![],
            downbeats: vec![],
            beats_per_bar: 4,
            key: None,
            camelot: Some(camelot.into()),
            key_confidence: 0.5,
            lufs: None,
            peak: 1.0,
            grids: vec![grid],
            bar_energy: vec![],
            bars: vec![],
            first_sound: 0.0,
            last_sound: duration,
            intro_end: Some(intro_bars * bar),
            outro_start: Some(duration - outro_bars * bar),
        }
    }

    #[test]
    fn beatmatched_plan_uses_outro_and_intro() {
        let a = fake(120.0, 240.0, 16.0, 16.0, "8A");
        let b = fake(124.0, 200.0, 16.0, 16.0, "9A");
        let p = plan(&a, &b, &AutomixSettings::default(), 30.0);
        assert!(p.beatmatched);
        assert_eq!(p.bars, 16);
        assert!((p.from_start - (240.0 - 32.0)).abs() < 1e-6, "{p:?}");
        assert!((p.to_start - 0.0).abs() < 1e-6);
        assert!((p.speed - 120.0 / 124.0).abs() < 1e-9);
        assert_eq!(p.style, MixStyle::BassSwap);
        assert!((p.duration - 32.0).abs() < 1e-6);
    }

    #[test]
    fn half_time_is_matched_2_to_1() {
        let a = fake(87.0, 240.0, 16.0, 16.0, "4A");
        let b = fake(174.0, 240.0, 16.0, 16.0, "4A");
        let p = plan(&a, &b, &AutomixSettings::default(), 30.0);
        assert!(p.beatmatched);
        assert!((p.speed - 1.0).abs() < 1e-9);
    }

    #[test]
    fn too_different_echoes_out_on_the_bar() {
        // 90 → 128 BPM: não casa; A ecoa num compasso e B entra no 1º tempo.
        let a = fake(90.0, 240.0, 16.0, 16.0, "8A");
        let b = fake(128.0, 240.0, 16.0, 16.0, "8A");
        let p = plan(&a, &b, &AutomixSettings::default(), 30.0);
        assert!(!p.beatmatched);
        assert_eq!(p.style, MixStyle::Echo);
        let bar_a = 4.0 * 60.0 / 90.0;
        assert!((p.duration - 2.0 * bar_a).abs() < 1e-9);
        assert!(((p.from_start / bar_a) - (p.from_start / bar_a).round()).abs() < 1e-6, "{p:?}");
        assert!((p.to_start - 0.0).abs() < 1e-9, "B entra no primeiro compasso");
        // Quem escolheu "mistura" continua com a transição simples.
        let s = AutomixSettings { style: MixStyle::Blend, ..Default::default() };
        let p = plan(&a, &b, &s, 30.0);
        assert_eq!(p.style, MixStyle::Blend);
        assert!((p.duration - 8.0).abs() < 1e-6);
    }

    #[test]
    fn key_clash_shortens_and_filters() {
        let a = fake(120.0, 240.0, 16.0, 16.0, "8A");
        let b = fake(120.0, 240.0, 16.0, 16.0, "2B");
        let p = plan(&a, &b, &AutomixSettings::default(), 30.0);
        assert_eq!(p.bars, 8);
        assert_eq!(p.style, MixStyle::Filter);
    }

    #[test]
    fn respects_max_seconds() {
        let a = fake(120.0, 240.0, 32.0, 32.0, "8A");
        let b = fake(120.0, 240.0, 32.0, 32.0, "8A");
        let s = AutomixSettings { preferred_bars: 32, max_seconds: 20.0, ..Default::default() };
        let p = plan(&a, &b, &s, 30.0);
        assert!(p.duration <= 20.0, "{p:?}");
        assert_eq!(p.bars, 8);
    }

    #[test]
    fn local_phase_shifts_both_entry_points() {
        // Ataques de A 6 ms depois da grade no fim; os de B 4 ms antes no começo.
        let mut a = fake(128.0, 240.0, 16.0, 16.0, "8A");
        let mut b = fake(128.0, 240.0, 16.0, 16.0, "8A");
        b.first_sound = 1.0; // batida de B longe de t=0 (sem o atraso de borda)
        let base = plan(&a, &b, &AutomixSettings::default(), 30.0);
        a.grids[0].windows.iter_mut().for_each(|w| w.1 = 0.006);
        b.grids[0].windows.iter_mut().for_each(|w| w.1 = -0.004);
        let p = plan(&a, &b, &AutomixSettings::default(), 30.0);
        assert!(p.beatmatched);
        assert!((p.from_start - (base.from_start + 0.006)).abs() < 1e-9, "{p:?} {base:?}");
        assert!((p.to_start - (base.to_start - 0.004)).abs() < 1e-9, "{p:?} {base:?}");
    }

    #[test]
    fn phase_far_off_at_mix_point_falls_back() {
        let a = fake(128.0, 240.0, 16.0, 16.0, "8A");
        let mut b = fake(128.0, 240.0, 16.0, 16.0, "8A");
        b.grids[0].windows.iter_mut().for_each(|w| w.1 = 0.028);
        let p = plan(&a, &b, &AutomixSettings::default(), 30.0);
        assert!(!p.beatmatched, "{p:?}");
    }

    #[test]
    fn seamless_album_detection() {
        let mut a = fake(120.0, 240.0, 16.0, 16.0, "8A");
        let mut b = fake(120.0, 240.0, 16.0, 16.0, "8A");
        (a.last_sound, b.first_sound) = (239.9, 0.0);
        assert!(seamless(&a, &b), "ao vivo/mixado: emenda contínua");
        a.last_sound = 238.5;
        assert!(!seamless(&a, &b), "silêncio no fim de A: álbum comum");
        (a.last_sound, b.first_sound) = (239.9, 0.8);
        assert!(!seamless(&a, &b), "silêncio no começo de B: álbum comum");
    }

    #[test]
    fn tempo_map_roundtrip() {
        let m = TempoMap { speed: 0.96, hold: 48000.0 * 30.0, ramp: 48000.0 * 20.0 };
        for out in [0.0, 1000.0, 48000.0 * 30.0, 48000.0 * 40.0, 48000.0 * 60.0, 48000.0 * 90.0] {
            let i = m.input_at(out);
            assert!((m.output_at(i) - out).abs() < 1e-3, "{out}");
        }
        assert!((m.speed_at(48000.0 * 40.0) - 0.98).abs() < 1e-9);
    }
}
