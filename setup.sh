#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Hermes Agent — one-shot bootstrap.
# Idempotent: safe to run repeatedly. Brings a fresh clone to a running state.
#
#   ./setup.sh          # bootstrap + start
#   ./setup.sh --no-up  # bootstrap only, don't start the service
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

MODEL_PROVIDER="anthropic"
MODEL_DEFAULT="anthropic/claude-opus-4.8"

say()  { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

gen_secret() { openssl rand -hex 32; }
gen_pass()   { openssl rand -base64 12 | tr -d '/+=' | cut -c1-16; }

# 1. Prerequisites ----------------------------------------------------------
command -v docker >/dev/null   || die "Docker is not installed."
docker info >/dev/null 2>&1    || die "Docker daemon is not running. Start Docker Desktop."
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required."
ok "Docker is available."

# 2. Create .env from template (generating fresh secrets) -------------------
if [ ! -f .env ]; then
  say "No .env found — creating one from .env.example with fresh secrets."
  cp .env.example .env
  # Fill the random secrets (portable in-place sed for macOS + Linux).
  sed -i.bak \
    -e "s|^API_SERVER_KEY=.*|API_SERVER_KEY=$(gen_secret)|" \
    -e "s|^HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=.*|HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=$(gen_pass)|" \
    -e "s|^HERMES_DASHBOARD_BASIC_AUTH_SECRET=.*|HERMES_DASHBOARD_BASIC_AUTH_SECRET=$(gen_secret)|" \
    .env && rm -f .env.bak
  ok "Created .env."
fi

# 3. Require a real Anthropic key -------------------------------------------
if grep -q 'sk-ant-REPLACE_ME' .env; then
  cat >&2 <<'EOF'

  ⚠  Your Anthropic API key is not set yet.
     Edit .env and replace the ANTHROPIC_API_KEY value with your real key:

         ANTHROPIC_API_KEY=sk-ant-...

     Get one at https://console.anthropic.com — then re-run ./setup.sh
EOF
  exit 1
fi
ok "Anthropic API key is set."

# 4. Pull the image ---------------------------------------------------------
say "Pulling Hermes image..."
docker compose pull
ok "Image ready."

# 5. Configure model non-interactively --------------------------------------
# The container's init creates/migrates ./data/config.yaml on first run.
say "Configuring model: provider=$MODEL_PROVIDER, default=$MODEL_DEFAULT"
docker compose run --rm --no-TTY hermes config set model.provider "$MODEL_PROVIDER" >/dev/null
docker compose run --rm --no-TTY hermes config set model.default  "$MODEL_DEFAULT"  >/dev/null
ok "Model configured."

# 6. Start (unless --no-up) -------------------------------------------------
if [ "${1:-}" = "--no-up" ]; then
  ok "Bootstrap complete (service not started; pass no flag to start it)."
  exit 0
fi

say "Starting Hermes (gateway + dashboard)..."
docker compose up -d

# 7. Wait for the dashboard to answer ---------------------------------------
say "Waiting for the dashboard to come up..."
for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9119 || true)
  case "$code" in 200|302|401) break;; esac
  sleep 2
done

USER=$(grep '^HERMES_DASHBOARD_BASIC_AUTH_USERNAME=' .env | cut -d= -f2-)
PASS=$(grep '^HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=' .env | cut -d= -f2-)

cat <<EOF

$(ok "Hermes is running.")

  Web dashboard : http://localhost:9119/login   (login: $USER / $PASS)
  API endpoint  : http://localhost:8642          (Bearer token = API_SERVER_KEY in .env)

  NOTE: open the dashboard at /login  — the bare root (/) hits an upstream
        Hermes redirect bug (500) when using basic auth. /login works fine.

  Logs : docker compose logs -f
  Chat : docker compose run --rm hermes chat
  Stop : docker compose down
EOF
