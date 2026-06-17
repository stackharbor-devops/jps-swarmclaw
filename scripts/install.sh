#!/usr/bin/env bash
#
# install.sh — one-shot SwarmClaw installer for an Ubuntu-like / Docker Engine node.
#
# Orchestrates the full first-time deployment:
#   1. install base deps (git, curl, openssl, ca-certificates) if missing
#   2. install Docker Engine + Compose plugin if missing
#   3. fetch SwarmClaw source into /opt/swarmclaw (clone or update; idempotent)
#   4. obtain the helper scripts (generate-credentials / start / healthcheck / update)
#   5. generate & persist unique credentials
#   6. start SwarmClaw via Docker Compose
#   7. health-check the local endpoint
#
# Safe to re-run. Requires root (or passwordless sudo). No secrets are printed.
#
# Environment overrides:
#   SWARMCLAW_BASE_URL   raw base URL of THIS package repo (to fetch sibling scripts)
#   SWARMCLAW_APP_DIR    install dir              (default: /opt/swarmclaw)
#   SWARMCLAW_REPO_URL   SwarmClaw git repo       (default: upstream)
#   SWARMCLAW_BRANCH     branch/ref              (default: main, falls back to master)
#   SWARMCLAW_PORT       app port                (default: 3456)
#
set -euo pipefail

APP_DIR="${SWARMCLAW_APP_DIR:-/opt/swarmclaw}"
REPO_URL="${SWARMCLAW_REPO_URL:-https://github.com/swarmclawai/swarmclaw.git}"
REPO_BRANCH="${SWARMCLAW_BRANCH:-main}"
BASE_URL="${SWARMCLAW_BASE_URL:-}"
PORT="${SWARMCLAW_PORT:-3456}"
SCRIPTS_DIR="${APP_DIR}/scripts"
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo /tmp)"

log()  { printf '%s [swarmclaw] %s\n'        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
err()  { printf '%s [swarmclaw][ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die()  { err "$*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

if   [ "$(id -u)" -eq 0 ];            then SUDO=""
elif command -v sudo >/dev/null 2>&1; then SUDO="sudo -n"
else die "must run as root or have passwordless sudo"; fi

PKG=""
detect_pkg() {
  if   command -v apt-get >/dev/null 2>&1; then PKG=apt
  elif command -v dnf     >/dev/null 2>&1; then PKG=dnf
  elif command -v yum     >/dev/null 2>&1; then PKG=yum
  else PKG=""; fi
}

pkg_install() {
  case "$PKG" in
    apt) $SUDO apt-get update -y -q && $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$@" ;;
    dnf) $SUDO dnf install -y -q "$@" ;;
    yum) $SUDO yum install -y -q "$@" ;;
    *)   err "no supported package manager found; please install: $*"; return 1 ;;
  esac
}

ensure_base_deps() {
  detect_pkg
  local c missing=()
  for c in git curl openssl; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    log "Installing base dependencies: ${missing[*]} (+ ca-certificates)"
    pkg_install "${missing[@]}" ca-certificates || die "failed to install base dependencies"
  else
    log "Base dependencies present (git, curl, openssl)"
  fi
  need git; need curl; need openssl
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Docker not found — installing via get.docker.com"
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh || die "cannot download Docker installer"
    $SUDO sh /tmp/get-docker.sh || die "Docker installation failed"
  else
    log "Docker present"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    $SUDO systemctl enable --now docker >/dev/null 2>&1 || true
  fi
  $SUDO docker info >/dev/null 2>&1 || die "Docker daemon is not reachable"

  if ! ( $SUDO docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1 ); then
    log "Docker Compose plugin missing — installing"
    pkg_install docker-compose-plugin || log "could not install compose plugin via package manager"
  fi
  $SUDO docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1 \
    || die "Docker Compose is still unavailable"
  log "Docker + Compose ready"
}

clone_or_update() {
  mkdir -p "$APP_DIR"
  if [ -d "${APP_DIR}/.git" ]; then
    log "Updating existing SwarmClaw checkout in ${APP_DIR}"
    git -C "$APP_DIR" remote set-url origin "$REPO_URL" 2>/dev/null || \
      git -C "$APP_DIR" remote add origin "$REPO_URL" 2>/dev/null || true
    git -C "$APP_DIR" fetch --depth 1 origin "$REPO_BRANCH" \
      || git -C "$APP_DIR" fetch --depth 1 origin
    git -C "$APP_DIR" checkout -f -B "$REPO_BRANCH" FETCH_HEAD
  else
    # Use init+fetch so we can overlay onto a possibly non-empty /opt/swarmclaw
    # (scripts/, data/, .env.local stay untouched — they are not tracked upstream).
    log "Fetching SwarmClaw source into ${APP_DIR}"
    git -C "$APP_DIR" init -q
    git -C "$APP_DIR" remote add origin "$REPO_URL" 2>/dev/null \
      || git -C "$APP_DIR" remote set-url origin "$REPO_URL"
    if ! git -C "$APP_DIR" fetch --depth 1 origin "$REPO_BRANCH"; then
      log "Branch '${REPO_BRANCH}' not found — trying 'master'"
      REPO_BRANCH=master
      git -C "$APP_DIR" fetch --depth 1 origin "$REPO_BRANCH" || die "cannot fetch SwarmClaw repo"
    fi
    git -C "$APP_DIR" checkout -f -B "$REPO_BRANCH" FETCH_HEAD
  fi
  log "SwarmClaw source ready at ${APP_DIR} (branch: ${REPO_BRANCH})"
}

obtain_scripts() {
  mkdir -p "$SCRIPTS_DIR"
  local s
  for s in generate-credentials start healthcheck update; do
    if [ -n "$BASE_URL" ] && curl -fsSL "${BASE_URL}/scripts/${s}.sh" -o "${SCRIPTS_DIR}/${s}.sh"; then
      :
    elif [ -f "${SELF_DIR}/${s}.sh" ]; then
      cp "${SELF_DIR}/${s}.sh" "${SCRIPTS_DIR}/${s}.sh"
    fi
    [ -f "${SCRIPTS_DIR}/${s}.sh" ] \
      || die "cannot obtain ${s}.sh (set SWARMCLAW_BASE_URL, or run install.sh from the package dir)"
    chmod +x "${SCRIPTS_DIR}/${s}.sh"
  done
  log "Helper scripts available in ${SCRIPTS_DIR}"
}

run_helper() {
  local f="${SCRIPTS_DIR}/$1"
  [ -f "$f" ] || die "missing helper script: $f"
  SWARMCLAW_APP_DIR="$APP_DIR" SWARMCLAW_PORT="$PORT" bash "$f"
}

main() {
  log "=== SwarmClaw installation starting ==="
  ensure_base_deps
  ensure_docker
  clone_or_update
  mkdir -p "${APP_DIR}/data"
  obtain_scripts
  run_helper generate-credentials.sh
  run_helper start.sh
  run_helper healthcheck.sh
  log "=== SwarmClaw installation completed ==="
  log "Location: ${APP_DIR} | Port: ${PORT}"
}

main "$@"
