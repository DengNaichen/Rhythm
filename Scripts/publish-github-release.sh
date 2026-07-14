#!/bin/zsh
set -euo pipefail

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required.}"
: "${GITHUB_TAG:?GITHUB_TAG is required.}"
: "${GITHUB_RELEASE_TARGET:?GITHUB_RELEASE_TARGET is required.}"

[[ "$GITHUB_REPOSITORY" =~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ]] || {
  echo "Invalid GITHUB_REPOSITORY." >&2
  exit 1
}
[[ "$GITHUB_TAG" =~ '^v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$' ]] || {
  echo "Invalid GITHUB_TAG." >&2
  exit 1
}
[[ "$GITHUB_RELEASE_TARGET" =~ '^[0-9a-f]{40}$' ]] || {
  echo "GITHUB_RELEASE_TARGET must be a full lowercase SHA." >&2
  exit 1
}

RELEASE_DIR="${RELEASE_DIR:-}"
RELEASE_MODE="${GITHUB_RELEASE_MODE:-formal}"
VERIFY_TAG="${GITHUB_RELEASE_VERIFY_TAG:-true}"
[[ -d "$RELEASE_DIR" ]] || {
  echo "Release directory not found: $RELEASE_DIR" >&2
  exit 1
}
[[ "$RELEASE_MODE" == "formal" || "$RELEASE_MODE" == "draft" ]] || {
  echo "GITHUB_RELEASE_MODE must be formal or draft." >&2
  exit 1
}
[[ "$VERIFY_TAG" == "true" || "$VERIFY_TAG" == "false" ]] || {
  echo "GITHUB_RELEASE_VERIFY_TAG must be true or false." >&2
  exit 1
}

