//! Integração com o sistema no desktop:
//! - controles de mídia (MPRIS no Linux, SMTC no Windows, macOS) com capa como
//!   arquivo local — é o que KDE Connect/GSConnect repassam pro celular;
//! - notificação de troca de música que **substitui** a anterior em vez de empilhar.

use std::path::PathBuf;
use std::sync::mpsc;
use std::time::Duration;

use souvlaki::{MediaControlEvent, MediaControls, MediaMetadata, MediaPlayback, MediaPosition, PlatformConfig, SeekDirection};

use super::{EngineEvent, EventCallback, MediaAction};

/// Acha a janela do próprio app, que o Windows exige para os controles de
/// mídia.
///
/// O SMTC é preso a uma janela, e o souvlaki entra em **pânico** se receber
/// `hwnd: None` — no Linux o MPRIS não precisa de nada disso, então passar
/// `None` funcionava. Procura entre as janelas de topo a que pertence a este
/// processo.
#[cfg(target_os = "windows")]
mod own_window {
    use std::sync::atomic::{AtomicIsize, Ordering};

    #[link(name = "user32")]
    extern "system" {
        fn EnumWindows(cb: unsafe extern "system" fn(isize, isize) -> i32, lparam: isize) -> i32;
        fn GetWindowThreadProcessId(hwnd: isize, pid: *mut u32) -> u32;
        fn IsWindowVisible(hwnd: isize) -> i32;
        fn GetWindow(hwnd: isize, cmd: u32) -> isize;
    }
    #[link(name = "kernel32")]
    extern "system" {
        fn GetCurrentProcessId() -> u32;
    }

    /// GW_OWNER: quem tem dono é caixa de diálogo, não a janela principal.
    const GW_OWNER: u32 = 4;
    static FOUND: AtomicIsize = AtomicIsize::new(0);

    unsafe extern "system" fn visit(hwnd: isize, wanted_pid: isize) -> i32 {
        let mut pid = 0u32;
        GetWindowThreadProcessId(hwnd, &mut pid);
        if pid as isize == wanted_pid && IsWindowVisible(hwnd) != 0 && GetWindow(hwnd, GW_OWNER) == 0 {
            FOUND.store(hwnd, Ordering::SeqCst);
            return 0; // achou: para de enumerar
        }
        1
    }

    pub fn find() -> Option<*mut std::ffi::c_void> {
        FOUND.store(0, Ordering::SeqCst);
        // SAFETY: EnumWindows só chama `visit`, que lê propriedades da janela
        // e grava num atômico.
        unsafe {
            let me = GetCurrentProcessId() as isize;
            EnumWindows(visit, me);
        }
        match FOUND.load(Ordering::SeqCst) {
            0 => None,
            h => Some(h as *mut std::ffi::c_void),
        }
    }
}

pub struct NotifyMsg {
    pub title: String,
    pub body: String,
    pub image: Option<PathBuf>,
}

/// Quantas vezes tentar achar a janela antes de desistir dos controles.
#[cfg(target_os = "windows")]
const RETRIES: u8 = 10;

pub struct Desktop {
    controls: Option<MediaControls>,
    notifier: mpsc::Sender<NotifyMsg>,
    /// No Windows os controles só nascem depois da janela; o que falta para
    /// tentar de novo fica guardado aqui (`None` = já deu certo ou desistiu).
    #[cfg(target_os = "windows")]
    later: Option<(String, String, EventCallback, u8)>,
    /// Player registrado no BlueZ (botões de caixa/fone/carro).
    #[cfg(target_os = "linux")]
    bluetooth: Option<super::bluetooth::Bluetooth>,
}

