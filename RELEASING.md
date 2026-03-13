# Releasing Rhythm

Rhythm can publish a notarized macOS app through GitHub Actions once the signing
and notarization secrets are configured.

## Required GitHub Secrets

Set these repository secrets on `DengNaichen/Rhythm`:

- `DEVELOPER_ID_APPLICATION_P12_BASE64`
  - Base64-encoded `.p12` export of the `Developer ID Application` certificate.
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`
  - Password used when exporting the `.p12`.
- `APPLE_TEAM_ID`
  - Apple Developer Team ID used for the Developer ID certificate and notarization.
- `NOTARY_APPLE_ID`
  - Apple ID used for notarization.
- `NOTARY_APP_PASSWORD`
  - App-specific password for the Apple ID above.
- `KEYCHAIN_PASSWORD`
  - Random password used to create the temporary CI keychain.

## Publish a Binary Release

1. Make sure the tag exists locally and is pushed:

   ```bash
   git tag -a 1.0.1 -m "Release 1.0.1"
   git push origin main --follow-tags
   ```

2. The `Release Binary` workflow will:
   - import the Developer ID certificate
   - archive the app
   - export a signed `Developer ID` build
   - notarize it
   - staple the ticket
   - upload `Rhythm-<version>.zip` and its checksum to the GitHub release

## Local Release Prerequisites

For local binary releases, this machine needs:

- a valid `Developer ID Application` certificate in Keychain Access
- notarization credentials stored with `xcrun notarytool store-credentials`

Without those two pieces, local release can archive the app but cannot produce a
direct-installable notarized binary.
