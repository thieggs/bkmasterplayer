//! Trabalhador: pega músicas do coordenador, baixa o arquivo original por ele,
//! analisa com o mesmo código do app (modelo completo por padrão) e devolve o
//! resultado. Roda com prioridade baixa de CPU e pausa na bateria.

use std::io::{Cursor, Read};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{anyhow, bail, Context, Result};
use player_engine::engine::analysis::{Analyzer, BeatModel, TrackAnalysis, ANALYSIS_VERSION};
use serde::Deserialize;
use serde_json::json;

pub struct Args {
    pub server: String,
    pub token: String,
    pub jobs: usize,
    pub models: PathBuf,
    pub model: BeatModel,
    pub name: String,
    pub on_battery: bool,
    pub nice: i32,
}

#[derive(Deserialize)]
struct Job {
    id: String,
    suffix: String,
    title: String,
    artist: String,
}

struct Ctx {
    args: Args,
    cpu: String,
    agent: ureq::Agent,
}

pub fn run(args: Args) -> Result<()> {
    // Antes de criar qualquer thread: todas (inclusive as do rayon) herdam.
    unsafe {
        libc::setpriority(libc::PRIO_PROCESS, 0, args.nice);
    }
    let probe = Analyzer::new(&args.models, std::env::temp_dir().join("bk-analyzer-probe"));
    if !probe.model_available(args.model) {
        bail!("modelo {} não encontrado em {} (precisa de {} e mel_spectrogram.onnx)", args.model.name(), args.models.display(), args.model.file_name());
    }
    let cpu = cpu_name();
    eprintln!(
        "trabalhador {} → {} ({} ao mesmo tempo, modelo {}, {cpu})",
        args.name,
        args.server,
        args.jobs,
        args.model.name()
    );
    let agent = ureq::Agent::config_builder()
        .timeout_connect(Some(Duration::from_secs(10)))
        .timeout_recv_response(Some(Duration::from_secs(60)))
        .http_status_as_error(false)
        .user_agent(concat!("bk-analyzer-worker/", env!("CARGO_PKG_VERSION")))
        .build()
        .into();
    let ctx = Arc::new(Ctx { args, cpu, agent });
    let handles: Vec<_> = (0..ctx.args.jobs)
        .map(|slot| {
            let ctx = ctx.clone();
            std::thread::Builder::new().name(format!("job{slot}")).spawn(move || ctx.job_loop(slot)).expect("thread")
        })
        .collect();
    for h in handles {
        let _ = h.join();
    }
    Ok(())
}

impl Ctx {
    fn url(&self, path: &str) -> String {
        format!("{}/api/worker/{path}", self.args.server)
    }

    fn auth(&self) -> String {
        format!("Bearer {}", self.args.token)
    }

    fn post(&self, path: &str, body: &serde_json::Value) -> Result<ureq::http::Response<ureq::Body>, ureq::Error> {
        self.agent
            .post(&self.url(path))
            .header("Authorization", &self.auth())
            .header("Content-Type", "application/json")
            .send(&serde_json::to_vec(body).unwrap_or_default()[..])
    }

    fn job_loop(&self, slot: usize) {
        let cache = std::env::temp_dir().join(format!("bk-analyzer-{}-{slot}", std::process::id()));
        let analyzer = Analyzer::new(&self.args.models, &cache);
        analyzer.set_model(self.args.model);
        std::thread::sleep(Duration::from_secs(slot as u64 * 2));
        let mut warned = false;
        loop {
            let paused = (!self.args.on_battery && on_battery()).then(|| "na bateria".to_string());
            match self.claim(paused.as_deref()) {
                Ok(Some(job)) => {
                    warned = false;
                    self.process(&analyzer, job);
                }
                // Fila vazia: pergunta de novo logo (o player pode pedir uma música a qualquer hora).
                Ok(None) => std::thread::sleep(Duration::from_secs(if paused.is_some() { 60 } else { 5 } + slot as u64 * 2)),
                Err(e) => {
                    if !warned || slot == 0 {
                        eprintln!("coordenador: {e:#}");
                    }
                    warned = true;
                    std::thread::sleep(Duration::from_secs(30 + slot as u64));
                }
            }
        }
    }

    fn claim(&self, paused: Option<&str>) -> Result<Option<Job>> {
        let body = json!({
            "name": self.args.name, "model": self.args.model.name(), "cpu": self.cpu, "jobs": self.args.jobs,
            "paused": paused, "analysis_version": ANALYSIS_VERSION,
        });
        let mut resp = self.post("claim", &body)?;
        match resp.status().as_u16() {
            200 => Ok(Some(serde_json::from_slice(&resp.body_mut().read_to_vec()?)?)),
            204 => Ok(None),
            code => {
                let msg = resp.body_mut().read_to_string().unwrap_or_default();
                let msg = serde_json::from_str::<serde_json::Value>(&msg).ok().and_then(|v| v["error"].as_str().map(String::from)).unwrap_or(msg);
                bail!("HTTP {code}: {msg}")
            }
        }
    }

