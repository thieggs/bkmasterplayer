#!/usr/bin/env bash
# Checkup de bugs e segurança do app inteiro (Flutter, motor Rust, BK Analyzer,
# Android). Roda tudo e mostra um resumo no fim; sai com erro se algo falhou.
#
#   ./dev/auditoria.sh             # tudo (uns 10 min)
#   ./dev/auditoria.sh --rapido    # sem fuzzing e sem os testes longos
#   FUZZ_SECS=300 ./dev/auditoria.sh
#   FUZZ_SSH=thieggs@192.168.1.67 FUZZ_KEY=~/.ssh/id_segunda_tela ./dev/auditoria.sh
#       (fuzzing também no notebook, com todos os núcleos de lá)
#
# O que roda (ver docs/SEGURANCA.md):
#   1. dependências com vulnerabilidade conhecida (cargo-audit, osv-scanner)
#   2. licenças das dependências Rust (cargo-deny, política em app/rust/deny.toml)
#   3. segredos no histórico do git (gitleaks)
#   4. análise estática (clippy sem avisos, flutter analyze, semgrep)
#   5. testes (cargo test, flutter test)
#   6. fuzzing do decodificador de áudio (arquivos corrompidos de propósito)
#   7. validação das análises gravadas (nenhuma real pode ser recusada)
#   8. Android: componentes exportados, backup, depuração
#
# As ferramentas que faltam são baixadas (versão fixa, SHA-256 conferido) para
# ~/.cache/bk-auditoria. Nada é instalado no sistema.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/app"
RUST="$APP/rust"
TOOLS="${XDG_CACHE_HOME:-$HOME/.cache}/bk-auditoria/bin"
FAST=0
[ "${1:-}" = "--rapido" ] && FAST=1
FUZZ_SECS="${FUZZ_SECS:-90}"
mkdir -p "$TOOLS"

RESULTS=()
FAILED=0
ok() { RESULTS+=("✔ $1"); }
bad() { RESULTS+=("✘ $1"); FAILED=1; }
info() { RESULTS+=("• $1"); }
step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

# baixar <nome> <url> <sha256> [arquivo dentro do tar]
fetch() {
  local name=$1 url=$2 sum=$3 inner=${4:-}
  [ -x "$TOOLS/$name" ] && return 0
  local tmp
  tmp=$(mktemp)
  curl -fsSL -o "$tmp" "$url" || { rm -f "$tmp"; return 1; }
  if [ "$(sha256sum "$tmp" | cut -c1-64)" != "$sum" ]; then
    echo "SHA-256 de $name não confere: download recusado" >&2
    rm -f "$tmp"
    return 1
  fi
  if [ -n "$inner" ]; then
    tar -xzf "$tmp" -C "$TOOLS" --strip-components="$(tr -cd / <<<"$inner" | wc -c)" "$inner"
  else
    install -m 755 "$tmp" "$TOOLS/$name"
  fi
  rm -f "$tmp"
}

step "ferramentas"
fetch osv-scanner https://github.com/google/osv-scanner/releases/download/v2.6.0/osv-scanner_linux_amd64 \
  ca69b3d3cd08f889a49dc0a383122f71cc528b83803671df5fd874d97485b108
fetch gitleaks https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz \
  551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb gitleaks
fetch cargo-deny https://github.com/EmbarkStudios/cargo-deny/releases/download/0.20.2/cargo-deny-0.20.2-x86_64-unknown-linux-musl.tar.gz \
  9f12ed4c49936e09b48bf862b595cde2fe64fcbd9d74dfacac6131ca824c8d5f cargo-deny-0.20.2-x86_64-unknown-linux-musl/cargo-deny
fetch cargo-audit https://github.com/rustsec/rustsec/releases/download/cargo-audit/v0.22.2/cargo-audit-x86_64-unknown-linux-musl-v0.22.2.tgz \
  7fb9497f8594b389e5fce5ef9b92db08432996895b2e0c5a0167a69ed445c428 cargo-audit-x86_64-unknown-linux-musl-v0.22.2/cargo-audit
ls "$TOOLS"

step "1. dependências com vulnerabilidade conhecida"
if out=$(cd "$RUST" && "$TOOLS/cargo-audit" audit 2>&1); then
  warn=$(grep -c '^Warning:' <<<"$out")
  ok "cargo-audit: nenhuma vulnerabilidade ($warn avisos de manutenção em dependências indiretas)"
else
  echo "$out" | grep -E '^(Crate|ID|Title|Solution)' | head -20
  bad "cargo-audit: vulnerabilidade em dependência Rust (acima)"
