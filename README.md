# Player de Música (nome provisório)

Player open source para servidores **OpenSubsonic** (Navidrome, Gonic, Ampache…),
com integração ao **AudioMuse-AI**, **AutoMix DJ** (transições sincronizadas por
BPM, como um DJ) e personalização completa. Linux primeiro; Windows, Android e
iOS a seguir.

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
- **Fila:** salva no disco e sincronizada com o servidor (continuar em outro aparelho).
- **Desktop:**
  - MPRIS com capa (KDE Connect, widgets), notificação que não empilha.
  - Bandeja do sistema, mini player, atalhos de teclado.
  - Segue a saída padrão do sistema (Bluetooth incluso).
- **Personalização:** tema, cores (inclusive da capa), AMOLED, cantos, densidade, capas, 4 layouts do "tocando agora" (vinil incluso), barra lateral, botões do player, seções do Início, perfis exportáveis.
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

Ambiente de teste (opcional): `./dev/setup_navidrome.sh` gera as músicas e sobe um Navidrome em http://localhost:4534 (dev/dev).

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

## Licença

GPL-3.0-or-later.
