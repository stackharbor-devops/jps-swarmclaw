# SwarmClaw — Stack Harbor JPS Package

A production-ready [Jelastic / Virtuozzo Application Platform](https://www.virtuozzo.com/application-platform/)
**JPS package** that deploys [SwarmClaw](https://github.com/swarmclawai/swarmclaw) —
a self-hosted AI agent runtime and multi-agent framework — onto a single
Docker Engine node, end to end, in one import.

---

## What this package deploys

On import, the manifest:

1. Creates a **new environment** with one Docker Engine node.
2. Ensures **Docker Engine + Compose**, `git`, `curl`, `openssl`, `ca-certificates`.
3. Clones SwarmClaw into **`/opt/swarmclaw`**.
4. Creates persistent **`/opt/swarmclaw/data`** and **`/opt/swarmclaw/.env.local`**.
5. Generates **unique credentials** (`ACCESS_KEY`, `CREDENTIAL_SECRET`) — platform-generated, with an `openssl` fallback.
6. Stores them in **`/opt/swarmclaw/.deployment-secrets`** (`chmod 600`) and writes them to `.env.local` (`chmod 600`).
7. Starts SwarmClaw with **Docker Compose** (`docker compose up -d --build`), using the repo's own compose file, and installs the **Claude Code** + **OpenAI Codex** provider CLIs into the container.
8. Ensures the container **restarts after reboot** (`restart: unless-stopped`).
9. Exposes SwarmClaw via the **environment URL** (host `:80` → container `:3456`).
10. **Health-checks** `http://127.0.0.1:3456/api/healthz`.
11. **Emails** the customer the deployment details.
12. Shows a **success panel** in the dashboard.

---

## Deployment architecture

```
  ┌──────────────────────────────────────────────┐
  │  Jelastic / Virtuozzo Environment             │
  │                                                │
  │   nodeGroup: cp                                │
  │   ┌──────────────────────────────────────┐    │
  │   │  Docker Engine node                   │    │
  │   │                                        │    │
  │   │   /opt/swarmclaw  (git checkout)       │    │
  │   │     ├─ docker-compose.yml (upstream)   │    │
  │   │     ├─ docker-compose.override.yml     │    │
  │   │     ├─ .env.local        (600)         │    │
  │   │     ├─ .deployment-secrets (600)       │    │
  │   │     ├─ data/             (persistent)  │    │
  │   │     └─ scripts/ (install/start/…)      │    │
  │   │                                        │    │
  │   │   docker compose ─► container          │    │
  │   │      swarmclaw  host :80 → :3456        │    │
  │   └──────────────────────────────────────┘    │
  └──────────────────────────────────────────────┘
            ▲
            │  ${env.url}   (dashboard "Open in Browser" → host :80)
            └── customer browser
```

Single node, no Kubernetes, no HA (v1). Docker provides Node.js 22.6+ inside the
container, so the host OS version is irrelevant.

---

## How to import (Virtuozzo / Jelastic Developer UI)

1. Push this repository to a Git host where the files are reachable as **raw** URLs
   (e.g. GitHub).
2. `baseUrl` in **`manifest.jps`** is already set for this repo:
   `https://raw.githubusercontent.com/stackharbor-devops/jps-swarmclaw/main`
   (the installer fetches `scripts/*.sh` from `${baseUrl}/scripts/...`). If you fork or
   rename the repo/branch, update it to match.
3. In the dashboard: **Import** → **URL** → paste:
   `https://raw.githubusercontent.com/stackharbor-devops/jps-swarmclaw/main/manifest.jps` → **Import**.
4. Pick an environment name + region when prompted → **Install**.
5. When it finishes, read the success panel and the email sent to your account address.

> `baseUrl` **must** match where the manifest is hosted, or script fetching fails.

---

## Required platform assumptions

| Assumption | Detail / fallback |
|---|---|
| **Node type** | `dockerengine` (Docker Engine CE). If unavailable, set `nodeType: vps` (Ubuntu); `install.sh` installs Docker/Compose itself. |
| **`cmd` runs as root** | True on Docker Engine / VPS nodes. Scripts also fall back to `sudo -n`. |
| **Env URL routing** | The app is published on host `:80`; the environment URL / "Open in Browser" must route to the node on port 80 (default for a single-node env). See *Exposing SwarmClaw* for public-IP / Endpoint alternatives. |
| **Outbound internet** | Needed to pull the SwarmClaw repo, base image and packages. |
| **Email** | Sent via `message.email.Send` to `${user.email}`. Requires the platform's outgoing SMTP to be configured (default on most installs). |
| **App URL macro** | `${env.url}` (always resolves; this is what the dashboard "Open in Browser" uses). |

---

## Deployment parameters

This package is intentionally **one-click** — the platform prompts only for the
environment name and region. Behaviour can be tuned via environment variables
honoured by the scripts (override in `manifest.jps` or when running manually):

| Variable | Default | Purpose |
|---|---|---|
| `SWARMCLAW_APP_DIR` | `/opt/swarmclaw` | Install directory |
| `SWARMCLAW_PORT` | `3456` | Container app port (health checks) |
| `SWARMCLAW_REPO_URL` | upstream repo | SwarmClaw git source |
| `SWARMCLAW_BRANCH` | `main` (→ `master`) | Branch/ref to deploy |
| `SWARMCLAW_BASE_URL` | — | Raw base URL of this package (script fetch) |
| `SWARMCLAW_ACCESS_KEY` / `SWARMCLAW_CREDENTIAL_SECRET` | — | Pre-set credentials (the manifest passes the platform-generated globals here) |
| `SWARMCLAW_NO_BUILD` | `0` | `1` = pull prebuilt image instead of building |
| `SWARMCLAW_INSTALL_CLIS` | `1` | Install provider CLIs in the container (`0` to skip) |
| `SWARMCLAW_CLI_SPECS` | `@anthropic-ai/claude-code:claude @openai/codex:codex` | `pkg:binary` list of CLIs to install |
| `SWARMCLAW_REF` | current branch | `update.sh`: ref to update to |

---

## Post-install access

- **URL:** the **environment URL** (`${env.url}`), shown in the success panel and
  email; the dashboard **Open in Browser** button opens it too.
- **Access Key:** in the email, the success panel, and `/opt/swarmclaw/.deployment-secrets`.
- Open the URL, authenticate with your **Access Key**, then configure providers,
  agents, Hermes Agent, tools, schedules and credentials in the SwarmClaw UI.

### Exposing SwarmClaw

`docker-compose.override.yml` publishes the container on host **port 80**, so the
single-node environment URL (port 80, via the platform resolver/SLB) reaches
SwarmClaw — which also makes **Open in Browser** work. The container ports
`3456`/`3457` remain published on the host as well.

**Alternatives** if you need a fixed public `:3456`, or port 80 is taken on the node:

- **Public IP:** add `extip: true` to the node and use `http://<public-ip>:3456`
  (open TCP 3456 in the environment **Firewall**). Public-IP / `extIPs` placeholder
  support is version-dependent.
- **TCP Endpoint:** map 3456 to a public port via the API:

  ```yaml
  - api: environment.binder.AddEndPoint
    nodeId: ${nodes.cp.first.id}
    name: swarmclaw
    privatePort: 3456
    protocol: TCP
  ```

> SwarmClaw also listens on **3457** (secondary). If a browser feature needs it and
> you front the app on port 80 only, publish/route 3457 too.

---

## Default AI providers

Every deployment pre-installs two CLI-based providers inside the container so the
default **Assistant** agent (and any `claude-code` / `codex` agent) works without
manual setup:

- **Claude Code** — `@anthropic-ai/claude-code` (`claude`)
- **OpenAI Codex** — `@openai/codex` (`codex`)

`start.sh` installs them on every deploy — idempotent, best-effort (a failure never
breaks the app). Toggle with `SWARMCLAW_INSTALL_CLIS=0`; customise the list with
`SWARMCLAW_CLI_SPECS`.

> **Credentials are still required.** Installing the CLIs fixes *"Claude CLI not
> found"*, but each backend needs auth before it answers. Add an API key in the
> SwarmClaw UI (**Providers / Secrets**), or set it in `/opt/swarmclaw/.env.local`
> (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`) then `docker compose restart`. SwarmClaw's
> built-in **OpenAI / Anthropic _API_ providers** need only a key (no CLI).

**Add the CLIs to an already-running instance** (no redeploy needed):

```bash
docker compose -f /opt/swarmclaw/docker-compose.yml exec -u root -T \
  swarmclaw npm install -g @anthropic-ai/claude-code @openai/codex
```

---

## Credential handling

- Generated by the platform (`${fn.password}`) and passed into the installer;
  `generate-credentials.sh` falls back to `openssl rand -base64 32` for manual runs.
  Never hardcoded, never committed.
- Stored in `/opt/swarmclaw/.deployment-secrets` and `/opt/swarmclaw/.env.local`, both `chmod 600`.
- `.gitignore` excludes `.env.local`, `.deployment-secrets`, `data/`.
- **Idempotent:** re-running install/update reuses existing on-disk secrets — keys are not rotated.
- Secrets are surfaced only in the final customer email and success output (the
  permitted exception); scripts otherwise never print secret values.
- `CREDENTIAL_SECRET` is set explicitly in `.env.local`, which is the stable, first
  resolution source SwarmClaw uses for credential encryption.

> **Rotate** by editing the two keys in `.deployment-secrets` **and** `.env.local`
> (keep them in sync), then `bash /opt/swarmclaw/scripts/start.sh`. Re-encrypting
> stored credentials after rotating `CREDENTIAL_SECRET` is handled in the SwarmClaw UI.

---

## Updating SwarmClaw

```bash
bash /opt/swarmclaw/scripts/update.sh           # latest of current branch
SWARMCLAW_REF=v1.2.3 bash /opt/swarmclaw/scripts/update.sh   # pin a tag
```

Pulls the latest source, rebuilds, restarts, and health-checks. `.env.local`,
`.deployment-secrets` and `data/` are preserved.

## Restarting SwarmClaw

```bash
cd /opt/swarmclaw
docker compose restart            # restart in place
docker compose down && docker compose up -d    # full recreate
bash /opt/swarmclaw/scripts/start.sh            # idempotent (re)start
```

The container auto-restarts after a node reboot (`restart: unless-stopped`).

---

## Troubleshooting commands

```bash
cd /opt/swarmclaw

docker compose ps                 # container status
docker compose logs -f --tail=100 # follow logs
docker compose config             # effective merged compose config (incl. override)

bash scripts/healthcheck.sh       # probe :3456/api/healthz
curl -i http://127.0.0.1:3456/api/healthz
curl -i http://127.0.0.1:80/      # verify the host :80 → :3456 publish

cat /var/log/swarmclaw-install.log   # full install log (redirected here from the JPS bootstrap)
systemctl status docker              # docker daemon
```

- **Install fails with `org.hibernate.exception.DataException`:** the install command
  must not stream large output back to the platform — this package redirects it to
  `/var/log/swarmclaw-install.log` and returns only a status line. If you customise the
  manifest, keep the `cmd` output small.
- **Port 80 already allocated:** another container/service holds host :80. Change
  `"80:3456"` in `docker-compose.override.yml`, or use a public IP / Endpoint instead.
- If the build is killed (OOM), raise `flexibleCloudlets` on the node or set
  `SWARMCLAW_NO_BUILD=1` to pull the prebuilt image.

---

## Health checks

- **Liveness:** `GET http://127.0.0.1:3456/api/healthz` (used by `healthcheck.sh`
  and the upstream compose `HEALTHCHECK`).
- **Container:** `docker compose ps` should show `swarmclaw` as `running`/`healthy`.
- `healthcheck.sh` retries for ~150s and dumps the last logs on failure.

---

## File layout

```
.
├── manifest.jps                  # JPS manifest (import this)
├── README.md
├── docker-compose.override.yml   # installed to node: host :80 routing + restart policy
├── .gitignore
└── scripts/
    ├── install.sh                # full first-time deploy (orchestrator)
    ├── generate-credentials.sh   # create/persist ACCESS_KEY & CREDENTIAL_SECRET
    ├── start.sh                  # docker compose up + restart policy
    ├── healthcheck.sh            # probe :3456/api/healthz
    └── update.sh                 # pull + rebuild + restart + health
```

On the node (`/opt/swarmclaw`): the SwarmClaw checkout plus `docker-compose.override.yml`,
`.env.local` (600), `.deployment-secrets` (600), `data/` (persistent) and `scripts/`.

---

## Known limitations

- **Single node, no HA (v1).** No clustering, load balancing or failover.
- **Vertical scaling only** via node cloudlets.
- **Plain HTTP on port 80.** Served over the environment URL without TLS/custom
  domain out of the box — front it with a reverse proxy / Let's Encrypt add-on for
  HTTPS. Routing assumes the env URL reaches the node on port 80 (true for a single-node env).
- **Persistence is node-local.** `data/` lives on the node's disk (survives reboots
  and container recreation), but is not replicated off-node — snapshot/back up `data/`.
- **Hermes Agent is not auto-deployed** (see below).
- **Upstream-driven.** Tracks the SwarmClaw repo; a breaking upstream change to the
  compose file or env vars may require package updates.

---

## Hermes Agent integration note

This package deploys **SwarmClaw itself**. It does **not** automatically provision a
separate Hermes Agent runtime. SwarmClaw integrates Hermes as a backend/provider
through its **OpenAI-compatible API** — point SwarmClaw at a reachable Hermes `/v1`
endpoint (local or remote) from the SwarmClaw UI/config after deployment. The
deployed instance is ready for that configuration; no extra package steps are needed.

---

## Future roadmap (HA / multi-node)

- Multi-node SwarmClaw with a shared/replicated data backend and a load balancer.
- Managed reverse proxy + automatic TLS (Let's Encrypt) and custom domains.
- Optional co-deployment of a Hermes Agent runtime node, wired to SwarmClaw automatically.
- Horizontal auto-scaling triggers and scheduled off-node backups of `data/`.

---

## Credits

- App: [SwarmClaw](https://github.com/swarmclawai/swarmclaw) by SwarmClaw AI.
- JPS style modelled on [`jelastic-jps/wordpress-cluster`](https://github.com/jelastic-jps/wordpress-cluster)
  and [`jelastic-jps/minio`](https://github.com/jelastic-jps/minio).
- Packaged by **Stack Harbor**.
```