dmg_matches=("$RELEASE_DIR"/*.dmg(N))
manifest_matches=("$RELEASE_DIR"/release-manifest.json(N))
(( ${#dmg_matches[@]} == 1 )) || {
  echo "Expected exactly one DMG in $RELEASE_DIR." >&2
  exit 1
}
(( ${#manifest_matches[@]} == 1 )) || {
  echo "Expected release-manifest.json in $RELEASE_DIR." >&2
  exit 1
}

DMG_PATH="${dmg_matches[1]}"
CHECKSUM_PATH="${DMG_PATH}.sha256"
MANIFEST_PATH="${manifest_matches[1]}"
[[ -f "$CHECKSUM_PATH" ]] || {
  echo "Checksum not found: $CHECKSUM_PATH" >&2
  exit 1
}

checksum_entries="$(awk 'NF { count += 1 } END { print count + 0 }' "$CHECKSUM_PATH")"
checksum_dmg="$(awk 'NF { print $2; exit }' "$CHECKSUM_PATH")"
[[ "$checksum_entries" == "1" && "$checksum_dmg" == "$(basename "$DMG_PATH")" ]] || {
  echo "Checksum must contain exactly the downloaded DMG basename." >&2
  exit 1
}

(
  cd "$(dirname "$DMG_PATH")"
  shasum -a 256 -c "$(basename "$CHECKSUM_PATH")"
)

MANIFEST_TAG="$(plutil -extract tag raw -o - "$MANIFEST_PATH")"
MANIFEST_COMMIT="$(plutil -extract commit raw -o - "$MANIFEST_PATH")"
MANIFEST_DMG="$(plutil -extract dmg raw -o - "$MANIFEST_PATH")"
MANIFEST_SHA256="$(plutil -extract sha256 raw -o - "$MANIFEST_PATH")"
ACTUAL_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
[[ "$MANIFEST_TAG" == "$GITHUB_TAG" ]] || {
  echo "Manifest tag $MANIFEST_TAG does not match $GITHUB_TAG." >&2
  exit 1
}
[[ "$MANIFEST_COMMIT" == "$GITHUB_RELEASE_TARGET" ]] || {
  echo "Manifest commit $MANIFEST_COMMIT does not match $GITHUB_RELEASE_TARGET." >&2
  exit 1
}
[[ "$MANIFEST_DMG" == "$(basename "$DMG_PATH")" ]] || {
  echo "Manifest DMG $MANIFEST_DMG does not match the release asset." >&2
  exit 1
}
[[ "$MANIFEST_SHA256" == "$ACTUAL_SHA256" ]] || {
  echo "Manifest SHA-256 does not match the release asset." >&2
  exit 1
}

remote_tag_exists() {
  gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$GITHUB_TAG" --silent >/dev/null 2>&1
}

verify_remote_tag_target() {
  local remote_type="$(gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$GITHUB_TAG" --jq .object.type)"
  local remote_sha="$(gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$GITHUB_TAG" --jq .object.sha)"
  local dereference_count=0
  while [[ "$remote_type" == "tag" ]]; do
    (( dereference_count += 1 ))
    (( dereference_count <= 5 )) || {
      echo "Tag dereference depth exceeded for $GITHUB_TAG." >&2
      exit 1
    }
    remote_type="$(gh api "repos/$GITHUB_REPOSITORY/git/tags/$remote_sha" --jq .object.type)"
    remote_sha="$(gh api "repos/$GITHUB_REPOSITORY/git/tags/$remote_sha" --jq .object.sha)"
  done
  [[ "$remote_type" == "commit" && "$remote_sha" == "$GITHUB_RELEASE_TARGET" ]] || {
    echo "Remote tag target changed after the build; refusing to publish." >&2
    exit 1
  }
}

if remote_tag_exists; then
  verify_remote_tag_target
elif [[ "$VERIFY_TAG" == "true" ]]; then
  echo "Remote tag does not exist: $GITHUB_TAG" >&2
  exit 1
fi

assets=("$DMG_PATH" "$CHECKSUM_PATH" "$MANIFEST_PATH")
release_exists=false
release_is_draft=false
if gh release view "$GITHUB_TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  release_exists=true
  release_is_draft="$(gh release view "$GITHUB_TAG" --repo "$GITHUB_REPOSITORY" --json isDraft --jq .isDraft)"
  [[ "$release_is_draft" == "true" ]] || {
    echo "Release $GITHUB_TAG is already published; refusing to replace stable assets." >&2
    exit 1
  }
fi

is_prerelease=false
[[ "$GITHUB_TAG" == *-rc* || "$RELEASE_MODE" == "draft" ]] && is_prerelease=true

if [[ "$release_exists" == "false" ]]; then
  create_args=(
    "$GITHUB_TAG"
    --repo "$GITHUB_REPOSITORY"
    --title "$GITHUB_TAG"
    --draft
    --generate-notes
    --latest=false
  )
  if [[ "$VERIFY_TAG" == "true" ]]; then
    create_args+=(--verify-tag)
  else
    create_args+=(--target "$GITHUB_RELEASE_TARGET")
  fi
  [[ "$is_prerelease" == "true" ]] && create_args+=(--prerelease)
  gh release create "${create_args[@]}"
fi

gh release upload "$GITHUB_TAG" "${assets[@]}" --clobber --repo "$GITHUB_REPOSITORY"

remote_assets=("${(@f)$(gh release view "$GITHUB_TAG" --repo "$GITHUB_REPOSITORY" --json assets --jq '.assets[].name')}")
(( ${#remote_assets[@]} == ${#assets[@]} )) || {
  echo "Draft release contains unexpected or missing assets; refusing to publish." >&2
  exit 1
}
for asset in "${assets[@]}"; do
  asset_name="$(basename "$asset")"
  (( ${remote_assets[(Ie)$asset_name]} > 0 )) || {
    echo "Uploaded asset was not found on the draft release: $asset_name" >&2
    exit 1
  }
done

# Recheck after upload so a moved tag cannot publish assets built from another commit.
verify_remote_tag_target

if [[ "$RELEASE_MODE" == "formal" ]]; then
  if [[ "$is_prerelease" == "true" ]]; then
    gh release edit "$GITHUB_TAG" --repo "$GITHUB_REPOSITORY" --draft=false --prerelease --latest=false
  else
    gh release edit "$GITHUB_TAG" --repo "$GITHUB_REPOSITORY" --draft=false --prerelease=false --latest
  fi
  echo "Published https://github.com/$GITHUB_REPOSITORY/releases/tag/$GITHUB_TAG"
else
  echo "Draft release is ready for review: https://github.com/$GITHUB_REPOSITORY/releases/tag/$GITHUB_TAG"
fi
