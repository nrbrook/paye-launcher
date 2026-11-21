# Security

Please report security problems privately, through
[GitHub security advisories](https://github.com/nrbrook/paye-launcher/security/advisories/new).
Do not open a public issue for a security problem.

Problems in Basic PAYE Tools itself are HMRC's to fix. Report them to HMRC.

## Design notes

- The app connects only to the local Basic PAYE Tools server on 127.0.0.1.
  Other links open in the default browser.
- It removes `PYTHON*` and `DYLD_*` variables from the server environment.
- Release builds are signed with a Developer ID, use the hardened runtime, and
  are notarised by Apple. Each release has a GitHub build provenance attestation.
- The native runtime is built from pinned sources with SHA-256 checks
  (`runtime/sources.sh`). OpenSSL is a supported 3.6 release.
