#!/usr/bin/env bash
# Deploy OpenClaw Docker stack to a remote Ubuntu server.
# Usage (run with bash so zsh does not parse the script):
#   bash ./scripts/deploy-docker-to-server.sh
#   OPENCLAW_DEPLOY_HOST=devdb.sphereemr.com OPENCLAW_DEPLOY_KEY=/path/to/key.pem bash ./scripts/deploy-docker-to-server.sh
# Or set env then run:
#   export OPENCLAW_DEPLOY_HOST=devdb.sphereemr.com OPENCLAW_DEPLOY_KEY=/path/to/key.pem
#   bash ./scripts/deploy-docker-to-server.sh
#
# Prerequisites on server: Docker and Docker Compose (script can install them if INSTALL_DOCKER=1).
# Your repo root must have: docker-compose.yml, Dockerfile, .openclaw-docker/ (or OPENCLAW_CONFIG_DIR set), .env (optional).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SSH_KEY="${SSH_KEY:-${OPENCLAW_DEPLOY_KEY:-}}"
SSH_USER="${SSH_USER:-${OPENCLAW_DEPLOY_USER:-ubuntu}}"
SSH_HOST="${SSH_HOST:-${OPENCLAW_DEPLOY_HOST:-}}"
REMOTE_DIR="${REMOTE_DIR:-${OPENCLAW_DEPLOY_DIR:-~/openclaw}}"
# Data dir on server (config + workspace). Default: same parent as REMOTE_DIR, openclaw-data
REMOTE_DATA_DIR="${REMOTE_DATA_DIR:-${OPENCLAW_DEPLOY_DATA_DIR:-}}"
if [[ -z "$REMOTE_DATA_DIR" ]]; then
  REMOTE_DATA_DIR="$(dirname "$REMOTE_DIR")/openclaw-data"
fi
SKIP_SYNC="${SKIP_SYNC:-0}"
RUN_REMOTE="${RUN_REMOTE:-1}"
INSTALL_DOCKER="${INSTALL_DOCKER:-0}"

CONFIG_SOURCE="${OPENCLAW_CONFIG_DIR:-$ROOT_DIR/.openclaw-docker}"
if [[ ! -d "$CONFIG_SOURCE" ]]; then
  echo "Config source not found: $CONFIG_SOURCE" >&2
  echo "Set OPENCLAW_CONFIG_DIR to a dir containing openclaw.json, or create .openclaw-docker/" >&2
  exit 1
fi

if [[ -z "$SSH_HOST" ]]; then
  echo "Usage: SSH_HOST=devdb.sphereemr.com [SSH_KEY=path/to/key.pem] [SSH_USER=ubuntu] $0" >&2
  echo "  Or: OPENCLAW_DEPLOY_HOST=devdb.sphereemr.com OPENCLAW_DEPLOY_KEY=/path/to/key.pem $0" >&2
  exit 1
fi

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
[[ -n "${SSH_KEY:-}" && -f "$SSH_KEY" ]] && SSH_OPTS+=(-i "$SSH_KEY")
SSH_CMD=(ssh "${SSH_OPTS[@]}" "$SSH_USER@$SSH_HOST")
RSYNC_SSH="ssh ${SSH_OPTS[*]}"
RSYNC_DEST="$SSH_USER@$SSH_HOST"

echo "==> Target: $SSH_USER@$SSH_HOST ($REMOTE_DIR)"
echo "==> Config source: $CONFIG_SOURCE"
echo "==> Remote data dir: $REMOTE_DATA_DIR"

if [[ "$SKIP_SYNC" != "1" ]]; then
  echo "==> Creating remote dirs"
  "${SSH_CMD[@]}" "mkdir -p $REMOTE_DIR $REMOTE_DATA_DIR/.openclaw $REMOTE_DATA_DIR/workspace"

  echo "==> Syncing repo (Dockerfile, docker-compose, package files, source)"
  # REMOTE_DIR should contain only this repo; if you see "cannot delete non-empty directory", clean the remote:
  #   ssh ... 'rm -rf ~/openclaw/Desktop ~/openclaw/.vscode ~/openclaw/.cursor 2>/dev/null; true'
  rsync -avz --delete \
    -e "$RSYNC_SSH" \
    --exclude=.git \
    --exclude=node_modules \
    --exclude=dist \
    --exclude=ui/node_modules \
    --exclude=.openclaw-docker \
    --exclude=.env \
    --exclude=modifications \
    "$ROOT_DIR/" "$RSYNC_DEST:$REMOTE_DIR/"

  echo "==> Syncing config to $REMOTE_DATA_DIR/.openclaw"
  rsync -avz -e "$RSYNC_SSH" \
    "$CONFIG_SOURCE/" "$RSYNC_DEST:$REMOTE_DATA_DIR/.openclaw/"

  echo "==> Writing server .env"
  GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"
  if [[ -z "$GATEWAY_TOKEN" && -f "$ROOT_DIR/.env" ]]; then
    GATEWAY_TOKEN=$(grep -E '^OPENCLAW_GATEWAY_TOKEN=' "$ROOT_DIR/.env" 2>/dev/null | cut -d= -f2- || true)
  fi
  if [[ -z "$GATEWAY_TOKEN" && -f "$CONFIG_SOURCE/openclaw.json" ]]; then
    GATEWAY_TOKEN=$(grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_SOURCE/openclaw.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || true)
  fi
  if [[ -z "$GATEWAY_TOKEN" ]]; then
    GATEWAY_TOKEN=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))")
    echo "Generated OPENCLAW_GATEWAY_TOKEN (save this): $GATEWAY_TOKEN"
  fi

  ENV_TMP=$(mktemp)
  cat >>"$ENV_TMP" <<ENV
