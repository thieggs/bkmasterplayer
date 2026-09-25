# Instalar no iPhone

> 🇧🇷 [Versão em português](#português) mais abaixo.

The `.ipa` in the [releases](https://github.com/thieggs/bkmasterplayer/releases)
is **unsigned**. That is not a mistake — Apple only lets signed apps run, and
the tools below sign it with *your own* Apple ID as they install it. A free
Apple ID is enough.

Two ways. Pick by what you have.

| | you need | signature lasts | renews itself |
|---|---|---|---|
| **Sideloadly** | a Windows or Mac computer | 7 days | no — plug in and redo |
| **SideStore** | a computer **once**, then nothing | 7 days | **yes**, on the phone |

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
3. Inside SideStore, install `BKmasterplayer-*.ipa` with your Apple ID.
4. SideStore keeps it signed from then on, using a local VPN on the device.

The pairing file expires at random, and whenever you update or reset the
phone. When that happens you go back to the computer once and regenerate it.

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

| | precisa de | a assinatura dura | renova sozinho |
|---|---|---|---|
| **Sideloadly** | um computador Windows ou Mac | 7 dias | não — liga o cabo e refaz |
| **SideStore** | computador **uma vez**, depois nada | 7 dias | **sim**, no próprio celular |

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
3. Dentro do SideStore, instale o `BKmasterplayer-*.ipa` com o seu Apple ID.
4. Daí em diante ele mantém a assinatura sozinho, com uma VPN local no aparelho.

O arquivo de pareamento vence em momentos aleatórios, e sempre que você
atualizar ou resetar o celular. Quando isso acontecer, é voltar ao computador
uma vez e gerar outro.

### O que não funciona no iPhone

**Connect** (escolher em qual aparelho tocar) e **Festa** acham os aparelhos
por multicast UDP. A Apple esconde isso atrás de uma permissão que só conta
**paga** pode pedir, então num app instalado por fora eles ficam desligados. O
resto — tocar, AutoMix, AudioMuse, downloads, recomendação sem internet —
funciona.
