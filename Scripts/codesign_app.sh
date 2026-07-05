#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_PATH="${1:-$ROOT/.build/release/BlackBar.app}"
IDENTITY="${2:-${BLACKBAR_CODE_SIGN_IDENTITY:-${CODESIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-}}}}"
APP_NAME="BlackBar"
BUNDLE_ID="com.steipete.blackbar"
TIMESTAMP="${CODESIGN_TIMESTAMP:-1}"
KEYCHAIN="${CODESIGN_KEYCHAIN:-}"
KEYCHAIN_PASSWORD="${CODESIGN_KEYCHAIN_PASSWORD:-}"

log() { printf '%s\n' "[$(date '+%H:%M:%S')] $*"; }

if [[ -z "$IDENTITY" ]]; then
  log "No signing identity provided; skipping codesign for $APP_PATH"
  exit 0
fi
[[ -d "$APP_PATH" ]] || { echo "App bundle not found: $APP_PATH" >&2; exit 1; }

CODESIGN_ARGS=(--force --options runtime)
if [[ "$TIMESTAMP" != "0" ]]; then
  CODESIGN_ARGS+=(--timestamp)
fi
if [[ -n "$KEYCHAIN" ]]; then
  [[ -n "$KEYCHAIN_PASSWORD" ]] || {
    echo "CODESIGN_KEYCHAIN_PASSWORD is required with CODESIGN_KEYCHAIN" >&2
    exit 1
  }
  log "Unlocking signing keychain"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  CODESIGN_ARGS+=(--keychain "$KEYCHAIN")
fi

TMP_ENTITLEMENTS=$(mktemp "${TMPDIR:-/tmp}/BlackBar_entitlements.XXXXXX.plist")
trap 'rm -f "$TMP_ENTITLEMENTS"' EXIT

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "$BUNDLE_ID")"
cat > "$TMP_ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.hardened-runtime</key>
    <true/>
    <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
    <array>
        <string>${bundle_id}-spks</string>
        <string>${bundle_id}-spkd</string>
    </array>
</dict>
</plist>
PLIST

xattr -cr "$APP_PATH" 2>/dev/null || true

log "Signing frameworks"
if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
  while read -r framework; do
    codesign "${CODESIGN_ARGS[@]}" --sign "$IDENTITY" "$framework"
  done < <(find "$APP_PATH/Contents/Frameworks" \( -type d -name '*.framework' -o -type f -name '*.dylib' \))
fi

SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  log "Signing Sparkle components"
  SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/B"
  for path in \
    "$SPARKLE_VERSION/Sparkle" \
    "$SPARKLE_VERSION/Autoupdate" \
    "$SPARKLE_VERSION/Updater.app/Contents/MacOS/Updater" \
    "$SPARKLE_VERSION/Updater.app" \
    "$SPARKLE_VERSION/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
    "$SPARKLE_VERSION/XPCServices/Downloader.xpc" \
    "$SPARKLE_VERSION/XPCServices/Installer.xpc/Contents/MacOS/Installer" \
    "$SPARKLE_VERSION/XPCServices/Installer.xpc" \
    "$SPARKLE_VERSION" \
    "$SPARKLE_FRAMEWORK"; do
    if [[ -e "$path" ]]; then
      codesign "${CODESIGN_ARGS[@]}" --sign "$IDENTITY" "$path"
    fi
  done
fi

log "Signing app executable"
codesign "${CODESIGN_ARGS[@]}" --entitlements "$TMP_ENTITLEMENTS" --sign "$IDENTITY" "$APP_PATH/Contents/MacOS/$APP_NAME"

log "Signing app bundle"
codesign "${CODESIGN_ARGS[@]}" --entitlements "$TMP_ENTITLEMENTS" --sign "$IDENTITY" "$APP_PATH"

log "Verifying"
codesign --verify --verbose=2 "$APP_PATH"
log "Done codesigning $APP_PATH"
