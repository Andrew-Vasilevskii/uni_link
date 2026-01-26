#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: generate_changelog.sh --flavor <FLAVOR> --version <VERSION> --build <NUMBER> [OPTIONS]

Generates a Markdown changelog by comparing the two most recent flavor tags.

Required Arguments:
  --flavor <FLAVOR>         Build flavor (e.g., dev, beta, prod)
  --version <VERSION>       Version number (e.g., 1.0.0)
  --build <NUMBER>          Build number (e.g., 123)

Optional Arguments:
  --output <PATH>           Output file path (default: changelog.md)
  --jira-url <URL>          Base Jira URL (e.g., https://company.atlassian.net)
  --jira-project <KEY>      Jira project key (e.g., PROJ)
                          When both --jira-url and --jira-project are provided,
                          ticket references (PROJ-123) will be converted to
                          standard Markdown links.

  -h, --help               Show this help message

Examples:
  # Basic usage
  generate_changelog.sh --flavor beta --version 1.0.0 --build 42

  # With Jira integration
  generate_changelog.sh --flavor prod --version 2.1.0 --build 100 \
    --jira-url "https://company.atlassian.net" \
    --jira-project "MAPP"

  # Custom output file
  generate_changelog.sh --flavor dev --version 1.0.0 --build 1 \
    --output CHANGELOG.md
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

# Fetch all tags
git fetch --tags --force --quiet

FLAVOR_NORMALIZED="${FLAVOR,,}"

current_tag="${FLAVOR_NORMALIZED}-${VERSION}(${BUILD_NUMBER})"

latest_tag=$(git tag -l "${FLAVOR_NORMALIZED}-*" --sort=-v:refname | head -n 1 || true)
previous_tag=$(git tag -l "${FLAVOR_NORMALIZED}-*" --sort=-v:refname | head -n 2 | tail -n 1 || true)

if [[ -z "$previous_tag" || "$previous_tag" == "$latest_tag" ]]; then
  baseline_commit=$(git rev-list --max-parents=0 HEAD | tail -n 1)
  range="$baseline_commit..HEAD"
  summary_line="Initial release for ${FLAVOR}."
else
  range="$previous_tag..HEAD"
  summary_line="Changes since ${previous_tag}:"
fi

# %h could be used for abbreviated commit hash if needed
commit_log=$(git log --no-merges --pretty=format:'- %s (%an)' $range || true)
if [[ -z "$commit_log" ]]; then
  commit_log="- No code changes since the previous release."
fi

# Add Jira links if configured
if [[ -n "$JIRA_URL" && -n "$JIRA_PROJECT" ]]; then

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
