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

## Windows

O Flutter só compila app de Windows em host Windows
([flutter#110585](https://github.com/flutter/flutter/issues/110585)), então o
build é nativo. O que precisa estar instalado, com as pegadinhas que custaram
tempo:

| | por quê |
|---|---|
| **VS Build Tools 2022** com a carga C++ **e o componente ATL** | o ATL não vem na carga padrão, e o `flutter_secure_storage` usa `atlstr.h` |
| **LLVM** (`LIBCLANG_PATH` apontando para o `bin`) | o `signalsmith-stretch` usa bindgen, que precisa da `libclang.dll`; no Linux ela vem com o sistema |
| **Flutter na mesma versão do `pubspec.yaml`** | uma versão antiga traz um Dart velho demais e o `pub get` recusa |
| **Rust** (toolchain MSVC) e **Inno Setup 6** | o motor e o instalador |

```powershell
winget install Microsoft.VisualStudio.2022.BuildTools --override `
  "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.ATL --includeRecommended"
winget install Rustlang.Rustup ; winget install LLVM.LLVM ; winget install JRSoftware.InnoSetup
cd app ; flutter build windows --release
cd .. ; iscc /DVersao=1.0.0 dev\windows\bkmasterplayer.iss   # sai em dist\
```

Duas coisas que só mordem quem automatiza por SSH: **não redirecione a saída do
`flutter.bat` para arquivo** (`>>` ou `Tee-Object`) — ele usa um handle de
arquivo para travar o cache e entra em laço de "Building flutter tool..."; deixe
a saída no console e guarde o log do outro lado. E **não baixe nada com
`Invoke-WebRequest`**: medi 0,85 Mbps contra 237 Mbps do `curl.exe`, que já vem
no Windows.

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

## Recomendação sem internet (vetores do AudioMuse)

O AudioMuse analisa cada música com uma rede neural e guarda os vetores no
Postgres dele. `dev/exporta_audiomuse.py` lê — só lê — e empacota tudo num
arquivo de uns 21 MB, que o BK Analyzer entrega ao aparelho em `/api/vectors`
(com versão no ETag: o app pergunta antes e recebe 304 quando nada mudou).

Com o arquivo no aparelho, "parecidas" (mix instantâneo, rádio e AutoMix) é
resolvido ali mesmo, em poucos milissegundos. Funciona sem internet e gasta
menos bateria do que perguntar ao servidor: acordar o rádio do celular custa
cerca de mil vezes mais que a conta.

O **ícone de rádio na tela do player** abre as opções e já começa a rádio do
jeito escolhido. Isto não é o AutoMix: o AutoMix costura uma música na outra,
a recomendação decide **qual** música vem. Em Ajustes → Recomendações fica o
mesmo, para valer também no mix instantâneo e na fila infinita:

| estilo | o que compara |
|---|---|
| Parecida no som | o timbre e o arranjo (padrão) |
| Mesmo clima | dançante, agressiva, feliz, festa, relaxada, triste |
| Mesmo estilo musical | os gêneros que a análise reconheceu |
| Mesma época | anos próximos, com o som desempatando |
| Mesmo assunto | o que a letra fala |
| Combina pra emendar | andamento próximo e tom que casa, como os DJs |
| Como o AudioMuse faz | a conta do servidor: 0,75 letra + 0,25 som |

```bash
./dev/exporta_audiomuse.py                    # gera ~/.local/share/bk-analyzer/vetores.bkvec
```

Vale automatizar com um timer do systemd (`bk-vetores.timer`), para o aparelho
acompanhar a biblioteca. A mesma faixa costuma existir em vários arquivos
(single, álbum, coletânea): o vetor vai uma vez e os ids apontam para ele,
senão a mesma música apareceria repetida nas sugestões.

## Limpeza: repetidas e lixo do banco

No PC, o atalho **"Limpar biblioteca"** na área de trabalho faz tudo de uma
vez: mostra o que faria, pede confirmação e só então mexe. Por baixo é
`dev/manutencao.sh`, que encadeia as ferramentas abaixo e ainda manda o
Navidrome reler e refaz os vetores do celular.

Cada uma também roda sozinha, e só mostra o que faria até levar `--aplicar`:

```bash
./dev/limpa_repetidas.py --descarte /media/.../repetidas   # músicas repetidas
./dev/separa_artistas.py                                   # artistas grudados
./dev/limpa_audiomuse.py                                   # lixo no banco
```

`separa_artistas.py` conserta a etiqueta que veio com tudo num campo só
(`Mandragora,420`), que faz o Navidrome criar **um** artista com o nome
inteiro e sumir com a música na busca por qualquer um deles. Grava
ARTIST/ALBUMARTIST como vários valores (ID3v2.4), que é o jeito correto — a
configuração do próprio Navidrome para isso (`Tags.artists.Split`) não
funciona na 0.63.2. Divide em vírgula e em barra sem espaço, nunca em `&`,
e guarda o valor original para `--desfazer`.

`limpa_repetidas.py` junta como a mesma música o que tem **áudio idêntico byte
a byte** (só nome e etiqueta mudam) e o que o AudioMuse marcou com a **mesma
impressão digital acústica** — a mesma gravação, ainda que em qualidades
diferentes. Fica a de melhor taxa; empatou, fica a que pertence a um álbum,
para não abrir buraco num disco por causa de uma avulsa baixada duas vezes. As
outras são **movidas** (não apagadas) para a pasta de descarte, com a letra
`.lrc` junto; no mesmo disco isso é instantâneo e dá para voltar atrás.

A impressão digital reconhece a gravação, não a edição, então o mesmo show
pode aparecer cortado em pontos diferentes: o grupo é separado por duração e
só o que casa dentro de 3 s é tratado; o resto sai numa lista para conferir.

`limpa_audiomuse.py` tira do AudioMuse as **ligações mortas** (a cada releitura
o Navidrome dá um id novo para a mesma música e o AudioMuse guarda os dois; aqui
havia arquivo apontado por cinco ids), as impressões digitais de música que saiu
e as **análises com vetores idênticos**. Análise sem dono fica: o `item_id` é a
própria impressão digital do som, então ela é reencontrada se o arquivo voltar —
apagar só obrigaria a rede neural a refazer o trabalho (`--orfas` força).

> O caminho que o AudioMuse guarda é uma foto de quando a análise rodou e
> **não serve para decidir nada** depois que a biblioteca é reorganizada. Quem
> sabe onde a música está hoje é o Navidrome, lido só para leitura; a ligação
> entre os dois é o id do Navidrome.

Depois da limpeza, vale reexportar os vetores (`./dev/exporta_audiomuse.py`)
para o aparelho não sugerir música que não existe mais.

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
