#!/bin/bash
# Builds the native runtime that PAYE Launcher bundles, for ONE architecture.
# runtime/build_runtime.sh runs this for arm64 and x86_64 and joins the results.
#
# The runtime is Python 2.7.16 with native builds of the open-source packages
# that Basic PAYE Tools uses. It contains NO HMRC code: at run time,
# bpt_native_boot.py loads the HMRC files from the Basic PAYE Tools app that
# the user installed from GOV.UK.
#
# OpenSSL, SQLite and libjpeg-turbo are built from pinned sources and linked
# statically, so the runtime needs only macOS system libraries.
#
# Usage:  ARCH=arm64 runtime/build_runtime_arch.sh
#         ARCH=x86_64 runtime/build_runtime_arch.sh   (on Apple Silicon: needs Rosetta 2)
# Output: $OUT (default: $WORK/runtime)
#
# On Apple Silicon, the x86_64 build is a cross-build: the compilers run
# natively and make x86_64 code. Only the new x86_64 Python runs in Rosetta,
# because Python's build and the package builds run it. This is about four
# times faster than a build that runs completely in Rosetta.
#
# Needs: Xcode command line tools, cmake, curl, python3 (macOS has all but cmake).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
# shellcheck source=runtime/sources.sh
source "$HERE/sources.sh"

ARCH="${ARCH:-$(uname -m)}"
WORK="${WORK:-$HOME/Library/Caches/PAYELauncher/runtime-build/$ARCH}"
OUT="${OUT:-$WORK/runtime}"
case "$WORK$OUT" in *" "*) echo "WORK and OUT must not contain spaces (the Python 2.7 Makefiles do not allow it)" >&2; exit 1 ;; esac

DL="${DL:-$WORK/downloads}"
SRC="$WORK/src"
DEPS="$WORK/deps"
PREFIX="$WORK/python-prefix"
LOGS="$WORK/logs"
JOBS="$(sysctl -n hw.ncpu)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
export MACOSX_DEPLOYMENT_TARGET=13.0
ARCHFLAGS="-arch $ARCH -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
export ARCHFLAGS

case "$ARCH" in arm64|x86_64) ;; *) echo "ARCH must be arm64 or x86_64" >&2; exit 1 ;; esac

mkdir -p "$DL" "$SRC" "$LOGS"
rm -rf "$DEPS" "$PREFIX" "$OUT"

if [ "$(uname -m)" != "$ARCH" ]; then
  # Cross-build of x86_64 on Apple Silicon. Python's build and the package builds
  # run the new x86_64 interpreter (in Rosetta), and a process started by a
  # translated process is also translated. This wrapper keeps the compiler native.
  if [ "$ARCH" != x86_64 ] || ! arch -x86_64 /usr/bin/true 2> /dev/null; then
    echo "Build ARCH=$ARCH on a Mac of that architecture, or ARCH=x86_64 on Apple Silicon with Rosetta 2." >&2
    exit 1
  fi
  NATIVE_HOST="$(uname -m)"
  mkdir -p "$WORK/bin"
  printf '#!/bin/sh\nexec /usr/bin/arch -%s /usr/bin/xcrun clang "$@"\n' "$NATIVE_HOST" > "$WORK/bin/cc"
  printf '#!/bin/sh\nexec /usr/bin/arch -%s /usr/bin/xcrun clang++ "$@"\n' "$NATIVE_HOST" > "$WORK/bin/c++"
  chmod +x "$WORK/bin/cc" "$WORK/bin/c++"
  export CC="$WORK/bin/cc" CXX="$WORK/bin/c++"
fi

step() { printf '\n==> %s\n' "$*"; }
fail_with_log() { echo "Failed: $1 (log: $2)" >&2; tail -40 "$2" >&2; exit 1; }

fetch() {  # url sha256
  local url="$1" sha="$2" file
  file="$DL/$(basename "$url")"
  if [ ! -f "$file" ]; then curl -sSfL --retry 3 -o "$file.part" "$url" && mv "$file.part" "$file"; fi
  echo "$sha  $file" | shasum -a 256 -c --quiet || { rm -f "$file"; echo "Checksum mismatch: $url" >&2; exit 1; }
}

unpack() {  # archive -> prints the folder name
  local archive="$DL/$1" name
  case "$archive" in
    *.zip) name="$(unzip -Z1 "$archive" | head -1 | cut -d/ -f1)"; rm -rf "${SRC:?}/$name"; unzip -q "$archive" -d "$SRC" ;;
    *) name="$(tar -tf "$archive" | head -1 | cut -d/ -f1)"; rm -rf "${SRC:?}/$name"; tar -xf "$archive" -C "$SRC" ;;
  esac
  echo "$SRC/$name"
}

