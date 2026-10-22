#!/usr/bin/env bash
# Manutenção do AudioMuse que a rádio do app precisa (ver app/lib/player/radio.dart).
#
#   vigia    O AudioMuse está de pé? Se não, conserta. Visto em 22/10/2026:
#            depois de reiniciar o PC o Postgres subiu SEM REDE (o container
#            rodando, mas fora da rede do compose), o app web não achava o
#            banco ("could not translate host name postgres") e desistiu. Sem
#            ele o Navidrome responde erro à análise sônica e a rádio cai no
#            "similar" genérico, de três ou quatro músicas.
#   alinhar  Re-casa as músicas analisadas com o Navidrome (o "sweep" do
#            AudioMuse: só metadados, não baixa nem analisa nada) e espera
#            terminar. Necessário depois que a biblioteca muda: o Navidrome dá
#            outro id à música trocada, e o AudioMuse deixa de conhecê-la — em
#            22/10/2026, depois da troca pela versão hi-fi, 25% da biblioteca
#            estava assim.
#
# Uso: ./dev/audiomuse_manutencao.sh vigia|alinhar
set -uo pipefail
COMPOSE=/media/thieggs/RAID0/audiomuse/docker-compose.yml
DB=audiomuse-postgres
WEB=audiomuse-ai-flask-app
URL=http://localhost:8010/api/health

de_pe() {
  # O Postgres precisa estar numa rede (sem ela ninguém acha o nome "postgres")
  # e o app web precisa responder.
  local redes
  redes=$(docker inspect "$DB" --format '{{len .NetworkSettings.Networks}}' 2>/dev/null) || return 1
  [ "${redes:-0}" -gt 0 ] || return 1
  curl -fs -m 10 -o /dev/null "$URL"
}

vigia() {
  de_pe && return 0
  echo "AudioMuse fora do ar; recriando o Postgres e reiniciando o app web e o trabalhador"
  docker compose -f "$COMPOSE" up -d --force-recreate postgres || return 1
  sleep 5
  docker compose -f "$COMPOSE" restart audiomuse-ai-flask audiomuse-ai-worker || return 1
  for _ in $(seq 1 24); do
    de_pe && { echo "AudioMuse de volta"; return 0; }
    sleep 5
  done
  echo "AudioMuse continua fora do ar" >&2
  return 1
}

alinhar() {
  vigia || return 1
  local tarefa
  tarefa=$(docker exec "$WEB" sh -c 'cd /app && python3 -c "
from flask_app import app
from app_music_servers import _enqueue_sweep
with app.app_context():
    print(_enqueue_sweep(at_front=True) or \"\")
"' 2>/dev/null | tail -1)
  if [ -z "$tarefa" ]; then
    echo "não consegui pedir o alinhamento (outra tarefa rodando?)" >&2
    return 1
  fi
  for _ in $(seq 1 120); do
    linha=$(docker exec "$DB" psql -U audiomuse -d audiomusedb -Atc \
      "select status || '|' || coalesce((details::json)->>'status_message','') from task_status where task_id='$tarefa'")
    case "$linha" in
      SUCCESS*) echo "${linha#*|}"; return 0 ;;
      FAILURE*|REVOKED*) echo "alinhamento falhou: ${linha#*|}" >&2; return 1 ;;
    esac
    sleep 10
  done
  echo "alinhamento demorou demais" >&2
  return 1
}

case "${1:-}" in
  vigia) vigia ;;
  alinhar) alinhar ;;
  *) echo "uso: $0 vigia|alinhar" >&2; exit 2 ;;
esac
