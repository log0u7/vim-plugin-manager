# Contributing to Vim Plugin Manager

Thank you for considering contributing to the Vim Plugin Manager project! This document outlines the process for contributing to this project and helps ensure a smooth collaboration experience.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Architecture Overview](#architecture-overview)
- [Testing](#testing)
- [Documentation](#documentation)
- [Issue Reporting](#issue-reporting)

## Code of Conduct

This project adheres to a code of conduct that expects all participants to be respectful, inclusive, and considerate. By participating, you are expected to uphold this code. Please report unacceptable behavior to [gke@6admin.io](mailto:gke@6admin.io).

## Getting Started

1. **Fork the repository** on GitHub.
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/yourusername/vim-plugin-manager.git
   cd vim-plugin-manager
   ```
3. **Add the upstream repository** as a remote:
   ```bash
   git remote add upstream https://github.com/username/vim-plugin-manager.git
   ```
4. **Create a branch** for your work:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Development Workflow

1. Ensure you're working on the latest code:
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. Make your changes, following the [coding standards](#coding-standards).

3. Test your changes (see [Testing](#testing)).

4. Commit your changes with a descriptive message:
   ```bash
   git commit -m "feature: Add support for XYZ"
   ```
   
   Commit message prefixes to use:
   - `feature:` for new features
   - `fix:` for bug fixes
   - `docs:` for documentation changes
   - `test:` for test additions or modifications
   - `refactor:` for code refactoring
   - `style:` for formatting changes
   - `chore:` for routine tasks and maintenance

5. Push your branch to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

6. Create a [pull request](#pull-request-process).

## Pull Request Process

1. Fill out the pull request template completely.
2. Link any relevant issues using GitHub keywords (e.g., "Fixes #123").
3. Ensure your PR passes all tests and CI checks.
4. Request a review from a maintainer.
5. Be responsive to feedback and make necessary changes.
6. Once approved, a maintainer will merge your PR.

## Coding Standards

- Follow existing code style and structure.
- For Vimscript:
  - Use 2-space indentation.
  - Keep lines under 100 characters when possible.
  - Use snake_case for functions and variables.
  - Prefix internal functions with `s:`.
  - Prefix plugin-specific functions with `plugin_manager#`.
  - Document functions with comments.
  - Use Vim script's native idioms.

## Architecture Overview

The plugin is designed using a modular architecture that follows the principles of separation of concerns and single responsibility. Understanding this architecture will help you contribute effectively.

### Core Components

The project is organized into several key components:

1. **Plugin Entry Point**
   - `plugin/plugin_manager.vim`: Defines commands, initializes global variables, and provides the main entry point function.

2. **Command Dispatcher**
   - `autoload/plugin_manager/cmd.vim`: Parses command arguments and dispatches to specialized command modules.

3. **Public API Façade**
   - `autoload/plugin_manager/api.vim`: Provides a unified API for all plugin operations.

4. **Core Functionality**
   - `autoload/plugin_manager/core.vim`: Contains fundamental utilities, error handling, path management and configuration functions.
   - `autoload/plugin_manager/git.vim`: Abstracts all Git operations and submodule management.
   - `autoload/plugin_manager/async.vim`: Provides unified async operations with Vim/Neovim compatibility.
   - `autoload/plugin_manager/ui.vim`: Handles user interface, sidebar rendering, and progress indication.

5. **Command Modules**
   - `autoload/plugin_manager/cmd/*.vim`: Contains implementation of specific commands:
     - `add.vim`: Plugin installation logic.
     - `remove.vim`: Plugin removal operations.
     - `list.vim`: Plugin listing and status reporting.
     - `update.vim`: Plugin update operations.
     - `backup.vim`: Configuration backup operations.
     - `restore.vim`: Plugin restoration operations.
     - `helptags.vim`: Helptags generation.
     - `reload.vim`: Plugin reloading operations.
     - `status.vim`: Plugin status reporting.
     - `declare.vim`: Declarative plugin configuration.
     - `remote.vim`: Remote repository management.

6. **Utility Files**
   - `ftdetect/pluginmanager.vim`: Defines filetype detection rules.
   - `ftplugin/pluginmanager.vim`: Sets buffer configuration and key mappings.
   - `syntax/pluginmanager.vim`: Defines syntax highlighting for the plugin interface.

### Control Flow

1. User commands are processed through `:PluginManager` which calls `plugin_manager#cmd#dispatch()`.
2. The dispatcher parses arguments and routes to the appropriate command module.
3. Command modules implement specific operations using the core functionality.
4. UI feedback is provided through the UI module.
5. Git operations are abstracted through the Git module.
6. Asynchronous operations are handled through the Async module.

### Error Handling

Errors follow a structured format:
- `PM_ERROR:component:message` for internal errors
- The Core module provides utilities for creating, handling, and formatting errors.
- UI error display is handled through the UI module.

### Extending the Plugin

When adding new features:

1. **Determine the Appropriate Module**: New functionality should be placed in the most relevant module, or create a new one if needed.
2. **Follow the API Pattern**: 
   - Internal functions should be prefixed with `s:`.
   - Public functions should follow the naming pattern `plugin_manager#modulename#functionname()`.
3. **Use Core Utilities**: Leverage existing utilities from the Core, Git, UI, and Async modules.
4. **Add Command Implementation**: Place new commands in the cmd/ directory.
5. **Update API**: Add API functions to api.vim for new commands.
6. **Add Documentation**: Update help docs and README.md with new functionality.
7. **Update Command Handling**: Update the command dispatcher in cmd.vim.

### Configuration System

The plugin uses global configuration variables defined in `plugin/plugin_manager.vim`, and accessed via `plugin_manager#core#get_config()`:

- `g:plugin_manager_vim_dir`: Base directory for Vim configuration.
- `g:plugin_manager_plugins_dir`: Directory for storing plugins.
- `g:plugin_manager_start_dir`: Directory for auto-loaded plugins.
- `g:plugin_manager_opt_dir`: Directory for optional (lazy-loaded) plugins.
- `g:plugin_manager_vimrc_path`: Path to vimrc file.
- `g:plugin_manager_sidebar_width`: Width of the sidebar UI.
- `g:plugin_manager_default_git_host`: Default Git host for short plugin names.
- `g:plugin_manager_fancy_ui`: Controls whether to use Unicode symbols in the UI.

When adding new configuration options, follow this pattern and provide sensible defaults.

## Testing

Currently, the project uses manual testing. When adding new features or fixing bugs:

1. Verify your changes work correctly in both Vim and Neovim.
2. Test all related functionality to ensure no regressions.
3. Include steps to manually test your changes in the PR description.

Future improvements may include automated tests.

## Documentation

- Update documentation for any changed functionality.
- Document new features in:
  - The README.md file
  - The plugin's help documentation (doc/plugin_manager.txt)
  - Code comments for functions

Documentation should be clear, concise, and include examples where appropriate.

## Issue Reporting

When reporting issues, please include:

1. A clear and descriptive title.
2. Steps to reproduce the issue.
3. Expected and actual behavior.
4. Vim/Neovim version and OS information.
5. Relevant error messages or screenshots.
6. Any relevant configuration or setup.

Feature requests should include:
1. A clear description of the problem the feature would solve.
2. Any proposed solutions or implementation details.

## Project Structure

Understanding the project's complete structure will help you contribute effectively:

```
.
├── autoload/
│   ├── plugin_manager/
│   │   ├── api.vim                  # Public API façade
│   │   ├── async.vim                # Asynchronous operations support
│   │   ├── cmd.vim                  # Command dispatcher
│   │   ├── core.vim                 # Core utilities and error handling
│   │   ├── git.vim                  # Git operations abstraction
│   │   ├── ui.vim                   # User interface components
│   │   └── cmd/                     # Command implementations
│   │       ├── add.vim              # Plugin installation
│   │       ├── backup.vim           # Configuration backup
│   │       ├── declare.vim          # Declarative plugin configuration
│   │       ├── helptags.vim         # Help documentation generation
│   │       ├── list.vim             # Plugin listing and status
│   │       ├── reload.vim           # Plugin reloading
│   │       ├── remote.vim           # Remote repository management
│   │       ├── remove.vim           # Plugin removal
│   │       ├── restore.vim          # Plugin restoration
│   │       ├── status.vim           # Plugin status reporting
│   │       └── update.vim           # Plugin updating
├── doc/                             # Documentation
│   └── plugin_manager.txt           # Help documentation
├── ftdetect/                        # Filetype detection
│   └── pluginmanager.vim            # Filetype detection for PluginManager
├── ftplugin/                        # Filetype plugin
│   └── pluginmanager.vim            # Buffers config for PluginManager
├── plugin/                          # Plugin initialization
│   └── plugin_manager.vim           # Entry point and command definitions
├── syntax/                          # Syntax highlighting
│   └── pluginmanager.vim            # Syntax definitions for the UI
├── CHANGELOG.md                     # History of changes and versions
├── CONTRIBUTING.md                  # Contribution guidelines (this file)
├── LICENSE                          # License information
├── Makefile                         # Build and version management
└── README.md                        # Project overview and usage information
```

## License

By contributing to this project, you agree that your contributions will be licensed under the same [MIT License](LICENSE) that covers the project.

---

Thank you for contributing to Vim Plugin Manager! Your efforts help make this project better for everyone.