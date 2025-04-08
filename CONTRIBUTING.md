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
   - `plugin/plugin_manager.vim`: Defines commands, initializes global variables, and provides the main entry point function `plugin_manager#main()`.

2. **Core Command Handler**
   - `autoload/plugin_manager.vim`: Contains the main command parser and dispatcher.

3. **Modular Architecture**
   - `autoload/plugin_manager/modules.vim`: Acts as a façade that loads and coordinates specialized submodules.
   - `autoload/plugin_manager/ui.vim`: Handles all user interface operations and visualizations.
   - `autoload/plugin_manager/utils.vim`: Contains utility functions used throughout the codebase.

4. **Feature-specific Modules**
   - `autoload/plugin_manager/modules/add.vim`: Handles plugin installation logic.
   - `autoload/plugin_manager/modules/remove.vim`: Manages plugin removal operations.
   - `autoload/plugin_manager/modules/list.vim`: Implements plugin listing and status reporting.
   - `autoload/plugin_manager/modules/update.vim`: Manages plugin update operations.
   - `autoload/plugin_manager/modules/backup.vim`: Handles configuration backup and restore.
   - `autoload/plugin_manager/modules/helptags.vim`: Manages generation of helptags.
   - `autoload/plugin_manager/modules/reload.vim`: Handles plugin reloading operations.

5. **Filetype Support**
   - `ftdetect/pluginmanager.vim`: Defines filetype detection rules.
   - `ftplugin/pluginmanager.vim`: Sets buffer configuration and provides key mappings.
   - `syntax/pluginmanager.vim`: Defines syntax highlighting for the plugin interface.

### Control Flow

1. User commands are processed through `:PluginManager` which calls `plugin_manager#main()`.
2. `plugin_manager#main()` parses arguments and dispatches to appropriate module functions.
3. Module functions perform specific tasks using utilities from `plugin_manager/utils.vim`.
4. UI feedback is provided through functions in `plugin_manager/ui.vim`.

### Extending the Plugin

When adding new features:

1. **Determine the Appropriate Module**: New functionality should be placed in the most relevant module, or a new one if needed.
2. **Follow the API Pattern**: Public functions should be named `plugin_manager#modules#<module>#<function>()`.
3. **Use Utility Functions**: Leverage existing utility functions from `utils.vim` and UI functions from `ui.vim`.
4. **Add Documentation**: Update help docs and README.md with new functionality.
5. **Update Command Handling**: If adding a new command, update the command processing in `plugin_manager#main()`.

### Configuration System

The plugin uses several configuration variables defined in `plugin/plugin_manager.vim`:

- `g:plugin_manager_vim_dir`: Base directory for Vim configuration.
- `g:plugin_manager_plugins_dir`: Directory for storing plugins.
- `g:plugin_manager_start_dir`: Directory for auto-loaded plugins.
- `g:plugin_manager_opt_dir`: Directory for optional (lazy-loaded) plugins.
- `g:plugin_manager_vimrc_path`: Path to vimrc file.
- `g:plugin_manager_sidebar_width`: Width of the sidebar UI.
- `g:plugin_manager_default_git_host`: Default Git host for short plugin names.
- `g:plugin_manager_fancy_ui`: Controls whether to use Unicode symbols in the UI (true by default if supported).

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
│   ├── plugin_manager.vim           # Main autoload file (command dispatcher)
│   └── plugin_manager/              # Core functionality modules
│       ├── modules.vim              # Module façade and API
│       ├── ui.vim                   # User interface components
│       ├── utils.vim                # Utility functions
│       └── modules/                 # Feature-specific modules
│           ├── add.vim              # Plugin installation
│           ├── backup.vim           # Configuration backup and restore
│           ├── helptags.vim         # Help documentation generation
│           ├── list.vim             # Plugin listing and status
│           ├── reload.vim           # Plugin reloading
│           ├── remove.vim           # Plugin removal
│           └── update.vim           # Plugin updating
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
├── README.md                        # Project overview and usage information
├── CONTRIBUTING.md                  # Contribution guidelines (this file)
├── CHANGELOG.md                     # History of changes and versions
└── LICENSE                          # License information
```

## License

By contributing to this project, you agree that your contributions will be licensed under the same [MIT License](LICENSE) that covers the project.

---

Thank you for contributing to Vim Plugin Manager! Your efforts help make this project better for everyone.