/// Monta os controles de mídia do sistema, ou `None` se não der.
///
/// No Windows precisa da janela do app; se ela ainda não existe (o motor
/// inicia junto com a interface), devolve `None` e quem chamou tenta de novo
/// depois. Nunca passa `hwnd: None` adiante: o souvlaki entra em pânico.
fn make_controls(app_id: &str, app_name: &str, callback: &EventCallback) -> Option<MediaControls> {
    #[cfg(target_os = "windows")]
    let hwnd = match own_window::find() {
        Some(h) => Some(h),
        None => {
            log::debug!("janela ainda não existe; controles de mídia depois");
            return None;
        }
    };
    #[cfg(not(target_os = "windows"))]
    let hwnd = None;

    match MediaControls::new(PlatformConfig {
            dbus_name: app_id,
            display_name: app_name,
            hwnd,
        }) {
            Ok(mut c) => {
                let cb = callback.clone();
                let attached = c.attach(move |ev: MediaControlEvent| {
                    let action = match ev {
                        MediaControlEvent::Play => MediaAction::Play,
                        MediaControlEvent::Pause => MediaAction::Pause,
                        MediaControlEvent::Toggle => MediaAction::Toggle,
                        MediaControlEvent::Next => MediaAction::Next,
                        MediaControlEvent::Previous => MediaAction::Previous,
                        MediaControlEvent::Stop => MediaAction::Stop,
                        MediaControlEvent::Seek(SeekDirection::Forward) => MediaAction::SeekBy(10_000),
                        MediaControlEvent::Seek(SeekDirection::Backward) => MediaAction::SeekBy(-10_000),
                        MediaControlEvent::SeekBy(dir, d) => {
                            let ms = d.as_millis() as i64;
                            MediaAction::SeekBy(if dir == SeekDirection::Forward { ms } else { -ms })
                        }
                        MediaControlEvent::SetPosition(MediaPosition(p)) => MediaAction::SeekTo(p.as_millis() as u64),
                        MediaControlEvent::SetVolume(v) => MediaAction::SetVolume(v),
                        MediaControlEvent::Raise => MediaAction::Raise,
                        MediaControlEvent::Quit => MediaAction::Quit,
                        MediaControlEvent::OpenUri(_) => return,
                    };
                    cb(EngineEvent::MediaControl(action));
                });
                match attached {
                    Ok(()) => Some(c),
                    Err(e) => {
                        log::warn!("controles de mídia indisponíveis: {e:?}");
                        None
                    }
                }
            }
            Err(e) => {
                log::warn!("controles de mídia indisponíveis: {e:?}");
                None
            }
    }
}

impl Desktop {
    pub fn new(app_id: &str, app_name: &str, callback: EventCallback) -> Self {
        let controls = make_controls(app_id, app_name, &callback);
        #[cfg(target_os = "windows")]
        let later = controls
            .is_none()
            .then(|| (app_id.to_string(), app_name.to_string(), callback.clone(), RETRIES));

        let (tx, rx) = mpsc::channel::<NotifyMsg>();
        let app = app_name.to_string();
        let tag = app_id.to_string();
        let _ = std::thread::Builder::new()
            .name("notifier".into())
            .spawn(move || notifier_loop(rx, app, tag));

        Self {
            controls,
            notifier: tx,
            #[cfg(target_os = "windows")]
            later,
            #[cfg(target_os = "linux")]
            bluetooth: super::bluetooth::Bluetooth::new(callback),
        }
    }

    /// Tenta de novo os controles do Windows, agora que há música tocando e a
    /// janela certamente existe. Desiste depois de algumas tentativas para não
    /// varrer as janelas do sistema a cada faixa.
    #[cfg(target_os = "windows")]
    fn controls_later(&mut self) {
        let Some((id, name, cb, left)) = self.later.as_mut() else { return };
        if *left == 0 {
            self.later = None;
            return;
        }
        *left -= 1;
        if let Some(c) = make_controls(id, name, cb) {
            self.controls = Some(c);
            self.later = None;
        }
    }

    pub fn set_metadata(
        &mut self,
        title: &str,
        artist: &str,
        album: &str,
        cover: Option<&std::path::Path>,
        duration_ms: Option<u64>,
    ) {
        // Tocou música: a janela já existe, então vale tentar de novo.
        #[cfg(target_os = "windows")]
        self.controls_later();
        #[cfg(target_os = "linux")]
        if let Some(bt) = &self.bluetooth {
            bt.set_metadata(title, artist, album, duration_ms);
        }
        let Some(c) = self.controls.as_mut() else { return };
        let cover_url = cover.map(file_url);
        let _ = c.set_metadata(MediaMetadata {
            title: Some(title),
            artist: Some(artist),
            album: Some(album),
            cover_url: cover_url.as_deref(),
            duration: duration_ms.map(Duration::from_millis),
        });
    }

