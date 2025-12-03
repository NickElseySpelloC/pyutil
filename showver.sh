#!/bin/bash
: '=======================================================
Show Version

Displays the current version of the project as specified in pyproject.toml.
=========================================================='

PYPROJECT="pyproject.toml"

# Get the current version from pyproject.toml
if [ -f "$PYPROJECT" ]; then
    CURRENT_VERSION=$(grep -E '^version *= *"' "$PYPROJECT" | head -1 | sed -E 's/^version *= *"([^"]+)".*$/\1/')
    PROJECT_NAME=$(grep -E '^name *= *"' "$PYPROJECT" | head -1 | sed -E 's/^name *= *"([^"]+)".*$/\1/')
else
    echo "Error: $PYPROJECT not found."
    exit 1
fi

if [ -z "$CURRENT_VERSION" ]; then
	echo "Error: version not defined in $PYPROJECT."
	exit 1
fi

echo "Project $PROJECT_NAME current version: $CURRENT_VERSION"
exit 0
