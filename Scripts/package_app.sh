#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"

APP_NAME="BlackBar"
BUNDLE_ID="${BLACKBAR_BUNDLE_IDENTIFIER:-com.steipete.blackbar}"
BUILD_ARGS=(-c "$CONFIGURATION")

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  log "==> Building ${APP_NAME} (${CONFIGURATION})"
  if [[ "$CONFIGURATION" == "release" ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
  fi
  swift build "${BUILD_ARGS[@]}"
fi

BUILD_DIR="$ROOT/.build/$CONFIGURATION"
if [[ "$CONFIGURATION" == "release" && -f "$ROOT/.build/apple/Products/Release/$APP_NAME" ]]; then
  BUILD_DIR="$ROOT/.build/apple/Products/Release"
elif [[ -f "$ROOT/.build/arm64-apple-macosx/$CONFIGURATION/$APP_NAME" ]]; then
  BUILD_DIR="$ROOT/.build/arm64-apple-macosx/$CONFIGURATION"
fi

APP_EXECUTABLE="$BUILD_DIR/$APP_NAME"
[[ -f "$APP_EXECUTABLE" ]] || fail "Missing executable: $APP_EXECUTABLE"

APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Frameworks" "$APP_BUNDLE/Contents/Resources"
cp "$APP_EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [[ -f "$ROOT/Resources/Icon.icns" ]]; then
  cp "$ROOT/Resources/Icon.icns" "$APP_BUNDLE/Contents/Resources/Icon.icns"
fi

SPARKLE_FRAMEWORK="$BUILD_DIR/Sparkle.framework"
[[ -d "$SPARKLE_FRAMEWORK" ]] || fail "Missing Sparkle.framework: $SPARKLE_FRAMEWORK"
log "==> Installing Sparkle.framework"
/usr/bin/ditto "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleIconFile</key>
    <string>Icon</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Peter Steinberger</string>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/steipete/BlackBar/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>oIgha2beQWnyCXgOIlB8+oaUzFNtWgkqq6jKXNNDhv4=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUEnableInstallerLauncherService</key>
    <true/>
</dict>
</plist>
PLIST

VERIFY_ARGS=("$APP_BUNDLE")
if [[ "$CONFIGURATION" == "release" ]]; then VERIFY_ARGS+=(--universal); fi
"$ROOT/Scripts/verify_app_bundle.sh" "${VERIFY_ARGS[@]}"

if [[ -n "${CODESIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-}}" ]]; then
  IDENTITY="${CODESIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-}}"
  log "==> Codesigning with $IDENTITY"
  "$ROOT/Scripts/codesign_app.sh" "$APP_BUNDLE" "$IDENTITY"
fi

if [[ "$CONFIGURATION" == "release" ]]; then
  ZIP_NAME="$ROOT/$APP_NAME-$MARKETING_VERSION.zip"
  DSYM_ZIP="$ROOT/$APP_NAME-$MARKETING_VERSION.dSYM.zip"
  log "==> Zipping app to $(basename "$ZIP_NAME")"
  /usr/bin/ditto -c -k --keepParent --sequesterRsrc "$APP_BUNDLE" "$ZIP_NAME"

  DSYM_PATH="$BUILD_DIR/$APP_NAME.dSYM"
  if [[ -d "$DSYM_PATH" ]]; then
    log "==> Zipping dSYM to $(basename "$DSYM_ZIP")"
    /usr/bin/ditto -c -k --keepParent "$DSYM_PATH" "$DSYM_ZIP"
  else
    fail "Missing dSYM: $DSYM_PATH"
  fi
fi

log "Done: $APP_BUNDLE"