fi
# Avisos só informativos da RustSec ("sem manutenção") não reprovam.
osv=$("$TOOLS/osv-scanner" scan source --format json -L "$APP/pubspec.lock" -L "$RUST/Cargo.lock" 2>/dev/null |
  python3 -c '
import json, sys
real, infos = [], []
for r in json.load(sys.stdin).get("results", []):
    for p in r["packages"]:
        for v in p["vulnerabilities"]:
            inf = any((a.get("database_specific") or {}).get("informational") for a in v.get("affected", []))
            (infos if inf else real).append(p["package"]["name"] + " " + v["id"])
print(len(real), "|", ", ".join(real), "|", len(infos))')
IFS='|' read -r nreal list ninfo <<<"$osv"
if [ "${nreal// /}" = "0" ]; then
  ok "osv-scanner (Dart + Rust): nenhuma vulnerabilidade (${ninfo// /} avisos de manutenção)"
else
  bad "osv-scanner: vulnerabilidade conhecida:$list"
fi

step "2. licenças"
if (cd "$RUST" && "$TOOLS/cargo-deny" check licenses >/dev/null 2>&1); then
  ok "cargo-deny: todas as licenças Rust dentro da política (deny.toml)"
else
  (cd "$RUST" && "$TOOLS/cargo-deny" check licenses 2>&1 | grep -E 'error|rejected' | head -10)
  bad "cargo-deny: licença fora da política"
fi

step "3. segredos no git"
if (cd "$ROOT" && "$TOOLS/gitleaks" git . --redact --no-banner >/dev/null 2>&1); then
  ok "gitleaks: nenhum segredo no histórico ($(cd "$ROOT" && git rev-list --count HEAD) commits)"
else
  (cd "$ROOT" && "$TOOLS/gitleaks" git . --redact --no-banner 2>&1 | grep -E 'RuleID|File|Line' | head -12)
  bad "gitleaks: possível segredo no histórico (acima)"
fi
if (cd "$ROOT" && git ls-files --error-unmatch app/android/key.properties >/dev/null 2>&1); then
  bad "app/android/key.properties está no git!"
else
  ok "chave de assinatura do Android fora do git"
fi

step "4. análise estática"
if (cd "$RUST" && cargo clippy --all-targets --features analyzer-server -- -D warnings >/dev/null 2>&1); then
  ok "clippy: zero avisos (Rust, com o BK Analyzer)"
else
  (cd "$RUST" && cargo clippy --all-targets --features analyzer-server --message-format short 2>&1 | grep -E '^(src|tests|examples)/' | head -15)
  bad "clippy: avisos (acima)"
fi
if (cd "$APP" && flutter analyze >/dev/null 2>&1); then
  ok "flutter analyze: nenhum problema"
else
  (cd "$APP" && flutter analyze 2>&1 | grep -E 'error|warning|info' | head -15)
  bad "flutter analyze: problemas (acima)"
fi
if command -v semgrep >/dev/null; then
  # Regras que já foram revisadas: unsafe (libc/JNI, com comentário SAFETY),
  # argumentos de linha de comando e pasta temporária (testes e fallback).
  SG=$(mktemp)
  (cd "$ROOT" && semgrep scan --metrics=off --quiet --config p/rust --config p/secrets --config p/kotlin \
    --exclude 'frb_generated*' --exclude 'app/rust/examples' --json -o "$SG" \
    app/rust/src app/android/app/src app/lib dev >/dev/null 2>&1)
  sg=$(python3 - "$SG" <<'PY'
import json, sys
known = {"unsafe-usage", "args", "temp-dir"}
r = json.load(open(sys.argv[1]))["results"]
rule = lambda x: x["check_id"].split(".")[-1]
new = [rule(x) + " " + x["path"] + ":" + str(x["start"]["line"]) for x in r if rule(x) not in known]
print("NOVO " + "; ".join(new) if new else "OK " + str(len(r)))
PY
)
  rm -f "$SG"
  if [[ $sg == OK* ]]; then
    ok "semgrep (rust, kotlin, segredos): ${sg#OK } achados, todos já revisados (unsafe documentado, args, temp)"
  else
    bad "semgrep: ${sg#NOVO }"
  fi
else
  info "semgrep não instalado (pipx install semgrep): pulado"
fi

step "5. testes"
if [ $FAST = 1 ]; then
  rust_tests=(--lib --bins)
else
  rust_tests=()
fi
if out=$(cd "$RUST" && cargo test --features analyzer-server "${rust_tests[@]}" 2>&1); then
  ok "cargo test: $(grep -E '^test result' <<<"$out" | awk '{s+=$4} END {print s}') testes Rust passaram"
else
  grep -E 'FAILED|panicked' <<<"$out" | head -10
  bad "cargo test: falhas (acima)"
fi
if out=$(cd "$APP" && flutter test 2>&1); then
  ok "flutter test: $(grep -oE '\+[0-9]+' <<<"$out" | tail -1 | tr -d +) testes Flutter passaram"
else
  grep -E 'FAILED|Expected|Actual|\[E\]' <<<"$out" | head -10
  bad "flutter test: falhas (acima)"
fi

step "6. fuzzing do decodificador"
mapfile -d '' SAMPLES < <(find "$ROOT/dev/music" -type f \( -name '*.mp3' -o -name '*.flac' -o -name '*.ogg' -o -name '*.m4a' -o -name '*.opus' -o -name '*.wav' \) -size -3M -print0 2>/dev/null)
if [ $FAST = 1 ]; then
  info "fuzzing pulado (--rapido)"
elif [ ${#SAMPLES[@]} -eq 0 ]; then
  info "fuzzing pulado: sem amostras em dev/music (dev/tools/gen_test_music.py)"
else
  (cd "$RUST" && cargo build --release --example fuzz_decode >/dev/null 2>&1)
  FZ="$RUST/target/release/examples/fuzz_decode"
  OUT=$(mktemp -d)
  jobs=$(( $(nproc) / 2 ))
  [ $jobs -lt 1 ] && jobs=1
  for s in $(seq $jobs); do
    nice -n 10 "$FZ" --secs "$FUZZ_SECS" --seed "$RANDOM$s" --out "$OUT/l$s" "${SAMPLES[@]}" >"$OUT/l$s.log" 2>&1 &
  done
  if [ -n "${FUZZ_SSH:-}" ]; then
    SSH=(ssh -o BatchMode=yes -o ConnectTimeout=5 ${FUZZ_KEY:+-i "$FUZZ_KEY"} "$FUZZ_SSH")
    if "${SSH[@]}" 'mkdir -p /tmp/bk-fuzz/c' && scp -q -o BatchMode=yes ${FUZZ_KEY:+-i "$FUZZ_KEY"} "$FZ" "$FUZZ_SSH:/tmp/bk-fuzz/" &&
      i=0 && for f in "${SAMPLES[@]}"; do i=$((i + 1)); scp -q -o BatchMode=yes ${FUZZ_KEY:+-i "$FUZZ_KEY"} "$f" "$FUZZ_SSH:/tmp/bk-fuzz/c/$i.${f##*.}"; done; then
      "${SSH[@]}" "cd /tmp/bk-fuzz && for s in \$(seq \$(nproc)); do (nice -n 10 ./fuzz_decode --secs $FUZZ_SECS --seed \$RANDOM\$s --out o\$s c/* > o\$s.log 2>&1 &); done; sleep $((FUZZ_SECS + 5)); cat o*.log; rm -rf /tmp/bk-fuzz" >"$OUT/remoto.log" 2>&1 &
    fi
  fi
  wait
  cases=$(cat "$OUT"/*.log | grep -oE '^[0-9]+ casos' | awk '{s+=$1} END {print s+0}')
  if grep -qE 'PÂNICO|TRAVOU' "$OUT"/*.log; then
    grep -hE 'PÂNICO|TRAVOU|caso:' "$OUT"/*.log | head -10
    bad "fuzzing: pânico ou travamento em $cases arquivos corrompidos (casos em $OUT)"
  else
    ok "fuzzing: $cases arquivos de áudio corrompidos, nenhum pânico nem travamento"
    rm -rf "$OUT"
  fi
fi

step "7. análises gravadas"
(cd "$RUST" && cargo build --release --example check_analyses >/dev/null 2>&1)
for d in "$HOME/.local/share/bk-analyzer/analyses" "${XDG_CACHE_HOME:-$HOME/.cache}/io.github.playermusica.player_musica/analysis"; do
  [ -d "$d" ] || continue
  if out=$("$RUST/target/release/examples/check_analyses" "$d" 2>&1); then
    ok "análises reais aceitas pela validação: $(tail -1 <<<"$out") — ${d/#$HOME/~}"
  else
    echo "$out" | head
    bad "validação recusou análise de verdade em ${d/#$HOME/~}"
  fi
done

step "8. Android"
MAN="$APP/android/app/src/main/AndroidManifest.xml"
exported=$(grep -B3 'android:exported="true"' "$MAN" | grep -oE 'android:name="[^"]+"' | sed 's/android:name=//; s/"//g' | tr '\n' ' ')
info "componentes exportados (esperados: tela, serviço de mídia, botão de mídia, capas do Android Auto): $exported"
if grep -q 'android:debuggable="true"' "$MAN"; then bad "manifest com debuggable=true"; else ok "manifest sem debuggable"; fi
if grep -q 'dataExtractionRules' "$MAN" && grep -q 'FlutterSecureStorage' "$APP/android/app/src/main/res/xml/data_extraction_rules.xml"; then
  ok "backup do Android sem as credenciais cifradas"
else
  bad "backup do Android levaria as credenciais cifradas"
fi

printf '\n\033[1m== Resumo\033[0m\n'
printf '%s\n' "${RESULTS[@]}"
exit $FAILED
