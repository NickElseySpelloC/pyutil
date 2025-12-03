#!/usr/bin/env bash
: '=======================================================
Refresh from github

Gets the latest version of this app from github. To only be used in deployed environments.
=========================================================='

set -euo pipefail

# --- Safety & Portability Guards -------------------------------------------
# This script aims to be reusable across projects.
# Customize behaviour via environment variables (export before running) or by
# creating marker files in a development workspace to prevent accidental runs.
#
# Environment overrides:
#   ALLOW_DEV_REFRESH=1          Force execution even if a dev marker or block rule triggers.
#   BLOCK_MARKERS=".dev_workspace:.development"  Colon list of files/dirs at repo root that block execution.
#   REQUIRE_MARKERS=".deployment:.prod"  Colon list of files; at least one must exist (if list non-empty) or script aborts.
#   BLOCK_PATH_PATTERNS="pattern1:pattern2"  Colon list of substrings; if REPO_ROOT matches any -> block.
#   REQUIRE_REMOTE_HOST=github.com   If set, require 'origin' remote URL to contain this string.
#   STASH_BEFORE_REFRESH=1       (default 1) If 1, stash uncommitted changes automatically.
#   BRANCH=main                  Branch to reset to (default: main)
#
# To block refresh in a development clone, create an empty file named
# (by default) .dev_workspace in the repository root.

# General parameters
REPO_ROOT="$(pwd)"
BRANCH="${BRANCH:-main}"
PYPROJECT="pyproject.toml"

# if BLOCK_PATH_PATTERNS is not set, default to Development
BLOCK_PATH_PATTERNS="${BLOCK_PATH_PATTERNS:-Development}"

# 1. Inspect the pyproject.toml file and extract the project name and current version
if [ -f "$PYPROJECT" ]; then
    CURRENT_VERSION=$(grep -E '^version *= *"' "$PYPROJECT" | head -1 | sed -E 's/^version *= *"([^"]+)".*$/\1/')
    PROJECT_NAME=$(grep -E '^name *= *"' "$PYPROJECT" | head -1 | sed -E 's/^name *= *"([^"]+)".*$/\1/')
    SERVICE=$(grep -E '^service_name *= *"' "$PYPROJECT" | head -1 | sed -E 's/^service_name *= *"([^"]+)".*$/\1/')
else
    echo "Error: $PYPROJECT not found."
    exit 1
fi

if [ -z "$CURRENT_VERSION" ]; then
	echo "Error: version not defined in $PYPROJECT."
	exit 1
fi


# 2. Ensure we are inside a git working tree
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[Refresh] Error: Not inside a git working tree." >&2
  exit 3
fi

# 3. Determine repo root
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [[ -z "$REPO_ROOT" ]]; then
  echo "[Refresh] Error: Unable to determine repo root." >&2
  exit 3
fi

# 4. Block if any marker file exists unless override set
BLOCK_MARKERS_DEFAULT=".gitignore:.dev_workspace:.development:.local_dev"
BLOCK_MARKERS="${BLOCK_MARKERS:-$BLOCK_MARKERS_DEFAULT}"
IFS=":" read -r -a _markers <<<"$BLOCK_MARKERS"
for m in "${_markers[@]}"; do
  if [[ -n "$m" && -e "$REPO_ROOT/$m" ]]; then
    if [[ "${ALLOW_DEV_REFRESH:-}" != "1" ]]; then
      echo "[Refresh] Refusing to run: dev marker '$m' found at repo root ($REPO_ROOT)." >&2
      echo "Set ALLOW_DEV_REFRESH=1 to override (not recommended)." >&2
      exit 99
    else
      echo "[Refresh] ALLOW_DEV_REFRESH=1 set; ignoring dev marker '$m'." >&2
    fi
  fi
done

# 5. Block based on path pattern match (optional)
if [[ -n "${BLOCK_PATH_PATTERNS:-}" ]]; then
  IFS=":" read -r -a _block_paths <<<"$BLOCK_PATH_PATTERNS"
  for p in "${_block_paths[@]}"; do
    [[ -z "$p" ]] && continue
    if [[ "$REPO_ROOT" == *"$p"* ]]; then
      if [[ "${ALLOW_DEV_REFRESH:-}" != "1" ]]; then
        echo "[Refresh] Refusing to run: repo path '$REPO_ROOT' matches blocked pattern '$p'." >&2
        exit 100
      else
        echo "[Refresh] ALLOW_DEV_REFRESH=1 set; ignoring blocked path pattern '$p'." >&2
      fi
    fi
  done
