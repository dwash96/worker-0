#!/bin/bash
# Create the w0-cli command that accepts a worker name
cat > /usr/local/bin/w0-cli <<'EOF'
#!/bin/bash
WORKER="$1"

# If no worker specified, try to determine from current directory
if [ -z "${WORKER}" ]; then
    # Try to find which worker corresponds to the current path
    CURRENT_PATH=$(pwd)

    # Extract the first directory after PROJECTS_BASE_DIR
    POTENTIAL_WORKER=$(echo "${CURRENT_PATH}" | sed -E "s|${PROJECTS_BASE_DIR}/([^/]+).*|\1|")
        
    # Check if this potential worker exists in the config
    if yq eval '.projects | has("'${POTENTIAL_WORKER}'")' /app/.w0/w0.config.yaml | grep -q "true"; then
        WORKER="${POTENTIAL_WORKER}"
    fi

    if [ -z "${WORKER}" ]; then
        echo "Error: No worker specified and couldn't determine worker from current directory."
        echo "Usage: w0 cli <worker>"
        echo "Available workers:"
        yq eval '.projects | keys | .[]' /app/.w0/w0.config.yaml | sed 's/^/  /'
        exit 1
    fi
fi

# Verify worker exists
if ! yq eval '.projects | has("'${WORKER}'")' /app/.w0/w0.config.yaml | grep -q "true"; then
    echo "Error: Worker '${WORKER}' not found in configuration."
    echo "Available workers:"
    yq eval '.projects | keys | .[]' /app/.w0/w0.config.yaml | sed 's/^/  /'
    exit 1
fi

PROJECT_PATH="${PROJECTS_BASE_DIR}/${WORKER}"
CONFIG_PATH=$(cat "${PROJECT_PATH}/.w0/config_path" 2>/dev/null)

if [ -z "${CONFIG_PATH}" ] || [ ! -f "${CONFIG_PATH}" ]; then
    echo "Error: Configuration for worker ${WORKER} not found."
    exit 1
fi

REPO_PATH="${PROJECT_PATH}/$(yq eval ".projects.${WORKER}.config.folder" /app/.w0/w0.config.yaml)"

# Check if current directory is within a worktree
CURRENT_PATH=$(pwd)
if [[ "${CURRENT_PATH}" == *"/worktrees/"* ]]; then
    # Extract the worktree name from path
    WORKTREE_NAME=$(echo "${CURRENT_PATH}" | sed -E "s|.*/worktrees/([^/]+).*|\1|")
    
    if [ -n "${WORKTREE_NAME}" ]; then
        echo "Detected worktree: ${WORKTREE_NAME}"
        # Override REPO_PATH to use the worktree path
        WORKTREE_PATH="${PROJECT_PATH}/worktrees/${WORKTREE_NAME}"
        if [ -d "${WORKTREE_PATH}" ]; then
            REPO_PATH="${WORKTREE_PATH}"
        fi
    fi
fi

# Execute aider in the worker's repo directory
cd "${REPO_PATH}"

# Load environment from direnv if available
if command -v direnv &> /dev/null; then
  eval "$(direnv export bash)"
fi

/venv/bin/aider \
    --watch-files \
    --analytics-disable \
    --no-auto-commits \
    --no-verify-ssl \
    --multiline \
    --config "${CONFIG_PATH}"
EOF

# Create the w0-review command that accepts a worker name
cat > /usr/local/bin/w0-review <<'EOF'
#!/bin/bash
WORKER="$1"

# If no worker specified, try to determine from current directory
if [ -z "${WORKER}" ]; then
    # Try to find which worker corresponds to the current path
    CURRENT_PATH=$(pwd)

    # Extract the first directory after PROJECTS_BASE_DIR
    POTENTIAL_WORKER=$(echo "${CURRENT_PATH}" | sed -E "s|${PROJECTS_BASE_DIR}/([^/]+).*|\1|")
        
    # Check if this potential worker exists in the config
    if yq eval '.projects | has("'${POTENTIAL_WORKER}'")' /app/.w0/w0.config.yaml | grep -q "true"; then
        WORKER="${POTENTIAL_WORKER}"
    fi

    if [ -z "${WORKER}" ]; then
        echo "Error: No worker specified and couldn't determine worker from current directory."
        echo "Usage: w0 review <worker>"
        echo "Available workers:"
        yq eval '.projects | keys | .[]' /app/.w0/w0.config.yaml | sed 's/^/  /'
        exit 1
    fi
