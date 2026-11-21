# Releasing

## Make a release

1. Open **Actions > Release > Run workflow** on GitHub.
2. The workflow:
   - takes today's date (UTC) as the version (`2026.11.21`, then `2026.11.21.2`),
   - runs the unit tests,
   - builds the native runtime from the pinned sources,
   - builds, signs and notarises the app and the DMG,
   - compares the signed runtime with HMRC's own server,
   - makes a build provenance attestation,
   - creates the tag `v<version>` and the GitHub release with the DMG and its SHA-256.

If the signing secrets are missing, the workflow makes an ad-hoc signed build
and creates the release as a **draft**.

## Signing secrets

Create a GitHub environment called `release` (Settings > Environments). You
can require approval for it. Add these secrets to it:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Your "Developer ID Application" certificate and private key, exported from Keychain Access as a `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | The password of the `.p12` |
| `NOTARY_KEY_P8_BASE64` | An App Store Connect API key (Users and Access > Integrations > Team Keys, role "Developer"), as `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `NOTARY_KEY_ID` | The key ID |
| `NOTARY_ISSUER_ID` | The issuer ID |

## Signing details

- Release builds use the hardened runtime and a secure timestamp. The app has
  no extra entitlements and is not sandboxed (it must start the installed HMRC
  server).
- Every Mach-O file in the runtime is signed one by one, then the app.
- Ad-hoc builds (local and pull requests) do not use the hardened runtime:
  without a Team ID, library validation refuses the runtime's own modules.
- The DMG is notarised and stapled.

## Update a runtime component

1. Change the version, URL and SHA-256 in `runtime/sources.sh`.
2. Run `make runtime compare`.
3. Open a pull request. CI builds and compares again.