fi

# 6. Require at least one deployment marker (if list provided)
REQUIRE_MARKERS_DEFAULT=""  # Empty by default (no requirement unless user sets)
REQUIRE_MARKERS="${REQUIRE_MARKERS:-$REQUIRE_MARKERS_DEFAULT}"
if [[ -n "$REQUIRE_MARKERS" ]]; then
  IFS=":" read -r -a _req_markers <<<"$REQUIRE_MARKERS"
  _found_req=0
  for rm in "${_req_markers[@]}"; do
    [[ -z "$rm" ]] && continue
    if [[ -e "$REPO_ROOT/$rm" ]]; then
      _found_req=1
      break
    fi
  done
  if [[ $_found_req -eq 0 ]]; then
    if [[ "${ALLOW_DEV_REFRESH:-}" != "1" ]]; then
      echo "[Refresh] Refusing to run: none of the required markers ($REQUIRE_MARKERS) found at repo root ($REPO_ROOT)." >&2
      echo "Create one of these files (e.g. 'touch .deployment') in deployment clones, or set ALLOW_DEV_REFRESH=1 to override." >&2
      exit 101
    else
      echo "[Refresh] ALLOW_DEV_REFRESH=1 set; proceeding without required markers ($REQUIRE_MARKERS)." >&2
    fi
  fi
fi

# 7. Remote origin validation (optional)
remote_url="$(git config --get remote.origin.url || true)"
if [[ -z "$remote_url" ]]; then
  echo "[Refresh] Error: No 'origin' remote configured." >&2
  exit 4
fi
if [[ -n "${REQUIRE_REMOTE_HOST:-}" && "$remote_url" != *"$REQUIRE_REMOTE_HOST"* ]]; then
  echo "[Refresh] Error: origin remote ('$remote_url') does not match REQUIRED_REMOTE_HOST='$REQUIRE_REMOTE_HOST'." >&2
  exit 5
fi

# 8. Find uv reliably (systemd often has a minimal PATH)
if command -v uv >/dev/null 2>&1; then
  UVCmd="$(command -v uv)"
elif [ -x "$HOME/.local/bin/uv" ]; then
  UVCmd="$HOME/.local/bin/uv"
else
  echo "[Refresh from Github] Error: 'uv' not found in PATH or at \$HOME/.local/bin/uv" >&2
  exit 1
fi

echo "Project $PROJECT_NAME (v$CURRENT_VERSION): Starting refresh from branch '$BRANCH'"
if [[ -n "$SERVICE" ]]; then
  echo "The $SERVICE service will be stopped during this process."
fi
read -p "Enter Y to continue, any other key to abort: " CONFIRM

if [[ "$CONFIRM" != "Y" && "$CONFIRM" != "y" ]]; then
    echo "Aborted."
    exit 0
fi

# If SERVICE is defined, stop it before refreshing
if [[ -n "$SERVICE" ]]; then
  echo "[Refresh] Stopping service '$SERVICE' before refresh..."
  sudo systemctl stop "$SERVICE"

  # Wait a moment to ensure service has stopped
  sleep 3

  # Ensure service is stopped
  if systemctl is-active --quiet "$SERVICE"; then
    echo "[Refresh] Error: Service '$SERVICE' is still running after stop command." >&2
    exit 1
  fi
fi



# Optional: ensure we're on the right branch
current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$current_branch" != "$BRANCH" ]]; then
  echo "[Refresh] Checking out branch '$BRANCH' (was on '$current_branch')."
  git checkout "$BRANCH"
fi

# Stash tracked changes only (no -u)
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "[Refresh] Stashing tracked changes..."
  git stash push -m "pre-refresh $(date -u +%Y%m%dT%H%M%SZ)" >/dev/null 2>&1 \
    || echo "[Refresh] Warning: git stash failed."
fi

echo "[Refresh] Fetching origin..."
git fetch origin

echo "[Refresh] Resetting '$BRANCH' to origin/$BRANCH..."
git reset --hard "origin/$BRANCH"


echo "[Refresh] Running 'uv sync'..."
"$UVCmd" sync

echo "[Refresh] Done."
