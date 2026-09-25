#!/usr/bin/env bash
# Instala o BK Analyzer (análise do AutoMix no servidor) como serviço do
# systemd de usuário.
#
#   ./dev/install_analyzer.sh server
#       coordenador nesta máquina (a do Navidrome): painel em http://<ip>:4540
#
#   ./dev/install_analyzer.sh worker <ssh-destino> <endereço do coordenador> [jobs]
#       trabalhador em outra máquina, por SSH, ex.:
#       ./dev/install_analyzer.sh worker usuario@192.168.1.67 http://maquina-de-casa.local:4540
#       (sem jobs: 1 análise a cada 3 threads da CPU, até 4)
#       O token vem do coordenador desta máquina e fica num arquivo 0600 lá.
#       SSH_OPTS="-i ~/.ssh/chave" para escolher a chave.
#
# Compila antes: cargo build --release --features analyzer-server --bin bk-analyzer
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/app/rust/target/release/bk-analyzer"
[ -x "$BIN" ] || (cd "$ROOT/app/rust" && cargo build --release --features analyzer-server --bin bk-analyzer)

case "${1:-}" in
server)
  mkdir -p ~/.local/bin ~/.config/systemd/user
  install -m 755 "$BIN" ~/.local/bin/bk-analyzer
  cat > ~/.config/systemd/user/bk-analyzer.service <<'EOF'
[Unit]
Description=BK Analyzer: coordenador da análise do AutoMix (painel na porta 4540)
After=network-online.target

[Service]
ExecStart=%h/.local/bin/bk-analyzer serve --listen 0.0.0.0:4540
Restart=on-failure
RestartSec=5
Nice=5

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable bk-analyzer.service
  systemctl --user restart bk-analyzer.service
  echo "coordenador no ar: http://$(hostname).local:4540 (entre com a conta do Navidrome)"
  ;;
worker)
  DEST="$2"; SERVER="$3"; JOBS="${4:-}"
  TOKEN="$(~/.local/bin/bk-analyzer token 2>/dev/null || "$BIN" token)"
  # shellcheck disable=SC2086
  scp ${SSH_OPTS:-} -q "$BIN" "$DEST:/tmp/bk-analyzer.new"
  # shellcheck disable=SC2086
  ssh ${SSH_OPTS:-} "$DEST" bash -s -- "$SERVER" "$JOBS" <<EOF
set -euo pipefail
mkdir -p ~/.local/bin ~/.config/systemd/user ~/.config/bk-analyzer
install -m 755 /tmp/bk-analyzer.new ~/.local/bin/bk-analyzer && rm -f /tmp/bk-analyzer.new
umask 077
printf 'BK_ANALYZER_SERVER=%s\nBK_ANALYZER_TOKEN=%s\n' "\$1" "$TOKEN" > ~/.config/bk-analyzer/worker.env
cat > ~/.config/systemd/user/bk-analyzer-worker.service <<UNIT
[Unit]
Description=BK Analyzer: trabalhador da análise do AutoMix
After=network-online.target

[Service]
EnvironmentFile=%h/.config/bk-analyzer/worker.env
ExecStart=%h/.local/bin/bk-analyzer worker \${2:+--jobs \$2}
Restart=always
RestartSec=30
Nice=15

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable bk-analyzer-worker.service
systemctl --user restart bk-analyzer-worker.service
systemctl --user --no-pager status bk-analyzer-worker.service | head -5
EOF
  ;;
*)
  sed -n '2,15p' "$0"; exit 2 ;;
esac
