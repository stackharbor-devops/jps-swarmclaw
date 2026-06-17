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
5. Generates **unique credentials** (`ACCESS_KEY`, `CREDENTIAL_SECRET`) with `openssl rand -base64 32`.
6. Stores them in **`/opt/swarmclaw/.deployment-secrets`** (`chmod 600`) and writes them to `.env.local` (`chmod 600`).
7. Starts SwarmClaw with **Docker Compose** (`docker compose up -d --build`), using the repo's own compose file.
8. Ensures the container **restarts after reboot** (`restart: unless-stopped`).
9. Exposes SwarmClaw on **port 3456**.
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
  │   │  Docker Engine node (public IPv4)     │    │
  │   │                                        │    │
  │   │   /opt/swarmclaw  (git checkout)       │    │
  │   │     ├─ docker-compose.yml (upstream)   │    │
  │   │     ├─ .env.local        (600)         │    │
  │   │     ├─ .deployment-secrets (600)       │    │
  │   │     ├─ data/             (persistent)  │    │
  │   │     └─ scripts/ (install/start/…)      │    │
  │   │                                        │    │
  │   │   docker compose ─► container          │    │
  │   │      swarmclaw  :3456 (+3457)          │    │
  │   └──────────────────────────────────────┘    │
  └──────────────────────────────────────────────┘
            ▲
            │  http://<public-ip>:3456
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
| **Public IPv4** | `extip: true` requests one so `http://<ip>:3456` works. Key may be `externalIp: true` on some versions. See *Exposing SwarmClaw* for a no-public-IP path. |
| **Outbound internet** | Needed to pull the SwarmClaw repo, base image and packages. |
| **Email** | Sent via `message.email.Send` to `${user.email}`. Requires the platform's outgoing SMTP to be configured (default on most installs). |
| **Public URL macro** | `${nodes.cp.first.extIPs[1]}` (alt: `${nodes.cp.first.extIP}`). |

---

## Deployment parameters

This package is intentionally **one-click** — the platform prompts only for the
environment name and region. Behaviour can be tuned via environment variables
honoured by the scripts (override in `manifest.jps` or when running manually):

| Variable | Default | Purpose |
|---|---|---|
| `SWARMCLAW_APP_DIR` | `/opt/swarmclaw` | Install directory |
| `SWARMCLAW_PORT` | `3456` | App port for health checks / URL |
| `SWARMCLAW_REPO_URL` | upstream repo | SwarmClaw git source |
| `SWARMCLAW_BRANCH` | `main` (→ `master`) | Branch/ref to deploy |
| `SWARMCLAW_BASE_URL` | — | Raw base URL of this package (script fetch) |
| `SWARMCLAW_NO_BUILD` | `0` | `1` = pull prebuilt image instead of building |
| `SWARMCLAW_REF` | current branch | `update.sh`: ref to update to |

---

## Post-install access

- **URL:** `http://<public-ip>:3456` (shown in the success panel and email).
- **Access Key:** in the email, the success panel, and `/opt/swarmclaw/.deployment-secrets`.
- Open the URL, authenticate with your **Access Key**, then configure providers,
  agents, Hermes Agent, tools, schedules and credentials in the SwarmClaw UI.

### Exposing SwarmClaw

This package attaches a **public IPv4** and serves on `:3456` directly. If you cannot
use a public IP, expose port 3456 through Jelastic **Endpoints** instead — replace
`captureUrl` in the manifest with an API call and build the URL from its response:

```yaml
- api: environment.binder.AddEndPoint
  nodeId: ${nodes.cp.first.id}
  name: swarmclaw
  privatePort: 3456
  protocol: TCP
- setGlobals:
    SWARMCLAW_URL: http://${response.object.host}:${response.object.publicPort}
```

If `:3456` is unreachable with a public IP, check the environment **Firewall**
(add an inbound rule for TCP 3456).

---

## Credential handling

- Generated **on the node** with `openssl rand -base64 32` — never hardcoded, never committed.
- Stored in `/opt/swarmclaw/.deployment-secrets` and `/opt/swarmclaw/.env.local`, both `chmod 600`.
- `.gitignore` excludes `.env.local`, `.deployment-secrets`, `data/`.
- **Idempotent:** re-running install/update reuses existing secrets — keys are not rotated.
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
docker compose config             # effective merged compose config

bash scripts/healthcheck.sh       # probe :3456/api/healthz
curl -i http://127.0.0.1:3456/api/healthz

cat /var/log/swarmclaw-install.log   # full install log (from the JPS bootstrap)
systemctl status docker              # docker daemon
```

If the build is killed (OOM), raise `flexibleCloudlets` on the node or set
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
├── docker-compose.override.yml   # reference template (restart policy)
├── .gitignore
└── scripts/
    ├── install.sh                # full first-time deploy (orchestrator)
    ├── generate-credentials.sh   # create/persist ACCESS_KEY & CREDENTIAL_SECRET
    ├── start.sh                  # docker compose up + restart policy
    ├── healthcheck.sh            # probe :3456/api/healthz
    └── update.sh                 # pull + rebuild + restart + health
```

On the node (`/opt/swarmclaw`): the SwarmClaw checkout plus `.env.local` (600),
`.deployment-secrets` (600), `data/` (persistent) and `scripts/`.

---

## Known limitations

- **Single node, no HA (v1).** No clustering, load balancing or failover.
- **Vertical scaling only** via node cloudlets.
- **Public IP exposure.** Uses a public IPv4 + raw `:3456`. No TLS/custom domain
  out of the box — front it with a reverse proxy / Let's Encrypt add-on for HTTPS.
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
