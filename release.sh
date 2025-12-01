#!/bin/bash
: '=======================================================
Release

Stages, commits and pushes a new release of the project to git.
=========================================================='

set -euo pipefail

PYPROJECT="pyproject.toml"

# Get the current version from pyproject.toml
if [ -f "$PYPROJECT" ]; then
    CURRENT_VERSION=$(grep -E '^version *= *"' "$PYPROJECT" | head -1 | sed -E 's/^version *= *"([^"]+)".*$/\1/')
    PROJECT_NAME=$(grep -E '^name *= *"' "$PYPROJECT" | head -1 | sed -E 's/^name *= *"([^"]+)".*$/\1/')
else
    echo "Error: $PYPROJECT not found."
    exit 1
fi

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <version> <comment>"
    exit 1
fi
VERSION=$1
COMMENT=$2

# Make sure our virtual environment is activated
if [ -z "$VIRTUAL_ENV" ]; then
    echo "Error: No virtual environment activated."
    exit 1
fi

# Check if there is a tests/ folder to determine if pytest is needed
if [ -d "tests" ]; then
    PYTEST_NEEDED=true
    # Make sure pytest is in the path
    if ! command -v pytest &> /dev/null; then
        echo "Error: pytest could not be found. Please install it in your virtual environment."
        exit 1
    fi
else
    PYTEST_NEEDED=false
fi

# Check if there is a docs/ folder to determine if pytest is needed
if [ -d "docs" ]; then
    DOCS_NEEDED=true
    # Make sure mkdocs is in the path
    if ! command -v mkdocs &> /dev/null; then
        echo "Error: mkdocs could not be found. Please install it in your virtual environment."
        exit 1
    fi
else
    DOCS_NEEDED=false
fi


echo "Current version: $CURRENT_VERSION"
echo "New version:     $VERSION"
echo "Comment:         $COMMENT"
echo
read -p "Enter Y to continue, any other key to abort: " CONFIRM

if [[ "$CONFIRM" != "Y" && "$CONFIRM" != "y" ]]; then
    echo "Aborted."
    exit 0
fi

# Run tests using pytest and check for errors
if [ "$PYTEST_NEEDED" = true ]; then
    echo "Running tests with pytest..."
    pytest
    if [ $? -ne 0 ]; then
        echo "Error: Tests failed."
        exit 1
    fi
fi

# Build the documentation using mkdocs and check for errors
if [ "$DOCS_NEEDED" = true ]; then
    echo "Building documentation with mkdocs..."
    mkdocs build --clean
    if [ $? -ne 0 ]; then
        echo "Error: mkdocs build failed."
        exit 1
    fi
fi

# Update the version in pyproject.toml
echo "Updating version in $PYPROJECT to $VERSION..."
sed -i '' -E "s/(^version *= *\").*(\")/\1$VERSION\2/" "$PYPROJECT"

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

# Tag the new release
echo "Tagging release v$VERSION..."
git tag "v$VERSION"
if [ $? -ne 0 ]; then
    echo "Error: git tag failed."
    exit 1
fi

# Push to origin
echo "Pushing to origin main..."
git push origin main
if [ $? -ne 0 ]; then
    echo "Error: git push main failed."
    exit 1
fi

git push origin "v$VERSION"
echo "Pushing to origin v$VERSION..."
if [ $? -ne 0 ]; then
    echo "Error: git push origin v$VERSION failed."
    exit 1
fi

# Push the documentation to the gh-pages branch
if [ "$DOCS_NEEDED" = true ]; then
    echo "Deploying documentation to gh-pages..."
    mkdocs gh-deploy --clean
    if [ $? -ne 0 ]; then
        echo "Error: mkdocs deployment failed."
        exit 1
    fi
fi

echo "Release v$VERSION committed and pushed with comment: $COMMENT"