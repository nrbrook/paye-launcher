# Built-in runtime

`build_runtime.sh` builds the universal (arm64 and x86_64) built-in runtime from the pinned
sources in `sources.sh`. See [../docs/how-it-works.md](../docs/how-it-works.md).

| File | Purpose |
|---|---|
| `build_runtime.sh` | The universal build: runs `build_runtime_arch.sh` for arm64 and then x86_64 (a cross-build: the compilers run natively, and only the new x86_64 Python runs in Rosetta), then joins the binaries with `lipo`. Output: `~/Library/Caches/PAYELauncher/runtime-build/runtime`. `--join-only` repeats only the join |
| `build_runtime_arch.sh` | The build of one architecture |
| `sources.sh` | Versions, URLs and SHA-256 of all sources |
| `bpt_native_boot.py` | Starts HMRC's installed server code on the native Python (Python 2.7) |
| `ft__config__.py` | The configuration file that the 4Suite installer normally makes |
| `patches/0001…0007-*.patch` | Apple Silicon patches for Python 2.7, from [pyenv](https://github.com/pyenv/pyenv) (MIT, see `patches/LICENSE.pyenv`); 0002 (Tk) is left out |
| `patches/patch_setup_openssl3.py` | Lets Python 2.7's `setup.py` read the OpenSSL 3 version |
| `tests/` | The comparison with HMRC's own server |

The build also changes two lines of Python's `setup.py`: it skips Tk, and it
finds `zlib.h` in the macOS SDK.

The runtime folder has:

```
runtime/
  bpt_native_boot.py
  python/bin/python2.7
  python/lib/python2.7/...            standard library
  python/lib/python2.7/bpt-native/    4Suite-XML, Pillow, lxml, scandir
  licenses/                           license texts of all components
  BUILD-INFO.txt                      versions, hashes, SDK, compiler
```

Run a server command by hand (for example for tests):

```bash
BPT_RTI_APP="/Applications/Basic PAYE Tools.app/Contents/Helpers/rti.app" \
  runtime/python/bin/python2.7 -S -E -B -u runtime/bpt_native_boot.py runserver 46729
```
