#!/usr/bin/env bash
# Create a new development environment for a project.

set -euo pipefail

# Set BASE_DIR to the parent directory that this script is located in, not the current working directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"


# Settings for the script
TEMPLATE_PARENT_FOLDER="$BASE_DIR/py_templates"
GITHUB_PERSONAL_ACCOUNT="NickElseySpelloC"
GITHUB_ORG_ACCOUNT="Spello-Consulting"
# Files/folders to skip when copying the template, matched against each path segment and the full relative path (shell wildcards supported)
EXCLUDE_PATTERNS=(".venv" ".git" "__pycache__" "uv.lock" ".env.target" "logs")

# See if the user has gh installed and is authenticated
if ! command -v gh &> /dev/null; then
    echo "gh command not found. Please install the GitHub CLI and authenticate before running this script again." >&2
    exit 1
fi

usage() {
    echo "Usage: $0 <project-name> [--skip_remote] [--account <personal | org>] [--public|--private] [--desc <description>]" >&2
    echo "Arguments:" >&2
    echo "  <project-name>             Name of the project to create" >&2
    echo "  --template <template-name> Specify which template to use" >&2
    echo "  --skip_remote              Skip creating and linking the GitHub remote repository" >&2
    echo "  --account <personal|org>   GitHub account to use (default: personal)" >&2
    echo "  --public                   Make the GitHub repository public" >&2
    echo "  --private                  Make the GitHub repository private (default)" >&2
    echo "  --desc <description>       Project description (default: 'My Project')" >&2
    exit "${1:-1}"
}

# Return success (0) if rel_path matches one of EXCLUDE_PATTERNS, either as a whole or via any path segment
is_excluded() {
    local rel_path="$1"
    local pattern segment
    local -a segments

    # Split into path segments without triggering pathname expansion
    IFS='/' read -ra segments <<< "$rel_path"

    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        # Match against the full relative path
        case "$rel_path" in
            $pattern) return 0 ;;
        esac
        # Match against each individual path segment (so nested matches like foo/.venv/bin also get excluded)
        for segment in "${segments[@]}"; do
            case "$segment" in
                $pattern) return 0 ;;
            esac
        done
    done
    return 1
}

# Recursively copy template files to the destination, substituting TEMPLATE_PROJECT_NAME/TEMPLATE_DESCRIPTION
# tokens in file/directory names, and in the contents of text files. Paths matching EXCLUDE_PATTERNS are skipped.
copy_template() {
    local src_dir="$1"
    local dest_dir="$2"
    local esc_project esc_description

    # Escape sed special characters (/, &, \) in the replacement values
    esc_project=$(printf '%s' "$project" | sed -e 's/[\/&\\]/\\&/g')
    esc_description=$(printf '%s' "$description" | sed -e 's/[\/&\\]/\\&/g')

    while IFS= read -r -d '' src_path; do
        local rel_path="${src_path#"$src_dir"/}"

        is_excluded "$rel_path" && continue

        local dest_rel_path="${rel_path//TEMPLATE_PROJECT_NAME/$project}"
        dest_rel_path="${dest_rel_path//TEMPLATE_DESCRIPTION/$description}"
        local dest_path="$dest_dir/$dest_rel_path"

        if [[ -d "$src_path" ]]; then
            mkdir -p "$dest_path"
        elif [[ -f "$src_path" ]]; then
            mkdir -p "$(dirname "$dest_path")"
            if file -b --mime-encoding "$src_path" | grep -qv '^binary$'; then
                sed -e "s/TEMPLATE_PROJECT_NAME/$esc_project/g" -e "s/TEMPLATE_DESCRIPTION/$esc_description/g" "$src_path" > "$dest_path"
            else
                cp "$src_path" "$dest_path"
            fi
        fi
    done < <(find "$src_dir" -mindepth 1 -print0)
}

# Handle --help/no-args before treating $1 as the project name
if [[ $# -eq 0 ]]; then
    usage
fi
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    usage 0
fi

project="$1"
shift || true
template=basic
skip_remote=false
GITHUB_ACCOUNT="$GITHUB_PERSONAL_ACCOUNT"
repo_visibility="private"
description="My Project"

while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
        --skip_remote)
            skip_remote=true
            ;;
        --account)
            shift
            account="$1"
            if [[ "$account" == "personal" ]]; then
                GITHUB_ACCOUNT="$GITHUB_PERSONAL_ACCOUNT"
            elif [[ "$account" == "org" ]]; then
                GITHUB_ACCOUNT="$GITHUB_ORG_ACCOUNT"
            else
                echo "Invalid account type: $account. Must be 'personal' or 'org'." >&2
                usage
            fi
            ;;
        --template)
            shift
            template="$1"
            ;;
        --public)
            repo_visibility="public"
            ;;
        --private)
            repo_visibility="private"
            ;;
        --help|-h)
            usage 0
            ;;
        --desc)
            shift
            description="$1"
            ;;
        -*)
            echo "Unknown option: $arg" >&2
            usage
            ;;
        *)
            echo "Unknown positional argument: $arg" >&2
            usage
            ;;
    esac
    shift