fi

# Verify worker exists
if ! yq eval '.projects | has("'${WORKER}'")' /app/.w0/w0.config.yaml | grep -q "true"; then
    echo "Error: Worker '${WORKER}' not found in configuration."
    echo "Available workers:"
    yq eval '.projects | keys | .[]' /app/.w0/w0.config.yaml | sed 's/^/  /'
    exit 1
fi

PROJECT_PATH="${PROJECTS_BASE_DIR}/${WORKER}"
CONFIG_PATH=$(cat "${PROJECT_PATH}/.w0/config_path" 2>/dev/null)

if [ -z "${CONFIG_PATH}" ] || [ ! -f "${CONFIG_PATH}" ]; then
    echo "Error: Configuration for worker ${WORKER} not found."
    exit 1
fi

DIFF_BRANCH="$(yq eval ".projects.${WORKER}.config.diff_branch" /app/.w0/w0.config.yaml)"
REPO_PATH="${PROJECT_PATH}/$(yq eval ".projects.${WORKER}.config.folder" /app/.w0/w0.config.yaml)"

# Check if current directory is within a worktree
CURRENT_PATH=$(pwd)
if [[ "${CURRENT_PATH}" == *"/worktrees/"* ]]; then
    # Extract the worktree name from path
    WORKTREE_NAME=$(echo "${CURRENT_PATH}" | sed -E "s|.*/worktrees/([^/]+).*|\1|")
    
    if [ -n "${WORKTREE_NAME}" ]; then
        echo "Detected worktree: ${WORKTREE_NAME}"
        # Override REPO_PATH to use the worktree path
        WORKTREE_PATH="${PROJECT_PATH}/worktrees/${WORKTREE_NAME}"
        if [ -d "${WORKTREE_PATH}" ]; then
            REPO_PATH="${WORKTREE_PATH}"
        fi
    fi
fi

if [ -z "${DIFF_BRANCH}" ]; then
    echo "WARNING: No diff branch specified for worker ${WORKER}. Defaulting to main"
    DIFF_BRANCH="main"
fi

# Execute aider review in the worker's repo directory
cd "$REPO_PATH"

# Load environment from direnv if available
if command -v direnv &> /dev/null; then
  eval "$(direnv export bash)"
fi

echo -e "Please conduct a code review for the following changes per the projects guidelines:\n" > "${PROJECT_PATH}/.w0-diff"
git diff main >> "${PROJECT_PATH}/.w0-diff"

/venv/bin/aider \
    --watch-files \
    --analytics-disable \
    --no-auto-commits \
    --no-verify-ssl \
    --config "${CONFIG_PATH}" \
    --message-file "${PROJECT_PATH}/.w0-diff"
EOF

# Create the w0-list command to display all workers and worktrees
cat > /usr/local/bin/w0-list <<'EOF'
#!/bin/bash

