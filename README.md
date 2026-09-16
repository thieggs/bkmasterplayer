# BKmasterplayer 🎵

Player open source para servidores **OpenSubsonic** (Navidrome, Gonic, Ampache…),
com integração ao **AudioMuse-AI**, **AutoMix DJ** (transições sincronizadas por
BPM, como um DJ) e personalização completa. Linux e Android; Windows e iOS a
seguir.

- Plano, status e roadmap: [`docs/PLANO.md`](docs/PLANO.md)
- App (Flutter): [`app/`](app/) · Motor de áudio (Rust): [`app/rust/`](app/rust/)
- Ambiente de teste (Navidrome + músicas sintéticas com gabarito): [`dev/`](dev/)

## O que tem

- **Streaming com cache:** seek imediato mesmo baixando, cache LRU, downloads para ouvir offline.
- **Gapless:** perfeito, amostra por amostra, mesmo com conversão de taxa. Crossfade, ReplayGain, equalizador de 10 bandas.
- **AutoMix DJ:**
  - Análise por rede neural (Beat This!): batidas, compassos, BPM, tom Camelot, intro/outro.
  - Transição em compassos com time-stretch sem mudar o tom.
  - Música tocada (bateria humana, tempo que varia): troca no compasso, cada uma no seu tempo.
  - Estilos: troca de grave, filtro, eco, mistura ou corte. Tudo configurável.
- **Análise no servidor (BK Analyzer):** um computador analisa a biblioteca inteira (os trabalhadores podem ser outras máquinas, como um notebook) e o app só baixa o resultado. Painel web com o andamento e as músicas que não deram, e por quê.
- **AudioMuse-AI (via Navidrome):** Mix instantâneo, rádio sônica, caminho sônico entre duas músicas e rádio infinita.
- **Modo DJ:** a partir de uma música, o AudioMuse e o AutoMix escolhem cada próxima pelo melhor encaixe (parecença, BPM e tom).
- **Sem servidor:** toca as músicas do aparelho (pastas escolhidas); o Last.fm dá as parecidas quando não há AudioMuse.
- **Festa:** quem está perto entra na sua música, adiciona (da sua biblioteca ou das dele) e controla. Pela rede local ou, no Android, por Bluetooth/Wi-Fi Direct; cada pessoa só entra com a sua aprovação (ou com o passe que ganhou ao ser posta em "aceitar sempre").
- **Fila:** salva no disco e sincronizada com o servidor (continuar em outro aparelho).
- **Connect:** escolher em qual aparelho tocar e controlá-lo (PC, notebook, celular da mesma conta). Protegido por desafio e resposta com uma chave que vem da senha: o token do servidor nunca vai para outro aparelho.
- **Timer para dormir:** 15 a 90 minutos ou no fim da música, com o volume descendo aos poucos antes de pausar.
- **Dados móveis:** qualidade própria para quando não há Wi-Fi e downloads que esperam o Wi-Fi.
- **Compartilhar link** de música ou álbum (Navidrome com compartilhamento ligado), já com o endereço de fora mesmo criado em casa.
- **Buscas recentes** (só no aparelho).
- **Diagnóstico** (Ajustes → Sobre): o app registra os erros e gera um relatório para mandar junto com um problema, sem senha, tokens, endereço do servidor nem usuário.
- **Acessibilidade:** botões com nome para o leitor de tela, área de toque de 48 dp e contraste conferidos por testes.
- **Endereço de casa:** usa o endereço da rede local quando ele responde (mais rápido) e o principal fora de casa.
- **Letras e capas que faltam:** LRCLIB e Musixmatch (com a sua chave), com a fonte mostrada; capas do Cover Art Archive (MusicBrainz) e do Deezer.
- **Desktop:**
  - MPRIS com capa (KDE Connect, widgets), notificação que não empilha.
  - Bandeja do sistema, mini player, atalhos de teclado.
  - Segue a saída padrão do sistema (Bluetooth incluso).
- **Android:** notificação de mídia com capa, tela de bloqueio, botões do fone e da caixa Bluetooth, pausa em ligações, **Android Auto** (biblioteca, busca e voz no carro), layouts para celular deitado e tablet, baixar a biblioteca inteira.
- **Personalização gráfica total** (o padrão é o visual original): cores (da capa ou fixa, 9 estilos de paleta, contraste, cores à mão), fontes de título e texto, formas, fundo (gradiente, capa desfocada ou imagem), estrutura das telas (abas, player flutuante, botões, seções) e animações. Galeria com 8 temas prontos, temas próprios, exportar/importar tema e backup completo em arquivo, backups automáticos.
- **Ajustes em telas por categoria**, com idioma (português/inglês).
- **Idiomas:** português e inglês.

## Compilar e rodar no Linux

Pré-requisitos: Flutter 3.41+, Rust 1.90+ e
`clang lld-19 cmake ninja-build pkg-config libgtk-3-dev libasound2-dev libsecret-1-dev libayatana-appindicator3-dev`.

```bash
cd app
flutter run -d linux                  # desenvolvimento
flutter build linux --release         # versão otimizada
../dev/install_linux.sh               # instala no menu de aplicativos (--remove desfaz)
```

Se o CMake não achar o `ld.lld` (Debian só instala `ld.lld-19`), compile com `PATH=/usr/lib/llvm-19/bin:$PATH flutter build linux --release` (depois de trocar de compilador, apague `app/build/linux`).

Ambiente de teste (opcional): `./dev/setup_navidrome.sh` gera as músicas e sobe um Navidrome em http://localhost:4534 (dev/dev).

## Android

