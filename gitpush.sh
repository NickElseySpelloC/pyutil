#!/usr/bin/env bash
: '=======================================================
Push local config changes back to github

Commits and pushes locally modified files back to the remote repo. To only
be used in deployed environments, e.g. to push a modified config file back
to the repo it was deployed from. Only files that already exist in the
remote repo and have been modified locally are committed - new/untracked
files are never included.
=========================================================='

# set -euo pipefail

print_help() {
  cat <<'EOF'
Usage: gitpush.sh "<commit message>" [options]

Options (CLI overrides environment variables):
  --allow-dev-override          Allow push even if dev markers/patterns match (env: ALLOW_DEV_OVERRIDE=1)
  --block-markers <list>        Colon-separated list of marker files/dirs to block (env: BLOCK_MARKERS)
  --require-markers <list>      Colon-separated list; at least one must exist or abort (env: REQUIRE_MARKERS)
  --block-path-patterns <list>  Colon-separated substrings; if repo path contains any -> block (env: BLOCK_PATH_PATTERNS)
  --require-remote-host <host>  Require origin remote URL to contain this host (env: REQUIRE_REMOTE_HOST)
  --yes                         Non-interactive; skip confirmation prompt
  --help                        Show this help and exit

Example:
  ../pyutil/gitpush.sh "Update production config" --yes
EOF
}

# --- Safety & Portability Guards -------------------------------------------
# Environment overrides:
#   ALLOW_DEV_OVERRIDE=1
#   BLOCK_MARKERS=".dev_workspace:.development"
#   REQUIRE_MARKERS=".deployment:.prod"
#   BLOCK_PATH_PATTERNS="pattern1:pattern2"
#   REQUIRE_REMOTE_HOST=github.com
#
# General parameters (defaults, then env, then CLI)
BLOCK_PATH_PATTERNS="${BLOCK_PATH_PATTERNS:-Development}"
BLOCK_MARKERS_DEFAULT=".dev_workspace:.development:.local_dev:.devcontainer:.ruff_cache"
BLOCK_MARKERS="${BLOCK_MARKERS:-$BLOCK_MARKERS_DEFAULT}"
REQUIRE_MARKERS_DEFAULT=""
REQUIRE_MARKERS="${REQUIRE_MARKERS:-$REQUIRE_MARKERS_DEFAULT}"
ALLOW_DEV_OVERRIDE="${ALLOW_DEV_OVERRIDE:-}"
REQUIRE_REMOTE_HOST="${REQUIRE_REMOTE_HOST:-}"
DEV_CHECK_PREFIX="[Push]"

# shellcheck source=git_dev_env_check.sh
source "$(dirname "$0")/git_dev_env_check.sh"

# Parse CLI args (override env/defaults)
YES_MODE=0
COMMENT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      print_help
      exit 0
      ;;
    --yes)
      YES_MODE=1
      shift
      ;;
    --allow-dev-override)
      ALLOW_DEV_OVERRIDE="1"
      shift
      ;;
    --block-markers)
      BLOCK_MARKERS="$2"
      shift 2
      ;;
    --require-markers)
      REQUIRE_MARKERS="$2"
      shift 2
      ;;
    --block-path-patterns)
      BLOCK_PATH_PATTERNS="$2"
      shift 2
      ;;
    --require-remote-host)
      REQUIRE_REMOTE_HOST="$2"
      shift 2
      ;;
    -*)
      echo "[Push] Unknown argument: $1" >&2
      echo "Use --help to see supported options." >&2
      exit 2
      ;;
    *)
      if [[ -n "$COMMENT" ]]; then
        echo "[Push] Error: Unexpected extra argument: $1" >&2
        exit 2
      fi
      COMMENT="$1"
      shift
      ;;
  esac
done

# 1. A commit message is required
if [[ -z "$COMMENT" ]]; then
  echo "[Push] Error: A commit message is required." >&2
  print_help
  exit 1
fi

# 2. Ensure we are inside a git working tree
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[Push] Error: Not inside a git working tree." >&2
  exit 3
fi

# 3. Determine repo root
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [[ -z "$REPO_ROOT" ]]; then
  echo "[Push] Error: Unable to determine repo root." >&2
  exit 3
fi

# 4-7. Dev-environment guard checks (shared with gitrefresh.sh)
check_dev_environment

# 8. Determine current branch and its upstream
current_branch="$(git rev-parse --abbrev-ref HEAD)"
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
if [[ -z "$upstream" ]]; then
  echo "[Push] Error: Branch '$current_branch' has no upstream tracking branch configured." >&2
  exit 7
fi
remote_name="${upstream%%/*}"

# 9. Fetch the remote so the ahead/behind comparison is current
echo "[Push] Fetching '$remote_name'..."
if ! git fetch --quiet "$remote_name"; then
  echo "[Push] Error: Failed to fetch remote '$remote_name'." >&2
  exit 8
fi

# 10. Refuse to push if local is behind (or diverged from) the upstream branch
read -r ahead behind <<<"$(git rev-list --left-right --count "HEAD...$upstream")"
if [[ "$behind" -gt 0 ]]; then
  echo "[Push] Error: Local branch '$current_branch' is behind '$upstream' by $behind commit(s)." >&2
  echo "[Push] Run gitrefresh.sh first, then try gitpush.sh again." >&2
  exit 9
fi

# 11. Build the list of changed, already-tracked files (vs HEAD), split into
#     files eligible to commit and new files that must be excluded.
eligible=()
skipped_new=()
while IFS=$'\t' read -r status path; do
  [[ -z "$status" ]] && continue
  if [[ "$status" == A* ]]; then
    skipped_new+=("$path")
  else
    eligible+=("$path")
  fi
done < <(git diff --name-status HEAD)

if [[ ${#eligible[@]} -eq 0 ]]; then
  if [[ ${#skipped_new[@]} -gt 0 ]]; then
    echo "[Push] No changes to existing files to commit (only new, untracked files present)."
  else
    echo "[Push] No local changes to commit."
  fi
  exit 0
fi

echo "[Push] Files to be committed and pushed:"
for path in "${eligible[@]}"; do
  echo "    $path"
done

if [[ ${#skipped_new[@]} -gt 0 ]]; then
  echo "[Push] Warning: the following new files are not in the remote repo and will be excluded:"
  for path in "${skipped_new[@]}"; do
    echo "    $path"
  done
fi

if [[ "$YES_MODE" -ne 1 ]]; then
  read -r -p "Enter Y to continue, any other key to abort: " CONFIRM
  if [[ "$CONFIRM" != "Y" && "$CONFIRM" != "y" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# 12. Stage only the eligible files, never new/untracked ones
echo "[Push] Staging changes..."
if ! git add -- "${eligible[@]}"; then
  echo "[Push] Error: git add failed." >&2
  exit 10
fi

echo "[Push] Committing changes..."
if ! git commit -m "$COMMENT"; then
  echo "[Push] Error: git commit failed." >&2
  exit 11
fi

echo "[Push] Pushing to '$upstream'..."
if ! git push "$remote_name" "HEAD:$current_branch"; then
  echo "[Push] Error: git push failed." >&2
  exit 12
fi

echo "[Push] Done."
