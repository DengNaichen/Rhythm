#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Rhythm.xcodeproj"
PROJECT_FILE="$PROJECT_PATH/project.pbxproj"
SCHEME="Rhythm"
APP_NAME="Rhythm"
DIST_ROOT="$ROOT_DIR/dist/github-release"
ENV_FILE="$ROOT_DIR/.env.release"
COMMAND="${1:-build}"

load_env_file() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "${line:0:1}" == "#" || "$line" != *"="* ]] && continue

    local key="${line%%=*}"
    local value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ ${+parameters[$key]} -eq 0 ]]; then
      export "$key=$value"
    fi
  done < "$env_file"
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

require_value() {
  local name="$1"
  [[ -n "${(P)name:-}" ]] || fail "$name is required."
}

validate_release_tag() {
  [[ "$GITHUB_TAG" =~ '^v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$' ]] ||
    fail "GITHUB_TAG must match vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-rcN."
}

release_version_from_tag() {
  local version="${GITHUB_TAG#v}"
  echo "${version%%-*}"
}

expected_build_number() {
  local version="$1"
  local major=""
  local minor=""
  local patch=""
  local extra=""
  IFS='.' read -r major minor patch extra <<< "$version"

  [[ -z "$extra" && "$major" =~ '^[0-9]+$' && "$minor" =~ '^[0-9]+$' && "$patch" =~ '^[0-9]+$' ]] ||
    fail "Unsupported semantic version: $version"
  (( 10#$minor <= 999 && 10#$patch <= 999 )) ||
    fail "Minor and patch versions must be between 0 and 999."

  printf '%d\n' $((10#$major * 1000000 + 10#$minor * 1000 + 10#$patch))
}

unique_project_setting() {
  local setting="$1"
  local values=""
  values="$(sed -n "s/.*${setting} = \([^;]*\);.*/\1/p" "$PROJECT_FILE" | sort -u)"
  [[ -n "$values" ]] || fail "Unable to read $setting from $PROJECT_FILE."
  [[ "$values" != *$'\n'* ]] || fail "$setting is inconsistent across project configurations: $values"
  echo "$values"
}

notary_credentials() {
  reply=(--keychain-profile "$NOTARY_PROFILE")
  if [[ -n "${NOTARY_KEYCHAIN_PATH:-}" ]]; then
    reply+=(--keychain "$NOTARY_KEYCHAIN_PATH")
  fi
}

print_usage() {
  cat <<'EOF'
Usage: Scripts/release.sh [preflight|build]

preflight  Validate tag, commit, MARKETING_VERSION, and CURRENT_PROJECT_VERSION.
build      Archive, sign, package, notarize, staple, and create release artifacts.

Required for both commands:
  GITHUB_REPOSITORY   owner/repository
  GITHUB_TAG          vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-rcN
  RELEASE_COMMIT_SHA  Full SHA checked out for the release

Additional build requirements:
  APPLE_TEAM_ID
  DEVELOPER_ID_APPLICATION
  NOTARY_PROFILE

Optional:
  ARCHIVE_PROVISIONING_PROFILE_SPECIFIER
  NOTARY_KEYCHAIN_PATH
  RELEASE_ARCHS       Single architecture; defaults to arm64
EOF
}

load_env_file "$ENV_FILE"

GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GITHUB_TAG="${GITHUB_TAG:-}"
RELEASE_COMMIT_SHA="${RELEASE_COMMIT_SHA:-$(git -C "$ROOT_DIR" rev-parse HEAD)}"
RELEASE_ARCHS="${RELEASE_ARCHS:-arm64}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-Developer ID Application}"
ARCHIVE_PROVISIONING_PROFILE_SPECIFIER="${ARCHIVE_PROVISIONING_PROFILE_SPECIFIER:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

validate_preflight() {
  require_value GITHUB_REPOSITORY
  require_value GITHUB_TAG
  require_value RELEASE_COMMIT_SHA
  [[ "$GITHUB_REPOSITORY" =~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ]] ||
    fail "GITHUB_REPOSITORY must be owner/repository."
  validate_release_tag
  [[ "$RELEASE_COMMIT_SHA" =~ '^[0-9a-f]{40}$' ]] || fail "RELEASE_COMMIT_SHA must be a full lowercase SHA."
  [[ "$(git -C "$ROOT_DIR" rev-parse HEAD)" == "$RELEASE_COMMIT_SHA" ]] ||
    fail "Checked out HEAD does not match RELEASE_COMMIT_SHA."
  [[ "$RELEASE_ARCHS" == "arm64" || "$RELEASE_ARCHS" == "x86_64" ]] ||
    fail "RELEASE_ARCHS must contain exactly one supported architecture."

  local release_version="$(release_version_from_tag)"
  local expected_build="$(expected_build_number "$release_version")"
  local project_version="$(unique_project_setting MARKETING_VERSION)"
  local project_build="$(unique_project_setting CURRENT_PROJECT_VERSION)"

  [[ "$project_version" == "$release_version" ]] ||
    fail "MARKETING_VERSION is $project_version, but $GITHUB_TAG requires $release_version."
  [[ "$project_build" == "$expected_build" ]] ||
    fail "CURRENT_PROJECT_VERSION is $project_build, but $release_version requires $expected_build."

  echo "Release metadata is valid: $GITHUB_TAG, build $project_build, commit $RELEASE_COMMIT_SHA."
}

build_release() {
  validate_preflight
  require_value APPLE_TEAM_ID
  require_value DEVELOPER_ID_APPLICATION
  require_value NOTARY_PROFILE

  if [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]]; then
    fail "Working tree is dirty. Release only from a committed checkout."
  fi

  security find-identity -v -p codesigning | grep -Fq "$DEVELOPER_ID_APPLICATION" ||
    fail "Missing signing identity: $DEVELOPER_ID_APPLICATION"

  local release_version="$(release_version_from_tag)"
  local expected_build="$(expected_build_number "$release_version")"
  local work_dir="$DIST_ROOT/$GITHUB_TAG"
  local archive_path="$work_dir/${APP_NAME}.xcarchive"
  local app_path="$work_dir/${APP_NAME}.app"
  local app_entitlements="$work_dir/${APP_NAME}.entitlements.plist"
  local dmg_staging_dir="$work_dir/dmg-staging"
  local dmg_dir="$work_dir/dmg"
  local payload_dir="$work_dir/artifacts"
  local dmg_name="${APP_NAME}-${GITHUB_TAG}-macos-${RELEASE_ARCHS}.dmg"
  local final_dmg="$dmg_dir/$dmg_name"
  local checksum_path="$dmg_dir/${dmg_name}.sha256"
  local manifest_path="$work_dir/release-manifest.json"
  local notary_submission="$work_dir/notary-submission.plist"
  local notary_log="$work_dir/notary-log.json"
  local notary_submit_error="$work_dir/notary-submit-error.log"

  rm -rf "$work_dir"
  mkdir -p "$work_dir" "$dmg_dir" "$payload_dir"

  copy_notary_diagnostics() {
    local diagnostic=""
    for diagnostic in "$notary_submission" "$notary_log" "$notary_submit_error"; do
      if [[ -s "$diagnostic" ]]; then
        cp "$diagnostic" "$payload_dir/"
      fi
    done
    return 0
  }

  echo "Archiving $APP_NAME for $RELEASE_ARCHS..."
  local archive_command=(
    xcodebuild
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration Release
    -onlyUsePackageVersionsFromResolvedFile
    -destination 'generic/platform=macOS'
    -archivePath "$archive_path"
    archive
    "ARCHS=$RELEASE_ARCHS"
    ONLY_ACTIVE_ARCH=NO
    CODE_SIGN_STYLE=Manual
    "DEVELOPMENT_TEAM=$APPLE_TEAM_ID"
    "CODE_SIGN_IDENTITY=$DEVELOPER_ID_APPLICATION"
    'OTHER_CODE_SIGN_FLAGS=--timestamp'
    SWIFT_VERSION=5
    'OTHER_SWIFT_FLAGS=$(inherited) -enable-bare-slash-regex'
  )
  if [[ -n "$ARCHIVE_PROVISIONING_PROFILE_SPECIFIER" ]]; then
    archive_command+=("PROVISIONING_PROFILE_SPECIFIER=$ARCHIVE_PROVISIONING_PROFILE_SPECIFIER")
  fi
  "${archive_command[@]}"

  local archived_app="$archive_path/Products/Applications/${APP_NAME}.app"
  [[ -d "$archived_app" ]] || fail "Archive did not contain $archived_app."
  ditto "$archived_app" "$app_path"

  codesign -d --entitlements - --xml "$app_path" > "$app_entitlements" 2>/dev/null
  plutil -lint "$app_entitlements" >/dev/null

  local helper_path="$app_path/Contents/MacOS/rhythm-server"
  [[ -f "$helper_path" ]] || fail "Missing embedded rhythm-server executable."
  chmod +x "$helper_path"
  codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp --options runtime "$helper_path"

  echo "Re-signing main application..."
  codesign \
    --force \
    --sign "$DEVELOPER_ID_APPLICATION" \
    --timestamp \
    --options runtime \
    --entitlements "$app_entitlements" \
    "$app_path"
  codesign --verify --deep --strict --verbose=2 "$app_path"

  local info_plist="$app_path/Contents/Info.plist"
  local app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
  local app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
  local bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
  local executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")"
  local minimum_system_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist" 2>/dev/null || true)"
  [[ -n "$minimum_system_version" ]] || minimum_system_version="unknown"
  [[ "$app_version" == "$release_version" ]] || fail "Archived app version is $app_version, expected $release_version."
  [[ "$app_build" == "$expected_build" ]] || fail "Archived app build is $app_build, expected $expected_build."

  local app_archs="$(lipo -archs "$app_path/Contents/MacOS/$executable_name")"
  local helper_archs="$(lipo -archs "$helper_path")"
  [[ "$app_archs" == "$RELEASE_ARCHS" ]] || fail "App architectures are '$app_archs', expected '$RELEASE_ARCHS'."
  [[ "$helper_archs" == "$RELEASE_ARCHS" ]] || fail "rhythm-server architectures are '$helper_archs', expected '$RELEASE_ARCHS'."

  echo "Creating signed DMG..."
  mkdir -p "$dmg_staging_dir"
  ditto "$app_path" "$dmg_staging_dir/${APP_NAME}.app"
  ln -s /Applications "$dmg_staging_dir/Applications"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$dmg_staging_dir" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$final_dmg"
  codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$final_dmg"
  codesign --verify --verbose=2 "$final_dmg"

  echo "Submitting DMG for notarization..."
  notary_credentials
  local notary_args=("${reply[@]}")
  if ! xcrun notarytool submit \
    "$final_dmg" \
    "${notary_args[@]}" \
    --wait \
    --output-format plist \
    > "$notary_submission" \
    2> "$notary_submit_error"; then
    [[ -s "$notary_submit_error" ]] && cat "$notary_submit_error" >&2
    copy_notary_diagnostics
    fail "Unable to submit DMG for notarization."
  fi

  local notary_id=""
  local notary_status=""
  if ! notary_id="$(/usr/libexec/PlistBuddy -c 'Print :id' "$notary_submission")"; then
    copy_notary_diagnostics
    fail "Notarization response did not contain a submission ID."
  fi
  if ! notary_status="$(/usr/libexec/PlistBuddy -c 'Print :status' "$notary_submission")"; then
    copy_notary_diagnostics
    fail "Notarization response did not contain a status."
  fi
  xcrun notarytool log "$notary_id" "$notary_log" "${notary_args[@]}" || true
  if [[ "$notary_status" != "Accepted" ]]; then
    copy_notary_diagnostics
    fail "Notarization failed with status: $notary_status"
  fi

  if ! xcrun stapler staple -v "$final_dmg"; then
    copy_notary_diagnostics
    fail "Unable to staple the notarization ticket to the DMG."
  fi
  if ! xcrun stapler validate -v "$final_dmg"; then
    copy_notary_diagnostics
    fail "Unable to validate the stapled DMG."
  fi
  codesign --verify --verbose=2 "$final_dmg"
  if ! spctl --assess --type open --context context:primary-signature -vv "$final_dmg"; then
    copy_notary_diagnostics
    fail "Gatekeeper rejected the notarized DMG."
  fi

  (
    cd "$dmg_dir"
    shasum -a 256 "$dmg_name" > "${dmg_name}.sha256"
  )
  local sha256="$(awk '{print $1}' "$checksum_path")"
  local xcode_version="$(xcodebuild -version | paste -sd ';' -)"
  local generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  cat > "$manifest_path" <<EOF
{
  "app": "$APP_NAME",
  "bundle_id": "$bundle_id",
  "tag": "$GITHUB_TAG",
  "version": "$app_version",
  "build": "$app_build",
  "commit": "$RELEASE_COMMIT_SHA",
  "architecture": "$RELEASE_ARCHS",
  "minimum_macos": "$minimum_system_version",
  "xcode": "$xcode_version",
  "dmg": "$dmg_name",
  "sha256": "$sha256",
  "notary_submission_id": "$notary_id",
  "generated_at": "$generated_at"
}
EOF
  plutil -convert xml1 -o /dev/null "$manifest_path"

  cp "$final_dmg" "$checksum_path" "$manifest_path" "$notary_submission" "$payload_dir/"
  [[ -f "$notary_log" ]] && cp "$notary_log" "$payload_dir/"

  echo "Release payload: $payload_dir"
}

case "$COMMAND" in
  preflight)
    validate_preflight
    ;;
  build)
    build_release
    ;;
  help|-h|--help)
    print_usage
    ;;
  *)
    print_usage >&2
    fail "Unknown command: $COMMAND"
    ;;
esac