step "Downloading and checking sources"
fetch "$PYTHON_URL" "$PYTHON_SHA256"
fetch "$OPENSSL_URL" "$OPENSSL_SHA256"
fetch "$SQLITE_URL" "$SQLITE_SHA256"
fetch "$LIBJPEG_TURBO_URL" "$LIBJPEG_TURBO_SHA256"
fetch "$SETUPTOOLS_URL" "$SETUPTOOLS_SHA256"
fetch "$SCANDIR_URL" "$SCANDIR_SHA256"
fetch "$FOURSUITE_URL" "$FOURSUITE_SHA256"
fetch "$PILLOW_URL" "$PILLOW_SHA256"
fetch "$LXML_URL" "$LXML_SHA256"

# ---- Static C libraries ------------------------------------------------------

step "OpenSSL $OPENSSL_VERSION (static)"
dir="$(unpack "$(basename "$OPENSSL_URL")")"
(cd "$dir" && ./Configure "darwin64-$ARCH-cc" no-shared no-tests \
    --prefix="$DEPS" --libdir=lib --openssldir=/private/etc/ssl "-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
  && make -j"$JOBS" build_libs && make install_dev) > "$LOGS/openssl.log" 2>&1 || fail_with_log openssl "$LOGS/openssl.log"

step "SQLite $SQLITE_VERSION (static)"
dir="$(unpack "$(basename "$SQLITE_URL")")"
mkdir -p "$DEPS/include" "$DEPS/lib"
# shellcheck disable=SC2086 # ARCHFLAGS holds several flags
(cd "$dir" && xcrun clang -O2 $ARCHFLAGS -isysroot "$SDK" -DSQLITE_THREADSAFE=1 -DSQLITE_ENABLE_FTS3 \
    -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_RTREE -c sqlite3.c -o sqlite3.o \
  && ar rcs "$DEPS/lib/libsqlite3.a" sqlite3.o && cp sqlite3.h sqlite3ext.h "$DEPS/include/") \
  > "$LOGS/sqlite.log" 2>&1 || fail_with_log sqlite "$LOGS/sqlite.log"

