# Hermes Agent — Hackathon Docker Setup

Runs [**Hermes Agent**](https://hermes-agent.nousresearch.com/) (Nous Research, MIT) in
Docker, backed by the **Claude / Anthropic API**.

> Hermes calls a remote model (Claude) over the network — it does **not** host a model
> locally — so **no GPU is required** and it runs fine on a Mac.

What you get:
- 🌐 **Web dashboard** to chat with Hermes in your browser — `http://localhost:9119`
- 🔌 **OpenAI-compatible API** for external clients — `http://localhost:8642` (token-protected)
- 💾 All state (config, sessions, memories, skills) persisted in `./data/`

---

## ⚡ Ask Hermes a question (curl)

Once it's running (`./setup.sh`), send a question to the API:

```bash
KEY=$(grep '^API_SERVER_KEY=' .env | cut -d= -f2-)

curl -s http://localhost:8642/v1/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"What is 7 times 8?"}]}'
```

Want **only the answer text** (no JSON)? Pipe it through `python3`:

```bash
KEY=$(grep '^API_SERVER_KEY=' .env | cut -d= -f2-)

curl -s http://localhost:8642/v1/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"What is 7 times 8?"}]}' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["choices"][0]["message"]["content"])'
```

| | Value |
|---|---|
| **URL** | `http://localhost:8642/v1/chat/completions` |
| **Model** | `hermes-agent` |
| **Auth** | header `Authorization: Bearer <API_SERVER_KEY>` (from `.env`) |
| **Answer** | JSON field `choices[0].message.content` |

> Each request carries Hermes' full agent context (~22k tokens of system prompt, skills,
> and memory), so replies take a few seconds — that's normal for an agent, not a bare model.

---

## Quick start (fresh clone)

```bash
git clone <this-repo>
cd hackathon
./setup.sh
```

The **first** run creates `.env` with fresh random secrets, then stops and asks you to
paste your Anthropic key. Edit `.env`:

```bash
ANTHROPIC_API_KEY=sk-ant-...your-real-key...   # get one at https://console.anthropic.com
```

Then run it again — it pulls the image, configures the model, and starts everything:

```bash
./setup.sh
```

That's it. Open **http://localhost:9119/login** and sign in (credentials are printed at
the end of `setup.sh`, and stored in `.env`).

> ⚠️ Use the **`/login`** path, not the bare `http://localhost:9119/`. With basic auth,
> Hermes' root URL hits an upstream redirect bug that returns a 500. `/login` works
> perfectly — log in there and the dashboard loads normally.

> Prefer `make`? `make setup` does the same thing. Run `make help` to see all targets.

---

## What's in the repo

| File | Purpose | In git? |
|------|---------|---------|
| `docker-compose.yml` | Service definition (gateway API + dashboard) | ✅ |
| `setup.sh` | Idempotent bootstrap script | ✅ |
| `.env.example` | Secrets template | ✅ |
| `Makefile` | Convenience commands | ✅ |
| `CLAUDE.md` | Run instructions for Claude Code | ✅ |
| `.env` | **Your secrets** (Anthropic key, API token, dashboard pass) | ❌ gitignored |
| `data/` | Hermes runtime state | ❌ gitignored |

Because `.env` and `data/` are **not committed**, anyone cloning the repo just runs
`./setup.sh` and pastes their own Anthropic key — no secrets ever leave your machine.

---

## Using it

**Web dashboard** → http://localhost:9119/login
Log in with the username/password in `.env` (`HERMES_DASHBOARD_BASIC_AUTH_*`).
(Use `/login`; the bare `/` 500s with basic auth — see the warning above.)

**API** (for an external interface/client):
```bash
KEY=$(grep '^API_SERVER_KEY=' .env | cut -d= -f2-)
curl http://localhost:8642/v1/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"hermes","messages":[{"role":"user","content":"Hello Hermes!"}]}'
```

**CLI chat:**
```bash
docker compose run --rm hermes chat
```

---

## Commands

| Action | `make` | raw |
|--------|--------|-----|
| Bootstrap + start | `make setup` | `./setup.sh` |
| Start | `make up` | `docker compose up -d` |
| Stop | `make down` | `docker compose down` |
| Logs | `make logs` | `docker compose logs -f` |
| Verify model works | `make test` | `docker compose run --rm --no-TTY hermes -z "say HERMES_OK"` |
| Component status | `make status` | `docker compose run --rm hermes status` |
| Update image | `make pull` | `docker compose pull` |
| **Reset all state** | `make reset` | `docker compose down && rm -rf data` |

---

## Configuration

Model defaults set by `setup.sh` (no interactive wizard needed):
- Provider: **Anthropic** (direct, using your `ANTHROPIC_API_KEY`)
- Model: **`anthropic/claude-opus-4.8`** (Claude Opus 4.8)

Change the model:
```bash
docker compose run --rm --no-TTY hermes config set model.default anthropic/<model-id>
docker compose restart
```

## Ports

| Port | Service | Auth |
|------|---------|------|
| `9119` | Web dashboard (open `/login`) | basic auth (user/pass from `.env`) |
| `8642` | OpenAI-compatible API | Bearer `API_SERVER_KEY` from `.env` |

## Security notes

- `.env` and `./data/` are gitignored — never commit them.
- The API server binds `0.0.0.0` with CORS `*` for hackathon convenience. Lock these
  down before exposing the machine to the internet.
