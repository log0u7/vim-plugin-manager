# Changelog

All notable changes to the Vim Plugin Manager will be documented in this file.

## [Unreleased] - v1.4
### Features
- Asynchronous jobs for background plugin installations and updates
- UI improvements with better progress indicators
- Enhanced error reporting with detailed diagnostics

### Bug Fixes
- Fixed inconsistent sidebar rendering on some terminal configurations
- Resolved issues with plugin installation path handling on Windows systems
- Fixed plugin reloading mechanism for certain plugin types

## [1.3.2] - 2025-04-09
### Improvements
- Enhanced error handling in module loading and plugin management
- Improved cross-platform compatibility for file operations
- More robust module detection and path resolution
- Better handling of local plugin installations

### Bug Fixes
- Resolved edge cases in submodule status tracking
- Improved error messages for plugin installation and removal
- Fixed path handling for plugins with special characters in names

### Refactoring
- Simplified and optimized utility functions
- Improved code modularity in add, remove, and update modules
- Enhanced logging and error reporting mechanism

## [1.3.1] - 2025-04-08
### Fixed
- Improved error handling for plugin removal process
- Fixed potential race condition during concurrent updates
- Corrected path handling for Windows environments during plugin copy operations
- Better handling of non-Git local plugin installations

### Changed
- Enhanced module update status detection with more accurate branch comparison
- Improved helptags generation for specific plugins
- More robust stashing of local changes during updates

## [1.3.0] - 2025-03-15
### Added
- Declarative configuration syntax with `PluginBegin`, `Plugin`, and `PluginEnd` blocks
- Advanced plugin options including branch, tag, and exec parameters
- Options dictionary syntax for plugin installation: `{'dir':'name', 'load':'start|opt', 'branch':'name', 'exec':'localscript --arguments'}`
- Local plugin installation support via filesystem paths
- Improved plugin reloading functionality
- More robust error handling and reporting

### Changed
- Redesigned sidebar interface with better formatting and organization
- Enhanced plugin status display with ahead/behind commit tracking
- Improved module cache system for better performance
- Restructured codebase into modular components

### Fixed
- Fixed issue with plugin removal leaving orphaned .git modules
- Resolved conflicts with doc/tags files during plugin updates
- Fixed path handling issues in Windows environments

## [1.2.0] - 2024-09-22
### Added
- Interactive sidebar interface with toggle command
- Keyboard shortcuts for common plugin operations
- Better visualization of plugin status with color coding
- Summary view to display pending plugin changes
- Optional plugins support (lazy loading)
- Support for custom sidebar width
- Plugin-specific helptags generation

### Changed
- Improved command structure with better argument handling
- Enhanced plugin repositories backup functionality
- Better submodule status tracking with additional status indicators

### Fixed
- Resolved issues with path handling in different environments
- Fixed plugin listing alignment for long plugin names

## [1.1.0] - 2024-05-03
### Added
- Configuration backup and restore functionality
- Multiple remote repository support
- Basic plugin status tracking
- Support for custom plugin directories
- More configuration options including vimrc path customization
- Better documentation with examples
- Support for both Vim and Neovim configurations

### Changed
- Improved error handling with more descriptive messages
- Enhanced command structure for better usability
- More efficient help documentation generation

### Fixed
- Resolving issues with Git submodule initialization
- Fixed directory permissions handling

## [1.0.0] - 2023-12-10
### Added
- Initial release with basic Git submodule management
- Plugin installation and removal via Git submodules
- Listing installed plugins
- Plugin update functionality
- Help documentation generation
- Support for Vim 8's native package system
- Basic configuration options