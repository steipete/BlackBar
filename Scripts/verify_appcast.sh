#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:-$(source "$ROOT/version.env" && echo "$MARKETING_VERSION")}
APPCAST="$ROOT/appcast.xml"

[[ -f "$APPCAST" ]] || { echo "appcast.xml not found at $APPCAST" >&2; exit 1; }

KEY_ARGS=()
KEY_FILE=""
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  [[ -f "$SPARKLE_PRIVATE_KEY_FILE" ]] || { echo "Sparkle key file not found: $SPARKLE_PRIVATE_KEY_FILE" >&2; exit 1; }
  key_lines=$(grep -v '^[[:space:]]*#' "$SPARKLE_PRIVATE_KEY_FILE" | sed '/^[[:space:]]*$/d')
  if [[ $(printf "%s\n" "$key_lines" | wc -l) -ne 1 ]]; then
    echo "Sparkle key file must contain exactly one base64 line (no comments/blank lines)." >&2
    exit 1
  fi
  KEY_FILE=$(mktemp)
  printf "%s" "$key_lines" > "$KEY_FILE"
  KEY_ARGS=(--ed-key-file "$KEY_FILE")
else
  expected_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/Resources/Info.plist")
  actual_key=$(generate_keys -p)
  if [[ "$actual_key" != "$expected_key" ]]; then
    echo "Default Sparkle keychain key does not match BlackBar SUPublicEDKey." >&2
    exit 1
  fi
fi
TMP_ZIP=$(mktemp /tmp/blackbar-enclosure.XXXX.zip)
TMP_META=$(mktemp /tmp/blackbar-enclosure.XXXX.meta)
TMP_DIR=$(mktemp -d /tmp/blackbar-enclosure.XXXX)
trap 'rm -f "$KEY_FILE" "$TMP_ZIP" "$TMP_META"; rm -rf "$TMP_DIR"' EXIT

python3 - "$APPCAST" "$VERSION" > "$TMP_META" <<'PY'
import sys
import xml.etree.ElementTree as ET

appcast = sys.argv[1]
version = sys.argv[2]
tree = ET.parse(appcast)
root = tree.getroot()
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}

entry = None
for item in root.findall("./channel/item"):
    sv = item.findtext("sparkle:shortVersionString", default="", namespaces=ns)
    if sv == version:
        entry = item
        break

if entry is None:
    sys.exit(f"No appcast entry found for version {version}")

enclosure = entry.find("enclosure")
url = enclosure.get("url")
sig = enclosure.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature")
length = enclosure.get("length")
if not all([url, sig, length]):
    sys.exit(f"Missing url/signature/length in appcast for version {version}")

print(url)
print(sig)
print(length)
PY

URL=$(sed -n '1p' "$TMP_META")
SIG=$(sed -n '2p' "$TMP_META")
LEN_EXPECTED=$(sed -n '3p' "$TMP_META")

echo "Downloading enclosure: $URL"
curl -L -o "$TMP_ZIP" "$URL"

LEN_ACTUAL=$(stat -f%z "$TMP_ZIP")
if [[ "$LEN_ACTUAL" != "$LEN_EXPECTED" ]]; then
  echo "Length mismatch: expected $LEN_EXPECTED, got $LEN_ACTUAL" >&2
  exit 1
fi

echo "Verifying Sparkle signature"
sign_update --verify "$TMP_ZIP" "$SIG" "${KEY_ARGS[@]}"

/usr/bin/ditto -x -k --norsrc "$TMP_ZIP" "$TMP_DIR"
APP_BUNDLE=$(find "$TMP_DIR" -maxdepth 2 -name "BlackBar.app" -not -path "*/__MACOSX/*" | head -n 1)
[[ -n "$APP_BUNDLE" ]] || { echo "No BlackBar.app found in enclosure" >&2; exit 1; }

echo "Verifying codesign and notarization"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
spctl --assess --type execute --verbose "$APP_BUNDLE"
stapler validate "$APP_BUNDLE"
echo "Appcast entry for $VERSION verified."
