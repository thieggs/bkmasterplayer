# Install on iPhone

> 🇧🇷 [Versão em português](#português) mais abaixo.

*Checked in November 2026, with iOS 26 and iOS 27.*

The `.ipa` in the [releases](https://github.com/thieggs/bkmasterplayer/releases)
is **unsigned**. That is not a mistake — Apple only lets signed apps run, and
the tools below sign it with *your own* Apple ID as they install it. A free
Apple ID is enough.

## Before you start

- **iPhone with a passcode**, iOS 15 or later.
- **A computer** — Linux, Windows or Mac — and a USB cable. Every path needs
  it at least once.
- **An Apple ID.** It does not have to be the one on the phone; a spare free
  account works and keeps your main one out of it.
- **One tool per Apple ID.** A free Apple ID holds very few signing
  certificates, and each tool that signs with it (iloader, SideStore,
  Sideloadly, Impactor, another device) creates a new one and revokes the old.
  Mixing tools is the usual reason an app that installed fine stops opening.
- **Limits of a free Apple ID:** signatures last **7 days**; at most **3 apps**
  installed this way at once (SideStore and LiveContainer count); at most **10
  new app IDs per 7 days**.
- **Developer Mode** has to be on. The switch only shows up after the first
  app is installed — the steps below say when.

## Pick a path

| | computer | renews itself | new versions |
|---|---|---|---|
| **1. iloader** | every 7 days, by cable | no — plug in and redo | download the `.ipa`, plug in |
| **2. SideStore** | **once** | **yes**, on the phone | **on the phone**, from the source |
| **3. LiveContainer + SideStore** | once | yes, on the phone | on the phone; many apps in one slot |

Path 1 takes ten minutes. Path 2 takes longer to set up and then stops
bothering you. Path 3 is path 2 for people who already use the three slots.

All three start with **iloader**, a free, open-source program that runs on
Linux, Windows and Mac. Download it **only** from
[github.com/nab138/iloader/releases](https://github.com/nab138/iloader/releases)
or [iloader.app](https://iloader.app) — copies elsewhere are not official.

- **Linux:** install `usbmuxd` (Debian/Ubuntu: `sudo apt install usbmuxd`;
  often already there), then the iloader `.deb`, `.rpm` or `.AppImage`. If
  iloader does not see the phone, run `sudo systemctl stop usbmuxd` and then
  `sudo usbmuxd -v -f` in another terminal, and try again.
- **Windows (64-bit):** install iTunes (from the Microsoft Store or from
  Apple), then the iloader `.msi`.
- **Mac:** the iloader `.dmg`; nothing else.

---

## 1. iloader — install the app directly

1. Plug the iPhone in by cable, unlock it, tap **Trust** and type the passcode.
2. Open iloader and **Sign in** with your Apple ID (it asks for the two-factor
   code).
3. Pick the iPhone.
4. **Import IPA** → choose `BKmasterplayer-*.ipa` from the
   [releases](https://github.com/thieggs/bkmasterplayer/releases).
5. On the iPhone: **Settings → General → VPN & Device Management →** your
   Apple ID under *Developer App* **→ Trust**.
6. **Settings → Privacy & Security →** scroll to the bottom **→ Developer
   Mode → on**. The phone restarts; confirm with **Turn On** and the passcode.

Now it opens. **Every 7 days**, when it stops opening, plug in and repeat
steps 1–4 — your data and settings stay.

## 2. SideStore — renews on the phone

SideStore runs on the phone and re-signs the app before the 7 days run out.
It reaches the phone's own system through **LocalDevVPN**, a local VPN app
(nothing leaves the phone).

1. On the iPhone, install **LocalDevVPN** from the App Store, open it and tap
   **Connect** (allow the VPN configuration).
2. In iloader: **Installers → SideStore (Stable)**. It also places the
   *pairing file* SideStore needs.
3. On the iPhone: trust the developer and turn on Developer Mode (steps 5 and
   6 of path 1).
4. Open SideStore → **Settings** → sign in with the **same** Apple ID you used
   in iloader. Getting **-80045** or **-80046**? See
   [the sign-in error](#sidestore-sign-in-error--80045---80046) below.
5. **My Apps** → tap the **7 DAYS** counter next to SideStore to refresh it. If
   it asks to revoke or create a certificate, say yes. SideStore closes and
   comes back.
6. **Sources → +** and paste the BKmasterplayer source:

   ```
   https://github.com/thieggs/bkmasterplayer/releases/latest/download/sidestore.json
   ```

7. Open the source → **BKmasterplayer → Free**.

From then on, with **Wi-Fi on and LocalDevVPN connected**, open SideStore now
and then and tap **My Apps → Refresh All** before the counter reaches zero.

**New versions:** **My Apps → Update**. The update notice inside the app has an
**Open in SideStore** button that takes you there. Install from the
**source** at least once: an app added from a file (the **+** in My Apps) is
"sideloaded" to SideStore, and it never offers updates for it. Reinstalling
from the source replaces the same app, data included.

The **pairing file** expires when you update or reset the phone, and sometimes
at random. Then: plug in, iloader → **Manage Pairing File → Place Pairing
File** next to SideStore.

### SideStore sign-in error (-80045 / -80046)

Since mid-October 2026 Apple rejects the sign-in data ("anisette") SideStore
uses by default, and signing in fails with "This action cannot be completed
at this time (-80045)" or "ALTAppleAPIError -80046". Until SideStore ships a
fix, this worked for most people
([SideStore#1709](https://github.com/SideStore/SideStore/issues/1709)):

1. **Settings → User Customizations:** turn off **On-Device Anisette**; say yes
   if it asks to restart.
2. **Settings → Anisette Servers:** pick **SideStore (New)**; at the bottom,
   turn off **Enable Auto Rotation**.
3. **User Customizations → Anisette Client Configuration → Remote Server
   Sync:** tap **Fetch**, then **Save as Overrides**.
4. **User Customizations → Reset adi.pb**.
5. Sign in again. It can take a while.

If **iloader** is the one failing to sign in: update it (2.4.1 or later), then
in its settings change the **Anisette Server** and use **Reset Anisette State**.

## 3. LiveContainer + SideStore — many apps in one slot

LiveContainer holds any number of apps while using one of the three slots;
SideStore runs inside it. Get it through iloader (below) or from
[github.com/LiveContainer/LiveContainer](https://github.com/LiveContainer/LiveContainer)
only. GitHub hid that project from October 4, 2026 for a few weeks; it is back,
and the copies that circulated meanwhile are not official.

1. LocalDevVPN from the App Store, **Connect** (path 2, step 1).
2. In iloader: **Installers → LiveContainer + SideStore (Stable)**.
3. Trust the developer and turn on Developer Mode (path 1, steps 5 and 6).
4. In LiveContainer, **Apps** tab, tap the **SideStore** button (top left).
   In SideStore, **Settings**: sign in (sign out and in again if it already
   looks signed in — the built-in SideStore cannot read the saved password).
   Then **My Apps → Refresh All**. Leave SideStore (the quit icon in its Apps
   page).
5. In LiveContainer, **Settings → Import Certificate from Built-in
   SideStore → OK**. It worked if the button turns into **Remove
   Certificate**. **Settings → JIT-Less Mode Diagnose** should be all green.
6. **Sources** tab → **+** → the same source address as path 2 →
   **Install**.

Apps *inside* LiveContainer are signed by LiveContainer in **JIT-less mode**,
with SideStore's certificate. Until step 5 is done, installing fails with
"Failed to find signing certificate… JIT-Less Diagnose" or "Certificate not
found. Did you log into built-in SideStore?" — nothing wrong with the `.ipa`.
If step 5 keeps saying the certificate is missing: in the built-in SideStore,
**Settings → Export Signing Certificate…**, pick a password, save; then in
LiveContainer, **Settings → Import Certificate** with that file.

Inside LiveContainer, **updates** go through LiveContainer's **Sources** tab
(the app's **Open in SideStore** button falls back there), and **lock screen
controls** can misbehave for Flutter apps (a known LiveContainer issue). If
that bothers you, install BKmasterplayer as a normal app from the built-in
SideStore instead (path 2, steps 6 and 7).

---

## When something fails

| What you see | What it is | What to do |
|---|---|---|
| "Untrusted Developer" | the profile is not trusted yet | Settings → General → VPN & Device Management → Trust |
| the app does not open, or asks for Developer Mode | Developer Mode off | Settings → Privacy & Security → Developer Mode |
| **-80045** / **-80046** when signing in to SideStore | Apple rejecting SideStore's sign-in data | [the five steps above](#sidestore-sign-in-error--80045---80046) |
| "code signature is invalid", **Certificate Status: Revoked** | another tool signed with the same Apple ID | use one tool; in SideStore **Refresh All**; in LiveContainer **Remove Certificate** and import again; if it stays revoked, reinstall with iloader |
| "Maximum certificates reached" in iloader | too many certificates on the Apple ID | let iloader revoke the old one — apps signed with it (from other tools) stop opening |
| "pairing file" or "InvalidVPN" errors in SideStore | the pairing file expired, or the VPN is off | LocalDevVPN **Connect**, on Wi-Fi; iloader → **Manage Pairing File → Place Pairing File** |
| "maximum number of apps" | the 3-app limit | remove one app installed this way |
| "maximum App ID limit" | 10 new app IDs in 7 days | wait for the week to pass, or use another Apple ID |
| it worked for 7 days and stopped | the signature expired | path 1: plug in and redo; paths 2–3: refresh (data stays) |

## Other ways, with Apple's blessing

- **AltStore PAL (Brazil, EU, Japan).** Since June 18, 2026, iPhones in Brazil
  on **iOS 26.5 or later** can install alternative app stores, and **AltStore
  PAL** is already here: no computer, no 7-day limit, no three-app limit.
  BKmasterplayer is **not** there yet. For that, the developer needs a paid
  Apple Developer account (US$ 99 a year) and Apple's *notarization* of every
  version — a lighter review than the App Store's. Free apps pay no
  commission.
- **Paid Apple Developer account** (US$ 99 a year), with the same tools:
  signatures last a year instead of 7 days, the three-app limit goes away, and
  Connect's automatic list could be turned on (see below).

## What changes on iPhone

- **Connect** (choose which device plays) fills its list by UDP broadcast,
  which Apple only allows with an entitlement **paid** developer accounts can
  request. On iPhone the list stays empty, but **adding a device by its
  address** works.
- **Party** finds the others through Bonjour, which iOS allows without that
  entitlement. The first time, the iPhone asks for permission to use the local
  network — say yes.

Everything else — playback, AutoMix, AudioMuse, downloads, offline
recommendations — is the same.

---

## Português

*Conferido em novembro de 2026, com o iOS 26 e o iOS 27.*

O `.ipa` dos [releases](https://github.com/thieggs/bkmasterplayer/releases) sai
**sem assinatura**. Não é descuido: a Apple só deixa rodar app assinado, e os
programas abaixo assinam com o **seu próprio** Apple ID na hora de instalar.
Apple ID gratuito serve.

### Antes de começar

- **iPhone com código de acesso**, iOS 15 ou mais novo.
- **Um computador** — Linux, Windows ou Mac — e um cabo USB. Todo caminho
  precisa dele pelo menos uma vez.
- **Um Apple ID.** Não precisa ser o do celular; um gratuito reserva funciona
  e deixa a sua conta principal de fora.
- **Um programa só por Apple ID.** Apple ID gratuito guarda pouquíssimos
  certificados de assinatura, e cada programa que assina com ele (iloader,
  SideStore, Sideloadly, Impactor, outro aparelho) cria um novo e revoga o
  anterior. Misturar programas é o motivo comum de um app que instalou bem
  parar de abrir.
- **Limites do Apple ID gratuito:** a assinatura dura **7 dias**; no máximo
  **3 apps** instalados assim ao mesmo tempo (o SideStore e o LiveContainer
  contam); no máximo **10 IDs de app novos a cada 7 dias**.
- **Modo de Desenvolvedor** precisa estar ligado. A chave só aparece depois
  do primeiro app instalado — os passos abaixo dizem quando.

### Escolha o caminho

| | computador | renova sozinho | versão nova |
|---|---|---|---|
| **1. iloader** | a cada 7 dias, por cabo | não — liga o cabo e refaz | baixa o `.ipa` e liga o cabo |
| **2. SideStore** | **uma vez** | **sim**, no celular | **no celular**, pela fonte |
| **3. LiveContainer + SideStore** | uma vez | sim, no celular | no celular; vários apps numa vaga |

O caminho 1 leva dez minutos. O 2 dá mais trabalho para montar e depois para
de te incomodar. O 3 é o 2 para quem já usa as três vagas.

Os três começam pelo **iloader**, um programa gratuito e de código aberto que
roda no Linux, no Windows e no Mac (e fala português). Baixe **só** de
[github.com/nab138/iloader/releases](https://github.com/nab138/iloader/releases)
ou de [iloader.app](https://iloader.app) — cópias em outros lugares não são
oficiais.

- **Linux:** instale o `usbmuxd` (Debian/Ubuntu: `sudo apt install usbmuxd`;
  muitas vezes já vem), depois o `.deb`, `.rpm` ou `.AppImage` do iloader. Se
  o iloader não enxergar o celular, rode `sudo systemctl stop usbmuxd` e, em
  outro terminal, `sudo usbmuxd -v -f`, e tente de novo.
- **Windows (64 bits):** instale o iTunes (da Microsoft Store ou da Apple),
  depois o `.msi` do iloader.
- **Mac:** o `.dmg` do iloader; mais nada.

---

### 1. iloader — instalar o app direto

1. Ligue o iPhone no cabo, desbloqueie, toque em **Confiar** e digite o
   código.
2. Abra o iloader e toque em **Registrar** com o seu Apple ID (ele pede o
   código da verificação em duas etapas).
3. Escolha o iPhone.
4. **Importar IPA** → escolha o `BKmasterplayer-*.ipa` dos
   [releases](https://github.com/thieggs/bkmasterplayer/releases).
5. No iPhone: **Ajustes → Geral → VPN e Gerenciamento de Dispositivo →** o
   seu Apple ID em *App de Desenvolvedor* **→ Confiar**.
6. **Ajustes → Privacidade e Segurança →** role até o fim **→ Modo de
   Desenvolvedor → ligado**. O celular reinicia; confirme com **Ativar** e o
   código.

Agora abre. **A cada 7 dias**, quando parar de abrir, ligue o cabo e repita os
passos 1 a 4 — seus dados e ajustes continuam lá.

### 2. SideStore — renova no próprio celular

O SideStore roda no celular e reassina o app antes dos 7 dias vencerem. Ele
fala com o sistema do próprio celular pela **LocalDevVPN**, um app de VPN
local (nada sai do celular). O SideStore é só em inglês, então os nomes abaixo
são os dele.

1. No iPhone, instale a **LocalDevVPN** pela App Store, abra e toque em
   **Connect** (permita a configuração de VPN).
2. No iloader: **Instaladores → SideStore (Estável)**. Ele também coloca o
   *arquivo de pareamento* de que o SideStore precisa.
3. No iPhone: confie no desenvolvedor e ligue o Modo de Desenvolvedor (passos
   5 e 6 do caminho 1).
4. Abra o SideStore → **Settings** → entre com o **mesmo** Apple ID que usou no
   iloader. Deu **-80045** ou **-80046**? Veja
   [o erro de login](#erro-de-login-no-sidestore--80045---80046) abaixo.
5. **My Apps** → toque no contador **7 DAYS** ao lado do SideStore para
   renovar. Se perguntar sobre revogar ou criar certificado, diga que sim. O
   SideStore fecha e volta.
6. **Sources → +** e cole a fonte do BKmasterplayer:

   ```
   https://github.com/thieggs/bkmasterplayer/releases/latest/download/sidestore.json
   ```

7. Abra a fonte → **BKmasterplayer → Free**.

Daí em diante, com o **Wi-Fi ligado e a LocalDevVPN conectada**, abra o
SideStore de vez em quando e toque em **My Apps → Refresh All** antes de o
contador chegar a zero.

**Versão nova:** **My Apps → Update**. O aviso de atualização dentro do app tem
o botão **Abrir no SideStore**, que leva até lá. Instale **pela fonte** pelo
menos uma vez: app instalado pelo arquivo (o **+** de My Apps) fica marcado
como "por fora" no SideStore, e ele nunca oferece atualização para esse app.
Instalar de novo pela fonte substitui o mesmo app, com os dados.

O **arquivo de pareamento** vence quando você atualiza ou reseta o celular, e
às vezes do nada. Aí: ligue o cabo, iloader → **Gerenciar Arquivo de
Pareamento → Colocar Arquivo de Pareamento** ao lado do SideStore.

#### Erro de login no SideStore (-80045 / -80046)

Desde meados de outubro de 2026 a Apple recusa os dados de login ("anisette")
que o SideStore usa por padrão, e entrar falha com "This action cannot be
completed at this time (-80045)" ou "ALTAppleAPIError -80046". Até o SideStore
lançar o conserto, isto funcionou para a maioria
([SideStore#1709](https://github.com/SideStore/SideStore/issues/1709)):

1. **Settings → User Customizations:** desligue **On-Device Anisette**; diga
   que sim se pedir para reiniciar.
2. **Settings → Anisette Servers:** escolha **SideStore (New)**; lá embaixo,
   desligue **Enable Auto Rotation**.
3. **User Customizations → Anisette Client Configuration → Remote Server
   Sync:** toque em **Fetch** e depois em **Save as Overrides**.
4. **User Customizations → Reset adi.pb**.
5. Entre de novo. Pode demorar um pouco.

Se quem não consegue entrar é o **iloader**: atualize (2.4.1 ou mais novo) e,
nos ajustes dele, troque o **Servidor Anisette** e use **Reiniciar estado
Anisette**.

### 3. LiveContainer + SideStore — vários apps numa vaga

O LiveContainer guarda quantos apps quiser gastando uma das três vagas; o
SideStore roda dentro dele. Pegue pelo iloader (abaixo) ou só de
[github.com/LiveContainer/LiveContainer](https://github.com/LiveContainer/LiveContainer).
O GitHub escondeu esse projeto a partir de 4 de outubro de 2026 por algumas
semanas; ele voltou, e as cópias que circularam nesse meio-tempo não são
oficiais.

1. LocalDevVPN pela App Store, **Connect** (passo 1 do caminho 2).
2. No iloader: **Instaladores → LiveContainer + SideStore (Estável)**.
3. Confie no desenvolvedor e ligue o Modo de Desenvolvedor (passos 5 e 6 do
   caminho 1).
4. No LiveContainer, aba **Aplicativos**, toque no botão **SideStore** (no
   alto, à esquerda). No SideStore, **Settings**: entre com o Apple ID (saia e
   entre de novo se já parecer logado — o SideStore embutido não consegue ler
   a senha guardada). Depois **My Apps → Refresh All**. Saia do SideStore (o
   ícone de sair na página Apps dele).
5. No LiveContainer, **Configurações → Importar Certificado da SideStore
   Integrada → OK**. Deu certo se o botão virar **Remover Certificado**.
   **Configurações → Diagnóstico do Modo JIT-Less** tem que estar todo verde.
6. Aba **Fontes** → **+** → o mesmo endereço de fonte do caminho 2 →
   **Instalar**.

App *dentro* do LiveContainer é assinado pelo próprio LiveContainer no **modo
JIT-less**, com o certificado do SideStore. Enquanto o passo 5 não é feito, a
instalação falha com "Falha ao encontrar certificado… diagnóstico do modo
JIT-Less" ou "Certificado não encontrado. Você fez login na SideStore
integrada?" — não é defeito do `.ipa`. Se o passo 5 continuar dizendo que não
achou o certificado: no SideStore embutido, **Settings → Export Signing
Certificate…**, escolha uma senha e salve; depois, no LiveContainer,
**Configurações → Importar Certificado** com esse arquivo.

Dentro do LiveContainer, a **atualização** é pela aba **Fontes** dele (o botão
**Abrir no SideStore** do app cai lá), e os **controles da tela de bloqueio**
podem falhar em app Flutter (problema conhecido do LiveContainer). Se
incomodar, instale o BKmasterplayer como app normal pelo SideStore embutido
(passos 6 e 7 do caminho 2).

---

### Quando algo dá errado

| O que aparece | O que é | O que fazer |
|---|---|---|
| "Desenvolvedor Não Confiável" | o perfil ainda não foi aceito | Ajustes → Geral → VPN e Gerenciamento de Dispositivo → Confiar |
| o app não abre, ou pede o Modo de Desenvolvedor | Modo de Desenvolvedor desligado | Ajustes → Privacidade e Segurança → Modo de Desenvolvedor |
| **-80045** / **-80046** ao entrar no SideStore | a Apple recusando os dados de login do SideStore | [os cinco passos acima](#erro-de-login-no-sidestore--80045---80046) |
| "assinatura do código é inválida", **'Status' do Certificado: Expirado** (é a tradução deles para *revogado*) | outro programa assinou com o mesmo Apple ID | use um programa só; no SideStore, **Refresh All**; no LiveContainer, **Remover Certificado** e importe de novo; se continuar revogado, reinstale pelo iloader |
| "Limite de certificados alcançado" no iloader | certificados demais no Apple ID | deixe o iloader revogar o antigo — os apps assinados com ele (por outros programas) param de abrir |
| erro de "pairing file" ou "InvalidVPN" no SideStore | o arquivo de pareamento venceu, ou a VPN está desligada | LocalDevVPN **Connect**, no Wi-Fi; iloader → **Gerenciar Arquivo de Pareamento → Colocar Arquivo de Pareamento** |
| "maximum number of apps" | o limite de 3 apps | tire um app instalado assim |
| "maximum App ID limit" | 10 IDs de app novos em 7 dias | espere a semana passar, ou use outro Apple ID |
| funcionou 7 dias e parou | a assinatura venceu | caminho 1: ligue o cabo e refaça; caminhos 2 e 3: renove (os dados ficam) |

### Outros caminhos, com a bênção da Apple

- **AltStore PAL (Brasil, União Europeia, Japão).** Desde 18 de junho de 2026,
  iPhone no Brasil com **iOS 26.5 ou mais novo** pode instalar lojas de apps
  alternativas, e a **AltStore PAL** já chegou: sem computador, sem o limite de
  7 dias, sem o limite de três apps. O BKmasterplayer **ainda não** está lá.
  Para isso, o desenvolvedor precisa de conta paga de desenvolvedor da Apple
  (US$ 99 por ano) e da *notarização* da Apple em cada versão — uma revisão
  mais leve que a da App Store. App gratuito não paga comissão.
- **Conta paga de desenvolvedor da Apple** (US$ 99 por ano), com os mesmos
  programas: a assinatura dura um ano em vez de 7 dias, o limite de três apps
  some, e a lista automática do Connect poderia ser ligada (veja abaixo).

### O que muda no iPhone

- **Connect** (escolher em qual aparelho tocar) monta a lista por broadcast
  UDP, que a Apple só libera com uma permissão que só conta **paga** pode
  pedir. No iPhone a lista fica vazia, mas **adicionar o aparelho pelo
  endereço** funciona.
- **Festa** acha os outros por Bonjour, que o iOS libera sem essa permissão. Na
  primeira vez o iPhone pede para usar a rede local — diga que sim.

O resto — tocar, AutoMix, AudioMuse, downloads, recomendação sem internet — é
igual.
