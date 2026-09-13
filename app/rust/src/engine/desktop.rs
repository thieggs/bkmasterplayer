//! Integração com o sistema no desktop:
//! - controles de mídia (MPRIS no Linux, SMTC no Windows, macOS) com capa como
//!   arquivo local — é o que KDE Connect/GSConnect repassam pro celular;
//! - notificação de troca de música que **substitui** a anterior em vez de empilhar.

use std::path::PathBuf;
use std::sync::mpsc;
use std::time::Duration;

use souvlaki::{MediaControlEvent, MediaControls, MediaMetadata, MediaPlayback, MediaPosition, PlatformConfig, SeekDirection};

use super::{EngineEvent, EventCallback, MediaAction};

pub struct NotifyMsg {
    pub title: String,
    pub body: String,
    pub image: Option<PathBuf>,
}

pub struct Desktop {
    controls: Option<MediaControls>,
    notifier: mpsc::Sender<NotifyMsg>,
}

impl Desktop {
    pub fn new(app_id: &str, app_name: &str, callback: EventCallback) -> Self {
        let controls = match MediaControls::new(PlatformConfig {
            dbus_name: app_id,
            display_name: app_name,
            hwnd: None,
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
        };

        let (tx, rx) = mpsc::channel::<NotifyMsg>();
        let app = app_name.to_string();
        let tag = app_id.to_string();
        let _ = std::thread::Builder::new()
            .name("notifier".into())
            .spawn(move || notifier_loop(rx, app, tag));

        Self { controls, notifier: tx }
    }

    pub fn set_metadata(
        &mut self,
        title: &str,
        artist: &str,
        album: &str,
        cover: Option<&std::path::Path>,
        duration_ms: Option<u64>,
    ) {
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

/// Mostra só a notificação mais recente, reaproveitando o id da anterior.
fn notifier_loop(rx: mpsc::Receiver<NotifyMsg>, app: String, tag: String) {
    let mut last_id: Option<u32> = None;
    while let Ok(mut msg) = rx.recv() {
        // Se chegaram várias em sequência (trocas rápidas), fica só com a última.
        std::thread::sleep(Duration::from_millis(150));
        while let Ok(newer) = rx.try_recv() {
            msg = newer;
        }
        let mut n = notify_rust::Notification::new();
        n.appname(&app).summary(&msg.title).body(&msg.body).timeout(notify_rust::Timeout::Milliseconds(5000));
        if let Some(img) = msg.image.as_ref().and_then(|p| p.to_str()) {
            n.image_path(img);
        }
        #[cfg(all(unix, not(target_os = "macos")))]
        {
            n.hint(notify_rust::Hint::Transient(true));
            n.hint(notify_rust::Hint::Custom("x-canonical-private-synchronous".into(), tag.clone()));
            n.hint(notify_rust::Hint::Category("x-gnome.music".into()));
        }
        #[cfg(not(all(unix, not(target_os = "macos"))))]
        let _ = &tag;
        if let Some(id) = last_id {
            n.id(id);
        }
        match n.show() {
            #[cfg(all(unix, not(target_os = "macos")))]
            Ok(handle) => last_id = Some(handle.id()),
            #[cfg(not(all(unix, not(target_os = "macos"))))]
            Ok(_) => last_id = Some(1),
            Err(e) => log::debug!("notificação falhou: {e}"),
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