Pré-requisitos: Android SDK com NDK 28.2 (`ANDROID_HOME`, padrão `~/android-sdk`) e
`rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android`.

```bash
./dev/build_apk.sh                    # dist/bkmasterplayer_<versão>_arm64.apk (Android 8+)
cd app && flutter run -d <aparelho>   # desenvolvimento (celular ou emulador)
```

A assinatura de release vem de `app/android/key.properties` (fora do git); sem ele o APK sai com a chave de debug.

## Análise no servidor (BK Analyzer)

O AutoMix precisa de uma análise de cada música (batidas, compassos, tom). O
aparelho faz sozinho, mas no celular é lento e usa o modelo pequeno. Com o
**BK Analyzer**, a análise sai pronta de um computador:

- o **coordenador** (na máquina do Navidrome) lê a biblioteca pela API Subsonic,
  só leitura, como o AudioMuse; guarda as análises e entrega para os players;
- os **trabalhadores** (qualquer Linux com CPU sobrando) baixam o arquivo pelo
  coordenador, analisam com o modelo completo e devolvem só o resultado. Rodam
  com prioridade baixa e pausam na bateria.

```bash
cd app/rust && cargo build --release --features analyzer-server --bin bk-analyzer
./dev/install_analyzer.sh server                                          # painel em http://<pc>:4540
SSH_OPTS="-i ~/.ssh/chave" ./dev/install_analyzer.sh worker usuario@notebook http://<pc>.local:4540 2
```

No painel, entre com a conta do Navidrome (fica guardado só o token, nunca a
senha): ele mostra o andamento, os trabalhadores e a lista das músicas que não
sincronizam, com o motivo. Dá para pausar a análise e escolher quantas músicas
cada trabalhador analisa ao mesmo tempo. No app: Ajustes → AutoMix → Servidor de análise.
A análise do servidor só é usada quando o app toca o mesmo arquivo analisado
(o original, sem limite de qualidade); fora de casa, sem o servidor, o aparelho
analisa como antes.

## Um endereço só, de qualquer lugar (BK Portal)

Servidor de casa exposto por túnel grátis (Cloudflare) ganha um endereço novo a
cada reinício, e o endereço guardado no aparelho para de valer. O **BK Portal**
resolve separando as duas coisas:

- um endereço **fixo e lento** (o Funnel do Tailscale) que só serve um anúncio
  assinado dizendo onde o servidor está agora;
- um endereço **que muda e é rápido** (o túnel), por onde passa a música.

O portal ainda põe o Navidrome e o BK Analyzer atrás do mesmo link: o Navidrome
na raiz (a interface web dele usa caminhos absolutos) e a análise em
`/bk/analise`. Quem recebe o link cola na tela de entrar e o app se configura
sozinho; quando o túnel troca de nome, o app pergunta ao portal e segue.

```bash
cd app/rust && cargo build --release --features portal-server --bin bk-portal
bk-portal serve --navidrome http://127.0.0.1:4533 --analyzer http://127.0.0.1:4540 \
                --cloudflared ~/cloudflared/cloudflared --nome "Servidor do Fulano"
sudo tailscale funnel --bg 4530      # o endereço fixo passa a ser o portal
bk-portal link                       # o link para mandar, e a impressão digital da chave
```

O anúncio é assinado com Ed25519 e a chave particular não sai da máquina de
casa. O app fixa a chave pública na primeira vez, como o SSH faz, e depois
recusa anúncio de outra — sem isso, quem escrevesse no anúncio mandaria o app,
e a senha de quem o usa, para o servidor que quisesse. Confira a impressão
digital com quem passou o link: ela aparece no app em Ajustes → Conta e
servidor e no `bk-portal link`.

Do BK Analyzer só saem para a internet `/api/hello`, `/api/summary` e
`/api/analysis/`; o painel e a API dos trabalhadores ficam para quem entra pela
rede de casa.

## Testes

```bash
cd app/rust && cargo test --release   # streaming, gapless bit-exato, mixer, análise, AutoMix, EQ
cd app/rust && cargo test --release --test engine_automix -- --ignored   # orquestração (usa a placa de som, volume 0)
cd app && flutter test                 # app (inclui segurança e acessibilidade)
```

## Segurança

`./dev/auditoria.sh` roda o checkup inteiro: dependências com vulnerabilidade
conhecida (cargo-audit, osv-scanner), licenças (cargo-deny), segredos no
histórico (gitleaks), análise estática (clippy, flutter analyze, semgrep),
testes, fuzzing do decodificador de áudio e checagens do Android. Com
`--rapido`, pula o fuzzing e os testes longos. O que foi achado e corrigido
na auditoria de 15/09/2026, e os riscos que ficam, estão em
[`docs/SEGURANCA.md`](docs/SEGURANCA.md).

## Créditos

- Beat This! (CPJKU/JKU Linz, pesos MIT) via [beat-this-rs](https://github.com/danigb/beat-this-rs).
- [Signalsmith Stretch](https://signalsmith-audio.co.uk/code/stretch/) (MIT).
- [symphonia](https://github.com/pdeljanov/Symphonia), [cpal](https://github.com/RustAudio/cpal), [rubato](https://github.com/HEnquist/rubato).
- Fontes dos temas (SIL Open Font License): Nunito, Space Grotesk, JetBrains Mono, Playfair Display e Bebas Neue (licenças em `app/assets/fonts/`).

## Licença

MIT (ver [`LICENSE`](LICENSE)). As bibliotecas, fontes e o modelo de análise usados têm licenças próprias, todas compatíveis (ver [`docs/JURIDICO.md`](docs/JURIDICO.md) e Ajustes → Sobre → Licenças no app).
