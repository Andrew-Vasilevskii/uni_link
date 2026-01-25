#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: generate_changelog.sh --flavor <DEV|BETA|PROD> --version <x.y.z> --build <number> [--output <path>]

Generates a Markdown changelog for the pending release by diffing the last
successful flavor tag against the current HEAD.
EOF
}

FLAVOR=""
VERSION=""
BUILD_NUMBER=""
OUTPUT_FILE="changelog.md"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --flavor)
      FLAVOR="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$FLAVOR" || -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
  echo "Missing required arguments." >&2
  usage
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git command not found" >&2
  exit 1
fi

if [[ ! -d .git ]]; then
  echo "This script must be run from the repository root." >&2
  exit 1
fi

# Ensure we have complete history to locate previous tags.
git fetch --tags --force >/dev/null 2>&1

FLAVOR_NORMALIZED="${FLAVOR,,}"

current_tag="${FLAVOR_NORMALIZED}-${VERSION}(${BUILD_NUMBER})"
previous_tag=$(git tag --list "${FLAVOR_NORMALIZED}-*" --sort=-creatordate | grep -v "^${current_tag}$" | head -n 1 || true)

if [[ -z "$previous_tag" ]]; then
  baseline_commit=$(git rev-list --max-parents=0 HEAD | tail -n 1)
  range="$baseline_commit..HEAD"
  summary_line="Initial release for ${FLAVOR}."
else
  range="$previous_tag..HEAD"
  summary_line="Changes since ${previous_tag}:"
fi

commit_log=$(git log --no-merges --pretty=format:'- %h %s (%an)' $range || true)
if [[ -z "$commit_log" ]]; then
  commit_log="- No code changes since the previous release."
fi

cat <<EOF > "$OUTPUT_FILE"
## ${current_tag}
${summary_line}

${commit_log}
EOF

printf 'Changelog written to %s\n' "$OUTPUT_FILE"