done

# Set the template folder based on the selected template
TEMPLATE_FOLDER="$TEMPLATE_PARENT_FOLDER/$template"

# Check if the template folder exists. If it doesn't, abort with an error message.
if [[ ! -d "$TEMPLATE_FOLDER" ]]; then
    echo "Template folder '$TEMPLATE_FOLDER' does not exist. Please choose a valid template." >&2
    usage
fi

# Check if the project name is provided. If not, print usage and exit.
if [[ -z "$project" ]]; then
    usage
fi


# Check if the project directory already exists. If it does, abort to avoid overwriting an existing project.
if [[ -d "$BASE_DIR/$project" ]]; then
    echo "A directory called '$BASE_DIR/$project' already exists. Please choose a different project name or delete the existing directory before running this script again." >&2
    exit 1
fi

# Check if the github repo already exists. If it does, abort to avoid overwriting an existing project.
if [[ "$skip_remote" = false ]] && gh repo view "$GITHUB_ACCOUNT/$project" &> /dev/null; then
    echo "A GitHub repository called '$GITHUB_ACCOUNT/$project' already exists. Please choose a different project name or delete the existing repository before running this script again." >&2
    exit 1
fi


# Tell the user what we're about to do. Ask for confirmation before proceeding.
echo "Creating a new development environment:"
echo "    Template:     $TEMPLATE_FOLDER"
echo "    Project:      $project"
echo "    Description:  $description"
echo "    Local folder: $BASE_DIR/$project"
if [[ "$skip_remote" = false ]]; then
    echo "    GH Account:   $GITHUB_ACCOUNT"
    echo "    GitHub repo:  $GITHUB_ACCOUNT/$project"
    echo "    Visibility:   $repo_visibility"
fi
echo -e "\nThis will initialise the project with uv and git and populate it with the template files from $TEMPLATE_FOLDER\n"

read -p "Are you sure you want to continue? [y/N] " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting."
    exit 1
fi

# Create the project directory if it doesn't exist
mkdir -p "$BASE_DIR/$project"

# Change to the project directory
cd "$BASE_DIR/$project"

# Initialise the project with uv which will intiialise git also
uv init --description "$description" --no-readme
git init

# Remove the default pyproject.toml and main.py file created by uv init, since we will be copying our own template files
rm -f main.py
rm -f pyproject.toml


# Copy all the template files from the TEMPLATE_FOLDER to the new project directory,
# substituting __PROJECT__/TEMPLATE_DESCRIPTION tokens in file names and file contents
echo "Copying template files from $TEMPLATE_FOLDER to $BASE_DIR/$project"
copy_template "$TEMPLATE_FOLDER" "$BASE_DIR/$project"

# Do a uv sync to ensure the uv.lock file is up to date with the new dependencies and the virtual environment is set up correctly
uv sync --extra all

# Make all the shell scripts in the scripts directory executable
if [[ -d "scripts" ]]; then
    echo "Making shell scripts in the scripts directory executable"
    find scripts -type f -name "*.sh" -exec chmod +x {} \;
fi

# Create the .env.target symbolic link to the .env file in the project root if it doesn't already exist
if [[ ! -L ".env.target" ]]; then
    echo "Creating .env.target symbolic link file"
    ln -s .env.dev.template .env.target
fi

# Push the initial commit to the new github repository
git add .
git commit -m "Initial commit"
if [[ "$skip_remote" = false ]]; then
    gh repo create "$GITHUB_ACCOUNT/$project" --"$repo_visibility" --source=. --remote=origin

    # Wait a few seconds to ensure the github repository is created before trying to push to it
    echo "Waiting for the GitHub repository to be created..."
    sleep 5

    git push -u origin main
fi

# If we created a remote repo, open it in the browser
if [[ "$skip_remote" = false ]]; then
    echo "Opening the GitHub repository in the browser..."
    gh repo view "$GITHUB_ACCOUNT/$project" --web
fi

# cd into the project directory and open it in VS Code
cd "$BASE_DIR/$project"

# Activate the virtual environment if it exists
if [[ -d ".venv" ]]; then
    echo "Activating the virtual environment..."
    # shellcheck disable=SC1091
    source .venv/bin/activate
fi

# Print a success message with next steps
echo "Successfully created a new development environment for project '$project' in $BASE_DIR/$project"

# Open the project in VS Code if the code command is available, using the .code-workspace file if present
if command -v code &> /dev/null; then
    workspace_file=$(find . -maxdepth 1 -name '*.code-workspace' -print -quit)
    echo "Opening the project in VS Code..."
    if [[ -n "$workspace_file" ]]; then
        code "$workspace_file"
    else
        code .
    fi
else
    echo "VS Code command 'code' not found. Please open the project in VS Code manually."
fi