# Instalar no iPhone

> 🇧🇷 [Versão em português](#português) mais abaixo.

The `.ipa` in the [releases](https://github.com/thieggs/bkmasterplayer/releases)
is **unsigned**. That is not a mistake — Apple only lets signed apps run, and
the tools below sign it with *your own* Apple ID as they install it. A free
Apple ID is enough.

Two ways. Pick by what you have.

| | you need | signature lasts | renews itself | new versions |
|---|---|---|---|---|
| **Sideloadly** | a Windows or Mac computer | 7 days | no — plug in and redo | download the `.ipa`, plug in |
| **SideStore** | a computer **once**, then nothing | 7 days | **yes**, on the phone | **on the phone**, from the source |

Sideloadly is quicker to get going. SideStore takes longer to set up and then
stops bothering you. If you have a Windows machine around, start with
Sideloadly.

---

## Sideloadly (Windows or Mac)

### 1. iTunes and iCloud — the part everyone gets wrong

On Windows, Sideloadly talks to the phone through Apple's drivers, and the
**Microsoft Store versions of iTunes and iCloud do not expose them**.

1. Uninstall iTunes and iCloud if they came from the Microsoft Store.
2. Install the **non-Store** versions, the ones Apple offers on its own site.

On a Mac there is nothing to install.

### 2. Sideloadly

Download it from [sideloadly.io](https://sideloadly.io) and install.

### 3. Install the app

1. Plug the iPhone into the computer with a cable — **the first time has to be
   over USB**. Unlock it and tap **Trust** on the phone.
2. Open Sideloadly. The phone should appear at the top.
3. Drag `BKmasterplayer-*.ipa` onto the window.
4. Type your Apple ID and press **Start**. It asks for the password; if your
   account has two-factor, it asks for the code too.
5. Wait for **Done**.

### 4. Trust the app on the phone

The app is installed but iOS will not open it yet:

**Settings → General → VPN & Device Management →** your Apple ID **→ Trust**.

Now it opens.

### 5. Every 7 days

A free Apple ID signs for 7 days. When it stops opening, plug the phone back
in and repeat step 3 — your data and settings stay. Three sideloaded apps at a
time is the limit.

---

## SideStore (renews on the phone)

Worth the longer setup if you do not want to plug the phone in every week.
It runs on the phone itself and re-signs the app before the 7 days run out.

Follow the official guide at [docs.sidestore.io](https://docs.sidestore.io) —
it changes with iOS versions, and a stale copy of the steps here would do more
harm than good. The shape of it:

1. On a computer, generate a **pairing file** for the phone (once).
2. Install SideStore on the phone.
3. Add the BKmasterplayer source and install the app from it (below).
4. SideStore keeps it signed from then on, using a local VPN on the device.

The pairing file expires at random, and whenever you update or reset the
phone. When that happens you go back to the computer once and regenerate it.

### The BKmasterplayer source — updates on the phone

Every release publishes a SideStore source next to the `.ipa`. With it added,
SideStore sees each new version and installs it right there, no computer:

1. In SideStore, open **Sources**, tap **+** and paste:

   ```
   https://github.com/thieggs/bkmasterplayer/releases/latest/download/sidestore.json
   ```

2. Open the source, then **BKmasterplayer → Free** to install.
3. When a new version is out: **My Apps → Update**. The update notice inside
   the app has an **Open in SideStore** button that takes you there.

Install it **from the source** at least once. An app installed from the file
(the **+** in My Apps) is "sideloaded" to SideStore, and it never offers
updates for it. Reinstalling from the source replaces the same app.

### LiveContainer + SideStore — the "JIT-less" message

SideStore's current guide installs **LiveContainer+SideStore**: SideStore runs
inside LiveContainer, which can hold many apps while using a single one of the
three free slots. Apps you install *inside* LiveContainer are signed by
LiveContainer itself, and since iOS 17.4 there is no JIT without a computer,
so it signs in **JIT-less mode**, with SideStore's certificate. Until that
certificate is imported, installing fails with "Failed to find signing
certificate… JIT-Less Diagnose" or "Certificate not found. Did you log into
built-in SideStore?". Nothing is wrong with the `.ipa` — it is a one-time
setup on the phone:

1. In LiveContainer, **Apps** tab, tap the **SideStore** button (top left).
2. In SideStore, **Settings**: sign in with your Apple ID. If it already looks
   signed in, sign out and in again — the built-in SideStore cannot read the
   saved password.
3. Turn on **LocalDevVPN**, go to **My Apps** and tap **Refresh All**.
4. Leave SideStore (the quit icon in its Apps page). Back in LiveContainer,
   **Settings → Import Certificate from Built-in SideStore → OK**. It worked if
   the button turns into **Remove Certificate**.
5. **Settings → JIT-Less Mode Diagnose**: everything should be green, and
   **Test JIT-Less Mode** should pass.

Then install BKmasterplayer from LiveContainer's **Sources** tab: **+**, paste
the same source address as above, then **Install**.

If step 4 keeps saying "Certificate not found": in the built-in SideStore,
**Settings → Export Signing Certificate…**, pick a password and save the file;
then in LiveContainer, **Settings → Import Certificate**, choose that file and
type the password.

Two things change inside LiveContainer:

- **Updates**: the **Open in SideStore** button in the app falls back to
  LiveContainer's **Sources**. Tap **Install** there again; the app data stays
  in its container.
- **Lock screen controls** can misbehave for Flutter apps inside LiveContainer
  (a known LiveContainer issue). If that bothers you, install BKmasterplayer as
  a normal app instead: open the built-in SideStore and install from the
  source as above. That uses one of the three slots and does not need JIT-less.

---

## What does not work on iPhone

**Connect** (choose which device plays) and **Party** both find devices over
UDP multicast. Apple hides that behind an entitlement only **paid** developer
accounts can request, so on a sideloaded build they stay off. Everything else
— playback, AutoMix, AudioMuse, downloads, offline recommendations — works.

---

## Português

O `.ipa` dos [releases](https://github.com/thieggs/bkmasterplayer/releases) sai
**sem assinatura**. Não é descuido: a Apple só deixa rodar app assinado, e os
programas abaixo assinam com o **seu próprio** Apple ID na hora de instalar.
Apple ID gratuito serve.

São dois caminhos. Escolha pelo que você tem.

| | precisa de | a assinatura dura | renova sozinho | versão nova |
|---|---|---|---|---|
| **Sideloadly** | um computador Windows ou Mac | 7 dias | não — liga o cabo e refaz | baixa o `.ipa` e liga o cabo |
| **SideStore** | computador **uma vez**, depois nada | 7 dias | **sim**, no próprio celular | **no celular**, pela fonte |

O Sideloadly é mais rápido de começar. O SideStore dá mais trabalho para
montar e depois para de te incomodar. Se você tem um Windows por perto, comece
pelo Sideloadly.

### Sideloadly (Windows ou Mac)

#### 1. iTunes e iCloud — é aqui que todo mundo tropeça

No Windows o Sideloadly fala com o celular pelos drivers da Apple, e as
**versões da Microsoft Store do iTunes e do iCloud não expõem esses drivers**.

1. Desinstale o iTunes e o iCloud se vieram da Microsoft Store.
2. Instale as versões **de fora da Store**, as que a Apple oferece no site dela.

No Mac não precisa instalar nada.

#### 2. Sideloadly

Baixe em [sideloadly.io](https://sideloadly.io) e instale.

#### 3. Instalar o app

1. Ligue o iPhone no computador **por cabo** — a primeira vez tem que ser por
   USB. Desbloqueie e toque em **Confiar** no celular.
2. Abra o Sideloadly. O celular aparece no alto.
3. Arraste o `BKmasterplayer-*.ipa` para a janela.
4. Digite o seu Apple ID e aperte **Start**. Ele pede a senha; se a conta tem
   verificação em duas etapas, pede o código também.
5. Espere aparecer **Done**.

#### 4. Confiar no app, no celular

O app já está instalado, mas o iOS ainda não deixa abrir:

**Ajustes → Geral → VPN e Gerenciamento de Dispositivo →** seu Apple ID **→
Confiar**.

Agora abre.

#### 5. A cada 7 dias

Apple ID gratuito assina por 7 dias. Quando parar de abrir, ligue o cabo e
repita o passo 3 — seus dados e ajustes continuam lá. O limite é de três apps
instalados por fora ao mesmo tempo.

### SideStore (renova no próprio celular)

Vale o trabalho maior se você não quer ligar o cabo toda semana. Ele roda no
celular e reassina o app antes dos 7 dias vencerem.

Siga o guia oficial em [docs.sidestore.io](https://docs.sidestore.io) — ele
muda conforme a versão do iOS, e uma cópia velha dos passos aqui atrapalharia
mais que ajudaria. O formato é este:

1. Num computador, gere o **arquivo de pareamento** do celular (uma vez).
2. Instale o SideStore no celular.
3. Adicione a fonte do BKmasterplayer e instale o app por ela (abaixo).
4. Daí em diante ele mantém a assinatura sozinho, com uma VPN local no aparelho.

O arquivo de pareamento vence em momentos aleatórios, e sempre que você
atualizar ou resetar o celular. Quando isso acontecer, é voltar ao computador
uma vez e gerar outro.

#### A fonte do BKmasterplayer — atualiza no celular

Cada release publica uma fonte do SideStore junto com o `.ipa`. Com ela
adicionada, o SideStore vê cada versão nova e instala ali mesmo, sem
computador. O SideStore é só em inglês, então os nomes abaixo são os dele:

1. No SideStore, abra **Sources**, toque em **+** e cole:

   ```
   https://github.com/thieggs/bkmasterplayer/releases/latest/download/sidestore.json
   ```

2. Abra a fonte e toque em **BKmasterplayer → Free** para instalar.
3. Quando sair versão nova: **My Apps → Update**. O aviso de atualização
   dentro do app tem o botão **Abrir no SideStore**, que leva até lá.

Instale **pela fonte** pelo menos uma vez. App instalado pelo arquivo (o **+**
de My Apps) fica marcado como "por fora" no SideStore, e ele nunca oferece
atualização para esse app. Instalar de novo pela fonte substitui o mesmo app.

#### LiveContainer + SideStore — a mensagem do "JIT-less"

O guia atual do SideStore instala o **LiveContainer+SideStore**: o SideStore
roda dentro do LiveContainer, que guarda vários apps gastando uma só das três
vagas gratuitas. App instalado *dentro* do LiveContainer é assinado pelo
próprio LiveContainer, e desde o iOS 17.4 não há JIT sem computador, então ele
assina no **modo JIT-less**, com o certificado do SideStore. Enquanto esse
certificado não é importado, a instalação falha com "Falha ao encontrar
certificado… diagnóstico do modo JIT-Less" ou "Certificado não encontrado. Você
fez login na SideStore integrada?". Não é defeito do `.ipa`: é um ajuste de uma
vez só, no celular:

1. No LiveContainer, aba **Aplicativos**, toque no botão **SideStore** (no
   alto, à esquerda).
2. No SideStore, **Settings**: entre com o seu Apple ID. Se já parecer logado,
   saia e entre de novo — o SideStore embutido não consegue ler a senha
   guardada.
3. Ligue a **LocalDevVPN**, vá em **My Apps** e toque em **Refresh All**.
4. Saia do SideStore (o ícone de sair na página Apps dele). De volta ao
   LiveContainer, **Configurações → Importar Certificado da SideStore
   Integrada → OK**. Deu certo se o botão virar **Remover Certificado**.
5. **Configurações → Diagnóstico do Modo JIT-Less**: tudo verde, e **Testar modo
   JIT-Less** tem que passar.

Depois instale o BKmasterplayer pela aba **Fontes** do LiveContainer: **+**,
cole o mesmo endereço da fonte lá de cima e toque em **Instalar**.

Se o passo 4 continuar dizendo "Certificado não encontrado": no SideStore
embutido, **Settings → Export Signing Certificate…**, escolha uma senha e salve
o arquivo; depois, no LiveContainer, **Configurações → Importar Certificado**,
escolha esse arquivo e digite a senha.

Dentro do LiveContainer, duas coisas mudam:

- **Atualização**: o botão **Abrir no SideStore** do app cai na aba
  **Fontes** do LiveContainer. Toque em **Instalar** de novo; os dados do app
  ficam no contêiner dele.
- **Controles da tela de bloqueio** podem falhar em app Flutter dentro do
  LiveContainer (problema conhecido do LiveContainer). Se incomodar, instale o
  BKmasterplayer como app normal: abra o SideStore embutido e instale pela
  fonte, como acima. Isso gasta uma das três vagas e não precisa de JIT-less.

### O que não funciona no iPhone

**Connect** (escolher em qual aparelho tocar) e **Festa** acham os aparelhos
por multicast UDP. A Apple esconde isso atrás de uma permissão que só conta
**paga** pode pedir, então num app instalado por fora eles ficam desligados. O
resto — tocar, AutoMix, AudioMuse, downloads, recomendação sem internet —
funciona.
