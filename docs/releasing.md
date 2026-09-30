# Releasing BlackBar

BlackBar uses Sparkle for signed application updates. The wrappers in this repository delegate shared appcast, signing, and release logic to the `release-mac-app` skill in `agent-scripts`.

Keep `agent-scripts` next to this checkout or at `~/Projects/agent-scripts`, or set `MAC_RELEASE_TOOL=/path/to/mac-release`.

## Release inputs

| File | Owns |
| --- | --- |
| `version.env` | `MARKETING_VERSION` and `BUILD_NUMBER` |
| `CHANGELOG.md` | Release notes |
| `appcast.xml` | Signed Sparkle feed |
| `Resources/Info.plist` | Sparkle public EdDSA key (`SUPublicEDKey`) |

Pipeline scripts under `Scripts/`:

- `package_app.sh` builds the app, embeds Sparkle, and writes release metadata.
- `verify_app_bundle.sh APP_BUNDLE --universal` checks both CPU architectures for the bundle-relative Sparkle search path and the matching embedded framework. Packaging runs it before signing; CI also checks the extracted ZIP.
- `codesign_app.sh` signs the bundle, Sparkle framework, updater, and XPC services.
- `sign-and-notarize.sh` builds, signs, notarizes, staples, and archives the app.
- `release.sh` creates the tag and GitHub release, uploads app and dSYM archives, updates `appcast.xml`, and verifies the published artifacts.
- `verify_appcast.sh` validates a published appcast entry and downloaded app.
- `sparkle_key_status.sh` compares the embedded and active signing public keys without printing private key material.
- `test_live_update.sh` smoke-tests an update from the previous release.

## Credentials

The release needs these App Store Connect values:

```sh
export APP_STORE_CONNECT_API_KEY_P8='...'
export APP_STORE_CONNECT_KEY_ID='...'
export APP_STORE_CONNECT_ISSUER_ID='...'
```

Sparkle signing uses the macOS Keychain by default:

- Service: `https://sparkle-project.org`
- Account: `ed25519`
- Label: `Private key for signing Sparkle updates`

Apps that share the Sparkle private key must embed the same public key. Check the active key without exposing private key material:

```sh
Scripts/sparkle_key_status.sh
```

`SPARKLE_PRIVATE_KEY_FILE=/path/to/sparkle-ed25519.key` is an explicit file override. Release scripts reject either Keychain or file keys when the derived public key does not match `SUPublicEDKey` in `Resources/Info.plist`.

## Cut a release

`make ci` must pass before signing. It includes packaging regression tests and rejects missing frameworks or runtime search paths. The executable links Sparkle through `@executable_path/../Frameworks`; do not rely on Swift toolchain paths or build-directory symlinks to resolve it.

Replace the `Unreleased` date in `CHANGELOG.md` with the release date, then run:

```sh
make release
```

The release script performs the tag, GitHub Release, appcast update, signing checks, notarization checks, and published-artifact verification.
