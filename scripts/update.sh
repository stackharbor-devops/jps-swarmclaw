#!/usr/bin/env bash
#
# update.sh — pull the latest SwarmClaw source and rebuild/restart in place.
#
# Persistent state is preserved: .env.local, .deployment-secrets and data/ are not
# tracked by the upstream repo, so `git reset --hard` does not touch them.
#
# Environment overrides:
#   SWARMCLAW_APP_DIR   install dir (default: /opt/swarmclaw)
#   SWARMCLAW_REF       explicit branch/tag/ref to check out (default: current branch)
#
set -euo pipefail

APP_DIR="${SWARMCLAW_APP_DIR:-/opt/swarmclaw}"
REF="${SWARMCLAW_REF:-}"
SCRIPTS_DIR="${APP_DIR}/scripts"

log()  { printf '%s [swarmclaw] %s\n'        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
err()  { printf '%s [swarmclaw][ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die()  { err "$*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

main() {
  need git
  [ -d "${APP_DIR}/.git" ] || die "no git checkout at ${APP_DIR}; run install.sh first"
  cd "$APP_DIR"

  log "Fetching latest SwarmClaw source"
  git fetch --depth 1 origin

  if [ -n "$REF" ]; then
    log "Checking out ${REF}"
    git checkout -f "$REF"
    git reset --hard "origin/${REF}" 2>/dev/null || git reset --hard "$REF"
  else
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
    log "Updating branch ${branch}"
    git reset --hard "origin/${branch}" 2>/dev/null || git reset --hard FETCH_HEAD
  fi

  log "Rebuilding and restarting"
  [ -f "${SCRIPTS_DIR}/start.sh" ]       || die "missing ${SCRIPTS_DIR}/start.sh"
  [ -f "${SCRIPTS_DIR}/healthcheck.sh" ] || die "missing ${SCRIPTS_DIR}/healthcheck.sh"
  SWARMCLAW_APP_DIR="$APP_DIR" bash "${SCRIPTS_DIR}/start.sh"
  SWARMCLAW_APP_DIR="$APP_DIR" bash "${SCRIPTS_DIR}/healthcheck.sh"

  log "Update complete"
}

main "$@"
