#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"
source "$HOME/Projects/agent-scripts/release/sparkle_lib.sh"

APP_NAME="BlackBar"
APPCAST="$ROOT/appcast.xml"
BUNDLE_ID="com.steipete.blackbar"
TAG="v${MARKETING_VERSION}"

require_clean_worktree
ensure_changelog_finalized "$MARKETING_VERSION"
ensure_appcast_monotonic "$APPCAST" "$MARKETING_VERSION" "$BUILD_NUMBER"

swift build -c release

"$ROOT/Scripts/sign-and-notarize.sh"

KEY_FILE=""
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  KEY_FILE=$(clean_key "$SPARKLE_PRIVATE_KEY_FILE")
  probe_sparkle_key "$KEY_FILE"
else
  probe=$(mktemp /tmp/blackbar-sparkle-keychain.XXXX)
  echo test > "$probe"
  sign_update -p "$probe" >/dev/null
  rm -f "$probe"
fi
clear_sparkle_caches "$BUNDLE_ID"

NOTES_MD=$(mktemp /tmp/blackbar-notes.XXXX.md)
"$ROOT/Scripts/generate-release-notes.sh" "$MARKETING_VERSION" "$NOTES_MD"
trap 'rm -f "$KEY_FILE" "$NOTES_MD"' EXIT

git tag -f "$TAG" -m "${APP_NAME} ${MARKETING_VERSION}"
git push -f origin "$TAG"

gh release create "$TAG" "${APP_NAME}-${MARKETING_VERSION}.zip" "${APP_NAME}-${MARKETING_VERSION}.dSYM.zip" \
  --title "${APP_NAME} ${MARKETING_VERSION}" \
  --notes-file "$NOTES_MD"

if [[ -n "$KEY_FILE" ]]; then
  SPARKLE_PRIVATE_KEY_FILE="$KEY_FILE" \
    "$ROOT/Scripts/make_appcast.sh" \
    "${APP_NAME}-${MARKETING_VERSION}.zip" \
    "https://raw.githubusercontent.com/steipete/BlackBar/main/appcast.xml"
  SPARKLE_PRIVATE_KEY_FILE="$KEY_FILE" "$ROOT/Scripts/verify_appcast.sh" "$MARKETING_VERSION"
else
  env -u SPARKLE_PRIVATE_KEY_FILE \
    "$ROOT/Scripts/make_appcast.sh" \
    "${APP_NAME}-${MARKETING_VERSION}.zip" \
    "https://raw.githubusercontent.com/steipete/BlackBar/main/appcast.xml"
  env -u SPARKLE_PRIVATE_KEY_FILE "$ROOT/Scripts/verify_appcast.sh" "$MARKETING_VERSION"
fi

git add "$APPCAST"
git commit -m "docs: update appcast for ${MARKETING_VERSION}"
git push origin main
git push origin --tags

"$ROOT/Scripts/check-release-assets.sh" "$TAG"

echo "Release ${MARKETING_VERSION} complete."
