#!/usr/bin/env bash
# After5 — Mac 베타 빠른 설치 / Mac beta quick installer.
#
# Usage / 사용:
#   curl -fsSL https://raw.githubusercontent.com/jhyeo001/after5-release/main/install-mac.sh | bash
#
# Environment variables / 환경 변수 (선택):
#   AFTER5_DMG_URL          : 다른 DMG URL 사용 / Use a different DMG URL
#   AFTER5_EXPECTED_SHA256  : SHA256 검증 / Verify SHA256 (optional)
#   AFTER5_NO_LAUNCH=1      : 자동 실행 안 함 / Skip auto-launch
#   AFTER5_NO_PROMPT=1      : 진행 확인 prompt 생략 / Skip confirmation prompt
#
# 무엇을 하나 / What it does:
#   1. DMG 다운로드 / Download DMG
#   2. 실행 중인 After5 종료 / Quit any running After5
#   3. /Applications/After5.app 으로 설치 / Install to /Applications
#   4. macOS Gatekeeper 우회 (xattr -dr com.apple.quarantine) / Bypass Gatekeeper
#   5. 자동 실행 / Auto-launch
#
# 이는 Apple 의 우클릭→열기 / 시스템 설정→Open Anyway 와 본질적으로 동등합니다.
# This is essentially equivalent to right-click→Open / System Settings→Open Anyway.

set -euo pipefail

# ── 설정 / Config ────────────────────────────────────────
DMG_URL="${AFTER5_DMG_URL:-https://github.com/jhyeo001/after5-release/releases/latest/download/After5.dmg}"
APP_NAME="After5"
SUPPORT_EMAIL="jhyeo001@gmail.com"
TMP_DMG="$(mktemp -t after5_dmg).dmg"
TMP_DIR=""

# ── 출력 도우미 / Output helpers ─────────────────────────
ok() { printf '\033[32m✓\033[0m %s\n' "$1"; }
info() { printf '\033[34m·\033[0m %s\n' "$1"; }
warn() { printf '\033[33m!\033[0m %s\n' "$1" >&2; }
err()  { printf '\033[31m✗\033[0m %s\n' "$1" >&2; exit 1; }

cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    hdiutil detach "$TMP_DIR" -quiet 2>/dev/null || true
  fi
  rm -f "$TMP_DMG"
}
trap cleanup EXIT

# ── OS 체크 / OS check ───────────────────────────────────
if [ "$(uname -s)" != "Darwin" ]; then
  err "이 스크립트는 macOS 전용입니다 / This script is macOS only. (현재/current: $(uname -s))"
fi

# ── 환영 + 동의 확인 / Banner + confirmation ─────────────
cat <<'BANNER'

  ┌─────────────────────────────────────────────┐
  │            After5 베타 빠른 설치              │
  │            After5 Beta Quick Installer        │
  └─────────────────────────────────────────────┘

  이 스크립트가 수행할 작업:
  This script will:

    1. 공식 DMG 다운로드 / Download the official DMG경
    2. 실행 중인 After5 종료 / Quit any running After5
    3. /Applications/After5.app 으로 설치 / Install to /Applications
    4. macOS 의 미서명 앱 차단 우회 / Bypass macOS unsigned-app block
    5. After5 자동 실행 / Launch After5

  ⚠ 이 스크립트는 신뢰할 수 있는 공식 출처에서만 실행하세요.
  ⚠ Run this script only from a trusted official source.

BANNER

if [ "${AFTER5_NO_PROMPT:-}" != "1" ]; then
  # curl ... | bash 환경에서는 stdin 이 파이프라 사용자 입력을 못 받음 → /dev/tty 사용.
  # /dev/tty 도 없으면 (CI 등) prompt 생략하고 진행.
  if [ -t 0 ]; then
    read -p "  계속하시겠습니까? / Continue? [y/N] " -n 1 -r REPLY
    echo
  elif [ -e /dev/tty ]; then
    read -p "  계속하시겠습니까? / Continue? [y/N] " -n 1 -r REPLY < /dev/tty
    echo
  else
    REPLY="y"
    info "non-interactive 환경 — prompt 생략 / non-interactive — skipping prompt"
  fi
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    info "취소됨 / Cancelled."
    exit 0
  fi
fi

