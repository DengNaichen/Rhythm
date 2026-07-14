#!/bin/zsh
set -euo pipefail

VERSION="${1:-}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/Rhythm.xcodeproj/project.pbxproj"

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "Usage: $0 MAJOR.MINOR.PATCH" >&2
  exit 1
fi

major=""
minor=""
patch=""
IFS='.' read -r major minor patch <<< "$VERSION"
if (( 10#$minor > 999 || 10#$patch > 999 )); then
  echo "Minor and patch versions must be between 0 and 999." >&2
  exit 1
fi

BUILD_NUMBER=$((10#$major * 1000000 + 10#$minor * 1000 + 10#$patch))
[[ -f "$PROJECT_FILE" ]] || {
  echo "Project file not found: $PROJECT_FILE" >&2
  exit 1
}
grep -q 'MARKETING_VERSION =' "$PROJECT_FILE" || {
  echo "MARKETING_VERSION was not found in $PROJECT_FILE." >&2
  exit 1
}
grep -q 'CURRENT_PROJECT_VERSION =' "$PROJECT_FILE" || {
  echo "CURRENT_PROJECT_VERSION was not found in $PROJECT_FILE." >&2
  exit 1
}

TEMP_FILE="$(mktemp "${PROJECT_FILE}.tmp.XXXXXX")"
chmod "$(stat -f '%Lp' "$PROJECT_FILE")" "$TEMP_FILE"
trap 'rm -f "$TEMP_FILE"' EXIT

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == *"MARKETING_VERSION ="* ]]; then
    print -r -- "${line%%MARKETING_VERSION = *}MARKETING_VERSION = ${VERSION};" >> "$TEMP_FILE"
  elif [[ "$line" == *"CURRENT_PROJECT_VERSION ="* ]]; then
    print -r -- "${line%%CURRENT_PROJECT_VERSION = *}CURRENT_PROJECT_VERSION = ${BUILD_NUMBER};" >> "$TEMP_FILE"
  else
    print -r -- "$line" >> "$TEMP_FILE"
  fi
done < "$PROJECT_FILE"

mv "$TEMP_FILE" "$PROJECT_FILE"
trap - EXIT

echo "Updated MARKETING_VERSION to $VERSION."
echo "Updated CURRENT_PROJECT_VERSION to $BUILD_NUMBER."
echo "Review and commit the project change before creating v$VERSION."
