#!/usr/bin/env bash
# After5 — Mac beta quick installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/jhyeo001/after5-release/main/install-mac.sh | bash
#
# Environment variables (optional):
#   AFTER5_DMG_URL          : Use a different DMG URL
#   AFTER5_EXPECTED_SHA256  : Verify SHA256
#   AFTER5_NO_LAUNCH=1      : Skip auto-launch
#   AFTER5_NO_PROMPT=1      : Skip confirmation prompt
#
# What it does:
#   1. Download DMG
#   2. Quit any running After5
#   3. Install to /Applications/After5.app
#   4. Bypass macOS Gatekeeper (xattr -dr com.apple.quarantine)
#   5. Auto-launch
#
# This is essentially equivalent to right-click → Open / System Settings → Open Anyway.

set -euo pipefail

# ── Config ───────────────────────────────────────────────
DMG_URL="${AFTER5_DMG_URL:-https://github.com/jhyeo001/after5-release/releases/latest/download/After5.dmg}"
APP_NAME="After5"
SUPPORT_EMAIL="jhyeo001@gmail.com"
TMP_DMG="$(mktemp -t after5_dmg).dmg"
TMP_DIR=""

# ── Output helpers ───────────────────────────────────────
ok() { printf '\033[32m✓\033[0m %s\n' "$1"; }
info() { printf '\033[34m·\033[0m %s\n' "$1"; }
warn() { printf '\033[33m!\033[0m %s\n' "$1" >&2; }
err()  { printf '\033[31m✗\033[0m %s\n' "$1" >&2; exit 1; }

cleanup() {
  if [ -n "${TMP_DIR}" ] && [ -d "${TMP_DIR}" ]; then
    hdiutil detach "${TMP_DIR}" -quiet 2>/dev/null || true
  fi
  rm -f "${TMP_DMG}"
}
trap cleanup EXIT

# ── OS check ─────────────────────────────────────────────
if [ "$(uname -s)" != "Darwin" ]; then
  err "This script is macOS only. (current: $(uname -s))"
fi

# ── Banner + confirmation ────────────────────────────────
cat <<'BANNER'

  ┌─────────────────────────────────────────────┐
  │       After5 Beta Quick Installer           │
  └─────────────────────────────────────────────┘

  This script will:

    1. Download the official DMG
    2. Quit any running After5
    3. Install to /Applications/After5.app
    4. Bypass the macOS unsigned-app block
    5. Launch After5

  ⚠ Run this script only from a trusted official source.

BANNER

if [ "${AFTER5_NO_PROMPT:-}" != "1" ]; then
  # When run via `curl ... | bash`, stdin is the pipe — read from /dev/tty instead.
  # If /dev/tty is unavailable (e.g. CI), skip the prompt and proceed.
  if [ -t 0 ]; then
    read -p "  Continue? [y/N] " -n 1 -r REPLY
    echo
  elif [ -e /dev/tty ]; then
    read -p "  Continue? [y/N] " -n 1 -r REPLY < /dev/tty
    echo
  else
    REPLY="y"
    info "non-interactive — skipping prompt"
  fi
  if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
    info "Cancelled."
    exit 0
  fi
fi

# ── /Applications write permission ───────────────────────
if [ ! -w "/Applications" ]; then
  cat <<EOF >&2

  ✗ No write permission to /Applications.

  This often happens on managed Macs (work / school). Try on a personal
  Mac, or ask your IT admin for write access to /Applications.

  Contact: ${SUPPORT_EMAIL}
EOF
  exit 1
fi

# ── 1. Download ──────────────────────────────────────────
info "Downloading DMG…  ${DMG_URL}"
if ! curl -fL --progress-bar "${DMG_URL}" -o "${TMP_DMG}"; then
  err "Download failed. Check the URL or your network."
fi
ok "Downloaded ($(du -h "${TMP_DMG}" | awk '{print $1}'))"

# ── 2. SHA256 verify (optional) ──────────────────────────
if [ -n "${AFTER5_EXPECTED_SHA256:-}" ]; then
  info "Verifying SHA256…"
  ACTUAL=$(shasum -a 256 "${TMP_DMG}" | awk '{print $1}')
  if [ "${ACTUAL}" != "$AFTER5_EXPECTED_SHA256" ]; then
    err "SHA256 mismatch.
    expected: $AFTER5_EXPECTED_SHA256
    actual:   ${ACTUAL}"
  fi
  ok "SHA256 verified"
fi

# ── 3. Quit running After5 ───────────────────────────────
if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
  info "Quitting running ${APP_NAME}…"
  pkill -x "${APP_NAME}" 2>/dev/null || true
  sleep 1
  if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    pkill -9 -x "${APP_NAME}" 2>/dev/null || true
    sleep 1
  fi
  ok "Quit"
fi

# ── 4. Mount + copy + unmount ────────────────────────────
info "Mounting DMG…"
TMP_DIR=$(mktemp -d -t after5_mount)
hdiutil attach "${TMP_DMG}" -mountpoint "${TMP_DIR}" -nobrowse -quiet
ok "Mounted: ${TMP_DIR}"

if [ ! -d "${TMP_DIR}/${APP_NAME}.app" ]; then
  err "Cannot find ${APP_NAME}.app inside the DMG.
DMG structure may differ from expected.
Contact: ${SUPPORT_EMAIL}"
fi

if [ -d "/Applications/${APP_NAME}.app" ]; then
  info "Replacing existing /Applications/${APP_NAME}.app"
  rm -rf "/Applications/${APP_NAME}.app"
fi

info "Copying to /Applications/${APP_NAME}.app…"
cp -R "${TMP_DIR}/${APP_NAME}.app" /Applications/
ok "Installed"

hdiutil detach "${TMP_DIR}" -quiet
TMP_DIR=""

# ── 5. Remove quarantine (Gatekeeper bypass) ─────────────
info "Removing quarantine attribute…"
if xattr -dr com.apple.quarantine "/Applications/${APP_NAME}.app" 2>/dev/null; then
  ok "quarantine removed — no security warning"
else
  warn "quarantine skipped (already absent or permission)"
fi

# ── 6. Launch ────────────────────────────────────────────
if [ "${AFTER5_NO_LAUNCH:-}" = "1" ]; then
  ok "Installed. Launch from /Applications/${APP_NAME}.app."
else
  info "Launching ${APP_NAME}…"
  open "/Applications/${APP_NAME}.app"
  ok "Done. Enjoy the beta!"
fi

cat <<EOF

  Feedback or issues:
  ${SUPPORT_EMAIL}

EOF
