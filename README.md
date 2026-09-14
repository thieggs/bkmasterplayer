# BKplayer 🎵

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
  - Estilos: troca de grave, filtro, eco, mistura ou corte. Tudo configurável.
- **AudioMuse-AI (via Navidrome):** Mix instantâneo, rádio sônica, caminho sônico entre duas músicas e rádio infinita.
- **Modo DJ:** a partir de uma música, o AudioMuse e o AutoMix escolhem cada próxima pelo melhor encaixe (parecença, BPM e tom).
- **Sem servidor:** toca as músicas do aparelho (pastas escolhidas); o Last.fm dá as parecidas quando não há AudioMuse.
- **Festa:** quem está perto entra na sua música, adiciona (da sua biblioteca ou das dele) e controla. Pela rede local ou, no Android, por Bluetooth/Wi-Fi Direct; cada pessoa só entra com a sua aprovação (ou se estiver na lista de aceitos).
- **Fila:** salva no disco e sincronizada com o servidor (continuar em outro aparelho).
- **Connect:** escolher em qual aparelho tocar e controlá-lo (PC, notebook, celular da mesma conta), como no Spotify Connect.
- **Endereço de casa:** usa o endereço da rede local quando ele responde (mais rápido) e o principal fora de casa.
- **Letras e capas que faltam:** LRCLIB, Musixmatch (com a sua chave) e lyrics.ovh; capas do iTunes/Deezer.
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
./dev/build_apk.sh                    # dist/bkplayer_<versão>_arm64.apk (Android 8+)
cd app && flutter run -d <aparelho>   # desenvolvimento (celular ou emulador)
```

A assinatura de release vem de `app/android/key.properties` (fora do git); sem ele o APK sai com a chave de debug.

## Testes

```bash
cd app/rust && cargo test --release   # streaming, gapless bit-exato, mixer, análise, AutoMix, EQ
cd app/rust && cargo test --release --test engine_automix -- --ignored   # orquestração (usa a placa de som, volume 0)
cd app && flutter test                 # app
```

## Créditos

- Beat This! (CPJKU/JKU Linz, pesos MIT) via [beat-this-rs](https://github.com/danigb/beat-this-rs).
- [Signalsmith Stretch](https://signalsmith-audio.co.uk/code/stretch/) (MIT).
- [symphonia](https://github.com/pdeljanov/Symphonia), [cpal](https://github.com/RustAudio/cpal), [rubato](https://github.com/HEnquist/rubato).
- Fontes dos temas (SIL Open Font License): Nunito, Space Grotesk, JetBrains Mono, Playfair Display e Bebas Neue (licenças em `app/assets/fonts/`).

## Licença

GPL-3.0-or-later.
