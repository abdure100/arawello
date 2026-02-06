#!/usr/bin/env bash
# Quick sanity check for Docker deploy on remote server.
# Run on the server: bash -s < ./scripts/check-remote-deploy.sh
# Or: ssh ... 'bash -s' < ./scripts/check-remote-deploy.sh
set -euo pipefail

REMOTE_DIR="${REMOTE_DIR:-$HOME/openclaw}"
DATA_DIR="${REMOTE_DATA_DIR:-$(dirname "$REMOTE_DIR")/openclaw-data}"

echo "=== Remote deploy check (REMOTE_DIR=$REMOTE_DIR, DATA_DIR=$DATA_DIR) ==="
cd "$REMOTE_DIR"

echo ""
echo "1. Gateway container"
docker compose ps openclaw-gateway 2>/dev/null || true

echo ""
echo "2. Image (openclaw:local)"
docker compose images openclaw-gateway 2>/dev/null || docker images openclaw:local --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}" || true

echo ""
echo "3. Server .env (required vars; values redacted)"
if [[ -f .env ]]; then
  for key in OPENCLAW_CONFIG_DIR OPENCLAW_WORKSPACE_DIR OPENCLAW_GATEWAY_TOKEN OPENAI_COMPAT_API_KEY OPENAI_COMPAT_BASE_URL; do
    if grep -q "^${key}=" .env 2>/dev/null; then
      echo "  $key is set"
    else
      echo "  $key is MISSING"
    fi
  done
else
  echo "  .env not found in $REMOTE_DIR"
fi

echo ""
echo "4. Config (bind + optional allowInsecureAuth)"
if [[ -f "$DATA_DIR/.openclaw/openclaw.json" ]]; then
  grep -E '"bind"|"allowInsecureAuth"' "$DATA_DIR/.openclaw/openclaw.json" 2>/dev/null || echo "  (no bind/allowInsecureAuth found)"
else
  echo "  $DATA_DIR/.openclaw/openclaw.json not found"
fi

echo ""
echo "5. Last 20 gateway log lines"
docker compose logs --tail 20 openclaw-gateway 2>/dev/null || echo "  (no logs)"

echo ""
echo "6. Gateway port listening"
ss -ltnp 2>/dev/null | grep 18789 || true

echo ""
echo "7. Control UI chat updates (in running container bundle)"
CONTAINER=$(docker compose ps -q openclaw-gateway 2>/dev/null || true)
if [[ -n "$CONTAINER" ]]; then
  if docker exec "$CONTAINER" sh -c 'grep -q "gatewayConnecting" /app/dist/control-ui/assets/*.js 2>/dev/null'; then
    echo "  gatewayConnecting (Connect button state): present"
  else
    echo "  gatewayConnecting: NOT FOUND (chat UI may be old)"
  fi
  if docker exec "$CONTAINER" sh -c 'grep -q "No text in response" /app/dist/control-ui/assets/*.js 2>/dev/null'; then
    echo "  empty-assistant placeholder: present"
  else
    echo "  empty-assistant placeholder: NOT FOUND"
  fi
else
  echo "  (container not running, skip)"
fi

echo ""
echo "Done. If container is Up, .env has OPENCLAW_* and OPENAI_COMPAT_*, and logs show no errors, you are good."
