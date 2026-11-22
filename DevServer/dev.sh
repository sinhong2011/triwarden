#!/usr/bin/env bash
# Manage the Triwarden dev environment on the remote dev box.
#   ./dev.sh up | seed | test | logs [service] | reset | status
set -euo pipefail
cd "$(dirname "$0")"
REMOTE=${TRIWARDEN_DEV_REMOTE:-m1pro}
HOST=${TRIWARDEN_DEV_HOST:-devbox.local}
IP=${TRIWARDEN_DEV_IP:-192.168.1.50}
DIR=triwarden-dev
remote() { ssh -q "$REMOTE" "export PATH=/usr/local/bin:/opt/homebrew/bin:\$PATH; cd ~/$DIR && $*"; }

case "${1:-status}" in
  up)
    ssh -q "$REMOTE" "mkdir -p ~/$DIR"
    rsync -a compose.yml Caddyfile seed.py "$REMOTE:~/$DIR/"
    sed "s/DEV_IP/$IP/g" dex.yaml | ssh -q "$REMOTE" "mkdir -p ~/$DIR/data && cat > ~/$DIR/data/dex.yaml"
    remote "[ -f .env ] || printf 'DEV_HOST=$HOST\nDEV_IP=$IP\nADMIN_TOKEN=%s\n' \$(openssl rand -hex 24) > .env; docker compose up -d"
    mkdir -p data && sleep 3
    scp -q "$REMOTE:~/$DIR/data/caddy/caddy/pki/authorities/local/root.crt" data/root.crt
    echo "CA saved to DevServer/data/root.crt" ;;
  seed)
    for p in 18843 18844; do echo "== :$p"; python3 seed.py "https://$HOST:$p" --ca data/root.crt; done
    echo "== SSO :18881"; python3 seed.py "http://$IP:18881" ;;
  test)
    cd ../Packages/VaultCore
    TRIWARDEN_DEV_HOST=$HOST TRIWARDEN_DEV_CA="$OLDPWD/data/root.crt" TRIWARDEN_DEV_TOTP_DIR="$OLDPWD/data/totp" swift test ;;
  logs)  remote "docker compose logs --tail 100 ${2:-}" ;;
  reset) remote "docker compose down && rm -rf data/latest data/legacy && docker compose up -d" ;;
  status) remote "docker compose ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}'" ;;
  *) echo "usage: $0 up|seed|test|logs|reset|status"; exit 1 ;;
esac