OPENCLAW_CONFIG_DIR=$REMOTE_DATA_DIR/.openclaw
OPENCLAW_WORKSPACE_DIR=$REMOTE_DATA_DIR/workspace
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_BRIDGE_PORT=18790
OPENCLAW_GATEWAY_BIND=lan
OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN
OPENCLAW_IMAGE=openclaw:local
ENV
  if [[ -f "$ROOT_DIR/.env" ]]; then
    while IFS= read -r line; do
      for key in OPENAI_COMPAT_BASE_URL OPENAI_COMPAT_API_KEY CLAUDE_AI_SESSION_KEY CLAUDE_WEB_SESSION_KEY CLAUDE_WEB_COOKIE; do
        if [[ "$line" == "$key="* ]]; then
          echo "$line" >>"$ENV_TMP"
          break
        fi
      done
    done <"$ROOT_DIR/.env"
  fi
  scp "${SSH_OPTS[@]}" "$ENV_TMP" "$SSH_USER@$SSH_HOST:$REMOTE_DIR/.env"
  rm -f "$ENV_TMP"

  echo "==> Ensure gateway binds to lan on server (so it accepts external connections)"
  "${SSH_CMD[@]}" "sed -i.bak 's/\"bind\"[[:space:]]*:[[:space:]]*\"loopback\"/\"bind\": \"lan\"/' $REMOTE_DATA_DIR/.openclaw/openclaw.json 2>/dev/null || true"

  echo "==> Fix permissions for container user (uid 1000)"
  "${SSH_CMD[@]}" "sudo chown -R 1000:1000 $REMOTE_DATA_DIR"
fi

if [[ "$RUN_REMOTE" != "1" ]]; then
  echo "==> Skipping remote build/start (RUN_REMOTE=0). Run on server:"
  echo "  cd $REMOTE_DIR && docker compose build openclaw-gateway && docker compose up -d openclaw-gateway"
  exit 0
fi

echo "==> Running remote setup and start"
"${SSH_CMD[@]}" bash -s "$REMOTE_DIR" "$INSTALL_DOCKER" <<'REMOTE'
set -euo pipefail
REMOTE_DIR="$1"
INSTALL_DOCKER="$2"
cd "$REMOTE_DIR"

# Docker Compose does not expand ~ in .env; use absolute paths so volume mounts work
if [[ -f .env ]] && grep -q 'OPENCLAW_CONFIG_DIR=~/' .env 2>/dev/null; then
  sed -i.bak "s|OPENCLAW_CONFIG_DIR=~/|OPENCLAW_CONFIG_DIR=$HOME/|" .env
  sed -i "s|OPENCLAW_WORKSPACE_DIR=~/|OPENCLAW_WORKSPACE_DIR=$HOME/|" .env
fi

if [[ "$INSTALL_DOCKER" == "1" ]]; then
  echo "Installing Docker..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq git curl ca-certificates
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER" || true
fi

# docker compose reads .env from project dir
echo "Building image..."
docker compose build openclaw-gateway

echo "Starting gateway..."
docker compose up -d openclaw-gateway

echo "Done. Gateway should be up. Check: docker compose logs -f openclaw-gateway"
REMOTE

echo ""
echo "==> Deploy complete."
echo "  Dashboard — use token from server .env or gateway.auth.token in config:"
echo "    http://$SSH_HOST:18789/"
echo "  Or via SSH tunnel — recommended if you do not open port 18789 in cloud firewall:"
echo "    ssh -i ${SSH_KEY:-<key>} -N -L 18789:127.0.0.1:18789 $SSH_USER@$SSH_HOST"
echo "    Then open http://127.0.0.1:18789/"
echo "  Token: see $REMOTE_DIR/.env on server or output above."
