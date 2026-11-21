#!/bin/bash
# Builds "PAYE Launcher.app" (universal) with the native runtime, signs it and
# makes a DMG. Optionally notarises and staples the DMG.
#
# Usage: scripts/package_app.sh [options]
#   --runtime DIR     native runtime folder (default: ~/Library/Caches/PAYELauncher/runtime-build/runtime)
#   --no-runtime      build without the native runtime (HMRC server only)
#   --version V       version (default: scripts/version.sh)
#   --sign IDENTITY   "Developer ID Application: ..." (default: "-", ad-hoc)
#   --notarize        notarise and staple; needs NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#   --out DIR         output folder (default: dist)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
RUNTIME="$HOME/Library/Caches/PAYELauncher/runtime-build/runtime"
WITH_RUNTIME=1
VERSION=""
IDENTITY="-"
NOTARIZE=0
OUT="$REPO/dist"

while [ $# -gt 0 ]; do
  case "$1" in
    --runtime) RUNTIME="$2"; shift 2 ;;
    --no-runtime) WITH_RUNTIME=0; shift ;;
    --version) VERSION="$2"; shift 2 ;;
    --sign) IDENTITY="$2"; shift 2 ;;
    --notarize) NOTARIZE=1; shift ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

VERSION="${VERSION:-$(scripts/version.sh)}"
# CFBundleVersion: YYYYMMDDNN (NN = release number on that day, from 01).
IFS=. read -r year month day number <<< "$VERSION"
BUILD="$(printf '%04d%02d%02d%02d' "$((10#$year))" "$((10#$month))" "$((10#$day))" "$((10#${number:-1}))")"
APP_NAME="PAYE Launcher"
APP="$OUT/$APP_NAME.app"
DMG="$OUT/PAYE-Launcher-$VERSION.dmg"
WORK="$OUT/work"
rm -rf "$APP" "$WORK" "$DMG"
mkdir -p "$WORK" "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Building $APP_NAME $VERSION ($BUILD)"
for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx13.0" > "$WORK/swift-$arch.log" 2>&1 \
    || { tail -40 "$WORK/swift-$arch.log"; exit 1; }
  cp "$(swift build -c release --triple "$arch-apple-macosx13.0" --show-bin-path)/PAYELauncher" "$WORK/PAYELauncher-$arch"
done
lipo -create "$WORK/PAYELauncher-arm64" "$WORK/PAYELauncher-x86_64" -output "$APP/Contents/MacOS/$APP_NAME"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" app/Info.plist > "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

swift scripts/make_icon.swift "$WORK/AppIcon.iconset" > /dev/null
iconutil -c icns "$WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp THIRD-PARTY-NOTICES.md "$APP/Contents/Resources/THIRD-PARTY-NOTICES.md"

if [ "$WITH_RUNTIME" = 1 ]; then
  [ -x "$RUNTIME/python/bin/python2.7" ] || { echo "No runtime at $RUNTIME (run runtime/build_runtime.sh or use --no-runtime)" >&2; exit 1; }
  echo "==> Adding the native runtime"
  ditto "$RUNTIME" "$APP/Contents/Resources/runtime"
fi

echo "==> Signing with ${IDENTITY/#-/ad-hoc signature}"
sign_flags=(--force --sign "$IDENTITY")
if [ "$IDENTITY" = "-" ]; then
  # Ad-hoc signatures have no Team ID. With the hardened runtime, library
  # validation then refuses the runtime's own modules, so ad-hoc builds (local
  # and pull-request builds) do not use the hardened runtime.
  sign_flags+=(--timestamp=none)
else
  sign_flags+=(--options runtime --timestamp)
fi
if [ -d "$APP/Contents/Resources/runtime" ]; then
  while IFS= read -r -d '' file; do
    if file -b "$file" | grep -q "Mach-O"; then codesign "${sign_flags[@]}" "$file"; fi
  done < <(find "$APP/Contents/Resources/runtime" -type f \( -name '*.so' -o -name '*.dylib' -o -perm -u+x \) -print0)
fi
codesign "${sign_flags[@]}" --entitlements app/entitlements.plist "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Making the DMG"
# The window shows the app, an arrow and the Applications folder. dmgbuild
# writes the layout without Finder, so this also works on CI.
PYTHON=""
for candidate in python3.13 python3.12 python3.11 python3.10 python3; do
  if command -v "$candidate" > /dev/null \
    && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2> /dev/null; then
    PYTHON="$candidate"; break
  fi
done
[ -n "$PYTHON" ] || { echo "Python 3.10 or later is needed to make the DMG (brew install python)" >&2; exit 1; }
"$PYTHON" -m venv "$WORK/dmg-venv"
"$WORK/dmg-venv/bin/pip" install --quiet --disable-pip-version-check \
  --require-hashes --only-binary :all: -r scripts/dmg-requirements.txt
swift scripts/make_dmg_background.swift "$WORK/dmg-background" > /dev/null
tiffutil -cathidpicheck "$WORK/dmg-background/background.png" "$WORK/dmg-background/background@2x.png" \
  -out "$WORK/dmg-background/background.tiff" 2> /dev/null
"$WORK/dmg-venv/bin/dmgbuild" -s scripts/dmg_settings.py \
  -D app="$APP" -D readme=app/dmg-readme.txt -D background="$WORK/dmg-background/background.tiff" \
  "$APP_NAME $VERSION" "$DMG" > "$WORK/dmgbuild.log" 2>&1 \
  || { tail -40 "$WORK/dmgbuild.log"; exit 1; }
if [ "$IDENTITY" != "-" ]; then codesign --force --timestamp --sign "$IDENTITY" "$DMG"; fi

if [ "$NOTARIZE" = 1 ]; then
  : "${NOTARY_KEY_PATH:?}" "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER_ID:?}"
  echo "==> Notarising (this can take a few minutes)"
  xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
rm -rf "$WORK"
echo "Built: $DMG"
