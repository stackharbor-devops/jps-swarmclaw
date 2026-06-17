#!/usr/bin/env bash
#
# generate-credentials.sh — create & persist unique SwarmClaw credentials.
#
# Credential source priority:
#   1. values supplied by the installer via SWARMCLAW_ACCESS_KEY /
#      SWARMCLAW_CREDENTIAL_SECRET (the JPS platform-generated globals);
#   2. values already present in .deployment-secrets (idempotent reruns);
#   3. freshly generated with `openssl rand -base64 32` (manual/standalone runs).
#
# Writes two restrictive files:
#   /opt/swarmclaw/.deployment-secrets  (authoritative store, chmod 600)
#   /opt/swarmclaw/.env.local           (consumed by docker compose, chmod 600)
#
# No secret value is ever written to stdout/stderr by this script.
#
set -euo pipefail

APP_DIR="${SWARMCLAW_APP_DIR:-/opt/swarmclaw}"
SECRETS_FILE="${APP_DIR}/.deployment-secrets"
ENV_FILE="${APP_DIR}/.env.local"

log()  { printf '%s [swarmclaw] %s\n'        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
err()  { printf '%s [swarmclaw][ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die()  { err "$*"; exit 1; }

# Generate a 32-byte secret, base64-encoded, no trailing newline.
gen_secret() {
  command -v openssl >/dev/null 2>&1 || die "openssl is required to generate credentials"
  openssl rand -base64 32 | tr -d '\r\n'
}

# read_kv <file> <key> -> prints value (text after the first '='), or fails.
read_kv() {
  local f="$1" k="$2"
  [ -f "$f" ] || return 1
  grep -E "^${k}=" "$f" | head -n1 | cut -d= -f2-
}

# set_kv <file> <key> <value> -> upsert KEY=VALUE, preserving other lines.
# Avoids sed so base64 values containing '/' or '+' are handled safely.
set_kv() {
  local f="$1" k="$2" v="$3" tmp
  touch "$f"
  tmp="$(mktemp)"
  grep -vE "^${k}=" "$f" > "$tmp" 2>/dev/null || true
  printf '%s=%s\n' "$k" "$v" >> "$tmp"
  mv "$tmp" "$f"
}

main() {
  umask 077
  mkdir -p "$APP_DIR"

  local access="" cred=""

  # 1) supplied by installer (platform-generated globals)
  if [ -n "${SWARMCLAW_ACCESS_KEY:-}" ]; then
    access="$SWARMCLAW_ACCESS_KEY"
    log "Using ACCESS_KEY supplied by installer"
  fi
  if [ -n "${SWARMCLAW_CREDENTIAL_SECRET:-}" ]; then
    cred="$SWARMCLAW_CREDENTIAL_SECRET"
    log "Using CREDENTIAL_SECRET supplied by installer"
  fi

  # 2) existing on-disk values (keeps reruns idempotent)
  if [ -z "$access" ]; then
    access="$(read_kv "$SECRETS_FILE" ACCESS_KEY || true)"
    if [ -n "$access" ]; then log "Reusing existing ACCESS_KEY"; fi
  fi
  if [ -z "$cred" ]; then
    cred="$(read_kv "$SECRETS_FILE" CREDENTIAL_SECRET || true)"
    if [ -n "$cred" ]; then log "Reusing existing CREDENTIAL_SECRET"; fi
  fi

  # 3) generate (manual/standalone runs)
  if [ -z "$access" ]; then access="$(gen_secret)"; log "Generated ACCESS_KEY (openssl)"; fi
  if [ -z "$cred"   ]; then cred="$(gen_secret)";   log "Generated CREDENTIAL_SECRET (openssl)"; fi

  # Authoritative secret store (rewritten cleanly each run; values are stable).
  {
    printf '# SwarmClaw deployment secrets — DO NOT COMMIT. Keep this file private.\n'
    printf '# Maintained by generate-credentials.sh. Permissions: 600.\n'
    printf 'APP_DIR=%s\n'           "$APP_DIR"
    printf 'ACCESS_KEY=%s\n'        "$access"
    printf 'CREDENTIAL_SECRET=%s\n' "$cred"
  } > "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"

  # Runtime env consumed by docker compose (env_file: ./.env.local).
  touch "$ENV_FILE"
  set_kv "$ENV_FILE" ACCESS_KEY        "$access"
  set_kv "$ENV_FILE" CREDENTIAL_SECRET "$cred"
  chmod 600 "$ENV_FILE"

  log "Credentials ready (${SECRETS_FILE} [600], ${ENV_FILE} [600])"
}

main "$@"