# For each worker in the config
for worker in $(yq eval '.projects | keys | .[]' /app/.w0/w0.config.yaml); do
    project_path="${PROJECTS_BASE_DIR}/${worker}"
    folder=$(yq eval ".projects.${worker}.config.folder" /app/.w0/w0.config.yaml)
    repo_path="${project_path}/${folder}"
    
    # Get the current branch for the main repository
    CURRENT_DIR="$(pwd)"
    if [ -d "${repo_path}" ]; then
        cd "${repo_path}"
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
            # Get project name from config instead of repo name
            repo_name=$(yq eval ".projects.${worker}.config.name" /app/.w0/w0.config.yaml || basename "${repo_path}")
        else
            branch="not a git repo"
            repo_name="N/A"
        fi
        cd "${CURRENT_DIR}"
    else
        branch="N/A"
        repo_name="N/A"
    fi
    
    # Calculate the indentation based on the length of worker name + worktree
    worker_display="${worker} (main)"
    display_length=${#worker_display}
    padding=$((25 - display_length))
    if [ "$padding" -lt 1 ]; then padding=1; fi
    spaces=$(printf '%*s' "$padding" '')
    
    # Print the main worker repository
    echo "${worker_display}${spaces}Name:   ${repo_name}"
    echo "$(printf '%25s' '')Branch: ${branch}"
    echo "$(printf '%25s' '')Path:   ${repo_path}"
    echo ""
    
    # Check if there are worktrees defined
    if yq eval ".projects.${worker}.config.worktrees" /app/.w0/w0.config.yaml &>/dev/null; then
        # For each worktree
        for worktree in $(yq eval ".projects.${worker}.config.worktrees[].name" /app/.w0/w0.config.yaml); do
            worktree_path="${project_path}/worktrees/${worktree}"
            
            # Get the branch for the worktree
            if [ -d "${worktree_path}" ]; then
                cd "${worktree_path}"
                if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                    branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
                    # Use the main project name from config instead of worktree name
                    repo_name=$(yq eval ".projects.${worker}.config.name" /app/.w0/w0.config.yaml || echo "${worktree}")
                else
                    branch="not a git repo"
                    repo_name="N/A"
                fi
                cd "${CURRENT_DIR}"
            else
                branch="N/A"
                repo_name="N/A"
            fi
            
            # Calculate the indentation based on the length of worker name + worktree
            worker_display="${worker} (${worktree})"
            display_length=${#worker_display}
            padding=$((25 - display_length))
            if [ "$padding" -lt 1 ]; then padding=1; fi
            spaces=$(printf '%*s' "$padding" '')
            
            echo "${worker_display}${spaces}Name:   ${repo_name}"
            echo "$(printf '%25s' '')Branch: ${branch}"
            echo "$(printf '%25s' '')Path:   ${worktree_path}"
            echo ""
        done
    fi
done
EOF

# Create the w0 unified command
cat > /usr/local/bin/w0 <<'EOF'
#!/bin/bash

# Define usage function
usage() {
    echo "Usage: w0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  cli [worker]      Start an Aider session for the specified worker or current directory"
    echo "  review [worker]   Review code changes for the specified worker or current directory"
    echo "  list              List all configured workers and their worktrees"
    echo "  help              Display this help information"
    echo ""
    echo "For more information on a specific command, run: w0 <command> --help"
    exit 1
}

# No arguments provided
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

# Parse command
COMMAND="$1"
shift

case "${COMMAND}" in
    cli)
        # Call the ac-cli script with the remaining arguments
        w0-cli "$@"
        ;;
    review)
        # Call the ac-review script with the remaining arguments
        w0-review "$@"
        ;;
    list)
        # Call the ac-list script
        w0-list
        ;;
    help)
        # Call the ac-help script
        w0-help
        ;;
    *)
        echo "Error: Unknown command '${COMMAND}'"
        usage
        exit 1
        ;;
esac
EOF

# Create the w0-help command to show information about available commands
cat > /usr/local/bin/w0-help <<'EOF'
#!/bin/bash

echo "Worker-0 Commands:"
echo ""
echo "Usage: w0 <command> [options]"
echo ""
echo "Available commands:"
echo ""
echo "  w0 cli [worker]"
echo "    Start an Aider session for the specified worker or current directory."
echo "    Example: w0 cli frontend"
echo ""
echo "  w0 review [worker]"
echo "    Review code changes for the specified worker or current directory."
echo "    Compares against the diff_branch in the config."
echo "    Example: w0 review backend"
echo ""
echo "  w0 list"
echo "    List all configured workers and their worktrees."
echo "    Shows the worker name, project name, branch, and path."
echo ""
echo "  w0 help"
echo "    Display this help information."
echo ""
echo "Note: If no worker is specified for cli or review commands, they will try to detect"
echo "      the worker based on your current directory."
EOF

chmod +x /usr/local/bin/w0-cli
chmod +x /usr/local/bin/w0-review
chmod +x /usr/local/bin/w0-list
chmod +x /usr/local/bin/w0-help
chmod +x /usr/local/bin/w0
