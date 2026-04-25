#!/usr/bin/env bash
# Create a new development environment for a project.

set -euo pipefail

GITHUB_ACCOUNT="NickElseySpelloC"
DEFAULT_GITIGNORE=/Users/nick/Library/CloudStorage/Dropbox/Development/dev_setup/git/default.gitignore

# Set BASE_DIR to the parent directory that this script is located in, not the current working directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# See if the user has gh installed and is authenticated
if ! command -v gh &> /dev/null; then
    echo "gh command not found. Please install the GitHub CLI and authenticate before running this script again." >&2
    exit 1
fi

usage() {
    echo "Usage: $0 <project-name> [--public|--private]" >&2
    exit 1
}

project_name=""
repo_visibility="private"

for arg in "$@"; do
    case "$arg" in
        --public)
            repo_visibility="public"
            ;;
        --private)
            repo_visibility="private"
            ;;
        --help|-h)
            usage
            ;;
        -*)
            echo "Unknown option: $arg" >&2
            usage
            ;;
        *)
            if [[ -n "$project_name" ]]; then
                echo "Only one project name may be provided." >&2
                usage
            fi
            project_name="$arg"
            ;;
    esac
done

if [[ -z "$project_name" ]]; then
    usage
fi

# Check if the github repo already exists. If it does, abort to avoid overwriting an existing project.
if gh repo view "$GITHUB_ACCOUNT/$project_name" &> /dev/null; then
    echo "A GitHub repository called '$GITHUB_ACCOUNT/$project_name' already exists. Please choose a different project name or delete the existing repository before running this script again." >&2
    exit 1
fi

# Check if the project directory already exists. If it does, abort to avoid overwriting an existing project.
if [[ -d "$BASE_DIR/$project_name" ]]; then
    echo "A directory called '$BASE_DIR/$project_name' already exists. Please choose a different project name or delete the existing directory before running this script again." >&2
    exit 1
fi

# Tell the user what we're about to do. Ask for confirmation before proceeding.
echo "Creating a new development environment for project '$project_name' in $BASE_DIR/$project_name"
echo "This will initialise the project with uv and git. create a .env file and a default .gitignore file"
echo "The project will be linked to a new $repo_visibility github repository called '$project_name' under the '$GITHUB_ACCOUNT' account."

read -p "Are you sure you want to continue? [y/N] " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting."
    exit 1
fi

# Create the project directory if it doesn't exist
mkdir -p "$BASE_DIR/$project_name"

# Change to the project directory
cd "$BASE_DIR/$project_name"

# Initialise the project with uv and git
uv init
git init

# Copy the default .gitignore file to the project directory
echo "Copying default .gitignore file from $DEFAULT_GITIGNORE to $BASE_DIR/$project_name/.gitignore"
cp "$DEFAULT_GITIGNORE" .gitignore

# Create a .env file with some default content
echo "Creating .env file with default content"
cat <<EOF > .env
# Add your environment variables here
EOF

# Create a default vscode workspace file with some recommended settings for development
echo "Creating vscode workspace file with recommended settings for development"
cat <<EOF > $project_name.code-workspace
{
	"folders": [
		{
			"path": "."
		}
	],
	"settings": {}
}
EOF

# Create a .vscode directory with some recommended settings for development
echo "Creating .vscode directory with recommended settings for development"
mkdir -p .vscode
cat <<EOF > .vscode/launch.json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Python Debugger: Current File",
            "type": "debugpy",
            "request": "launch",
            "program": "main.py",
            "console": "integratedTerminal",
            "envFile": "${workspaceFolder}/.env"
        }
    ]
}
EOF

# Create the new github repository and link it to the local git repository
gh repo create "$GITHUB_ACCOUNT/$project_name" --"$repo_visibility" --source=. --remote=origin

# Wait a few seconds to ensure the github repository is created before trying to push to it
echo "Waiting for the GitHub repository to be created..."
sleep 5

# Push the initial commit to the new github repository
git add .
git commit -m "Initial commit"
git push -u origin main

# Print a success message with next steps
echo "Successfully created a new development environment for project '$project_name' in $BASE_DIR/$project_name"
echo "Next steps:"
echo "1. Start developing your project! Use 'uv run' to run your project and 'uv test' to run your tests."
echo "2. When you're ready to share your project, push your changes to the github repository with 'git push'."
echo "3. If you want to add collaborators to your project, you can do so on the github repository page: https://github.com/$GITHUB_ACCOUNT/$project_name"

