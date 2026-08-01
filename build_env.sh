#!/usr/bin/env bash
# Generate a project's .env file by injecting secrets with 1Password's `op`.
# Template and output paths are read from [dev.env.build] in the project's
# pyproject.toml, so this stays in sync with that config block.
#
# Usage: build_env.sh [PROJECT_DIR]   (PROJECT_DIR defaults to the current dir)
set -euo pipefail

PROJECT_DIR="${1:-$PWD}"
cd "$PROJECT_DIR"

if [[ ! -f pyproject.toml ]]; then
    echo "error: no pyproject.toml found in $PROJECT_DIR" >&2
    exit 1
fi

# Pull template/output from pyproject.toml (tomllib is stdlib on py3.11+).
read -r TEMPLATE OUTPUT < <(python3 - <<'PY'
import tomllib
try:
    with open("pyproject.toml", "rb") as f:
        cfg = tomllib.load(f)["dev"]["env"]["build"]
    print(cfg["template"], cfg["output"])
except (FileNotFoundError, KeyError):
    print(".env.template", ".env")
PY
)

if ! command -v op >/dev/null 2>&1; then
    echo "error: 1Password CLI (op) not found on PATH" >&2
    exit 1
fi

echo "Injecting secrets: $TEMPLATE -> $OUTPUT"
op inject -i "$TEMPLATE" -o "$OUTPUT" -f
