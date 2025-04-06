# Changelog

All notable changes to the Vim Plugin Manager will be documented in this file.

## [Unreleased] - v1.4
### Features
- Asynchronous jobs for background plugin installations and updates
  - Added compatibility checks for Vim 8+ and Neovim
  - Implemented non-blocking operations for plugin installation, updates, and removal
  - Added job sequencing for chained command execution
  - Added graceful fallback to synchronous operations for older Vim versions
  - Fixed initial UI blocking by immediately displaying progress indicators
  - Improved job tracking with unique identifiers and proper lifecycle management
- UI improvements with better progress indicators
  - Added real-time progress updates with spinners during long operations
  - Implemented dedicated job progress section in the sidebar
  - Added visual checkmarks and error indicators for operation results
  - Added proper job tracking with elapsed time display
  - Fixed duplicate entries in job progress display
  - Added batch processing for large operations to maintain UI responsiveness
- Enhanced error reporting with detailed diagnostics
  - Improved error handling with specific failure messages
  - Better output formatting for command results
  - Individual status reporting for multi-step operations
- New modular system for job handling in autoload/plugin_manager/jobs.vim
  - Centralized job management with dictionary-based job storage
  - Added automatic cleanup of completed jobs
  - Improved memory management for long-running sessions

### Bug Fixes
- Fixed inconsistent sidebar rendering on some terminal configurations
- Resolved issues with plugin installation path handling on Windows systems
- Fixed plugin reloading mechanism for certain plugin types
- Fixed UI blocking during the beginning of asynchronous operations
- Fixed duplicate progress lines in job status section
- Improved cleanup of temporary job data after completion
- Fixed progress display in terminal environments with limited Unicode support
- Fixed section detection in the sidebar buffer for more reliable updates

## [1.3.0] - 2025-03-15
### Added
- Declarative configuration syntax with `PluginBegin`, `Plugin`, and `PluginEnd` blocks
- Advanced plugin options including branch, tag, and exec parameters
- Options dictionary syntax for plugin installation: `{'dir':'name', 'load':'start|opt', 'branch':'name'}`
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