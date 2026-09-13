# Player de Música (nome provisório)

Player open source para servidores **OpenSubsonic** (Navidrome, Gonic, Ampache…),
com integração ao **AudioMuse-AI**, customização completa e **AutoMix DJ**
(transições sincronizadas por BPM). Linux primeiro, depois Windows, Android e iOS.

- Plano completo e roadmap: [`docs/PLANO.md`](docs/PLANO.md)
- App (Flutter): [`app/`](app/)
- Motor de áudio (Rust): [`app/rust/`](app/rust/)
- Ambiente de teste (Navidrome + músicas sintéticas): [`dev/`](dev/)

## Rodando no Linux

Pré-requisitos: Flutter 3.41+, Rust 1.90+, `clang cmake ninja-build pkg-config libgtk-3-dev libasound2-dev libsecret-1-dev`.

```bash
cd app
flutter run -d linux
```

Ambiente de teste (opcional):

```bash
./dev/setup_navidrome.sh   # gera as músicas e sobe um Navidrome em http://localhost:4534 (dev/dev)
```

## Testes

```bash
cd app/rust && cargo test --release   # motor: streaming, cache, gapless bit-exato, crossfade
cd app && flutter test                 # app
```

## Licença

GPL-3.0-or-later.