    fn download(&self, id: &str) -> Result<Vec<u8>> {
        let mut last = anyhow!("?");
        for attempt in 0..2 {
            if attempt > 0 {
                std::thread::sleep(Duration::from_secs(5));
            }
            let resp = match self.agent.get(&self.url(&format!("audio/{}", crate::navidrome::enc(id)))).header("Authorization", &self.auth()).call() {
                Ok(r) => r,
                Err(e) => {
                    last = anyhow!("download: {e}");
                    continue;
                }
            };
            let status = resp.status().as_u16();
            if status != 200 {
                let mut resp = resp;
                let msg = resp.body_mut().read_to_string().unwrap_or_default();
                let msg = serde_json::from_str::<serde_json::Value>(&msg).ok().and_then(|v| v["error"].as_str().map(String::from)).unwrap_or(msg);
                last = anyhow!("download: HTTP {status} {msg}");
                if status == 404 {
                    break;
                }
                continue;
            }
            let mut data = Vec::new();
            match resp.into_body().into_reader().take(2 << 30).read_to_end(&mut data) {
                Ok(_) if !data.is_empty() => return Ok(data),
                Ok(_) => last = anyhow!("download: arquivo vazio"),
                Err(e) => last = anyhow!("download interrompido: {e}"),
            }
        }
        Err(last)
    }

    fn beat(&self, id: &str) {
        let _ = self.post(&format!("beat/{}", crate::navidrome::enc(id)), &json!({"name": self.args.name}));
    }

    fn process(&self, analyzer: &Analyzer, job: Job) {
        let t = Instant::now();
        let done = AtomicBool::new(false);
        let result: Result<TrackAnalysis> = std::thread::scope(|s| {
            // Sinal de vida enquanto baixa e analisa.
            s.spawn(|| {
                let mut last = Instant::now();
                while !done.load(Ordering::Relaxed) {
                    std::thread::sleep(Duration::from_millis(500));
                    if last.elapsed() >= Duration::from_secs(30) {
                        self.beat(&job.id);
                        last = Instant::now();
                    }
                }
            });
            let r = self.download(&job.id).and_then(|data| {
                let ext = (!job.suffix.is_empty()).then_some(job.suffix.as_str());
                match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| analyzer.analyze_uncached(Box::new(Cursor::new(data)), ext))) {
                    Ok(r) => r.context("análise"),
                    Err(p) => Err(anyhow!("a análise travou: {}", panic_text(&p))),
                }
            });
            done.store(true, Ordering::Relaxed);
            r
        });
        let secs = t.elapsed().as_secs_f32();
        let who = format!("{} — {}", job.artist, job.title);
        let body = match &result {
            Ok(a) => {
                let (head, tail) = a.sync_ends();
                eprintln!(
                    "{} {who} ({secs:.1} s, {} BPM, entrada {} saída {})",
                    if head && tail { "✓" } else { "·" },
                    a.bpm.map(|b| format!("{b:.1}")).unwrap_or("?".into()),
                    if head { "✓" } else { "✗" },
                    if tail { "✓" } else { "✗" }
                );
                json!({"name": self.args.name, "secs": secs, "model": analyzer.model().name(), "analysis": a})
            }
            Err(e) => {
                eprintln!("✗ {who}: {e:#}");
                json!({"name": self.args.name, "secs": secs, "model": analyzer.model().name(), "error": format!("{e:#}")})
            }
        };
        // O resultado custou caro: insiste um pouco se o coordenador sumir.
        for attempt in 0..6 {
            if attempt > 0 {
                std::thread::sleep(Duration::from_secs(10));
            }
            match self.post(&format!("done/{}", crate::navidrome::enc(&job.id)), &body) {
                Ok(r) if r.status().as_u16() == 200 => return,
                Ok(r) => eprintln!("coordenador recusou o resultado: HTTP {}", r.status().as_u16()),
                Err(e) => eprintln!("coordenador: {e}"),
            }
        }
    }
}

fn panic_text(p: &Box<dyn std::any::Any + Send>) -> String {
    p.downcast_ref::<&str>().map(|s| s.to_string()).or_else(|| p.downcast_ref::<String>().cloned()).unwrap_or_else(|| "pânico".into())
}

fn cpu_name() -> String {
    std::fs::read_to_string("/proc/cpuinfo")
        .ok()
        .and_then(|c| c.lines().find(|l| l.starts_with("model name")).and_then(|l| l.split(':').nth(1)).map(|s| s.trim().to_string()))
        .unwrap_or_else(|| std::env::consts::ARCH.into())
}

/// Na bateria: tem fonte de tomada e nenhuma está ligada.
fn on_battery() -> bool {
    let Ok(rd) = std::fs::read_dir("/sys/class/power_supply") else { return false };
    let mut mains = false;
    for e in rd.flatten() {
        let p = e.path();
        if std::fs::read_to_string(p.join("type")).is_ok_and(|t| t.trim() == "Mains") {
            mains = true;
            if std::fs::read_to_string(p.join("online")).is_ok_and(|o| o.trim() == "1") {
                return false;
            }
        }
    }
    mains
}
