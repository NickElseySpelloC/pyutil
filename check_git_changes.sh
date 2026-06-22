#!/usr/bin/env bash
# check_git_changes.sh
# Iterate through immediate subfolders of ~/dev (or a custom path)
# and, for any Git repos found, list:
#   1. local uncommitted changes (pending commits)
#   2. remote changes that are ahead of the local repo (a `git pull` is needed)
#
# Run with --help for options.

set -uo pipefail

PROG="$(basename "$0")"

usage() {
  cat <<EOF
Usage: $PROG [OPTIONS] [DEV_ROOT]

Scan the immediate subfolders of DEV_ROOT (default: \$HOME/dev) and, for any
Git repos found, list local uncommitted changes and remote changes that are
ahead of the local repo (i.e. a 'git pull' is needed).

Arguments:
  DEV_ROOT          Directory whose immediate subdirectories are scanned.
                    Defaults to \$HOME/dev.

Options:
  -n, --no-fetch    Don't run 'git fetch'. Compare against already-fetched
                    remote-tracking refs only (no network access). Faster, but
                    remote results may be stale.
  -h, --help        Show this help and exit.
EOF
}

DO_FETCH=1
DEV_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--no-fetch)
      DO_FETCH=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Error: unknown option '$1'" >&2
      echo "Try '$PROG --help' for more information." >&2
      exit 2
      ;;
    *)
      if [[ -n "$DEV_ROOT" ]]; then
        echo "Error: unexpected extra argument '$1'" >&2
        echo "Try '$PROG --help' for more information." >&2
        exit 2
      fi
      DEV_ROOT="$1"
      shift
      ;;
  esac
done

# Positional args after '--'
if [[ $# -gt 0 ]]; then
  if [[ -n "$DEV_ROOT" ]]; then
    echo "Error: unexpected extra argument '$1'" >&2
    exit 2
  fi
  DEV_ROOT="$1"
fi

DEV_ROOT="${DEV_ROOT:-$HOME/dev}"

if [[ ! -d "$DEV_ROOT" ]]; then
  echo "Error: '$DEV_ROOT' is not a directory." >&2
  exit 1
fi


# Normalize git change lines into an aligned "<CODE>  <path>" column,
# indented under a repo heading. Handles both:
#   - porcelain v1 (status):       "XY path"        (2-char code + space)
#   - name-status (diff):          "X<TAB>path"      (code + tab, +tab for renames)
format_changes() {
  awk -F'\t' '
    {
      if (NF >= 2) {
        # tab-separated name-status: code in $1, path(s) in $2..
        code = $1
        path = $2
        for (i = 3; i <= NF; i++) path = path " -> " $i
      } else {
        # porcelain v1: first 2 chars are the status code, path starts at col 4
        code = substr($0, 1, 2)
        path = substr($0, 4)
      }
      gsub(/^ +| +$/, "", code)   # trim padding so codes left-align
      printf "    %-2s  %s\n", code, path
    }'
}

# Track if any repo had changes
had_changes=0

# Starting message
echo "Scanning Git repositories under '$DEV_ROOT'..."

# Find immediate subdirectories, safe for spaces/newlines
while IFS= read -r -d '' dir; do
  # Is this directory a Git work tree?
  if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    continue
  fi

  # --- Local changes (pending commits) ---
  local_changes="$(git -C "$dir" status --porcelain=v1 -unormal)"

  # --- Remote changes (ahead of local) ---
  remote_changes=""
  remote_note=""
  # Does this repo track an upstream branch?
  upstream="$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"
  if [[ -n "$upstream" ]]; then
    remote_name="${upstream%%/*}"
    fetch_ok=1
    if [[ $DO_FETCH -eq 1 ]]; then
      # Refresh remote tracking refs so the comparison is current.
      # Only fetch the remote backing this branch.
      if ! git -C "$dir" fetch --quiet "$remote_name" 2>/dev/null; then
        fetch_ok=0
        remote_note="(could not reach remote '$remote_name')"
      fi
    fi
    if [[ $fetch_ok -eq 1 ]]; then
      # Files present on the upstream branch but not yet in local HEAD.
      # status letters: M=modified, A=added, D=deleted, etc.
      remote_changes="$(git -C "$dir" diff --name-status HEAD.."@{upstream}" 2>/dev/null)"
    fi
  fi

  # Skip repos with nothing to report
  if [[ -z "$local_changes" && -z "$remote_changes" && -z "$remote_note" ]]; then
    continue
  fi

  had_changes=1
  repo_name="$(basename "$dir")"
  echo "📁 $repo_name"

  echo "  Local changes (pending commits):"
  if [[ -n "$local_changes" ]]; then
    echo "$local_changes" | format_changes
  else
    echo "    (none)"
  fi

  echo "  Remote changes (need git pull):"
  if [[ -n "$remote_changes" ]]; then
    echo "$remote_changes" | format_changes
  elif [[ -n "$remote_note" ]]; then
    echo "    $remote_note"
  elif [[ -z "$upstream" ]]; then
    echo "    (no upstream tracking branch)"
  else
    echo "    (up to date)"
  fi

  echo
done < <(find "$DEV_ROOT" -mindepth 1 -maxdepth 1 -type d -print0)

# Echo status code legend if any repo had changes
if [[ $had_changes -eq 1 ]]; then
  echo "Status codes: M=modified, A=added, D=deleted, R=renamed, C=copied, ??=untracked, !!=ignored"
else
  echo "No local or remote changes found in any Git repositories under '$DEV_ROOT'."
fi
