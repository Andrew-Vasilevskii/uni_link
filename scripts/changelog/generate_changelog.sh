#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: generate_changelog.sh --flavor <DEV|BETA|PROD> --version <x.y.z> --build <number> [--output <path>] [--jira-url <url>] [--jira-project <key>]

Generates a Markdown changelog for the pending release by diffing the last
successful flavor tag against the current HEAD.

Options:
  --jira-url       Base Jira URL (e.g., https://yourcompany.atlassian.net)
  --jira-project   Jira project key (e.g., PROJ)
EOF
}

FLAVOR=""
VERSION=""
BUILD_NUMBER=""
OUTPUT_FILE="changelog.md"
JIRA_URL=""
JIRA_PROJECT=""

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
    --jira-url)
      JIRA_URL="$2"
      shift 2
      ;;
    --jira-project)
      JIRA_PROJECT="$2"
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

# Add Jira links if configured
if [[ -n "$JIRA_URL" && -n "$JIRA_PROJECT" ]]; then
  # Replace PROJ-123 patterns with standard Markdown links
  # Supports both uppercase (PROJ-123) and lowercase (proj-123)
  # Standard Markdown format: [text](url)
  # Works on both BSD sed (macOS) and GNU sed (Linux)
  JIRA_PROJECT_UPPER="${JIRA_PROJECT^^}"
  JIRA_PROJECT_LOWER="${JIRA_PROJECT,,}"
  
  # Group 1: project key, Group 2: ticket number
  commit_log=$(echo "$commit_log" | sed -E "s#(${JIRA_PROJECT_UPPER}|${JIRA_PROJECT_LOWER})-([0-9]+)#[\1-\2](${JIRA_URL}/browse/${JIRA_PROJECT_UPPER}-\2)#g")
fi

cat <<EOF > "$OUTPUT_FILE"
## ${current_tag}
${summary_line}

${commit_log}
EOF

printf 'Changelog written to %s\n' "$OUTPUT_FILE"
