#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ $# -ge 1 && $# -le 2 ]] || fail "Usage: $0 APP_BUNDLE [--universal]"
APP_BUNDLE=$1
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/BlackBar"
[[ -x "$EXECUTABLE" ]] || fail "Missing executable: $EXECUTABLE"
ARCHS=$(/usr/bin/lipo -archs "$EXECUTABLE")
if [[ $# -eq 2 ]]; then
  [[ $2 == --universal ]] || fail "Unknown option: $2"
  [[ " $ARCHS " == *' arm64 '* && " $ARCHS " == *' x86_64 '* ]] || fail "App must contain arm64 and x86_64"
fi
read -r -a ARCHITECTURES <<< "$ARCHS"
[[ ${#ARCHITECTURES[@]} -gt 0 ]] || fail "No executable architectures"
for arch in "${ARCHITECTURES[@]}"; do
  RPATHS=$(/usr/bin/otool -arch "$arch" -l "$EXECUTABLE" | awk '
    $1 == "cmd" && $2 == "LC_RPATH" { getline; getline; print $2 }
  ')
  grep -Fxq '@executable_path/../Frameworks' <<< "$RPATHS" ||
    fail "$arch: missing @executable_path/../Frameworks runtime search path"

  SPARKLE_DEPENDENCY=$(/usr/bin/otool -arch "$arch" -L "$EXECUTABLE" | awk '
    $1 ~ /^@rpath\/Sparkle\.framework\// { print $1 }
  ')
  [[ -n "$SPARKLE_DEPENDENCY" ]] || fail "$arch: missing Sparkle framework dependency"
  SPARKLE_BINARY="$APP_BUNDLE/Contents/Frameworks/${SPARKLE_DEPENDENCY#@rpath/}"
  [[ -f "$SPARKLE_BINARY" ]] || fail "$arch: missing embedded Sparkle binary: $SPARKLE_BINARY"
  SPARKLE_ARCHS=$(/usr/bin/lipo -archs "$SPARKLE_BINARY")
  [[ " $SPARKLE_ARCHS " == *" $arch "* ]] || fail "Sparkle is missing architecture: $arch"
done

printf 'Verified app bundle (%s): %s\n' "$ARCHS" "$APP_BUNDLE"
