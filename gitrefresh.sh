#!/usr/bin/env bash
: '=======================================================
Refresh from github

Gets the latest version of this app from github. To only be used in deployed environments.
=========================================================='

# set -euo pipefail

print_help() {
  cat <<'EOF'
Usage: gitrefresh.sh [options]

Options (CLI overrides environment variables):
  --branch <name>               Branch to reset to (env: BRANCH, default: main)
  --allow-dev-refresh           Allow refresh even if dev markers/patterns match (env: ALLOW_DEV_REFRESH=1)
  --block-markers <list>        Colon-separated list of marker files/dirs to block (env: BLOCK_MARKERS)
  --require-markers <list>      Colon-separated list; at least one must exist or abort (env: REQUIRE_MARKERS)
  --block-path-patterns <list>  Colon-separated substrings; if repo path contains any -> block (env: BLOCK_PATH_PATTERNS)
  --require-remote-host <host>  Require origin remote URL to contain this host (env: REQUIRE_REMOTE_HOST)
  --stash-before-refresh <0|1>  If 1, stash tracked changes before refresh (env: STASH_BEFORE_REFRESH, default: 1)
  --service <name>              Service name to stop/start around refresh (overrides pyproject service_name)
  --yes                         Non-interactive; skip confirmation prompt
  --help                        Show this help and exit

Examples:
  BRANCH=release -- yes:
    gitrefresh.sh --branch release --yes
  Using environment:
    export ALLOW_DEV_REFRESH=1
    gitrefresh.sh --block-markers ".dev_workspace:.development"
EOF
}

# --- Safety & Portability Guards -------------------------------------------
# Environment overrides:
#   ALLOW_DEV_REFRESH=1
#   BLOCK_MARKERS=".dev_workspace:.development"
#   REQUIRE_MARKERS=".deployment:.prod"
#   BLOCK_PATH_PATTERNS="pattern1:pattern2"
#   REQUIRE_REMOTE_HOST=github.com
#   STASH_BEFORE_REFRESH=1
#   BRANCH=main
#
# General parameters (defaults, then env, then CLI)
REPO_ROOT="$(pwd)"
BRANCH="${BRANCH:-main}"
PYPROJECT="pyproject.toml"
BLOCK_PATH_PATTERNS="${BLOCK_PATH_PATTERNS:-Development}"
BLOCK_MARKERS_DEFAULT=".gitignore:.dev_workspace:.development:.local_dev:.vscode"
BLOCK_MARKERS="${BLOCK_MARKERS:-$BLOCK_MARKERS_DEFAULT}"
REQUIRE_MARKERS_DEFAULT=""
REQUIRE_MARKERS="${REQUIRE_MARKERS:-$REQUIRE_MARKERS_DEFAULT}"
STASH_BEFORE_REFRESH="${STASH_BEFORE_REFRESH:-1}"
ALLOW_DEV_REFRESH="${ALLOW_DEV_REFRESH:-}"
REQUIRE_REMOTE_HOST="${REQUIRE_REMOTE_HOST:-}"
SERVICE_OVERRIDE=""

# Parse CLI args (override env/defaults)
YES_MODE=0
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
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --allow-dev-refresh)
      ALLOW_DEV_REFRESH="1"
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
    --stash-before-refresh)
      STASH_BEFORE_REFRESH="$2"
      shift 2
      ;;
    --service)
      SERVICE_OVERRIDE="$2"
      shift 2
      ;;
    *)
      echo "[Refresh] Unknown argument: $1" >&2
      echo "Use --help to see supported options." >&2
      exit 2
      ;;
  esac
done

# 1. Inspect the pyproject.toml file and extract the project name and current version
if [ -f "$PYPROJECT" ]; then
    CURRENT_VERSION=$(grep -E '^version *= *"' "$PYPROJECT" | head -1 | sed -E 's/^version *= *"([^"]+)".*$/\1/')
    PROJECT_NAME=$(grep -E '^name *= *"' "$PYPROJECT" | head -1 | sed -E 's/^name *= *"([^"]+)".*$/\1/')
    SERVICE=$(grep -E '^service_name *= *"' "$PYPROJECT" | head -1 | sed -E 's/^service_name *= *"([^"]+)".*$/\1/')
else
    echo "Error: $PYPROJECT not found."
    exit 1
fi

