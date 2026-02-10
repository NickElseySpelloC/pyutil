#!/opt/homebrew/bin/bash
: '=======================================================
Sync development environment files between the current project and a remote folder.
Usage: sync_dev_files.sh [push|pull]
=========================================================='

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PYPROJECT="pyproject.toml"
PROJECT_DIR="$(pwd)"


# Function to print error and exit
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Function to print success message
success() {
    echo -e "${GREEN}$1${NC}"
}

# Function to print warning message
warning() {
    echo -e "${YELLOW}$1${NC}"
}

# Check if mode argument is provided
if [ $# -ne 1 ]; then
    error_exit "Usage: $0 [push|pull]"
fi

MODE="$1"

# Validate mode
if [[ "$MODE" != "push" && "$MODE" != "pull" ]]; then
    error_exit "Mode must be 'push' or 'pull', got: $MODE"
fi

# Check if pyproject.toml exists
if [ ! -f "$PROJECT_DIR/$PYPROJECT" ]; then
    error_exit "pyproject.toml not found in $PROJECT_DIR"
fi

# Function to parse pyproject.toml for dev.env.sync section
parse_config() {
    local in_section=false
    local remote=""
    local patterns=()
    
    while IFS= read -r line; do
        # Check if we're entering the dev.env.sync section
        if [[ "$line" =~ ^\[dev\.env\.sync\] ]]; then
            in_section=true
            continue
        fi
        
        # Check if we're entering a different section
        if [[ "$line" =~ ^\[.*\] ]] && [[ ! "$line" =~ ^\[dev\.env\.sync\] ]]; then
            in_section=false
            continue
        fi
        
        # Parse remote and patterns if we're in the right section
        if [ "$in_section" = true ]; then
            # Parse remote
            if [[ "$line" =~ ^remote[[:space:]]*=[[:space:]]*\"(.*)\" ]]; then
                remote="${BASH_REMATCH[1]}"
            # Parse patterns (array format)
            elif [[ "$line" =~ ^[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
                pattern="${BASH_REMATCH[1]}"
                patterns+=("$pattern")
            fi
        fi
    done < "$PROJECT_DIR/$PYPROJECT"
    
    # Validate configuration
    if [ -z "$remote" ]; then
        error_exit "[dev.env.sync] section missing 'remote' entry in $PYPROJECT"
    fi
    
    if [ ${#patterns[@]} -eq 0 ]; then
        error_exit "[dev.env.sync] section missing 'patterns' entry in $PYPROJECT"
    fi
    
    # Expand tilde in remote path
    remote="${remote/#\~/$HOME}"
    
    echo "$remote"
    printf '%s\n' "${patterns[@]}"
}

# Parse configuration
echo "Parsing configuration from $PYPROJECT..."
config_output=$(parse_config)
readarray -t config_array <<< "$config_output"

REMOTE_DIR="${config_array[0]}"
unset 'config_array[0]'
PATTERNS=("${config_array[@]}")

# Remove empty elements from patterns
PATTERNS=( "${PATTERNS[@]}" )
PATTERNS=( $(printf '%s\n' "${PATTERNS[@]}" | grep -v '^$') )

echo "Project directory: $PROJECT_DIR"
echo "Remote directory:  $REMOTE_DIR"
echo "Patterns:"
for pattern in "${PATTERNS[@]}"; do
    echo "  - $pattern"
done
echo ""

# Show confirmation and ask for user input
if [ "$MODE" = "push" ]; then
    warning "⚠️  PUSH mode: Files from project will OVERWRITE files in remote folder"
    warning "   Remote folder contents will be DELETED before copy"
else
    warning "⚠️  PULL mode: Files from remote will OVERWRITE files in project"
fi

echo ""
read -p "Continue? (y/n): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

# Execute sync based on mode
if [ "$MODE" = "push" ]; then
    echo "Starting PUSH operation..."
    
    # Create remote directory if it doesn't exist
    if [ ! -d "$REMOTE_DIR" ]; then
        echo "Creating remote directory: $REMOTE_DIR"
        mkdir -p "$REMOTE_DIR" || error_exit "Failed to create remote directory"
    fi
    
    # Verify remote directory exists
    if [ ! -d "$REMOTE_DIR" ]; then
        error_exit "Remote directory does not exist and could not be created: $REMOTE_DIR"
    fi
    
    # Remove existing files in remote directory
    echo "Cleaning remote directory..."
    for pattern in "${PATTERNS[@]}"; do
        # Handle wildcard patterns
        if [[ "$pattern" == *"*"* ]]; then
            # Get the base directory for the pattern
            base_dir=$(dirname "$pattern")
            if [ "$base_dir" != "." ]; then
                rm -rf "$REMOTE_DIR/$base_dir" 2>/dev/null || true
            else
                # Pattern in root, remove matching files
                for file in "$REMOTE_DIR"/$pattern; do
                    [ -e "$file" ] && rm -rf "$file"
                done
            fi
        else
            rm -rf "$REMOTE_DIR/$pattern" 2>/dev/null || true
        fi
    done
    
    # Copy files to remote
    echo "Copying files to remote..."
    for pattern in "${PATTERNS[@]}"; do
        # Handle wildcard patterns
        if [[ "$pattern" == *"*"* ]]; then
            # Use find to handle wildcards properly
            base_dir=$(dirname "$pattern")
            filename=$(basename "$pattern")
            
            if [ "$base_dir" = "." ]; then
                base_dir=""
            fi
            
            # Find and copy matching files/directories
            shopt -s nullglob
            for item in "$PROJECT_DIR"/$pattern; do
                if [ -e "$item" ]; then
                    rel_path="${item#$PROJECT_DIR/}"
                    target_dir="$REMOTE_DIR/$(dirname "$rel_path")"
                    mkdir -p "$target_dir"
                    cp -R "$item" "$target_dir/"
                    echo "  ✓ Copied: $rel_path"
                fi
            done
            shopt -u nullglob
        else
            # Direct file or directory
            if [ -e "$PROJECT_DIR/$pattern" ]; then
                target_dir="$REMOTE_DIR/$(dirname "$pattern")"
                mkdir -p "$target_dir"
                cp -R "$PROJECT_DIR/$pattern" "$target_dir/"
                echo "  ✓ Copied: $pattern"
            else
                warning "  ⚠ Not found: $pattern"
            fi
        fi
    done
    
    success "\n✅ PUSH completed successfully!"
    
elif [ "$MODE" = "pull" ]; then
    echo "Starting PULL operation..."
    
    # Check if remote directory exists
    if [ ! -d "$REMOTE_DIR" ]; then
        error_exit "Remote directory does not exist: $REMOTE_DIR"
    fi
    
    # Copy files from remote
    echo "Copying files from remote..."
    for pattern in "${PATTERNS[@]}"; do
        # Handle wildcard patterns
        if [[ "$pattern" == *"*"* ]]; then
            # Use find to handle wildcards properly
            shopt -s nullglob
            for item in "$REMOTE_DIR"/$pattern; do
                if [ -e "$item" ]; then
                    rel_path="${item#$REMOTE_DIR/}"
                    target_dir="$PROJECT_DIR/$(dirname "$rel_path")"
                    mkdir -p "$target_dir"
                    cp -R "$item" "$target_dir/"
                    echo "  ✓ Copied: $rel_path"
                fi
            done
            shopt -u nullglob
        else
            # Direct file or directory
            if [ -e "$REMOTE_DIR/$pattern" ]; then
                target_dir="$PROJECT_DIR/$(dirname "$pattern")"
                mkdir -p "$target_dir"
                cp -R "$REMOTE_DIR/$pattern" "$target_dir/"
                echo "  ✓ Copied: $pattern"
            else
                warning "  ⚠ Not found in remote: $pattern"
            fi
        fi
    done
    
    success "\n✅ PULL completed successfully!"
fi

