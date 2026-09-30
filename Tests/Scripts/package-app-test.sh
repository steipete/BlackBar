#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
FIXTURE="$TEST_ROOT/project"
BUILD="$FIXTURE/.build/apple/Products/Release"
FRAMEWORK="$BUILD/Sparkle.framework/Versions/B"
mkdir -p "$FIXTURE/Scripts" "$FIXTURE/Resources" "$FRAMEWORK" "$BUILD/BlackBar.dSYM"
cp "$ROOT/Scripts/package_app.sh" "$ROOT/Scripts/verify_app_bundle.sh" "$FIXTURE/Scripts/"
printf 'MARKETING_VERSION=0.0.0\nBUILD_NUMBER=1\n' > "$FIXTURE/version.env"
printf 'int sparkle_fixture(void) { return 0; }\n' > "$TEST_ROOT/sparkle.c"
printf 'extern int sparkle_fixture(void); int main(void) { return sparkle_fixture(); }\n' > "$TEST_ROOT/main.c"
xcrun clang -arch arm64 -arch x86_64 -dynamiclib "$TEST_ROOT/sparkle.c" \
  -install_name '@rpath/Sparkle.framework/Versions/B/Sparkle' -o "$FRAMEWORK/Sparkle"
ln -s B "$BUILD/Sparkle.framework/Versions/Current"
ln -s Versions/Current/Sparkle "$BUILD/Sparkle.framework/Sparkle"
xcrun clang -arch arm64 -arch x86_64 "$TEST_ROOT/main.c" "$FRAMEWORK/Sparkle" \
  -Wl,-headerpad_max_install_names -Wl,-rpath,@executable_path/../Frameworks -o "$BUILD/BlackBar"

package() {
  SKIP_BUILD=1 CODESIGN_IDENTITY= CODE_SIGN_IDENTITY= "$FIXTURE/Scripts/package_app.sh" release
}
expect_failure() {
  local expected=$1
  shift
  if "$@" > "$TEST_ROOT/failure.log" 2>&1; then
    echo "Expected failure: $expected" >&2
    exit 1
  fi
  grep -Fq "$expected" "$TEST_ROOT/failure.log" || { cat "$TEST_ROOT/failure.log"; exit 1; }
}

package
/usr/bin/ditto -x -k "$FIXTURE/BlackBar-0.0.0.zip" "$TEST_ROOT/extracted"
APP="$TEST_ROOT/extracted/BlackBar.app"
VERIFY="$ROOT/Scripts/verify_app_bundle.sh"
"$VERIFY" "$APP" --universal
[[ ! -e "$APP/Contents/lib" && ! -e "$APP/Contents/MacOS/Sparkle.framework" ]]

# A single broken slice must fail even on a host that runs the other slice.
/usr/bin/lipo "$BUILD/BlackBar" -thin x86_64 -output "$TEST_ROOT/intel"
/usr/bin/lipo "$BUILD/BlackBar" -thin arm64 -output "$TEST_ROOT/arm"
/usr/bin/install_name_tool -delete_rpath '@executable_path/../Frameworks' "$TEST_ROOT/intel"
/usr/bin/lipo -create "$TEST_ROOT/intel" "$TEST_ROOT/arm" -output "$APP/Contents/MacOS/BlackBar"
expect_failure 'x86_64: missing @executable_path/../Frameworks' "$VERIFY" "$APP" --universal
cp "$BUILD/BlackBar" "$APP/Contents/MacOS/BlackBar"

rm "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
expect_failure 'missing embedded Sparkle binary' "$VERIFY" "$APP" --universal
/usr/bin/lipo "$FRAMEWORK/Sparkle" -thin arm64 -output "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
expect_failure 'Sparkle is missing architecture: x86_64' "$VERIFY" "$APP" --universal

mv "$BUILD/Sparkle.framework" "$TEST_ROOT/Sparkle.framework"
expect_failure 'Missing Sparkle.framework' package
mv "$TEST_ROOT/Sparkle.framework" "$BUILD/Sparkle.framework"
/usr/bin/install_name_tool -delete_rpath '@executable_path/../Frameworks' "$BUILD/BlackBar"
expect_failure 'missing @executable_path/../Frameworks' package
echo 'App packaging regression tests passed'