# ── /Applications 쓰기 권한 확인 / Write permission ──────
if [ ! -w "/Applications" ]; then
  cat <<EOF >&2

  ✗ /Applications 폴더에 쓰기 권한이 없어요.
  ✗ No write permission to /Applications.

  관리되는 Mac (회사 / 학교) 일 가능성이 큽니다. 개인 Mac 에서 다시 시도하거나,
  IT 관리자에게 /Applications 쓰기 권한을 요청해주세요.

  This often happens on managed Macs (work / school). Try on a personal Mac,
  or ask your IT admin for write access to /Applications.

  문의 / Contact: $SUPPORT_EMAIL
EOF
  exit 1
fi

# ── 1. 다운로드 / Download ───────────────────────────────
info "DMG 다운로드 중… / Downloading DMG…  $DMG_URL"
if ! curl -fL --progress-bar "$DMG_URL" -o "$TMP_DMG"; then
  err "다운로드 실패 / Download failed. URL 또는 네트워크를 확인해주세요. / Check URL or network."
fi
ok "다운로드 완료 / Downloaded ($(du -h "$TMP_DMG" | awk '{print $1}'))"

# ── 2. SHA256 검증 (옵션) / SHA256 verify (optional) ─────
if [ -n "${AFTER5_EXPECTED_SHA256:-}" ]; then
  info "SHA256 검증 중… / Verifying SHA256…"
  ACTUAL=$(shasum -a 256 "$TMP_DMG" | awk '{print $1}')
  if [ "$ACTUAL" != "$AFTER5_EXPECTED_SHA256" ]; then
    err "SHA256 불일치 / SHA256 mismatch.
    expected: $AFTER5_EXPECTED_SHA256
    actual:   $ACTUAL"
  fi
  ok "SHA256 검증 통과 / SHA256 verified"
fi

# ── 3. 실행 중인 After5 종료 / Quit running After5 ───────
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  info "실행 중인 $APP_NAME 종료 중… / Quitting running $APP_NAME…"
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 1
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    pkill -9 -x "$APP_NAME" 2>/dev/null || true
    sleep 1
  fi
  ok "종료됨 / Quit"
fi

# ── 4. 마운트 + 복사 + 언마운트 / Mount + copy + unmount ─
info "DMG 마운트 중… / Mounting DMG…"
TMP_DIR=$(mktemp -d -t after5_mount)
hdiutil attach "$TMP_DMG" -mountpoint "$TMP_DIR" -nobrowse -quiet
ok "마운트됨 / Mounted: $TMP_DIR"

if [ ! -d "$TMP_DIR/$APP_NAME.app" ]; then
  err "$APP_NAME.app 을 DMG 안에서 찾을 수 없어요 / Cannot find $APP_NAME.app inside the DMG.
DMG 구조가 예상과 다를 수 있습니다. / DMG structure may differ from expected.
문의 / Contact: $SUPPORT_EMAIL"
fi

if [ -d "/Applications/$APP_NAME.app" ]; then
  info "기존 /Applications/$APP_NAME.app 교체 / Replacing existing /Applications/$APP_NAME.app"
  rm -rf "/Applications/$APP_NAME.app"
fi

info "/Applications/$APP_NAME.app 으로 복사 중… / Copying to /Applications/$APP_NAME.app…"
cp -R "$TMP_DIR/$APP_NAME.app" /Applications/
ok "설치 완료 / Installed"

hdiutil detach "$TMP_DIR" -quiet
TMP_DIR=""

# ── 5. Quarantine 제거 (Gatekeeper 우회) / Remove quarantine ─
info "Gatekeeper quarantine 속성 제거 중… / Removing quarantine attribute…"
if xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null; then
  ok "quarantine 제거 — 보안 경고 없음 / quarantine removed — no security warning"
else
  warn "quarantine 제거 건너뜀 (이미 없거나 권한 부족) / quarantine skip (already absent or permission)"
fi

# ── 6. 실행 / Launch ─────────────────────────────────────
if [ "${AFTER5_NO_LAUNCH:-}" = "1" ]; then
  ok "설치 완료 / Installed. /Applications/$APP_NAME.app 에서 실행 / Launch from /Applications/$APP_NAME.app."
else
  info "$APP_NAME 실행 중… / Launching $APP_NAME…"
  open "/Applications/$APP_NAME.app"
  ok "완료. 즐거운 베타 테스트 되세요!"
  ok "Done. Enjoy the beta!"
fi

cat <<EOF

  피드백 / 문제 / Feedback or issues:
  $SUPPORT_EMAIL

EOF
