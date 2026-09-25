# Compilar o BKmasterplayer

> 🇧🇷 [Versão em português](#português) mais abaixo. · **You don't have to
> build anything** — the [releases](https://github.com/thieggs/bkmasterplayer/releases)
> carry ready-made `.exe`, `.deb`, `.AppImage`, `.apk` and `.ipa`.

Every command, in order, from a clean machine. Pick your section and run the
blocks top to bottom.

---

## Common to every platform

The app is Flutter; the audio engine is Rust. You need both, at these versions
or newer.

```bash
# 1. Flutter — the version must match app/pubspec.yaml (3.41.6 today)
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
export PATH="$HOME/flutter/bin:$PATH"          # put this in ~/.bashrc too
flutter --version

# 2. Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
rustc --version

# 3. This project
git clone https://github.com/thieggs/bkmasterplayer.git
cd bkmasterplayer
```

Check that Flutter is happy before going further:

```bash
flutter doctor
```

---

## Linux

```bash
# System libraries (Debian/Ubuntu; other distros: same names, other package manager)
sudo apt update
sudo apt install -y clang lld cmake ninja-build pkg-config \
  libgtk-3-dev libasound2-dev libsecret-1-dev libayatana-appindicator3-dev

# Build
cd app
flutter pub get
flutter build linux --release
cd ..

# Either install it into your application menu…
./dev/install_linux.sh                   # --remove undoes it

# …or make the packages
./dev/build_deb.sh                       # dist/bkmasterplayer_*.deb
./dev/build_appimage.sh                  # dist/BKmasterplayer-*.AppImage
```

**If CMake cannot find `ld.lld`:** Debian installs it as `ld.lld-19` only.

```bash
PATH=/usr/lib/llvm-19/bin:$PATH flutter build linux --release
rm -rf app/build/linux                   # after switching compilers, start clean
```

---

## Android

Needs the Android SDK with **NDK 28.2**. Android Studio installs both; if you
only want the command line, install the command-line tools and:

```bash
export ANDROID_HOME="$HOME/android-sdk"
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --install "ndk;28.2.13676358" "platforms;android-36" "build-tools;36.0.0"

rustup target add aarch64-linux-android
./dev/build_apk.sh                       # dist/bkmasterplayer_*_arm64.apk
ALL_ABIS=1 ./dev/build_apk.sh            # 32-bit ARM and x86_64 as well
```

Install it on a phone over USB or Wi-Fi:

```bash
adb install -r dist/bkmasterplayer_*_arm64.apk
```

Without `app/android/key.properties` the APK is signed with the debug key: it
installs fine, but will not upgrade over one signed with a release key.

---

## Windows

Flutter only builds Windows apps **on Windows**
([flutter#110585](https://github.com/flutter/flutter/issues/110585)).

```powershell
# Everything at once
winget install Microsoft.VisualStudio.2022.BuildTools --override `
  "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.ATL --includeRecommended"
winget install Rustlang.Rustup
winget install LLVM.LLVM
winget install JRSoftware.InnoSetup

# bindgen needs libclang.dll
$env:LIBCLANG_PATH = "C:\Program Files\LLVM\bin"

cd app
flutter pub get
flutter build windows --release
cd ..

# Installer -> dist\
& "C:\Program Files (x86)\Inno Setup 6\iscc.exe" /DVersao=1.0.0 dev\windows\bkmasterplayer.iss
```

Two traps that cost real time:

- **The ATL component is not in the default C++ workload**, and
  `flutter_secure_storage` includes `atlstr.h`. Without it the build fails deep
  in a C++ header for no obvious reason.
- **Never redirect `flutter.bat` output to a file** (`>>`, `Tee-Object`). It
  uses a file handle to lock its cache and loops forever on "Building flutter
  tool...". Leave the output on the console.

---

## macOS

```bash
xcode-select --install
sudo xcodebuild -license accept
rustup target add aarch64-apple-darwin x86_64-apple-darwin

./dev/build_macos.sh                     # dist/BKmasterplayer-*.dmg
```

---

## iPhone

Flutter needs Xcode, and Xcode needs macOS. Two ways out.

**On a Mac:**

```bash
rustup target add aarch64-apple-ios
./dev/build_ios.sh                       # dist/BKmasterplayer-*.ipa, unsigned
```

**Without a Mac**, let GitHub's macOS machine do it — fork the repository, then
Actions → **Release** → Run workflow. The `.ipa` comes back as an artifact.

Either way the `.ipa` is **unsigned**. Install it with **SideStore** or
**AltStore**, which re-sign it with your own Apple ID. With a free Apple ID the
signature lasts 7 days and SideStore renews it on the device.

**Connect and Party do not work on iOS.** They find devices over UDP multicast,
which Apple gates behind an entitlement only paid accounts get.

---

## Tests

```bash
cd app
flutter analyze
flutter test                             # widgets, accessibility, engine
cd rust && cargo test                    # audio engine
```

A throwaway server with synthetic music — every track with an exact known BPM,
key and structure, so the AutoMix analysis can be measured rather than guessed:

```bash
./dev/setup_navidrome.sh                 # http://localhost:4534 — dev/dev
```

---

## Português

> **Você não precisa compilar nada** — os
> [releases](https://github.com/thieggs/bkmasterplayer/releases) trazem `.exe`,
> `.deb`, `.AppImage`, `.apk` e `.ipa` prontos.

Todos os comandos, em ordem, partindo de uma máquina limpa. Escolha a sua
seção e rode os blocos de cima para baixo.

### Comum a todos

O app é Flutter e o motor de áudio é Rust. Precisa dos dois.

```bash
# 1. Flutter — a versão tem que bater com app/pubspec.yaml (hoje, 3.41.6)
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
export PATH="$HOME/flutter/bin:$PATH"          # ponha também no ~/.bashrc
flutter --version

# 2. Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
rustc --version

# 3. O projeto
git clone https://github.com/thieggs/bkmasterplayer.git
cd bkmasterplayer

# 4. Conferir antes de seguir
flutter doctor
```

### Linux

```bash
# Bibliotecas do sistema (Debian/Ubuntu)
sudo apt update
sudo apt install -y clang lld cmake ninja-build pkg-config \
  libgtk-3-dev libasound2-dev libsecret-1-dev libayatana-appindicator3-dev

# Compilar
cd app
flutter pub get
flutter build linux --release
cd ..

# Instalar no menu de aplicativos…
./dev/install_linux.sh                   # --remove desfaz

# …ou gerar os pacotes
./dev/build_deb.sh                       # dist/bkmasterplayer_*.deb
./dev/build_appimage.sh                  # dist/BKmasterplayer-*.AppImage
```

**Se o CMake não achar o `ld.lld`:** o Debian instala só como `ld.lld-19`.

```bash
PATH=/usr/lib/llvm-19/bin:$PATH flutter build linux --release
rm -rf app/build/linux                   # depois de trocar de compilador, comece limpo
```

### Android

Precisa do SDK do Android com **NDK 28.2**.

```bash
export ANDROID_HOME="$HOME/android-sdk"
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --install "ndk;28.2.13676358" "platforms;android-36" "build-tools;36.0.0"

rustup target add aarch64-linux-android
./dev/build_apk.sh                       # dist/bkmasterplayer_*_arm64.apk
ALL_ABIS=1 ./dev/build_apk.sh            # inclui ARM 32 bits e x86_64

adb install -r dist/bkmasterplayer_*_arm64.apk
```

Sem `app/android/key.properties` o APK sai assinado com a chave de depuração:
instala, mas não atualiza por cima de um assinado com a chave de verdade.

### Windows

O Flutter só compila app de Windows **no Windows**.

```powershell
winget install Microsoft.VisualStudio.2022.BuildTools --override `
  "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.ATL --includeRecommended"
winget install Rustlang.Rustup
winget install LLVM.LLVM
winget install JRSoftware.InnoSetup

$env:LIBCLANG_PATH = "C:\Program Files\LLVM\bin"

cd app
flutter pub get
flutter build windows --release
cd ..

& "C:\Program Files (x86)\Inno Setup 6\iscc.exe" /DVersao=1.0.0 dev\windows\bkmasterplayer.iss
```

Duas pegadinhas que custam tempo:

- **O componente ATL não vem na carga padrão de C++**, e o
  `flutter_secure_storage` inclui `atlstr.h`. Sem ele o build quebra dentro de
  um cabeçalho C++, sem explicar por quê.
- **Nunca redirecione a saída do `flutter.bat` para arquivo** (`>>`,
  `Tee-Object`). Ele usa um handle de arquivo para travar o cache e entra em
  laço de "Building flutter tool...". Deixe a saída no console.

### macOS

```bash
xcode-select --install
sudo xcodebuild -license accept
rustup target add aarch64-apple-darwin x86_64-apple-darwin

./dev/build_macos.sh                     # dist/BKmasterplayer-*.dmg
```

### iPhone

O Flutter exige Xcode, e o Xcode exige macOS. Duas saídas.

**Com um Mac:**

```bash
rustup target add aarch64-apple-ios
./dev/build_ios.sh                       # dist/BKmasterplayer-*.ipa, sem assinatura
```

**Sem Mac**, deixe a máquina macOS do GitHub fazer: faça um fork, depois
Actions → **Release** → Run workflow. O `.ipa` volta como artefato.

De qualquer jeito o `.ipa` sai **sem assinatura**. Instale pelo **SideStore**
ou **AltStore**, que reassinam com o seu Apple ID. Com Apple ID gratuito a
assinatura vale 7 dias e o SideStore renova sozinho no aparelho.

**Connect e Festa não funcionam no iPhone.** Eles acham aparelhos por multicast
UDP, e a Apple só libera isso para conta paga.

### Testes

```bash
cd app
flutter analyze
flutter test                             # telas, acessibilidade, motor
cd rust && cargo test                    # motor de áudio
```

Um servidor descartável com músicas sintéticas — cada faixa com BPM, tom e
estrutura exatos e conhecidos, para a análise do AutoMix ser medida em vez de
chutada:

```bash
./dev/setup_navidrome.sh                 # http://localhost:4534 — dev/dev
```
