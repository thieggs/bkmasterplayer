#!/usr/bin/env bash
# Abre o app num iPhone simulado e confere que ele fica aberto. Roda num Mac
# com Xcode (no GitHub: .github/workflows/iphone-simulador.yml).
#
# Uso: ./dev/ios_simulador.sh <Runner.app do simulador> <pasta de saída>
#      (o .app sai de `flutter build ios --simulator --debug`)
#
# Na saída: tela.png (a tela depois de 40 s), log.txt (o que o app escreveu)
# e o relatório de falha, se ele caiu. Sai com erro se o app fechou sozinho.
#
# Não substitui um iPhone de verdade — o simulador não tem a assinatura nem o
# limite de memória do celular —, mas pega o "abre e fecha na hora": motor
# em Rust que não carrega, plugin que falta, Info.plist errado.
set -euo pipefail
APP=$1
OUT=$2
mkdir -p "$OUT"
ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")

# O iPhone do iOS mais novo que este Xcode tem.
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
melhor = None
for runtime, aparelhos in json.load(sys.stdin)["devices"].items():
    if ".iOS-" not in runtime:
        continue
    versao = tuple(int(x) for x in runtime.rsplit(".iOS-", 1)[1].split("-"))
    for a in aparelhos:
        if a["name"].startswith("iPhone") and (melhor is None or versao > melhor[0]):
            melhor = (versao, a["udid"], a["name"])
if melhor is None:
    sys.exit("nenhum iPhone simulado disponível")
print(melhor[1])
versao = ".".join(map(str, melhor[0]))
print(f"simulador: {melhor[2]}, iOS {versao}", file=sys.stderr)
')

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
# Responde "<id>: <pid>".
xcrun simctl launch "$UDID" "$ID" | tee "$OUT/launch.txt"
PID=$(sed 's/.*: *//' "$OUT/launch.txt")

sleep 40
xcrun simctl io "$UDID" screenshot "$OUT/tela.png"
xcrun simctl spawn "$UDID" log show --last 5m --style compact \
  --predicate 'process == "Runner"' > "$OUT/log.txt" 2>&1 || true
cp ~/Library/Logs/DiagnosticReports/Runner* "$OUT/" 2>/dev/null || true

if kill -0 "$PID" 2>/dev/null; then
  echo "o app continua aberto depois de 40 s"
else
  echo "::error::o app fechou sozinho no simulador (ver log.txt e o relatório de falha)"
  exit 1
fi
