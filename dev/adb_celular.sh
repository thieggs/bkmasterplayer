#!/usr/bin/env bash
# Conecta no celular pelo adb Wi-Fi numa porta fixa (5555), que continua
# valendo mesmo quando a "Depuração sem fio" desliga sozinha — até o celular
# reiniciar. Imprime o endereço conectado (IP:5555).
#
# 1) Tenta o último IP salvo, na porta fixa.
# 2) Se não der (IP mudou, celular reiniciou), acha o celular pela Depuração
#    sem fio (mDNS), conecta e passa para a porta fixa (`adb tcpip 5555`).
#
# Uso: ./dev/adb_celular.sh   (ex.: adb -s "$(./dev/adb_celular.sh)" install app.apk)
set -uo pipefail
SAVED="${XDG_CACHE_HOME:-$HOME/.cache}/bk-adb-celular"
PORT=5555

ok() { timeout 6 adb connect "$1" 2>/dev/null | grep -q "connected to" && timeout 6 adb -s "$1" shell true 2>/dev/null; }
done_at() { mkdir -p "$(dirname "$SAVED")"; echo "${1%%:*}" > "$SAVED"; echo "$1"; exit 0; }

if [ -f "$SAVED" ] && ok "$(cat "$SAVED"):$PORT"; then
  done_at "$(cat "$SAVED"):$PORT"
fi

found=$(timeout 10 avahi-browse -rpt _adb-tls-connect._tcp 2>/dev/null | awk -F';' '$1 == "=" && $3 == "IPv4" {print $8":"$9}' | sort -u | head -1)
if [ -z "$found" ]; then
  echo "celular não encontrado: ligue a Depuração sem fio (Opções do desenvolvedor)" >&2
  exit 1
fi
ip=${found%%:*}
ok "$ip:$PORT" && done_at "$ip:$PORT"

timeout 6 adb connect "$found" >/dev/null 2>&1
timeout 15 adb -s "$found" tcpip "$PORT" >/dev/null 2>&1
sleep 3
adb disconnect "$found" >/dev/null 2>&1
for _ in 1 2 3; do
  ok "$ip:$PORT" && done_at "$ip:$PORT"
  sleep 2
done
echo "não consegui passar para a porta fixa $PORT" >&2
exit 1
