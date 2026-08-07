#!/usr/bin/env bash
: '=======================================================
Dev environment guard checks

Shared by gitrefresh.sh and gitpush.sh. Refuses to proceed if the cwd looks
like a development checkout rather than a deployed clone. Not meant to be
run directly - source it and call check_dev_environment().
=========================================================='

# Expects these globals to already be set by the caller before invocation:
#   REPO_ROOT             - absolute path to the git repo root
#   BLOCK_MARKERS          - colon-separated marker files/dirs that block if present
#   BLOCK_PATH_PATTERNS    - colon-separated substrings; block if REPO_ROOT contains any
#   REQUIRE_MARKERS        - colon-separated markers; at least one must exist (if non-empty)
#   REQUIRE_REMOTE_HOST    - if set, origin remote URL must contain this host
#   ALLOW_DEV_OVERRIDE     - "1" to downgrade blocking checks to warnings
#   DEV_CHECK_PREFIX       - log message prefix, e.g. "[Refresh]" or "[Push]"
#
# On success, sets REMOTE_URL to the origin remote URL and returns 0.
# On failure, prints an error and exits the calling script (checks are fatal by design).
check_dev_environment() {
  local prefix="${DEV_CHECK_PREFIX:-[Check]}"

  # Block if any marker file exists unless override set
  IFS=":" read -r -a _markers <<<"$BLOCK_MARKERS"
  for m in "${_markers[@]}"; do
    if [[ -n "$m" && -e "$REPO_ROOT/$m" ]]; then
      if [[ "$ALLOW_DEV_OVERRIDE" != "1" ]]; then
        echo "$prefix Refusing to run: dev marker '$m' found at repo root ($REPO_ROOT)." >&2
        echo "Set ALLOW_DEV_OVERRIDE=1 or pass --allow-dev-override to override (not recommended)." >&2
        exit 99
      else
        echo "$prefix ALLOW_DEV_OVERRIDE=1 set; ignoring dev marker '$m'." >&2
      fi
    fi
  done

  # Block based on path pattern match (optional)
  if [[ -n "${BLOCK_PATH_PATTERNS:-}" ]]; then
    IFS=":" read -r -a _block_paths <<<"$BLOCK_PATH_PATTERNS"
    for p in "${_block_paths[@]}"; do
      [[ -z "$p" ]] && continue
      if [[ "$REPO_ROOT" == *"$p"* ]]; then
        if [[ "$ALLOW_DEV_OVERRIDE" != "1" ]]; then
          echo "$prefix Refusing to run: repo path '$REPO_ROOT' matches blocked pattern '$p'." >&2
          exit 100
        else
          echo "$prefix ALLOW_DEV_OVERRIDE=1 set; ignoring blocked path pattern '$p'." >&2
        fi
      fi
    done
  fi

  # Require at least one deployment marker (if list provided)
  if [[ -n "$REQUIRE_MARKERS" ]]; then
    IFS=":" read -r -a _req_markers <<<"$REQUIRE_MARKERS"
    local _found_req=0
    for rm in "${_req_markers[@]}"; do
      [[ -z "$rm" ]] && continue
      if [[ -e "$REPO_ROOT/$rm" ]]; then
        _found_req=1
        break
      fi
    done
    if [[ $_found_req -eq 0 ]]; then
      if [[ "$ALLOW_DEV_OVERRIDE" != "1" ]]; then
        echo "$prefix Refusing to run: none of the required markers ($REQUIRE_MARKERS) found at repo root ($REPO_ROOT)." >&2
        echo "Create one of these files (e.g. 'touch .deployment') in deployment clones, or set ALLOW_DEV_OVERRIDE=1 or use --allow-dev-override to override." >&2
        exit 101
      else
        echo "$prefix ALLOW_DEV_OVERRIDE=1 set; proceeding without required markers ($REQUIRE_MARKERS)." >&2
      fi
    fi
  fi

  # Remote origin validation (optional)
  REMOTE_URL="$(git config --get remote.origin.url || true)"
  if [[ -z "$REMOTE_URL" ]]; then
    echo "$prefix Error: No 'origin' remote configured." >&2
    exit 4
  fi
  if [[ -n "$REQUIRE_REMOTE_HOST" && "$REMOTE_URL" != *"$REQUIRE_REMOTE_HOST"* ]]; then
    echo "$prefix Error: origin remote ('$REMOTE_URL') does not match REQUIRE_REMOTE_HOST='$REQUIRE_REMOTE_HOST'." >&2
    exit 5
  fi
}
