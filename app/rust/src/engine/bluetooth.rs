//! Player do Bluetooth (AVRCP) no Linux: registra o app no BlueZ como o player
//! das caixas, fones e carros conectados. Os botões do aparelho (tocar,
//! pausar, próxima, anterior) chegam aqui, e o aparelho recebe o estado
//! (tocando/pausado) e o nome da música.
//!
//! Faz o papel do `mpris-proxy` só para este app: o BlueZ entrega os botões ao
//! primeiro player registrado, e o `mpris-proxy` costuma registrar antes outros
//! players (ex.: o celular via KDE Connect), aí os botões vão para o lugar
//! errado. Com o app fechado, o registro some e os botões voltam a ser teclas
//! de mídia comuns do sistema.

use std::collections::HashMap;

use zbus::blocking::Connection;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{ObjectPath, OwnedValue, Value};

use super::{EngineEvent, EventCallback, MediaAction};

const PATH: &str = "/io/github/bkplayer/avrcp";

struct BtPlayer {
    cb: EventCallback,
    status: String,
    title: String,
    artist: String,
    album: String,
    length_us: i64,
    position_us: i64,
}

impl BtPlayer {
    fn send(&self, a: MediaAction) {
        (self.cb)(EngineEvent::MediaControl(a));
    }

    fn metadata_map(&self) -> HashMap<String, OwnedValue> {
        let mut m = HashMap::new();
        let mut put = |k: &str, v: Value<'_>| {
            if let Ok(v) = v.try_to_owned() {
                m.insert(k.to_string(), v);
            }
        };
        put("mpris:trackid", Value::from(ObjectPath::from_static_str_unchecked("/io/github/bkplayer/track")));
        put("xesam:title", Value::from(self.title.as_str()));
        put("xesam:artist", Value::from(vec![self.artist.as_str()]));
        put("xesam:album", Value::from(self.album.as_str()));
        if self.length_us > 0 {
            put("mpris:length", Value::from(self.length_us));
        }
        m
    }
}

#[zbus::interface(name = "org.mpris.MediaPlayer2.Player")]
impl BtPlayer {
    fn play(&self) {
        self.send(MediaAction::Play);
    }
    fn pause(&self) {
        self.send(MediaAction::Pause);
    }
    fn play_pause(&self) {
        self.send(MediaAction::Toggle);
    }
    fn stop(&self) {
        self.send(MediaAction::Pause);
    }
    fn next(&self) {
        self.send(MediaAction::Next);
    }
    fn previous(&self) {
        self.send(MediaAction::Previous);
    }

    #[zbus(property)]
    fn playback_status(&self) -> String {
        self.status.clone()
    }
    #[zbus(property)]
    fn loop_status(&self) -> String {
        "None".into()
    }
    #[zbus(property)]
    fn shuffle(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn metadata(&self) -> HashMap<String, OwnedValue> {
        self.metadata_map()
    }
    #[zbus(property)]
    fn position(&self) -> i64 {
        self.position_us
    }
    #[zbus(property)]
    fn rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_play(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_pause(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_control(&self) -> bool {
        true
    }
}

pub struct Bluetooth {
    conn: Connection,
}

impl Bluetooth {
    /// Conecta no barramento do sistema e registra o player em cada adaptador.
    /// None se não há BlueZ (ou sem permissão): o resto do app segue normal.
    pub fn new(cb: EventCallback) -> Option<Self> {
        let conn = Connection::system().ok()?;
        let player = BtPlayer {
            cb,
            status: "Stopped".into(),
            title: String::new(),
            artist: String::new(),
            album: String::new(),
            length_us: 0,
            position_us: 0,
        };
        conn.object_server().at(PATH, player).ok()?;
        let bt = Self { conn };
        let n = bt.register_all();
        eprintln!("bluetooth: player registrado no BlueZ em {n} adaptador(es)");
        Some(bt)
    }

    /// Adaptadores com a interface de mídia do BlueZ.
    fn adapters(&self) -> Vec<String> {
        let reply = self.conn.call_method(
            Some("org.bluez"),
            "/",
            Some("org.freedesktop.DBus.ObjectManager"),
            "GetManagedObjects",
            &(),
        );
        let Ok(reply) = reply else { return Vec::new() };
        type Objects = HashMap<zbus::zvariant::OwnedObjectPath, HashMap<String, HashMap<String, OwnedValue>>>;
        let Ok(objects) = reply.body().deserialize::<Objects>() else { return Vec::new() };
        objects
            .into_iter()
            .filter(|(_, ifaces)| ifaces.contains_key("org.bluez.Media1"))
            .map(|(p, _)| p.to_string())
            .collect()
    }

    fn register_all(&self) -> usize {
        let mut ok = 0;
        for adapter in self.adapters() {
            let mut props: HashMap<&str, Value<'_>> = HashMap::new();
            props.insert("PlaybackStatus", Value::from("Stopped"));
            props.insert("LoopStatus", Value::from("None"));
            props.insert("Shuffle", Value::from(false));
            props.insert("Position", Value::from(0i64));
            props.insert("Rate", Value::from(1.0f64));
            props.insert("MinimumRate", Value::from(1.0f64));
            props.insert("MaximumRate", Value::from(1.0f64));
            props.insert("CanGoNext", Value::from(true));
            props.insert("CanGoPrevious", Value::from(true));
            props.insert("CanPlay", Value::from(true));
            props.insert("CanPause", Value::from(true));
            props.insert("CanSeek", Value::from(false));
            props.insert("CanControl", Value::from(true));
            let path = ObjectPath::from_static_str_unchecked(PATH);
            match self.conn.call_method(Some("org.bluez"), adapter.as_str(), Some("org.bluez.Media1"), "RegisterPlayer", &(path, props)) {
                Ok(_) => ok += 1,
                Err(e) => eprintln!("bluetooth: RegisterPlayer em {adapter} falhou: {e}"),
            }
        }
        ok
    }

    fn update(&self, f: impl FnOnce(&mut BtPlayer) -> (bool, bool)) {
        let Ok(iface) = self.conn.object_server().interface::<_, BtPlayer>(PATH) else { return };
        let (status_changed, meta_changed) = f(&mut iface.get_mut());
        let emitter: &SignalEmitter<'static> = iface.signal_emitter();
        let player = iface.get();
        if status_changed {
            let _ = zbus::block_on(player.playback_status_changed(emitter));
            let _ = zbus::block_on(player.position_changed(emitter));
        }
        if meta_changed {
            let _ = zbus::block_on(player.metadata_changed(emitter));
        }
    }

    pub fn set_metadata(&self, title: &str, artist: &str, album: &str, duration_ms: Option<u64>) {
        self.update(|p| {
            let changed = p.title != title || p.artist != artist || p.album != album;
            p.title = title.to_string();
            p.artist = artist.to_string();
            p.album = album.to_string();
            p.length_us = duration_ms.map(|d| d as i64 * 1000).unwrap_or(0);
            (false, changed)
        });
    }

    pub fn set_playback(&self, playing: bool, has_track: bool, position_ms: Option<u64>) {
        let status = match (has_track, playing) {
            (false, _) => "Stopped",
            (true, true) => "Playing",
            (true, false) => "Paused",
        };
        self.update(|p| {
            let changed = p.status != status;
            p.status = status.to_string();
            if let Some(ms) = position_ms {
                p.position_us = ms as i64 * 1000;
            }
            (changed, false)
        });
    }
}
