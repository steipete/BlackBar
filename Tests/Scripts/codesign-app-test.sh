#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

APP_PATH="$TEST_ROOT/BlackBar.app"
FAKE_LOG="$TEST_ROOT/codesign.log"
SECURITY_LOG="$TEST_ROOT/security.log"
mkdir -p "$TEST_ROOT/bin" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Frameworks/Test.framework"
touch "$APP_PATH/Contents/MacOS/BlackBar"

cat > "$TEST_ROOT/bin/codesign" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_LOG"
if [[ -n "${FAIL_MATCH:-}" && "$*" == *"$FAIL_MATCH"* ]]; then
  exit 86
fi
SCRIPT
chmod +x "$TEST_ROOT/bin/codesign"

cat > "$TEST_ROOT/bin/security" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$SECURITY_LOG"
SCRIPT
chmod +x "$TEST_ROOT/bin/security"

PATH="$TEST_ROOT/bin:$PATH" \
FAKE_LOG="$FAKE_LOG" \
SECURITY_LOG="$SECURITY_LOG" \
CODESIGN_TIMESTAMP=0 \
CODESIGN_KEYCHAIN="$TEST_ROOT/release.keychain-db" \
CODESIGN_KEYCHAIN_PASSWORD="test password" \
  "$ROOT/Scripts/codesign_app.sh" "$APP_PATH" "Developer ID Test" >/dev/null

if grep -q -- '--timestamp' "$FAKE_LOG"; then
  echo "Local signing unexpectedly requested a timestamp" >&2
  exit 1
fi
grep -q -- "--keychain $TEST_ROOT/release.keychain-db" "$FAKE_LOG"
grep -q -- "unlock-keychain -p test password $TEST_ROOT/release.keychain-db" "$SECURITY_LOG"

: > "$FAKE_LOG"
PATH="$TEST_ROOT/bin:$PATH" FAKE_LOG="$FAKE_LOG" \
  "$ROOT/Scripts/codesign_app.sh" "$APP_PATH" "Developer ID Test" >/dev/null
grep -q -- '--timestamp' "$FAKE_LOG"

set +e
PATH="$TEST_ROOT/bin:$PATH" FAKE_LOG="$FAKE_LOG" FAIL_MATCH="Test.framework" \
  "$ROOT/Scripts/codesign_app.sh" "$APP_PATH" "Developer ID Test" >/dev/null 2>&1
status=$?
set -e

if [[ "$status" -ne 86 ]]; then
  echo "Expected framework signing failure status 86, got $status" >&2
  exit 1
fi

echo "codesign app options test passed"
