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

- `9119` — web dashboard (basic auth: user/pass from `.env`). **Open `/login`, not `/`.**
- `8642` — OpenAI-compatible API (Bearer `API_SERVER_KEY` from `.env`)

## Known issue: dashboard root 500

With basic auth and a single provider, Hermes' auto-SSO middleware redirects the bare
root `/` to `/auth/login?provider=basic`, which 500s (it assumes an OAuth flow the
password-only provider doesn't implement). **Workaround: use `http://localhost:9119/login`**
— it renders the password form, login succeeds, and the dashboard then loads at `/`
normally. This is upstream Hermes behavior, not a misconfiguration; don't try to "fix" it
by changing our config. The API on `8642` is unaffected.

## Gotchas

- The container's init migrates `data/config.yaml` on first run; `config set` works even
  on an empty `data/`.
- Dashboard binds to `0.0.0.0` inside the container, so basic auth is mandatory — that's
  why `.env` carries `HERMES_DASHBOARD_BASIC_AUTH_*`.
- `API_SERVER_CORS_ORIGINS=*` and `0.0.0.0` binding are for local hackathon convenience.
  Tighten before any internet exposure.
