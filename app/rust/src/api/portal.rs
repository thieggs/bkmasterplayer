//! Confere o anúncio do portal para o Dart.
//!
//! Só a conferência mora no app: assinar exige a chave particular, que
//! nunca sai da máquina de casa. Ver [`crate::portal`].

use flutter_rust_bridge::frb;

use crate::portal;

/// O que o app aprendeu do anúncio.
pub struct PortalNotice {
    /// Nome que o dono deu ao servidor.
    pub name: String,
    /// Endereço do Navidrome agora.
    pub music: String,
    /// Endereço da análise do AutoMix, quando o portal serve uma.
    pub analysis: Option<String>,
    /// Chave pública de quem assinou, para o app guardar na primeira vez.
    pub key: String,
    /// A mesma chave em grupos legíveis, para conferir de viva voz.
    pub fingerprint: String,
    /// Até quando este anúncio vale (segundos desde 1970).
    pub expires: u64,
}

/// Lê um anúncio baixado.
///
/// `pinned_key` é a chave que o app guardou da primeira vez; passe vazio
/// quando ainda não há nenhuma. Devolve erro (com o motivo em português)
/// quando o anúncio não presta, e nunca aceita um assinado por outra chave.
#[frb(sync)]
pub fn portal_read(raw: Vec<u8>, pinned_key: String) -> Result<PortalNotice, String> {
    let pinned = (!pinned_key.trim().is_empty()).then(|| pinned_key.trim().to_string());
    match portal::verify(&raw, pinned.as_deref(), portal::now()) {
        Ok(n) => Ok(PortalNotice {
            name: n.name,
            music: n.music,
            analysis: n.analysis,
            fingerprint: portal::fingerprint(&n.key),
            key: n.key,
            expires: n.expires,
        }),
        Err(e) => Err(e.to_string()),
    }
}

/// Impressão digital de uma chave já fixada, para mostrar nos Ajustes.
///
/// Mesmo cálculo do `bk-portal link`, para os dois textos baterem quando a
/// pessoa confere de viva voz.
#[frb(sync)]
pub fn portal_fingerprint(key: String) -> String {
    portal::fingerprint(key.trim())
}

/// Caminho onde o anúncio fica dentro de um portal.
#[frb(sync)]
pub fn portal_notice_path() -> String {
    portal::NOTICE_PATH.to_string()
}

/// Tamanho máximo que vale a pena baixar de um anúncio.
#[frb(sync)]
pub fn portal_max_bytes() -> u32 {
    portal::MAX_BYTES as u32
}