# Allow CLI service override to take precedence
if [[ -n "$SERVICE_OVERRIDE" ]]; then
  SERVICE="$SERVICE_OVERRIDE"
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
IFS=":" read -r -a _markers <<<"$BLOCK_MARKERS"
for m in "${_markers[@]}"; do
  if [[ -n "$m" && -e "$REPO_ROOT/$m" ]]; then
    if [[ "$ALLOW_DEV_REFRESH" != "1" ]]; then
      echo "[Refresh] Refusing to run: dev marker '$m' found at repo root ($REPO_ROOT)." >&2
      echo "Set ALLOW_DEV_REFRESH=1 or pass --allow-dev-refresh to override (not recommended)." >&2
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
      if [[ "$ALLOW_DEV_REFRESH" != "1" ]]; then
        echo "[Refresh] Refusing to run: repo path '$REPO_ROOT' matches blocked pattern '$p'." >&2
        exit 100
      else
        echo "[Refresh] ALLOW_DEV_REFRESH=1 set; ignoring blocked path pattern '$p'." >&2
      fi
    fi
  done
fi

# 6. Require at least one deployment marker (if list provided)
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
    if [[ "$ALLOW_DEV_REFRESH" != "1" ]]; then
      echo "[Refresh] Refusing to run: none of the required markers ($REQUIRE_MARKERS) found at repo root ($REPO_ROOT)." >&2
      echo "Create one of these files (e.g. 'touch .deployment') in deployment clones, or set ALLOW_DEV_REFRESH=1 or use --allow-dev-refresh to override." >&2
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
if [[ -n "$REQUIRE_REMOTE_HOST" && "$remote_url" != *"$REQUIRE_REMOTE_HOST"* ]]; then
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

if [[ "$YES_MODE" -ne 1 ]]; then
  read -p "Enter Y to continue, any other key to abort: " CONFIRM
  if [[ "$CONFIRM" != "Y" && "$CONFIRM" != "y" ]]; then
      echo "Aborted."
      exit 0
  fi
fi

# If SERVICE is defined, stop it before refreshing
if [[ -n "$SERVICE" ]] && [[ "$(uname)" == "Linux" ]]; then
  echo "[Refresh] Stopping service '$SERVICE' before refresh..."
  sudo systemctl stop "$SERVICE"

  sleep 3

  if systemctl is-active --quiet "$SERVICE"; then
    echo "[Refresh] Error: Service '$SERVICE' is still running after stop command." >&2
    exit 1
  fi
fi

# Stash tracked changes only (no -u) based on setting
if [[ "$STASH_BEFORE_REFRESH" == "1" ]]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "[Refresh] Stashing tracked changes..."
    git stash push -m "pre-refresh $(date -u +%Y%m%dT%H%M%SZ)" >/dev/null 2>&1 \
      || echo "[Refresh] Warning: git stash failed."
  fi
fi

# Fetch before branch switching so remote branches are discoverable
echo "[Refresh] Fetching origin (including branch '$BRANCH')..."
if ! git fetch origin "$BRANCH" --tags; then
  echo "[Refresh] Warning: fetch of specific branch failed; fetching all."
  git fetch origin --tags
fi

# Ensure we are on the requested branch; create local tracking if only remote exists
current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$current_branch" != "$BRANCH" ]]; then
  echo "[Refresh] Checking out branch '$BRANCH' (was on '$current_branch')."
  if git rev-parse --verify "refs/heads/$BRANCH" >/dev/null 2>&1; then
    # Local branch exists
    if ! git checkout "$BRANCH"; then
      echo "[Refresh] Error: Failed to checkout existing local branch '$BRANCH'." >&2
      exit 6
    fi
  elif git rev-parse --verify "refs/remotes/origin/$BRANCH" >/dev/null 2>&1; then
    # Create local branch tracking remote
    if ! git checkout -B "$BRANCH" "origin/$BRANCH"; then
      echo "[Refresh] Error: Remote branch 'origin/$BRANCH' exists, but checkout -B failed." >&2
      exit 6
    fi
  else
    echo "[Refresh] Error: Branch '$BRANCH' not found locally or on origin." >&2
    echo "[Refresh] Tip: Verify the branch name, e.g. 'git branch -r --list origin/*'." >&2
    exit 6
  fi
fi

echo "[Refresh] Resetting '$BRANCH' to origin/$BRANCH..."
git reset --hard "origin/$BRANCH"

echo "[Refresh] Running 'uv sync'..."
"$UVCmd" sync

echo "[Refresh] Done."
