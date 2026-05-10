#!/usr/bin/env bash
# Studio One / After5 — Mac 베타 빠른 설치 스크립트.
#
# 사용:
#   curl -fsSL <SCRIPT_URL> | bash
#   또는 다운로드 후
#   bash install-mac.sh
#
# 환경 변수로 동작 변경 가능:
#   AFTER5_DMG_URL          : 다운로드할 DMG URL (default 아래 값)
#   AFTER5_EXPECTED_SHA256  : 검증 hash (있으면 다운 후 검증)
#   AFTER5_NO_LAUNCH=1      : 설치 후 자동 실행 안 함
#   AFTER5_NO_PROMPT=1      : 진행 확인 prompt 생략 (CI / 자동화)
#
# 무엇을 하나:
#   1. DMG 다운로드 (curl)
#   2. (옵션) SHA256 검증
#   3. DMG mount → /Applications 에 .app 복사 → unmount
#   4. xattr -dr com.apple.quarantine 으로 Gatekeeper 우회
#      (미서명 베타 빌드의 'unidentified developer' 차단을 매크로로 자동 처리)
#   5. 자동 실행 (안 하려면 AFTER5_NO_LAUNCH=1)
#
# Apple 의 우클릭→열기 / System Settings → Open Anyway 와 본질적으로 동등 —
# 차이는 다이얼로그 없이 자동 처리. 사용자가 이 스크립트를 실행한다는 것
# 자체가 출처 신뢰의 명시적 동의로 간주.

set -euo pipefail

# ── 기본 설정 ────────────────────────────────────────────
DMG_URL="${AFTER5_DMG_URL:-https://github.com/jhyeo001/studio-one/releases/latest/download/After5.dmg}"
APP_NAME="After5"
TMP_DMG="$(mktemp -t after5_dmg).dmg"
TMP_DIR=""

# ── 유틸 ────────────────────────────────────────────────
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

# ── OS 체크 ──────────────────────────────────────────────
if [ "$(uname -s)" != "Darwin" ]; then
  err "이 스크립트는 macOS 전용입니다. (현재: $(uname -s))"
fi

# ── 환영 + 동의 확인 ─────────────────────────────────────
cat <<'BANNER'

  ┌─────────────────────────────────────────────┐
  │            After5 베타 빠른 설치              │
  └─────────────────────────────────────────────┘

  이 스크립트가 수행할 작업:
    1. 공식 DMG 다운로드
    2. /Applications/After5.app 으로 설치
    3. macOS 의 미서명 앱 차단 우회 (xattr 제거)
    4. After5 자동 실행

  ⚠ 이 스크립트는 신뢰할 수 있는 공식 출처에서만 실행하세요.
     스크립트 출처를 모르면 중단하세요.

BANNER

if [ "${AFTER5_NO_PROMPT:-}" != "1" ]; then
  read -p "  계속하시겠습니까? [y/N] " -n 1 -r REPLY
  echo
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    info "취소됨."
    exit 0
  fi
fi

# ── 1. 다운로드 ──────────────────────────────────────────
info "DMG 다운로드 중…  $DMG_URL"
if ! curl -fL --progress-bar "$DMG_URL" -o "$TMP_DMG"; then
  err "다운로드 실패. URL 또는 네트워크를 확인하세요."
fi
ok "다운로드 완료 ($(du -h "$TMP_DMG" | awk '{print $1}'))"

# ── 2. SHA256 검증 (옵션) ────────────────────────────────
if [ -n "${AFTER5_EXPECTED_SHA256:-}" ]; then
  info "SHA256 검증 중…"
  ACTUAL=$(shasum -a 256 "$TMP_DMG" | awk '{print $1}')
  if [ "$ACTUAL" != "$AFTER5_EXPECTED_SHA256" ]; then
    err "SHA256 불일치. 받은 파일이 변조됐거나 출처가 잘못됐을 수 있습니다.
    expected: $AFTER5_EXPECTED_SHA256
    actual:   $ACTUAL"
  fi
  ok "SHA256 검증 통과"
fi

# ── 3. 마운트 + 복사 + 언마운트 ──────────────────────────
info "DMG 마운트 중…"
TMP_DIR=$(mktemp -d -t after5_mount)
hdiutil attach "$TMP_DMG" -mountpoint "$TMP_DIR" -nobrowse -quiet
ok "마운트됨: $TMP_DIR"

if [ ! -d "$TMP_DIR/$APP_NAME.app" ]; then
  err "$APP_NAME.app 을 DMG 안에서 찾을 수 없습니다. DMG 구조가 예상과 다를 수 있어요."
fi

if [ -d "/Applications/$APP_NAME.app" ]; then
  info "기존 /Applications/$APP_NAME.app 발견 — 교체합니다."
  rm -rf "/Applications/$APP_NAME.app"
fi

info "/Applications/$APP_NAME.app 으로 복사 중…"
cp -R "$TMP_DIR/$APP_NAME.app" /Applications/
ok "설치 완료"

hdiutil detach "$TMP_DIR" -quiet
TMP_DIR=""

# ── 4. Quarantine 제거 (Gatekeeper 우회) ─────────────────
info "Gatekeeper quarantine 속성 제거 중…"
if xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null; then
  ok "quarantine 제거 — 첫 실행 시 보안 경고 없음"
else
  # quarantine 이 없는 경우에도 -d 는 에러 — 무시 가능.
  warn "quarantine 제거 건너뜀 (이미 없거나 권한 부족). 첫 실행 시 우클릭 → 열기 필요할 수 있음."
fi

# ── 5. 실행 ──────────────────────────────────────────────
if [ "${AFTER5_NO_LAUNCH:-}" = "1" ]; then
  ok "설치 완료. /Applications/$APP_NAME.app 에서 실행하세요."
else
  info "After5 실행 중…"
  open "/Applications/$APP_NAME.app"
  ok "완료. 즐거운 베타 테스트 되세요!"
fi
