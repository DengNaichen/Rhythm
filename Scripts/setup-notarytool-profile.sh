#!/bin/zsh
set -euo pipefail

: "${APPLE_ID:?APPLE_ID is required.}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required.}"
: "${APP_SPECIFIC_PASSWORD:?APP_SPECIFIC_PASSWORD is required.}"
: "${NOTARY_PROFILE:?NOTARY_PROFILE is required.}"

command=(
  xcrun notarytool store-credentials
  "$NOTARY_PROFILE"
  --apple-id "$APPLE_ID"
  --team-id "$APPLE_TEAM_ID"
  --password "$APP_SPECIFIC_PASSWORD"
  --validate
)

if [[ -n "${NOTARY_KEYCHAIN_PATH:-}" ]]; then
  command+=(--keychain "$NOTARY_KEYCHAIN_PATH")
fi

"${command[@]}"
echo "Stored notarytool profile: $NOTARY_PROFILE"
