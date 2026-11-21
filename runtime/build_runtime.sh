#!/bin/bash
# Builds the universal (arm64 + x86_64) native runtime that PAYE Launcher bundles.
#
# The runtime is Python 2.7.16 with native builds of the open-source packages
# that Basic PAYE Tools uses. It contains NO HMRC code: at run time,
# bpt_native_boot.py loads the HMRC files from the Basic PAYE Tools app that
# the user installed from GOV.UK.
#
# It runs build_runtime_arch.sh twice (for arm64, then as a cross-build for
# x86_64), then joins every binary with lipo.
#
# Usage:  runtime/build_runtime.sh
# Output: $OUT (default: $WORK/runtime), ready to copy to Contents/Resources/runtime
#
# Needs: an Apple Silicon Mac with Rosetta 2, Xcode command line tools, cmake.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
WORK="${WORK:-$HOME/Library/Caches/PAYELauncher/runtime-build}"
OUT="${OUT:-$WORK/runtime}"
DL="$WORK/downloads"
case "$WORK$OUT" in *" "*) echo "WORK and OUT must not contain spaces (the Python 2.7 Makefiles do not allow it)" >&2; exit 1 ;; esac

[ "$(uname -m)" = arm64 ] || { echo "Build the universal runtime on an Apple Silicon Mac." >&2; exit 1; }
arch -x86_64 /usr/bin/true 2> /dev/null || { echo "Rosetta 2 is needed for the x86_64 half: softwareupdate --install-rosetta" >&2; exit 1; }

ARM_WORK="$WORK/arm64"
X86_WORK="$WORK/x86_64"
ARM="$ARM_WORK/runtime"
X86="$X86_WORK/runtime"
mkdir -p "$DL"
if [ "${1:-}" != "--join-only" ]; then
  echo "######## arm64 ########"
  env ARCH=arm64 WORK="$ARM_WORK" OUT="$ARM" DL="$DL" /bin/bash "$HERE/build_runtime_arch.sh"
  echo "######## x86_64 (cross-build; the new Python runs in Rosetta) ########"
  env ARCH=x86_64 WORK="$X86_WORK" OUT="$X86" DL="$DL" /bin/bash "$HERE/build_runtime_arch.sh"
fi

echo
echo "==> Joining arm64 and x86_64 into $OUT"
rm -rf "$OUT"
ditto "$ARM" "$OUT"

is_macho() { file -b "$1" | grep -q "Mach-O"; }
bad=0
while IFS= read -r -d '' file; do
  rel="${file#"$ARM"/}"
  is_macho "$file" || continue
  if [ ! -f "$X86/$rel" ] || ! is_macho "$X86/$rel"; then
    echo "No x86_64 file for $rel" >&2; bad=1; continue
  fi
  lipo -create "$file" "$X86/$rel" -output "$OUT/$rel"
done < <(find "$ARM" -type f -print0)
# Every x86_64 binary must have an arm64 partner.
while IFS= read -r -d '' file; do
  rel="${file#"$X86"/}"
  if is_macho "$file" && [ ! -f "$ARM/$rel" ]; then echo "No arm64 file for $rel" >&2; bad=1; fi
done < <(find "$X86" -type f -print0)
# Every binary in the result must be universal.
while IFS= read -r -d '' file; do
  if is_macho "$file" && [ "$(lipo -archs "$file")" != "x86_64 arm64" ]; then
    echo "Not universal: $file ($(lipo -archs "$file"))" >&2; bad=1
  fi
done < <(find "$OUT" -type f -print0)
[ "$bad" = 0 ] || exit 1

echo "==> Self-test of both halves"
LIB="$OUT/python/lib/python2.7"
for arch in arm64 x86_64; do
  (cd /tmp && arch "-$arch" "$OUT/python/bin/python2.7" -S -E -B -c "
import platform, sys, ssl, sqlite3
sys.frozen = 'macosx_app'
sys.path[:0] = ['$LIB/bpt-native', '$LIB/lib-dynload']
import PIL.Image, lxml.etree, Ft.Xml.cDomlette, _scandir
assert platform.machine() == '$arch', platform.machine()
print('$arch OK: %s, SQLite %s' % (ssl.OPENSSL_VERSION, sqlite3.sqlite_version))
")
done

{
  echo "PAYE Launcher native runtime"
  echo "Built: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "Architectures: arm64 x86_64"
  echo "Source commit: $(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "macOS SDK: $(xcrun --sdk macosx --show-sdk-version), deployment target 13.0"
  echo "Compiler: $(xcrun clang --version | head -1)"
  echo
  grep -E '^[A-Z_]+_(VERSION|URL|SHA256)=' "$HERE/sources.sh"
} > "$OUT/BUILD-INFO.txt"

du -sh "$OUT"
echo "Built universal native runtime: $OUT"
