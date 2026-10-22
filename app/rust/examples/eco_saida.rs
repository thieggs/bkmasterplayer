//! Onde o eco do AutoMix corta a música que sai, em análises gravadas (cache
//! do app ou pasta `analyses/` do BK Analyzer): segundos antes do último som e
//! quantos compassos ainda com música ficam para trás. Também mostra quantas
//! trocas no automático viram eco (pares em sequência, como uma fila).
//!
//! Uso: eco_saida <pasta ou arquivos .json...>
use player_engine::engine::analysis::TrackAnalysis;
use player_engine::engine::automix::{bar_exit, plan, AutomixSettings, MixStyle};

fn pct(v: &[f64], p: f64) -> f64 {
    v[((v.len() - 1) as f64 * p).round() as usize]
}

/// Compassos depois de `at` que ainda soam como música (a menos de 20 dB das
/// partes cheias): o que o corte joga fora.
fn lost_bars(a: &TrackAnalysis, at: f64) -> usize {
    let mut sorted: Vec<f32> = a.bar_energy.iter().copied().filter(|e| *e > -90.0).collect();
    if sorted.is_empty() || a.bars.len() != a.bar_energy.len() {
        return 0;
    }
    sorted.sort_by(|x, y| x.partial_cmp(y).unwrap());
    let reference = sorted[sorted.len() * 3 / 4];
    a.bars.iter().zip(&a.bar_energy).filter(|(t, e)| **t >= at - 0.05 && **e >= reference - 20.0).count()
}

fn main() -> anyhow::Result<()> {
    let mut files = Vec::new();
    for a in std::env::args().skip(1) {
        let p = std::path::PathBuf::from(a);
        if p.is_dir() {
            for e in std::fs::read_dir(&p)? {
                let e = e?.path();
                if e.extension().is_some_and(|x| x == "json") {
                    files.push(e);
                }
            }
        } else {
            files.push(p);
        }
    }
    files.sort();
    let tracks: Vec<TrackAnalysis> = files
        .iter()
        .filter_map(|f| serde_json::from_slice::<TrackAnalysis>(&std::fs::read(f).ok()?).ok())
        .filter(|a| a.is_sane())
        .collect();
    let s = AutomixSettings::default();

    let (mut before, mut lost, mut none) = (Vec::new(), Vec::new(), 0);
    for a in &tracks {
        match bar_exit(a, &s, 0.0) {
            Some((at, _, _)) => {
                before.push(a.last_sound - at);
                lost.push(lost_bars(a, at) as f64);
            }
            None => none += 1,
        }
    }
    before.sort_by(|x, y| x.partial_cmp(y).unwrap());
    lost.sort_by(|x, y| x.partial_cmp(y).unwrap());
    println!("{} análises; saída no compasso em {} ({} sem)", tracks.len(), before.len(), none);
    if !before.is_empty() {
        println!(
            "segundos antes do último som: mediana {:.1}, 90% até {:.1}, máx {:.1}",
            pct(&before, 0.5),
            pct(&before, 0.9),
            before[before.len() - 1]
        );
        let any = lost.iter().filter(|l| **l > 0.0).count();
        println!(
            "compassos de música jogados fora: mediana {:.0}, 90% até {:.0}, máx {:.0}; {:.0}% das faixas perdem algum",
            pct(&lost, 0.5),
            pct(&lost, 0.9),
            lost[lost.len() - 1],
            100.0 * any as f64 / lost.len() as f64
        );
    }

    // Fila: cada faixa seguida da próxima, no automático.
    let (mut eco, mut total) = (0, 0);
    let mut eco_before = Vec::new();
    for w in tracks.windows(2) {
        let p = plan(&w[0], &w[1], &s, 0.0);
        total += 1;
        if p.style == MixStyle::Echo {
            eco += 1;
            eco_before.push(w[0].last_sound - p.from_start);
        }
    }
    eco_before.sort_by(|x, y| x.partial_cmp(y).unwrap());
    println!("automático: {eco} de {total} trocas viram eco ({:.0}%)", 100.0 * eco as f64 / total.max(1) as f64);
    if !eco_before.is_empty() {
        println!(
            "  nelas, segundos antes do último som: mediana {:.1}, 90% até {:.1}, máx {:.1}",
            pct(&eco_before, 0.5),
            pct(&eco_before, 0.9),
            eco_before[eco_before.len() - 1]
        );
    }
    Ok(())
}
