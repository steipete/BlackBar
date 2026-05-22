#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"

APP_NAME="BlackBar"
APP_IDENTITY="${BLACKBAR_CODE_SIGN_IDENTITY:-Developer ID Application: Peter Steinberger (Y5PE65HELJ)}"
ZIP_NAME="$APP_NAME-$MARKETING_VERSION.zip"
DSYM_ZIP="$APP_NAME-$MARKETING_VERSION.dSYM.zip"
API_KEY_PATH="/tmp/blackbar-api-key.p8"
PKCS8_API_KEY_PATH="$API_KEY_PATH.pkcs8"
NOTARY_ZIP="/tmp/BlackBarNotarize.zip"

if [[ -z "${APP_STORE_CONNECT_API_KEY_P8:-}" || -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  echo "Missing APP_STORE_CONNECT_* env vars (API key, key id, issuer id)." >&2
  exit 1
fi

printf '%s\n' "$APP_STORE_CONNECT_API_KEY_P8" | sed 's/\\n/\n/g; 1s/^"//; $s/"$//' > "$API_KEY_PATH"
trap 'rm -f "$API_KEY_PATH" "$PKCS8_API_KEY_PATH" "$NOTARY_ZIP"' EXIT
if grep -q "BEGIN EC PRIVATE KEY" "$API_KEY_PATH"; then
  openssl pkcs8 -topk8 -nocrypt -in "$API_KEY_PATH" -out "$PKCS8_API_KEY_PATH"
  mv "$PKCS8_API_KEY_PATH" "$API_KEY_PATH"
fi

swift build -c release --arch arm64 --arch x86_64
SKIP_BUILD=1 CODESIGN_IDENTITY="$APP_IDENTITY" "$ROOT/Scripts/package_app.sh" release

APP_BUNDLE=""
for candidate in \
  ".build/apple/Products/Release/$APP_NAME.app" \
  ".build/release/$APP_NAME.app" \
  ".build/arm64-apple-macosx/release/$APP_NAME.app" \
  ".build/x86_64-apple-macosx/release/$APP_NAME.app"; do
  if [[ -d "$candidate" ]]; then
    APP_BUNDLE="$candidate"
    break
  fi
done
[[ -n "$APP_BUNDLE" ]] || { echo "ERROR: app bundle not found" >&2; exit 1; }

/usr/bin/ditto -c -k --keepParent --sequesterRsrc "$APP_BUNDLE" "$NOTARY_ZIP"

echo "Submitting for notarization"
xcrun notarytool submit "$NOTARY_ZIP" \
  --key "$API_KEY_PATH" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

echo "Stapling ticket"
xcrun stapler staple "$APP_BUNDLE"

/usr/bin/ditto -c -k --keepParent --sequesterRsrc "$APP_BUNDLE" "$ZIP_NAME"

spctl -a -t exec -vv "$APP_BUNDLE"
stapler validate "$APP_BUNDLE"

DSYM_PATH=".build/apple/Products/Release/$APP_NAME.dSYM"
if [[ ! -d "$DSYM_PATH" ]]; then DSYM_PATH=".build/release/$APP_NAME.dSYM"; fi
if [[ ! -d "$DSYM_PATH" ]]; then DSYM_PATH=".build/arm64-apple-macosx/release/$APP_NAME.dSYM"; fi
if [[ ! -d "$DSYM_PATH" ]]; then DSYM_PATH=".build/x86_64-apple-macosx/release/$APP_NAME.dSYM"; fi
[[ -d "$DSYM_PATH" ]] || { echo "Missing dSYM" >&2; exit 1; }
/usr/bin/ditto -c -k --keepParent "$DSYM_PATH" "$DSYM_ZIP"

echo "Done: $ZIP_NAME"
