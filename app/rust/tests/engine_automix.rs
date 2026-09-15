//! Orquestração do AutoMix no motor real (com saída de áudio, volume zero):
//! toca A, pede B com AutoMix, espera análise + plano, pula para perto do
//! ponto de mixagem e confere que a transição começa e B vira a atual.
//! Precisa de placa de som: `cargo test --release --test engine_automix -- --ignored`.

use std::path::PathBuf;
use std::sync::mpsc;
use std::time::{Duration, Instant};

use player_engine::engine::{Engine, EngineConfig, EngineEvent, TrackRequest, TransitionRequest};

fn track(id: &str, path: PathBuf, key: &str) -> TrackRequest {
    TrackRequest {
        id: id.into(),
        url: path.to_string_lossy().into(),
        format_hint: Some("flac".into()),
        title: id.into(),
        analysis_key: Some(key.into()),
        analysis_url: None,
        ..Default::default()
    }
}

#[test]
#[ignore]
fn automix_orchestration() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let music = root.join("../../dev/music/Sintético Beats/Pista Um");
    if !music.exists() {
        return;
    }
    let (tx, rx) = mpsc::channel::<EngineEvent>();
    let cache = std::env::temp_dir().join(format!("player-engine-automix-{}", std::process::id()));
    let engine = Engine::new(
        EngineConfig {
            cache_dir: cache,
            cache_limit_bytes: u64::MAX,
            device_id: None,
            app_id: "player_musica_test".into(),
            app_name: "teste".into(),
            media_controls: false,
            model_dir: Some(root.join("../assets/models")),
        },
        Some(std::sync::Arc::new(move |e| {
            let _ = tx.send(e);
        })),
    )
    .unwrap();
    engine.set_volume(0.0);
    engine.set_automix(player_engine::engine::automix::AutomixSettings { preferred_bars: 8, ..Default::default() });
    engine.play(track("A", music.join("01 - Abertura.flac"), "t:a"), 0);
    engine.set_next(Some(track("B", music.join("03 - Terceira Via.flac"), "t:b")), TransitionRequest::Automix).unwrap();

    let started = Instant::now();
    let mut log = Vec::new();
    let mut seeked = false;
    let mut mix_started = false;
    let mut b_started = false;
    while started.elapsed() < Duration::from_secs(90) {
        let Ok(ev) = rx.recv_timeout(Duration::from_millis(200)) else { continue };
        match &ev {
            EngineEvent::Position { .. } | EngineEvent::State { .. } | EngineEvent::DeviceChanged { .. } => continue,
            _ => {}
        }
        eprintln!("[{:5.1}s] {ev:?}", started.elapsed().as_secs_f32());
        match &ev {
            EngineEvent::MixPlanned { starts_in_ms, beatmatched, .. } => {
                assert!(*beatmatched);
                if !seeked {
                    // Pula para 5 s antes do ponto de mixagem.
                    seeked = true;
                    let pos = engine.position_ms().unwrap_or(0);
                    engine.seek(pos + starts_in_ms - 5000);
                }
            }
            EngineEvent::MixStarted { .. } => mix_started = true,
            EngineEvent::TrackStarted { id } if id == "B" => {
                b_started = true;
            }
            _ => {}
        }
        log.push(ev);
        if mix_started && b_started {
            break;
        }
    }
    engine.shutdown();
    assert!(log.iter().any(|e| matches!(e, EngineEvent::Analysis { id, reliable: true, .. } if id == "A")), "sem análise de A");
    assert!(log.iter().any(|e| matches!(e, EngineEvent::Analysis { id, reliable: true, .. } if id == "B")), "sem análise de B");
    assert!(mix_started, "a transição DJ não começou");
    assert!(b_started, "B não virou a faixa atual");
}

/// Pausa até a saída fechar (inatividade) e despausa: a música tem de voltar a
/// andar na hora, várias vezes seguidas (antes, às vezes o play não saía).
#[test]
#[ignore]
fn resume_after_idle_close() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let music = root.join("../../dev/music/Sintético Beats/Pista Um");
    if !music.exists() {
        return;
    }
    std::env::set_var("BK_IDLE_CLOSE_SECS", "2");
    let cache = std::env::temp_dir().join(format!("player-engine-resume-{}", std::process::id()));
    let engine = Engine::new(
        EngineConfig {
            cache_dir: cache,
            cache_limit_bytes: u64::MAX,
            device_id: None,
            app_id: "player_musica_test".into(),
            app_name: "teste".into(),
            media_controls: false,
            model_dir: None,
        },
        None,
    )
    .unwrap();
    engine.set_volume(0.0);
    engine.play(track("A", music.join("01 - Abertura.flac"), "t:a"), 0);
    std::thread::sleep(Duration::from_secs(2));
    let advancing = |what: &str| {
        let p0 = engine.position_ms().unwrap_or(0);
        let t = Instant::now();
        while t.elapsed() < Duration::from_secs(3) {
            std::thread::sleep(Duration::from_millis(50));
            if engine.position_ms().unwrap_or(0) > p0 + 200 {
                eprintln!("{what}: andando em {} ms", t.elapsed().as_millis());
                return;
            }
        }
        panic!("{what}: a música não voltou a andar");
    };
    advancing("começo");
    for round in 1..=4 {
        engine.pause();
        // Mais que o tempo de fechar a saída.
        std::thread::sleep(Duration::from_millis(std::env::var("BK_TEST_PAUSE_MS").ok().and_then(|s| s.parse().ok()).unwrap_or(3500)));
        let paused_at = engine.position_ms().unwrap_or(0);
        std::thread::sleep(Duration::from_millis(500));
        assert_eq!(engine.position_ms().unwrap_or(0), paused_at, "pausada, não anda");
        engine.resume();
        advancing(&format!("despausou {round}"));
    }
    engine.shutdown();
}
