# Worker-0 Configuration Guide

This document explains how to configure and use Worker-0 (A clusterized wrapper/IDE workspace around the Aider AI assistant) with multiple projects and worktrees within them.

## Main Configuration File: `w0.config.yaml`

The `w0.config.yaml` file is the central configuration file that defines global settings and project-specific configurations. It has two main sections:

1. **Base Settings**: Global configurations applied to all projects
2. **Project-Specific Settings**: Configurations for individual projects

### Base Settings

The `base` section defines global settings that apply to all projects:

```yaml
base:
    # General Aider Configuration Settings
    model: gemini-2.5-pro
    weak-model: gemini-2.5-flash
    show-model-warnings: false
    edit-format: diff
    editor-edit-format: editor-diff
    multiline: true
    auto-commits: false
    architect: true

    # Global VS Code extensions to install for all projects
    extensions:
        - arcticicestudio.nord-visual-studio-code
        - dbaeumer.vscode-eslint
        - vscode.python
```

The configuration is based on aider's configuration format:

https://aider.chat/docs/config/aider_conf.html

https://aider.chat/docs/config/options.html

### Project-Specific Settings

The `projects` section contains configurations for individual projects:

```yaml
projects:
    worker-0: # Project identifier
        config: # Project configuration
            folder: app # Main folder for the project
            diff_branch: main # Branch to compare against for reviews
            worktrees: # Git worktrees to create
                - name: app-2
                - name: app-3
        aider: # Aider-specific settings for this project
            read: CONVENTIONS.md # Files to read on startup
            aiderignore: aider.ignore # Ignore file for this project
            subtree-only: true # Only operate on specified subtrees
```

## Setting Up Project Files

### CONVENTIONS.md

It's highly recommended to create a CONVENTIONS.md (or similar) file in your repository root that outlines:

-   Coding standards and style guides
-   Project architecture overview
-   Naming conventions
-   Testing practices
-   Git workflow

This file will be read by Aider on startup (if specified in the `read` configuration) and help it understand your project's conventions.

### aider.ignore

Create an aider.ignore file in the linked repository to specify which files and directories Aider should ignore. This works similarly to .gitignore but specifically for the AI assistant. This helps focus the assistant's attention on relevant code and prevents it from attempting to modify files that shouldn't be changed.

## Environment Variables: `w0.env`

-   `CODER_PWD`: Password for browser based IDE to both edit and control your LLM assistant
-   `GIT_NAME`: Git username for commits
-   `GIT_EMAIL`: Git email for commits

Additional environment variables for LLM access keys will also be added in this file

## Example Configuration: `w0.config.yaml`

Here's a complete example of a `w0.config.yaml` file with multiple projects:

```yaml
base:
    model: gemini-2.5-pro
    weak-model: gemini-2.5-flash
    show-model-warnings: false
    edit-format: diff
    editor-edit-format: editor-diff
    multiline: true
    auto-commits: false
    architect: true
    extensions:
        - arcticicestudio.nord-visual-studio-code
        - dbaeumer.vscode-eslint
        - vscode.python

projects:
    frontend:
        config:
            name: Frontend App
            folder: app
            diff_branch: develop
            worktrees:
                - name: feature-a
                - name: feature-b
                - name: bugfix-123
        aider:
            read: FRONTEND_GUIDELINES.md
            aiderignore: frontend.ignore
            subtree-only: true

    backend:
        config:
            name: Backend API
            folder: api
            diff_branch: main
            worktrees:
                - name: api-v2
                - name: database-refactor
        aider:
            read: API_DOCUMENTATION.md
            aiderignore: backend.ignore
            editor: vim
```

## Docker Compose Configuration: `w0.docker-compose.yaml`

When setting up your `w0.docker-compose.yaml` file, ensure that your volume mounts match the project structure defined in your `w0.config.yaml` file:

```yaml
services:
    worker-0:
        # ... Other configuration options
        # ... But I'm assuming you're using the rest of the configuration options from templates/w0.docker-compose.yaml
        volumes:
            # For the 'frontend' project
            - ../frontend:/app/frontend/app # Main project folder
            - ./worktrees/:/app/frontend/worktrees/
            # For the 'backend' project
            - ../backend:/app/backend/api # Main project folder
            - ./worktrees/:/app/backend/worktrees/
```

The volume mounts should follow this pattern:

-   For the main project folder: `- {relative path to project folder}:/app/{project_id}/{project_folder}`
-   For worktrees: `- ./worktrees:/app/{project_id}/worktrees`

This ensures that your container has access to all the necessary files and that worktrees are properly linked.

## Git Worktrees

The configuration supports automatically creating Git worktrees for your projects. If you're not familiar with worktrees, this is your sign to get initiated. For each worktree section defined in the config:

1. A new directory will be created at `${project_path}/worktrees/${worktree_name}`
2. A new branch named `worktree-${worktree_name}` will be created
3. The worktree will be connected to your main repository

This allows you to work on multiple features or bug fixes in isolation while still being connected to the main codebase.

**Important:** Worktree names should must be unique across all projects in your configuration, as they all share the same `worktrees` directory by default. For example, if you have a worktree named `feature-a` in both the frontend and backend projects, this would cause conflicts unless you specify your own directories for worktree management.

## VS Code/Coder Config: `w0.vscode.settings.json`

This file needs to exist and should at least contain an empty json object `{}`. You can specify vscode options for the extensions you install and other editor preferences here to make your experience what you want it to be. I wouldn't recommend getting super bogged down in this but we all have out own editor aesthetics and ergonomics.

## Usage

**Important: By default, Aider uses multiline mode, so you submit prompts with Alt+Enter rather than just Enter.**

### Starting Worker-0 with a Specific Project

```bash
# Start Aider with a specific project
w0 cli frontend

# Aider will automatically detect the project if you're in its directory
cd /app/frontend && w0 cli
```

### Reviewing Code Changes

```bash
# Review changes in a specific project
w0 review backend

# Aider will also automatically detect the project if you're in its directory since remembering things is for people pre-2020
cd /app/backend && w0 review

# Aider will compare against the diff_branch specified in the config
```

As a note on reviewing changes, you should include your review instructions inside of one of the files (e.g. CONVENTIONS.md) specified by `read` so it can be included in the system prompt of the given project

### Listing Available Projects and Worktrees

```bash
# List all configured projects and their worktrees
w0 list
```

This command displays information about all configured workers and their worktrees, with each entry showing:

-   Worker name and worktree name
-   Project name (from projects.{worker}.config.name in the configuration)
-   Current branch name
-   Full repository path

Example output:

```
frontend (main)          Name:   Frontend App
                         Branch: develop
                         Path:   /app/frontend/src

frontend (feature-a)     Name:   Frontend App
                         Branch: worktree-feat-a
                         Path:   /app/frontend/worktrees/feature-a

frontend (feature-b)     Name:   Frontend App
                         Branch: worktree-feat-b
                         Path:   /app/frontend/worktrees/feature-b

backend (main)           Name:   Backend API
                         Branch: main
                         Path:   /app/backend/api

backend (api-v2)         Name:   Backend API
                         Branch: worktree-api-v2
                         Path:   /app/backend/worktrees/api-v2
```

Note: Inside the vscode/coder command line, the paths are directly clickable to open the folder for easy navigation.

### Getting Help

```bash
# Display information about available commands
w0 help
```

This command shows detailed information about all available Worker-0 commands:

-   `w0 cli`: Start an Aider session for a project
-   `w0 review`: Review code changes for a project
-   `w0 list`: List all configured projects and worktrees
-   `w0 help`: Display help information

The help text includes usage examples and notes about automatic project detection.
