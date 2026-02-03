#!/usr/bin/env bash
# check_git_changes.sh
# Iterate through immediate subfolders of ~/dev (or a custom path)
# and list files with uncommitted changes for any Git repos found.

set -uo pipefail

DEV_ROOT="${1:-$HOME/dev}"

if [[ ! -d "$DEV_ROOT" ]]; then
  echo "Error: '$DEV_ROOT' is not a directory." >&2
  exit 1
fi


# Track if any repo had changes
had_changes=0

# Find immediate subdirectories, safe for spaces/newlines
while IFS= read -r -d '' dir; do
  # Is this directory a Git work tree?
  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Get porcelain status; empty means no changes (clean)
    changes="$(git -C "$dir" status --porcelain=v1 -unormal)"
    if [[ -n "$changes" ]]; then
      had_changes=1
      repo_name="$(basename "$dir")"
      echo "📁 $repo_name"
      # Indent each status line for readability
      echo "$changes" | sed 's/^/  /'
      echo
    fi
  fi
done < <(find "$DEV_ROOT" -mindepth 1 -maxdepth 1 -type d -print0)

# Echo status code legend if any repo had changes
if [[ $had_changes -eq 1 ]]; then
  echo "Status codes: M=modified, A=added, D=deleted, R=renamed, C=copied, ??=untracked, !!=ignored"
else
  echo "No uncommitted changes found in any Git repositories under '$DEV_ROOT'."
fi
