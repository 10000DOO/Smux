# Smux Release And Distribution

Last updated: 2026-04-26

## Scope

This document covers the repository-owned release path for local and CI use.
It intentionally does not store Apple credentials, certificates, provisioning
profiles, or notarization passwords.

## Current Project State

- Project: `Smux.xcodeproj`
- Scheme: `Smux`
- Release configuration exists.
- App bundle identifier: `com.10000DOO.Smux`
- Marketing version: `0.0.1`
- Current project version: `1`
- Hardened Runtime is enabled for the app target.
- App Sandbox is disabled for the app target.
- Code signing is currently automatic.

## Release Script

Use `scripts/release-smux.sh` from the repository root.

```bash
scripts/release-smux.sh archive
```

This creates:

- `build/release/Smux.xcarchive`
- `build/release/Smux.zip`

The script archives the Release build, verifies the app signature with
`codesign --verify --deep --strict`, and zips the archived app bundle with
`ditto --keepParent`.

## Notarization

Preferred setup is an Apple notarytool keychain profile:
The release script only supports this Keychain-backed path so notarization
secrets are not passed through repository files or command arguments.
Notarization also requires a Developer ID Application signature. The script
checks this before submitting to Apple.

```bash
xcrun notarytool store-credentials smux-notary
SMUX_NOTARY_KEYCHAIN_PROFILE=smux-notary \
SMUX_DEVELOPMENT_TEAM="TEAMID1234" \
SMUX_CODE_SIGN_STYLE="Manual" \
SMUX_CODE_SIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID1234)" \
scripts/release-smux.sh all
```

## Optional Signing Overrides

The script does not hardcode signing identities. CI or a local release machine
can override Xcode build settings with environment variables:

```bash
SMUX_DEVELOPMENT_TEAM="TEAMID1234" \
SMUX_CODE_SIGN_STYLE="Manual" \
SMUX_CODE_SIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID1234)" \
scripts/release-smux.sh archive
```

Use a Developer ID Application certificate for distribution outside the Mac App
Store. Automatic signing can still be used for local verification.

For local smoke tests on a machine without release signing credentials, use
ad-hoc signing and a single architecture:

```bash
SMUX_DESTINATION="platform=macOS,arch=arm64" \
SMUX_ARCHS="arm64" \
SMUX_ONLY_ACTIVE_ARCH="YES" \
SMUX_ENABLE_PREVIEWS="NO" \
SMUX_CODE_SIGN_STYLE="Manual" \
SMUX_CODE_SIGN_IDENTITY="-" \
scripts/release-smux.sh archive
```

This is only a build pipeline check. It is not suitable for notarized public
distribution.

## Verification Checklist

- [ ] `scripts/release-smux.sh archive` succeeds.
- [ ] Ad-hoc smoke archive succeeds on non-release machines when needed.
- [ ] `codesign --verify --deep --strict` passes for the archived app.
- [ ] `SMUX_NOTARY_KEYCHAIN_PROFILE=... scripts/release-smux.sh all` succeeds.
- [ ] `xcrun stapler validate build/release/Smux.xcarchive/Products/Applications/Smux.app` succeeds.
- [ ] The final `build/release/Smux.zip` launches on a clean macOS machine.

## User-Owned Decisions

- Confirm the production Apple Developer team ID.
- Confirm whether distribution is Developer ID only or later includes Mac App Store.
- Confirm the public open-source license before adding `LICENSE`.
- Confirm public README positioning, screenshots, and support policy before public launch.
