# Testing

## Automatic checks on every pull request

The [CI workflow](../.github/workflows/ci.yml) runs on GitHub's Apple Silicon
Macs:

| Job | What it checks |
|---|---|
| Lint | SwiftLint (strict), Ruff, ShellCheck, actionlint |
| Unit tests | `swift test`: finding the HMRC app, the port setting, runtime choice and commands, Mach-O architectures, link rules, the GOV.UK download link, installer signature checks, file names, preferences, process control, the PID file, and a full start, wait, stop and backup cycle with a fake server |
| Install from GOV.UK | Downloads the real installer from GOV.UK, checks its signature, and installs Basic PAYE Tools into a temporary folder (`PAYE_LAUNCHER_NETWORK_TESTS=1`) |
| Build universal runtime | Builds both halves from pinned sources, checks that every binary is universal and links only to macOS libraries, and runs a self-test of each half |
| Compare with HMRC's server | Downloads the current Basic PAYE Tools from GOV.UK, then compares each half of the runtime (arm64, and x86_64 in Rosetta) with HMRC's own server (see below) |
| Package | Builds the universal app and the DMG (ad-hoc signed) |

The [release workflow](../.github/workflows/release.yml) runs the comparison
again on the signed runtime inside the app, before it publishes a release.

## The comparison

`runtime/tests/run_comparison.sh` starts the native runtime and HMRC's own
server side by side, each with its own temporary home folder. Real data is
never used. It fails if any result is different:

| Check | How |
|---|---|
| `startdb` | Both exit with 0, and the new databases have the same SQL content |
| Pages | Crawls every page that it can reach by local links (it never follows links that send, delete, restore or back up), and compares the HTML. Only the CSRF token, the page time and the data-folder path are ignored |
| Static files | Compares the bytes of all CSS, JavaScript and images |
| PAYE, NI and student loan | Posts 810 sets of inputs to HMRC's net pay estimator for each of two tax years (2025-26 and 2026-27): 16 tax codes, 17 NI category letters, 14 pay amounts, 7 pay periods, and 250 random combinations. Every result must be an amount and must be the same |
| IRmark | Makes the IRmark (C14N canonical XML and SHA-1) for 48 synthetic FPS, EPS, EYU and NVR documents with special characters, and compares the output. 36 must give an IRmark. EYU gives an error on both, because HMRC does not accept EYU any more |
| `autobackup` | Both exit with 0 and the backup file exists |

### Results

| Date | Basic PAYE Tools | macOS | Result |
|---|---|---|---|
| 2026-11-21 | 26.1.26134.173934 | 27.2.1 (Apple Silicon), arm64 half | All checks passed: 28 pages, 40 static files, 1,620 net pay results, 36 IRmarks |
| 2026-11-21 | 26.1.26134.173934 | 27.2.1 (Apple Silicon), x86_64 half in Rosetta | All checks passed (the same checks) |

## Not tested automatically

- A full employer flow: employees, a pay run, FPS and EPS made from real
  records, and a submission. A submission test would use HMRC's test service,
  never the live service.
- Printable PDF forms, restore from a backup, and Welsh.
- The user interface of PAYE Launcher (menus, downloads, printing, the install
  dialogs and Apple's Installer): test by hand.
- The x86_64 half is tested in Rosetta on Apple Silicon, not on an Intel Mac.

Some library versions are not exactly HMRC's: OpenSSL 3.6.5 (HMRC: 3.6.1),
zlib from macOS (HMRC: 1.3.2), and Python hashes with OpenSSL instead of its
built-in hash modules. The comparison shows no difference.

## Run the tests yourself

```bash
make test                # unit tests
make runtime compare     # needs Basic PAYE Tools in /Applications
RUNTIME_ARCH=x86_64 make compare
PAYE_LAUNCHER_NETWORK_TESTS=1 swift test --filter downloadsChecksAndInstallsFromGovUK
```
