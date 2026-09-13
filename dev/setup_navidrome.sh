#!/usr/bin/env bash
# Sobe o Navidrome de teste, cria o admin (dev/dev) e dispara a varredura da biblioteca.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f music/ground_truth.json ]; then
  python3 tools/gen_test_music.py music
fi

docker compose up -d
echo -n "Aguardando Navidrome"
for _ in $(seq 1 60); do
  if curl -fs http://localhost:4534/ping >/dev/null 2>&1; then break; fi
  echo -n "."; sleep 1
done
echo

# Primeiro acesso: cria o admin (ignora erro se já existir)
curl -fs -X POST http://localhost:4534/auth/createAdmin \
  -H 'Content-Type: application/json' \
  -d '{"username":"dev","password":"dev"}' >/dev/null 2>&1 || true

# Varredura completa via API Subsonic
curl -fs "http://localhost:4534/rest/startScan?u=dev&p=dev&v=1.16.1&c=setup&f=json&fullScan=true" >/dev/null
sleep 3
curl -fs "http://localhost:4534/rest/getScanStatus?u=dev&p=dev&v=1.16.1&c=setup&f=json"
echo
echo "Navidrome pronto em http://localhost:4534  (usuário: dev / senha: dev)"
