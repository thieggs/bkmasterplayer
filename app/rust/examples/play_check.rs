//! Toca músicas de um Navidrome pelo motor, do jeito do app (o original com a
//! conversão para MP3 de reserva, ou já convertida nos formatos que o motor não
//! lê), em volume zero. Para cada uma: se começou, em quanto tempo, se o tempo
//! anda, e onde caiu um seek para o meio.
//! Uso: play_check <url> <usuário> <senha> <trechos do caminho, separados por |>
use std::sync::mpsc;
use std::time::{Duration, Instant};

use player_engine::engine::{AudioSource, Engine, EngineConfig, EngineEvent, TrackRequest};

/// O mesmo `_undecodable` do app (lib/player/player_controller.dart).
const UNDECODABLE: &[&str] =
    &["wma", "asf", "mpc", "mp+", "mpp", "tta", "ac3", "eac3", "dts", "amr", "awb", "spx", "tak", "ofr", "ofs", "shn", "ra", "rm"];

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [base, user, pass, filter] = args.as_slice() else {
        anyhow::bail!("uso: play_check <url> <usuário> <senha> <trecho do caminho>");
    };
    let hex: String = pass.bytes().map(|b| format!("{b:02x}")).collect();
    let api = |method: &str, extra: &str| format!("{base}/rest/{method}?u={user}&p=enc:{hex}&v=1.16.1&c=play_check&f=json{extra}");
    let body = ureq::get(&api("search3", "&query=&songCount=1000&albumCount=0&artistCount=0")).call()?.body_mut().read_to_string()?;
    let found: serde_json::Value = serde_json::from_str(&body)?;
    let mut songs: Vec<serde_json::Value> = found["subsonic-response"]["searchResult3"]["song"]
        .as_array()
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter(|s| s["path"].as_str().is_some_and(|p| filter.split('|').any(|f| p.contains(f))))
        .collect();
    songs.sort_by_key(|s| s["path"].as_str().unwrap_or("").to_string());
    println!("{} músicas com \"{filter}\"", songs.len());

    let (tx, rx) = mpsc::channel::<EngineEvent>();
    let cache = std::env::temp_dir().join(format!("bk-play-check-{}", std::process::id()));
    let engine = Engine::new(
        EngineConfig {
            cache_dir: cache.clone(),
            cache_limit_bytes: u64::MAX,
            device_id: None,
            app_id: "player_musica_check".into(),
            app_name: "play_check".into(),
            media_controls: false,
            model_dir: None,
        },
        Some(std::sync::Arc::new(move |e| {
            let _ = tx.send(e);
        })),
    )?;
    engine.set_volume(0.0);

    for s in &songs {
        let id = s["id"].as_str().unwrap_or_default();
        let suffix = s["suffix"].as_str().unwrap_or_default().to_ascii_lowercase();
        let name = s["path"].as_str().unwrap_or_default().rsplit('/').next().unwrap_or_default().to_string();
        let duration_ms = s["duration"].as_u64().unwrap_or(0) * 1000;
        let convert = UNDECODABLE.contains(&suffix.as_str());
        let format = if convert { "mp3" } else { "raw" };
        let stream = |f: &str| api("stream", &format!("&id={id}&format={f}"));
        let req = TrackRequest {
            id: id.to_string(),
            url: stream(format),
            cache_key: Some(format!("check:{id}:{format}")),
            format_hint: Some(if convert { "mp3".into() } else { suffix.clone() }),
            duration_ms: Some(duration_ms),
            title: name.clone(),
            fallback: (!convert).then(|| AudioSource {
                url: stream("mp3"),
                cache_key: Some(format!("check:{id}:mp3")),
                format_hint: Some("mp3".into()),
            }),
            ..Default::default()
        };
        while rx.try_recv().is_ok() {}
        let t0 = Instant::now();
        engine.play(req, 0);
        let mut verdict = String::new();
        // Começou e andou 1,5 s?
        let mut started = None;
        while t0.elapsed() < Duration::from_secs(20) {
            if let Ok(EngineEvent::TrackEnded { error: Some(e), .. }) = rx.recv_timeout(Duration::from_millis(50)) {
                verdict = format!("ERRO: {e}");
                break;
            }
            let pos = engine.position_ms().unwrap_or(0);
            if pos > 0 && started.is_none() {
                started = Some(t0.elapsed());
            }
            if pos >= 1500 {
                break;
            }
        }
        if verdict.is_empty() {
            match started {
                None => verdict = "não começou".into(),
                Some(st) => {
                    // Seek para o meio: onde caiu, e se volta a andar.
                    let target = (duration_ms / 2).max(1000);
                    engine.seek(target);
                    let t1 = Instant::now();
                    let mut after = 0;
                    while t1.elapsed() < Duration::from_secs(10) {
                        std::thread::sleep(Duration::from_millis(50));
                        after = engine.position_ms().unwrap_or(0);
                        if after >= target + 800 {
                            break;
                        }
                    }
                    let ok = after >= target + 800;
                    verdict = format!(
                        "{} começou em {} ms; seek para {} s → {} s",
                        if ok { "OK" } else { "SEEK PAROU" },
                        st.as_millis(),
                        target / 1000,
                        after as f64 / 1000.0
                    );
                }
            }
        }
        engine.stop();
        std::thread::sleep(Duration::from_millis(300));
        let note = if convert {
            "  [servidor converte]"
        } else if engine.is_cached(&format!("check:{id}:mp3")) {
            "  [o motor não abriu: tocou a conversão]"
        } else {
            ""
        };
        println!("{:<50} .{:<5} {verdict}{note}", name.chars().take(50).collect::<String>(), suffix);
    }
    engine.shutdown();
    let _ = std::fs::remove_dir_all(&cache);
    Ok(())
}
