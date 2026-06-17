#!/usr/bin/env bash
#
# healthcheck.sh — verify SwarmClaw is up and answering locally.
#
# Polls http://127.0.0.1:<port>/api/healthz (SwarmClaw's documented health route),
# falling back to the root path. Exits 0 when healthy, non-zero otherwise.
#
set -euo pipefail

APP_DIR="${SWARMCLAW_APP_DIR:-/opt/swarmclaw}"
PORT="${SWARMCLAW_PORT:-3456}"
HEALTH_PATH="${SWARMCLAW_HEALTH_PATH:-/api/healthz}"
RETRIES="${SWARMCLAW_HEALTH_RETRIES:-30}"
SLEEP_SECS="${SWARMCLAW_HEALTH_SLEEP:-5}"

log()  { printf '%s [swarmclaw] %s\n'        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
err()  { printf '%s [swarmclaw][ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die()  { err "$*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

if   [ "$(id -u)" -eq 0 ];            then SUDO=""
elif command -v sudo >/dev/null 2>&1; then SUDO="sudo -n"
else SUDO=""; fi

dc() {
  if $SUDO docker compose version >/dev/null 2>&1; then $SUDO docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1;  then $SUDO docker-compose "$@"
  else return 0; fi
}

show_status() { ( cd "$APP_DIR" 2>/dev/null && dc ps ) || true; }

main() {
  need curl
  local health="http://127.0.0.1:${PORT}${HEALTH_PATH}"
  local root="http://127.0.0.1:${PORT}/"
  local i

  log "Waiting for SwarmClaw at ${health} (up to $((RETRIES * SLEEP_SECS))s)"
  for (( i = 1; i <= RETRIES; i++ )); do
    if curl -fsS -o /dev/null --max-time 5 "$health" 2>/dev/null; then
      log "Health endpoint OK: ${health}"
      show_status
      exit 0
    fi
    if curl -fsS -o /dev/null --max-time 5 "$root" 2>/dev/null; then
      log "App responding at ${root} (health path not ready yet, treating as up)"
      show_status
      exit 0
    fi
    sleep "$SLEEP_SECS"
  done

  err "SwarmClaw did not become healthy after $((RETRIES * SLEEP_SECS))s"
  show_status
  log "Last 50 log lines (for debugging):"
  ( cd "$APP_DIR" 2>/dev/null && dc logs --tail 50 ) || true
  exit 1
}

main "$@"
