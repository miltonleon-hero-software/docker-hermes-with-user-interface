# CLAUDE.md — guidance for Claude Code

This project runs **Hermes Agent** (Nous Research, MIT) in Docker, backed by the
**Anthropic / Claude API**. Hermes does NOT host a model locally — it calls Claude's
API over the network, so no GPU is needed and it runs fine on macOS/Linux.

## What lives where

| Path | Purpose | Committed? |
|------|---------|------------|
| `docker-compose.yml` | Service definition (gateway API + web dashboard) | ✅ yes |
| `setup.sh` | Idempotent bootstrap: secrets → config → start | ✅ yes |
| `.env.example` | Template for secrets | ✅ yes |
| `Makefile` | Convenience targets | ✅ yes |
| `.env` | Real secrets (Anthropic key, API token, dashboard pass) | ❌ gitignored |
| `data/` | All Hermes state: config.yaml, sessions, memories, skills, logs | ❌ gitignored |

> Because `.env` and `data/` are gitignored, a **fresh clone has no key and no model
> config**. `setup.sh` regenerates everything except the Anthropic key, which a human
> must paste in.

## How to run this project (fresh clone)

```bash
./setup.sh
```

On a fresh clone with no `.env`, `setup.sh` creates `.env` with fresh random secrets,
then **stops and asks the human to paste their Anthropic key** into `.env`
(`ANTHROPIC_API_KEY=sk-ant-...`). After the key is set, re-run `./setup.sh` — it pulls
the image, configures the model non-interactively, and starts the service.

⚠️ **Do not invent or hardcode an Anthropic API key.** If `ANTHROPIC_API_KEY` is still
`sk-ant-REPLACE_ME`, ask the user for their key; do not proceed past that point.

## Model configuration

`setup.sh` sets these non-interactively (no interactive wizard needed):
- `model.provider = anthropic`
- `model.default  = anthropic/claude-opus-4.8`

To change the model later:
```bash
docker compose run --rm --no-TTY hermes config set model.default anthropic/<model-id>
docker compose restart
```

## Common commands

| Goal | Command |
|------|---------|
| Bootstrap + start | `./setup.sh`  (or `make up`) |
| Start (already configured) | `docker compose up -d` |
| Stop | `docker compose down` |
| Tail logs | `docker compose logs -f` |
| One-shot prompt (verify it works) | `docker compose run --rm --no-TTY hermes -z "say HERMES_OK"` |
| Interactive chat | `docker compose run --rm hermes chat` |
| Status of components | `docker compose run --rm hermes status` |
| Reset all state | `docker compose down && rm -rf data` |

## Verifying a healthy deployment

```bash
docker compose ps                                          # container Up
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9119   # 302 / 401 = dashboard up
KEY=$(grep '^API_SERVER_KEY=' .env | cut -d= -f2-)
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $KEY" http://localhost:8642/v1/models  # 200 = API up
```

## Ports

- `9119` — web dashboard (basic auth: user/pass from `.env`)
- `8642` — OpenAI-compatible API (Bearer `API_SERVER_KEY` from `.env`)

## Patched: dashboard root redirect bug

**Upstream bug:** with a single password-only auth provider, Hermes' "auto-SSO"
middleware redirects the bare root `/` to `/auth/login?provider=basic` — an OAuth-only
route that returns HTTP 500 for password auth. First visit lands on a broken page; a
refresh then works (a loop-guard cookie gets set on the failed redirect).

**Our fix:** `patches/cont-init/99-login-redirect-fix` is mounted into the container's
s6 `/etc/cont-init.d/` and runs at startup, before the gateway imports the module. It
makes a password-capable single provider return early from the auto-SSO path, so the
middleware falls through to the normal login form:

```
"/"  ->  302  ->  /login?next=%2F   (works on the first visit)
```

The patch is idempotent (marker `HERMES_LOGIN_FIX`) and non-fatal: if a future image
changes the code, the anchor won't match and it's silently skipped (boot continues, you'd
just be back to needing `/login` directly). Verify it ran with
`docker compose logs hermes | grep login-fix` (expect `[login-fix] applied`). The API on
`8642` is unaffected by all of this.

## Gotchas

- The container's init migrates `data/config.yaml` on first run; `config set` works even
  on an empty `data/`.
- Dashboard binds to `0.0.0.0` inside the container, so basic auth is mandatory — that's
  why `.env` carries `HERMES_DASHBOARD_BASIC_AUTH_*`.
- `API_SERVER_CORS_ORIGINS=*` and `0.0.0.0` binding are for local hackathon convenience.
  Tighten before any internet exposure.
