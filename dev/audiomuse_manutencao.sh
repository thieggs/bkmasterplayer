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
#   analisar Pede ao AudioMuse para analisar o que ainda não tem análise, sem
#            esperar. A troca automática pelo hi-fi (melhora_qualidade.py) põe
#            música nova o dia inteiro, e o AudioMuse não analisa sozinho:
#            sem análise a música não tem vetor, e a rádio que parte dela não
#            tem como seguir o método escolhido.
#
# O bk-vetores.service roda alinhar, exporta e roda analisar, de hora em hora:
# o que a análise terminar entra no arquivo da hora seguinte.
#
# Uso: ./dev/audiomuse_manutencao.sh vigia|alinhar|analisar
set -uo pipefail
COMPOSE=/media/thieggs/RAID0/audiomuse/docker-compose.yml
DB=audiomuse-postgres
WEB=audiomuse-ai-flask-app
URL=http://localhost:8010/api/health
NAVIDROME_DB=/media/thieggs/RAID0/navidrome/data/navidrome.db
MARCA=$HOME/.local/share/bk-analyzer/analise-pedida

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
      # A linha nasce junto com o pedido; se some, o AudioMuse apagou o
      # registro (o fim de uma análise limpa o task_status, visto em
      # 23/10/2026). Esperar por ela só travava o timer por 20 minutos.
      "") echo "o registro do alinhamento sumiu; fica para a próxima" >&2; return 1 ;;
    esac
    sleep 10
  done
  echo "alinhamento demorou demais" >&2
  return 1
}

analisar() {
  vigia || return 1
  # As músicas do Navidrome que o AudioMuse não conhece: "quantas id id id...".
  local pendentes n
  pendentes=$(docker exec "$DB" psql -U audiomuse -d audiomusedb -Atc \
      "select provider_track_id from track_server_map where provider_track_id <> ''" |
    python3 -I -c '
import sqlite3, sys
conhecidas = set(sys.stdin.read().split())
db = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
falta = sorted(i for (i,) in db.execute("select id from media_file where missing = 0") if i not in conhecidas)
print(len(falta), *falta)
' "$NAVIDROME_DB") || return 1
  n=${pendentes%% *}
  if [ "$n" = 0 ]; then
    echo "nada sem análise"
    return 0
  fi
  # Só pede de novo quando a lista muda: música que falha sempre (arquivo
  # quebrado) não pode fazer o AudioMuse varrer a biblioteca toda de hora em hora.
  if [ -f "$MARCA" ] && [ "$(cat "$MARCA")" = "$(md5sum <<<"$pendentes")" ]; then
    echo "$n sem análise, já pedida"
    return 0
  fi
  local codigo
  codigo=$(docker exec "$WEB" sh -c 'cd /app && python3 -c "
from flask_app import app
from app_analysis import start_analysis_endpoint
with app.test_request_context(json={}):
    print(start_analysis_endpoint()[1])
"' 2>/dev/null | tail -1)
  case "$codigo" in
    202) md5sum <<<"$pendentes" >"$MARCA"; echo "$n sem análise: análise pedida" ;;
    409) echo "$n sem análise; o AudioMuse está ocupado, fica para a próxima" ;;
    *) echo "não consegui pedir a análise (resposta: ${codigo:-nenhuma})" >&2; return 1 ;;
  esac
}

case "${1:-}" in
  vigia) vigia ;;
  alinhar) alinhar ;;
  analisar) analisar ;;
  *) echo "uso: $0 vigia|alinhar|analisar" >&2; exit 2 ;;
esac
