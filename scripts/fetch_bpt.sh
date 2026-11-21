#!/bin/bash
# Downloads the current Basic PAYE Tools for macOS from GOV.UK and installs it.
# For CI and for test machines. It installs HMRC's own package into /Applications.
#
# Usage: scripts/fetch_bpt.sh [--download-only] [DIR]
set -euo pipefail

INSTALL=1
if [ "${1:-}" = "--download-only" ]; then INSTALL=0; shift; fi
DIR="${1:-${RUNNER_TEMP:-/tmp}/bpt-download}"
PAGE=https://www.gov.uk/basic-paye-tools
mkdir -p "$DIR"

path="$(curl -sSfL "$PAGE" | grep -o -E '/government/uploads/uploaded/hmrc/payetools-rti-[0-9.]+-osx\.zip' | head -1)"
[ -n "$path" ] || { echo "No macOS download link found on $PAGE" >&2; exit 1; }
zip="$DIR/$(basename "$path")"
echo "Downloading https://www.gov.uk$path"
curl -sSfL --retry 3 -o "$zip" "https://www.gov.uk$path"
shasum -a 256 "$zip"

rm -rf "$DIR/unpacked"
mkdir -p "$DIR/unpacked"
unzip -q "$zip" -d "$DIR/unpacked"
pkg="$(find "$DIR/unpacked" -name '*.pkg' | head -1)"
[ -n "$pkg" ] || { echo "No installer package in $zip" >&2; exit 1; }
pkgutil --check-signature "$pkg" || true

if [ "$INSTALL" = 1 ]; then
  sudo installer -pkg "$pkg" -target /
  /usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "/Applications/Basic PAYE Tools.app/Contents/Info.plist"
fi