    pub fn set_playback(&mut self, playing: bool, has_track: bool, position_ms: Option<u64>) {
        #[cfg(target_os = "linux")]
        if let Some(bt) = &self.bluetooth {
            bt.set_playback(playing, has_track, position_ms);
        }
        let Some(c) = self.controls.as_mut() else { return };
        let progress = position_ms.map(|p| MediaPosition(Duration::from_millis(p)));
        let state = match (has_track, playing) {
            (false, _) => MediaPlayback::Stopped,
            (true, true) => MediaPlayback::Playing { progress },
            (true, false) => MediaPlayback::Paused { progress },
        };
        let _ = c.set_playback(state);
    }

    pub fn set_volume(&mut self, volume: f64) {
        #[cfg(target_os = "linux")]
        if let Some(c) = self.controls.as_mut() {
            let _ = c.set_volume(volume);
        }
        #[cfg(not(target_os = "linux"))]
        let _ = volume;
    }

    pub fn notify(&self, msg: NotifyMsg) {
        let _ = self.notifier.send(msg);
    }
}

fn file_url(p: &std::path::Path) -> String {
    let s = p.to_string_lossy();
    let mut out = String::from("file://");
    #[cfg(windows)]
    out.push('/');
    for b in s.replace('\\', "/").bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'/' | b'-' | b'_' | b'.' | b'~' | b':' => out.push(b as char),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

const NOTIFY_TIMEOUT: Duration = Duration::from_millis(5000);

/// Mostra só a notificação mais recente. Se a anterior ainda está na tela, é
/// substituída no lugar (sem empilhar). Se já expirou, é fechada e uma nova é
/// mostrada — alguns servidores (KDE Plasma) atualizam em silêncio uma
/// notificação expirada em vez de mostrar o popup de novo.
#[cfg(all(unix, not(target_os = "macos")))]
fn notifier_loop(rx: mpsc::Receiver<NotifyMsg>, app: String, tag: String) {
    use std::time::Instant;
    let mut last: Option<(notify_rust::NotificationHandle, Instant)> = None;
    while let Ok(mut msg) = rx.recv() {
        std::thread::sleep(Duration::from_millis(150));
        while let Ok(newer) = rx.try_recv() {
            msg = newer;
        }
        let mut n = notify_rust::Notification::new();
        n.appname(&app)
            .summary(&msg.title)
            .body(&msg.body)
            .timeout(notify_rust::Timeout::Milliseconds(NOTIFY_TIMEOUT.as_millis() as u32))
            .hint(notify_rust::Hint::Transient(true))
            .hint(notify_rust::Hint::Custom("x-canonical-private-synchronous".into(), tag.clone()))
            .hint(notify_rust::Hint::Category("x-gnome.music".into()));
        if let Some(img) = msg.image.as_ref().and_then(|p| p.to_str()) {
            n.image_path(img);
        }
        if let Some((handle, shown_at)) = last.take() {
            if shown_at.elapsed() < NOTIFY_TIMEOUT - Duration::from_millis(300) {
                n.id(handle.id());
            } else {
                handle.close();
            }
        }
        match n.show() {
            Ok(handle) => last = Some((handle, Instant::now())),
            Err(e) => log::debug!("notificação falhou: {e}"),
        }
    }
}

#[cfg(not(all(unix, not(target_os = "macos"))))]
fn notifier_loop(rx: mpsc::Receiver<NotifyMsg>, app: String, tag: String) {
    // Windows: toasts com o mesmo id substituem o anterior na Central de Ações.
    let _ = &tag;
    while let Ok(mut msg) = rx.recv() {
        std::thread::sleep(Duration::from_millis(150));
        while let Ok(newer) = rx.try_recv() {
            msg = newer;
        }
        let mut n = notify_rust::Notification::new();
        n.appname(&app)
            .summary(&msg.title)
            .body(&msg.body)
            .timeout(notify_rust::Timeout::Milliseconds(NOTIFY_TIMEOUT.as_millis() as u32))
            .id(1);
        if let Some(img) = msg.image.as_ref().and_then(|p| p.to_str()) {
            n.image_path(img);
        }
        if let Err(e) = n.show() {
            log::debug!("notificação falhou: {e}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::file_url;

    #[test]
    fn file_url_escapes() {
        #[cfg(not(windows))]
        assert_eq!(
            file_url(std::path::Path::new("/home/a b/capa (1).jpg")),
            "file:///home/a%20b/capa%20%281%29.jpg"
        );
    }
}
