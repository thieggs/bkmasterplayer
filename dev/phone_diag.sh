#!/usr/bin/env bash
# Compara a análise do AutoMix no celular (processador ARM) com a do PC, nas
# mesmas músicas: roda o exemplo `diag` (a mesma análise do app) nos dois e
# compara batida a batida.
#
# Uso: ./dev/phone_diag.sh <IP:porta do adb> <arquivos de música...>
#   ex.: ./dev/phone_diag.sh 192.168.1.240:40123 /media/thieggs/RAID0/Music/Mandragora/*.mp3
# As músicas vão para /data/local/tmp/bkdiag no celular e são apagadas no fim.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUST="$ROOT/app/rust"
DEV="$1"; shift
NDK="${ANDROID_NDK:-$HOME/android-sdk/ndk/28.2.13676358}"
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
export CC_aarch64_linux_android="$TC/aarch64-linux-android26-clang"
export CXX_aarch64_linux_android="$TC/aarch64-linux-android26-clang++"
export AR_aarch64_linux_android="$TC/llvm-ar"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$TC/aarch64-linux-android26-clang"

(cd "$RUST" && cargo build --release --example diag --target aarch64-linux-android && cargo build --release --example diag)

OUT="$(mktemp -d /tmp/bkdiag.XXXX)"
REMOTE=/data/local/tmp/bkdiag
adb -s "$DEV" shell "rm -rf $REMOTE; mkdir -p $REMOTE/music"
adb -s "$DEV" push "$RUST/target/aarch64-linux-android/release/examples/diag" \
  "$TC/../sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" "$ROOT"/app/assets/models/*.onnx "$REMOTE/" >/dev/null
for f in "$@"; do adb -s "$DEV" push "$f" "$REMOTE/music/" >/dev/null; done

echo "== celular"
adb -s "$DEV" shell "cd $REMOTE && chmod +x diag && LD_LIBRARY_PATH=. ./diag --models . --out out music/*" | tee "$OUT/celular.txt"
adb -s "$DEV" pull "$REMOTE/out" "$OUT/celular_json" >/dev/null
adb -s "$DEV" shell "rm -rf $REMOTE"

echo "== PC"
"$RUST/target/release/examples/diag" --out "$OUT/pc_json" "$@" | tee "$OUT/pc.txt"

echo "== comparação das batidas (celular x PC)"
python3 - "$OUT" <<'EOF'
import json, os, sys, bisect
out = sys.argv[1]
pc, ph = os.path.join(out, 'pc_json'), os.path.join(out, 'celular_json')
for name in sorted(os.listdir(pc)):
    a = json.load(open(os.path.join(pc, name)))
    try:
        b = json.load(open(os.path.join(ph, name)))
    except FileNotFoundError:
        print(f'{name}: sem resultado no celular'); continue
    pb, cb = a['beats'], b['beats']
    diffs = []
    for t in pb:
        i = bisect.bisect_left(cb, t)
        near = [abs(t - cb[j]) for j in (i - 1, i) if 0 <= j < len(cb)]
        if near: diffs.append(min(near))
    same = sum(d <= 0.005 for d in diffs) / max(1, len(diffs))
    worst = max(diffs) if diffs else 0
    print(f"{name[:-11]:<32} batidas PC {len(pb):>4} celular {len(cb):>4}  iguais (±5 ms) {same*100:5.1f}%  pior {worst*1000:6.1f} ms  bpm {a['bpm']} x {b['bpm']}")
EOF
echo "(resultados em $OUT)"