step "libjpeg-turbo $LIBJPEG_TURBO_VERSION (static)"
dir="$(unpack "$(basename "$LIBJPEG_TURBO_URL")")"
(cmake -S "$dir" -B "$dir/build" -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$DEPS" -DCMAKE_INSTALL_LIBDIR=lib -DENABLE_SHARED=OFF -DWITH_TURBOJPEG=OFF \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" -DWITH_SIMD="$([ "$ARCH" = arm64 ] && echo 1 || echo 0)" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" -DCMAKE_OSX_SYSROOT="$SDK" \
  && cmake --build "$dir/build" -j "$JOBS" && cmake --install "$dir/build") \
  > "$LOGS/libjpeg-turbo.log" 2>&1 || fail_with_log libjpeg-turbo "$LOGS/libjpeg-turbo.log"

# ---- Python 2.7.16 -------------------------------------------------------------

step "Python $PYTHON_VERSION"
dir="$(unpack "$(basename "$PYTHON_URL")")"
(
  cd "$dir"
  for patch in "$HERE"/patches/*.patch; do patch -p1 -s < "$patch"; done
  python3 -I "$HERE/patches/patch_setup_openssl3.py" setup.py
  # Tk is not used by the server.
  /usr/bin/sed -i '' 's/^    def detect_tkinter(self, inc_dirs, lib_dirs):$/&\
        return/' setup.py
  # Find zlib.h in the SDK.
  /usr/bin/sed -i '' "s|find_file('zlib.h', \[\], inc_dirs)|find_file('zlib.h', [], inc_dirs + ['/usr/include'])|" setup.py
  WFLAGS="-Wno-error=implicit-function-declaration -Wno-error=incompatible-function-pointer-types -Wno-error=int-conversion -Wno-error=incompatible-pointer-types -Wno-deprecated-declarations"
  ./configure --prefix="$PREFIX" --enable-unicode=ucs2 --with-system-ffi \
    CFLAGS="-arch $ARCH -isysroot $SDK $WFLAGS" CPPFLAGS="-I$DEPS/include" LDFLAGS="-arch $ARCH -isysroot $SDK -L$DEPS/lib"
  make -j"$JOBS"
  make install
) > "$LOGS/python.log" 2>&1 || fail_with_log python "$LOGS/python.log"
PY="$PREFIX/bin/python2.7"
"$PY" -S -c "import ssl, sqlite3, zlib, hashlib, ctypes, pyexpat, _scproxy, bz2, datetime" \
  || fail_with_log "python modules" "$LOGS/python.log"

# ---- Open-source packages with C extensions ----------------------------------------

OVERLAY="$PREFIX/lib/python2.7/bpt-native"
mkdir -p "$OVERLAY"

step "setuptools $SETUPTOOLS_VERSION (build tool only)"
dir="$(unpack "$(basename "$SETUPTOOLS_URL")")"
(cd "$dir" && "$PY" setup.py -q install) > "$LOGS/setuptools.log" 2>&1 || fail_with_log setuptools "$LOGS/setuptools.log"

step "scandir $SCANDIR_VERSION"
dir="$(unpack "$(basename "$SCANDIR_URL")")"
(cd "$dir" && "$PY" setup.py build_ext) > "$LOGS/scandir.log" 2>&1 || fail_with_log scandir "$LOGS/scandir.log"
cp "$dir/scandir.py" "$dir"/build/lib.*/_scandir.so "$OVERLAY/"

step "4Suite-XML $FOURSUITE_VERSION"
dir="$(unpack "$(basename "$FOURSUITE_URL")")"
# 4Suite's own installer fails on the setuptools metadata, so build without site and copy.
# The build of one installer helper program fails; it is not needed, so check the modules instead.
(cd "$dir" && "$PY" -S setup.py build) > "$LOGS/4suite.log" 2>&1 || true
cp -R "$dir"/build/lib.*/Ft "$OVERLAY/"
[ "$(find "$OVERLAY/Ft" -name '*.so' | wc -l | tr -d ' ')" = 15 ] || fail_with_log "4Suite C modules" "$LOGS/4suite.log"
cp "$HERE/ft__config__.py" "$OVERLAY/Ft/__config__.py"

step "Pillow $PILLOW_VERSION"
dir="$(unpack "$(basename "$PILLOW_URL")")"
(cd "$dir" && CFLAGS="-I$DEPS/include -I$SDK/usr/include" LDFLAGS="-L$DEPS/lib -L$SDK/usr/lib" \
  "$PY" setup.py build_ext --disable-tiff --disable-freetype --disable-lcms --disable-webp --disable-webpmux \
    --disable-jpeg2000 --disable-imagequant build_py) > "$LOGS/pillow.log" 2>&1 || fail_with_log pillow "$LOGS/pillow.log"
grep -q -- "--- JPEG support available" "$LOGS/pillow.log" || fail_with_log "Pillow JPEG support" "$LOGS/pillow.log"
cp -R "$dir"/build/lib.*/PIL "$OVERLAY/"

step "lxml $LXML_VERSION (macOS libxml2 and libxslt, as HMRC's build)"
dir="$(unpack "$(basename "$LXML_URL")")"
(cd "$dir" && "$PY" setup.py build) > "$LOGS/lxml.log" 2>&1 || fail_with_log lxml "$LOGS/lxml.log"
cp -R "$dir"/build/lib.*/lxml "$OVERLAY/"

# ---- Assemble the runtime ---------------------------------------------------------------

step "Assembling $OUT"
mkdir -p "$OUT/python/bin" "$OUT/python/lib" "$OUT/licenses"
cp "$PY" "$OUT/python/bin/python2.7"
cp -R "$PREFIX/lib/python2.7" "$OUT/python/lib/python2.7"
LIB="$OUT/python/lib/python2.7"
# Remove what the server does not need: tests, IDE, Tk, build files, setuptools.
rm -rf "$LIB"/{test,idlelib,lib-tk,lib2to3,ensurepip,site-packages} \
  "$LIB"/{bsddb/test,ctypes/test,distutils/tests,email/test,json/tests,sqlite3/test,unittest/test} \
  "$LIB"/config/libpython2.7.a "$LIB"/lib-dynload/{_tkinter.so,_testcapi.so,_ctypes_test.so}
# Object files (config/python.o) cannot be code signed, and notarisation refuses them.
find "$LIB" \( -name '*.pyc' -o -name '*.pyo' -o -name '*.exe' -o -name '*.a' -o -name '*.o' \) -delete
find "$LIB/bpt-native" \( -name '*.c' -o -name '*.h' -o -name '*.pyx' -o -name '*.pxd' \) -delete
cp "$HERE/bpt_native_boot.py" "$OUT/bpt_native_boot.py"
# Precompile, so that the signed (read-only) runtime starts fast.
"$OUT/python/bin/python2.7" -S -E -m compileall -q -f -d "/runtime/python/lib/python2.7" "$LIB" > /dev/null || true

step "Collecting licenses"
mkdir -p "$OUT/licenses"/{python,openssl,sqlite,libjpeg-turbo,4suite-xml,pillow,lxml,scandir,pyenv-patches}
cp "$SRC/Python-$PYTHON_VERSION/LICENSE" "$OUT/licenses/python/LICENSE"
cp "$SRC/openssl-$OPENSSL_VERSION/LICENSE.txt" "$OUT/licenses/openssl/LICENSE.txt"
printf 'SQLite is in the public domain. See https://www.sqlite.org/copyright.html\n' > "$OUT/licenses/sqlite/NOTICE.txt"
cp "$SRC/libjpeg-turbo-$LIBJPEG_TURBO_VERSION/LICENSE.md" "$SRC/libjpeg-turbo-$LIBJPEG_TURBO_VERSION/README.ijg" "$OUT/licenses/libjpeg-turbo/"
cp "$SRC/4Suite-XML-$FOURSUITE_VERSION/COPYRIGHT" "$OUT/licenses/4suite-xml/COPYRIGHT"
cp "$SRC/Pillow-$PILLOW_VERSION/LICENSE" "$OUT/licenses/pillow/LICENSE"
cp "$SRC/lxml-$LXML_VERSION/LICENSES.txt" "$OUT/licenses/lxml/LICENSES.txt"
cp "$SRC/lxml-$LXML_VERSION"/doc/licenses/*.txt "$OUT/licenses/lxml/"
cp "$SRC/scandir-$SCANDIR_VERSION/LICENSE.txt" "$OUT/licenses/scandir/LICENSE.txt"
cp "$HERE/patches/LICENSE.pyenv" "$OUT/licenses/pyenv-patches/LICENSE"

step "Self-test"
cd /tmp
"$OUT/python/bin/python2.7" -S -E -B - <<PYEOF
import sys
sys.frozen = "macosx_app"
lib = "$LIB"
sys.path[:0] = [lib + "/bpt-native", lib + "/lib-dynload"]
import ssl, sqlite3, scandir, PIL.Image, lxml.etree, Ft.Xml.cDomlette, _scandir
from Ft.Xml.Domlette import NonvalidatingReader
assert ssl.OPENSSL_VERSION.startswith("OpenSSL $OPENSSL_VERSION "), ssl.OPENSSL_VERSION
assert sqlite3.sqlite_version == "$SQLITE_VERSION", sqlite3.sqlite_version
assert sys.maxunicode == 0xFFFF, "UCS-2 build expected"
for mod in (_scandir, PIL.Image.core, lxml.etree):
    assert mod.__file__.startswith(lib + "/bpt-native"), mod.__file__
NonvalidatingReader.parseString("<a><b/></a>", "urn:test")
print("Self-test OK: %s, SQLite %s, lxml %s" % (ssl.OPENSSL_VERSION, sqlite3.sqlite_version, lxml.etree.__version__))
PYEOF

# Every Mach-O file must be $ARCH only and link only to macOS system libraries.
bad=0
while IFS= read -r -d '' f; do
  if file "$f" | grep -q "Mach-O"; then
    lipo -archs "$f" | grep -qx "$ARCH" || { echo "Not $ARCH-only: $f" >&2; bad=1; }
    if otool -L "$f" | tail -n +2 | awk '{print $1}' | grep -v -E '^(/usr/lib/|/System/)'; then
      echo "Non-system library in $f" >&2; bad=1
    fi
  fi
done < <(find "$OUT" -type f \( -name '*.so' -o -name '*.dylib' -o -perm -u+x \) -print0)
[ "$bad" = 0 ] || exit 1

{
  echo "PAYE Launcher native runtime"
  echo "Built: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "Source commit: $(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "macOS SDK: $(xcrun --sdk macosx --show-sdk-version), deployment target $MACOSX_DEPLOYMENT_TARGET"
  echo "Compiler: $(xcrun clang --version | head -1)"
  echo
  grep -E '^[A-Z_]+_(VERSION|URL|SHA256)=' "$HERE/sources.sh"
} > "$OUT/BUILD-INFO.txt"

du -sh "$OUT"
echo "Built native runtime ($ARCH): $OUT"
