#!/bin/bash
: '=======================================================
Release (non-Python)

Stages, commits and pushes a new release of a non-Python
project to git. Version tracking is done via git tags only.
=========================================================='

# set -euo pipefail

# Get project name from the git repo directory name
PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
if [ $? -ne 0 ]; then
    echo "Error: Not a git repository."
    exit 1
fi

# Get the current version from the latest git tag
CURRENT_VERSION=$(git tag --sort=-v:refname 2>/dev/null | head -1)
if [ -z "$CURRENT_VERSION" ]; then
    CURRENT_VERSION="(none)"
fi

# Check arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <version> <comment>"
    exit 1
fi
VERSION=$1
COMMENT=$2

echo "Project:         $PROJECT_NAME"
echo "Current version: $CURRENT_VERSION"
echo "New version:     $VERSION"
echo "Comment:         $COMMENT"
echo
read -p "Enter Y to continue, any other key to abort: " CONFIRM

if [[ "$CONFIRM" != "Y" && "$CONFIRM" != "y" ]]; then
    echo "Aborted."
    exit 0
fi

# Stage all changes
echo "Staging changes..."
git add .
if [ $? -ne 0 ]; then
    echo "Error: git add failed."
    exit 1
fi

# Commit with the provided comment
echo "Committing changes..."
git commit -m "$COMMENT"
if [ $? -ne 0 ]; then
    echo "Error: git commit failed."
    exit 1
fi

# Tag the new release only if version changed
if [ "$VERSION" != "$CURRENT_VERSION" ]; then
    echo "Tagging release v$VERSION..."
    git tag "v$VERSION"
    if [ $? -ne 0 ]; then
        echo "Error: git tag failed."
        exit 1
    fi
fi

# Push to origin
echo "Pushing to origin main..."
git push origin main
if [ $? -ne 0 ]; then
    echo "Error: git push main failed."
    exit 1
fi

echo "Pushing to origin v$VERSION..."
git push origin "v$VERSION"
if [ $? -ne 0 ]; then
    echo "Error: git push origin v$VERSION failed."
    exit 1
fi

echo "Release v$VERSION committed and pushed with comment: $COMMENT"
