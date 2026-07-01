# Changelog

All notable changes to the Vim Plugin Manager will be documented in this file.

## [2.0.0] - 2026-07-01

### Breaking Changes
- **Dropped Windows support.** The project now targets Linux only
  (Debian, Ubuntu, Arch, Gentoo, RHEL/AlmaLinux/Rocky). All Windows-specific
  code paths removed: `has('win32')/has('win64')` branches in `async.vim`,
  `add.vim`, `core.vim` (3 functions), `backup.vim`, and
  `plugin/plugin_manager.vim`; `s:copy_files_windows()` (robocopy/xcopy)
  deleted; `~/vimfiles` default removed; `has('multi_byte')` dropped from
  `fancy_ui` default. See the Removed section below for the full list.

### Features
- Added `:PluginManager health` diagnostic command. Runs 9 read-only checks
  in the sidebar: git executable present, git version (>= 2.39), async
  support (+job/+channel), Vim version (>= 8.2), encoding (utf-8), vim dir
  is a git repo, log dir writable, submodules initialized and in sync,
  remotes configured. Each check renders an ok/warn/fail line via the
  standard UI API. Sidebar shortcut `H`. Wired into dispatch, completion,
  api.vim, ftplugin, and ui.vim usage(). Documented in README and
  doc/plugin_manager.txt.
- Tab completion for `:PluginManager`: sub-command names complete at position
  1; installed plugin names complete at position 2 for `remove`, `update`,
  `helptags`, and `reload`.

### Bug Fixes
- Fixed `async#git()` incorrectly passing `{}` (empty opts) to `start_job`
  instead of the caller's opts dict. Simplified to `start_job(cmd, a:opts)`
  directly.
- Fixed `plugin_manager#async#start_job(cmd, {'callback': X})` never calling
  the callback: the callback was stored in `s:jobs[id].opts.callback` but
  `s:process_job_completion` looked for it at `s:jobs[id].callback` (top-level).
  The callback in opts is now promoted to the top-level key during initialization.
- Fixed `async.vim` crash (`E121: Undefined variable: l:cmd`) in `s:spawn_job`:
  the job command was stored in `l:job.cmd` but referenced as the undefined
  `l:cmd`, crashing every real async job launch (update, check, status) in
  interactive Vim with `+job`.
- Fixed `restore` reporting success even when `git submodule init/update/sync`
  failed: each `git#execute` call now uses `throw_on_error=1`.
- Fixed `update` (single-plugin, sync path) never committing the updated
  submodule pointer after a successful pull.
- Fixed `:help plugin-manager` (hyphen form): the help tag `*plugin-manager*`
  was absent from `doc/plugin_manager.txt`.
- Fixed `cmd#complete()` calling the non-existent `git#get_modules()`; corrected
  to use `git#parse_modules()`.
- Fixed `git#find_module()` silently returning the wrong plugin on ambiguous
  partial matches for `update` and `reload`.
- Fixed `core.vim` SSH URL regex: `\\+` in single-quote string was a literal
  backslash+plus, making all `git@host:user/repo` URLs unrecognized.
- Fixed `check.vim` `s:check_sync`: `l:op_id` was conditionally assigned
  (`!silent`) but unconditionally referenced one line later, causing `E121`
  in silent+sync mode.
- Fixed `status.vim` async path: a missing plugin directory was resolved
  without decrementing `ctx.pending`, so the footer was never appended.

### Changed
- Replaced the hand-rolled regex parser in `parse_modules()` with native
  `git config -f <vim_dir>/.gitmodules --get-regexp` so git is the
  authoritative reader for `.gitmodules` (quoting, whitespace, encoding).
  The public contract is unchanged. Two new tests cover submodule names with
  dots and the whitespace-normalization guarantee.
- Eliminated the global `cd vim_dir` side effect from `ensure_vim_directory()`:
  the function is now a pure validation (no cwd mutation). All git commands
  pass `vim_dir` explicitly; all module paths use `abs_path` (absolute).
  A new `tests/cwd.vader` suite asserts that cwd is never mutated by any
  command.
- Lowered the documented minimum Git version from 2.40 to **2.39**, matching
  Debian Bookworm (the oldest fully-supported distribution). The codebase uses
  no git feature newer than 1.9.
- `git#find_module()` now accepts an optional second argument `strict` (default
  0). In strict mode a partial query matching more than one module throws
  `AMBIGUOUS_MATCH`.
- Sidebar `?` shortcut list now shows all mapped keys.
- Unified sidebar UI: all commands use `open_header()`/`footer()` helpers.
- `complete_operation()` accepts both legacy booleans and semantic keywords.
- `git.vim` `execute()` uses `shellescape()` for the `cd` prefix.
- `core.vim` `remove_path()` uses Vim's native `delete()` instead of `rm -rf`.
- `fancy_ui` default simplified to `&encoding ==# 'utf-8'` (dropped obsolete
  `has('multi_byte')` check).
- Minimum Git floor documented as 2.39 (Debian Bookworm proxy).

### Removed
- Windows support (all `has('win32')`/`has('win64')` branches): `shell_argv()`
  now unconditionally returns `['sh', '-c', cmd]`; `s:copy_files_windows()`
  (robocopy/xcopy) deleted; `~/vimfiles` default removed.
- Dead functions (0 callers): `core#format_error()`, `git#remove_submodule()`,
  `core#get_all_config()`, `ui#display_error()`, `ui#init()`,
  `git#execute_async()`, `git#update_all_submodules()`,
  `git#restore_all_submodules()`, `git#backup_config()`,
  `cmd/check#show_cached()`, `s:format_status_line()` in `status.vim`,
  `core#parse_options()`.
- 6 unused glyphs from `s:symbols` in `ui.vim`.
- Dead async option keys: `dir`, `ui_message`, `ui_show_output`.

### CI
- Multi-distro test matrix: AlmaLinux 9 (Vim 8.2 floor), AlmaLinux 10, Debian
  Bookworm/Trixie, Ubuntu 24.04/26.04, Arch Linux, Gentoo (non-blocking).
  Both GitHub Actions and GitLab CI. AlmaLinux 9 proves the Vim 8.2 floor.
- Real async smoke test (`make test-async`) under a pty (`script -qec`): Vim's
  event loop runs, job callbacks fire, three async code paths are exercised
  end-to-end: `start_job` with opts callback, `async#git`, and the concurrency
  queue. Runs on the same 7-distro matrix. Blocking on both CI systems.
- `vim-vint` linting: dedicated lint job in both CI systems; `.vintrc.yaml`
  enables correctness policies as errors.

### Documentation
- Documented the Vim 8.2 minimum as an intentional, permanent floor set by
  RHEL 9 / AlmaLinux 9 / Rocky 9 (Vim 8.2.2637, supported until 2032). A
  vim9script migration is explicitly deferred (dominant cost is git/network
  I/O, not script execution).
- Added "Supported platforms" section (Linux-only) to README, AGENTS,
  CONTRIBUTING, and doc/plugin_manager.txt.
- Added Mermaid architecture diagrams to CONTRIBUTING (static layers +
  dynamic `:PluginManager update` sequence diagram).
- Project Structure tree in CONTRIBUTING updated: alphabetical order, uniform
  descriptions, all 16 test files listed.

### Refactored (DRY)
- `core#require_vim_directory(component)`: new helper replacing a 3-line
  pattern at 12 call sites.
- `git#head_commit()` / `git#head_changed()`: centralize the
  `rev-parse HEAD + compare` pattern duplicated 5 times.
- `git#valid_modules()`: single source for the sorted-valid-modules list,
  replacing 4 duplicate sort+filter patterns across check/status/update/list.
- `core#parse_error()`: matchlist regex replaces fragile split/join.

### Tests
- 16 Vader test suites covering all command modules, core utilities, UI,
  async, git parsing, and cwd immutability.
- Real async smoke test (`tests/async_smoke.vim`) runs under pty with timers,
  non-skippable, exercises `start_job`, `async#git`, and the queue.

## [1.5.0] - 2026-06-22
### Features
- `check` and `update` (all) commands now use block-instant rendering with
  parallel async fan-out: all plugin lines appear at once with spinners, and
  resolve in place as jobs complete, matching the `status` command display.

### Changed
- Default `g:plugin_manager_sidebar_width` increased from 60 to 80.

### Improvements
- New shortcut `c` in the sidebar buffer for `:PluginManager check`.
- `check` and `check-updates` are now highlighted in the sidebar syntax.
- Usage/reminder sidebar now lists `helptags`, `c` (check), `?` (help)
  shortcuts alongside existing ones.
- After `update`/`add`, helptags are now generated silently and only for
  the plugins that were actually updated, instead of regenerating for all
  plugins with visible progress lines.
- Streamlined single-operation command UI (add, remove, reload, backup,
  restore): removed intermediate cosmetic steps, finish on rich result
  glyphs with short labels, and route verbose git output to the log
  instead of the sidebar.

### Bug Fixes
- Fixed `update` not actually applying plugin updates: the pull command used
  `origin/<branch>` as a refspec (e.g. `git pull origin origin/master`), which
  is invalid and left the plugin unchanged. The branch name is now correctly
  stripped of the `origin/` prefix before passing to `git pull`. The
  all-plugins path now uses the same per-module pull logic instead of `git
  submodule update --remote`. The UI reports `Updated` only when the plugin
  HEAD commit actually advances.

### CI
- Pushing a `vX.Y.Z` tag to GitHub triggers a workflow that builds a
  `.tar.gz` archive via `make archive` and publishes a GitHub Release with
  the asset and auto-generated release notes.

## [1.4.0] - 2026-06-17
### Features
- Update notifications: detect plugins with available updates and report them in
  the sidebar (`:PluginManager check`).
- Optional update checks on startup (`g:plugin_manager_check_on_startup`) and on a
  configurable interval (`g:plugin_manager_check_interval`), with a cache to avoid
  redundant network access. Disabled by default (opt-in).
- Optional automatic updates on startup (`g:plugin_manager_auto_update`), disabled
  by default (opt-in).
- Modern, non-blocking sidebar UI: operations render via buffer APIs without
  stealing focus or moving the user's cursor, with a dynamic spinner that only
  runs while operations are active (`g:plugin_manager_spinner_interval`).
- UI improvements with clearer progress indicators (`[i/N]`) for batch operations.
- Enhanced error reporting with detailed diagnostics from async jobs.

### Changed
- Dropped Neovim support: PluginManager now targets Vim 8.2+ only. Neovim users
  should use lazy.nvim, packer.nvim or vim-plug. A warning is shown if loaded
  under Neovim.
- Fully non-blocking update/status/check flows: the network `git fetch` runs as
  an async job and status is computed locally afterwards
  (`git#collect_status_local`), so long operations never freeze the editor.

### Improvements
- Simplified, lighter UI module with a unified operation API
  (`start_operation`/`update_operation`/`complete_operation`).
- Wired previously inert configuration options: `pull_strategy`,
  `auto_commit_on_update`, `max_concurrent_jobs`, `job_timeout`, `debug_mode`,
  `trace_commands`.
- Concurrency control for async jobs honoring `g:plugin_manager_max_concurrent_jobs`
  and `g:plugin_manager_job_timeout`.

### Bug Fixes
- Fixed `:PluginManager update` crashing on an undefined script-local symbol
  reference (`s:symbols`).
- Implemented the missing `plugin_manager#core#is_pm_error()` function that was
  called on every error path (would raise E117).
- Fixed the sync "update all" path to mark per-plugin operations complete and to
  commit the updated submodule pointers.
- Implemented the missing `s:check_log_rotation()` function so log rotation via
  `g:plugin_manager_max_log_size` and `g:plugin_manager_log_history_count`
  actually works instead of silently failing.
- Wired `async#cleanup(60)` into `s:process_job_completion` to prevent unbounded
  growth of the `s:jobs` dictionary.
- Removed dead public API functions `job_status()`, `job_info()`, and
  `wait_job()` from async.vim (unused; Vim built-in `job_status()` still used
  internally).
- Removed the inert `g:plugin_manager_progress_style` option (no longer wired
  in the 1.4.0 UI).

### Refactoring
- Migrated all command modules to the structured `plugin_manager#core#throw()`
  error API with component-specific codes (no more bare `throw 'PM_ERROR:...'`).
- Aligned all module version headers to 1.4.0.

### Testing
- Reworked the Vader test suite to match the actual command API and added
  coverage for core utilities, the update-check cache, `.gitmodules` parsing,
  and the non-blocking UI (cursor/focus preservation).
- Made the test runner use an absolute runtimepath so tests that change the
  working directory still resolve autoload functions.

### Documentation
- Added `AGENTS.md` and refreshed `CONTRIBUTING.md` (testing, error format,
  configuration, project structure).
- Documented the new commands and configuration in `README.md` and
  `doc/plugin_manager.txt`.

## [1.3.5] - 2025-04-12
### Improvements
- Enhanced documentation with more examples and clarification
- Improved user experience with clearer error messages
- Small UI refinements for better information display
- Minor performance optimizations in Git operation modules
- Better handling of path management on different platforms

### Bug Fixes
- Fixed minor log rotation issues on Windows systems
- Corrected behavior when handling plugins with special characters in names
- Improved error handling when Vim directory is not properly configured
- Fixed edge case in stashing local changes during plugin updates
- Resolved issues with command escaping in some shell environments

## [1.3.4] - 2025-04-11
### Improvements
- Merged refactorization branch with modular architecture into main
- Enhanced code organization with SOLID principles
- Improved error handling with structured error types
- Added better async operations support with unified API
- Strengthened cross-platform compatibility with robust path handling

### Bug Fixes
- Fixed edge case in plugin update detection for detached HEAD states
- Corrected path normalization issues on Windows systems
- Improved plugin removal process when git modules structure changes
- Fixed status detection when plugins are on custom branches

### Code Structure
- Reorganized codebase into functional modules with clear responsibilities:
  - core.vim: Core utilities, error handling, path management
  - git.vim: Git operations abstraction with comprehensive repository status
  - async.vim: Unified async API with Vim/Neovim compatibility
  - ui.vim: Enhanced user interface with progress indicators
  - api.vim: Public API façade with backward compatibility

## [1.3.3] - 2025-04-10
### Improvements
- Enhanced plugin update detection algorithm for more accurate updates
- Improved error handling and reporting in plugin operations
- Better cross-platform compatibility for file path handling
- Optimized module caching system for better performance

### Bug Fixes
- Fixed edge case in plugin branch detection during updates
- Resolved path handling issues with plugins containing special characters
- Improved stashing mechanism for local changes during updates
- Fixed handling of plugin removal when .git directory structure changes

### Documentation
- Updated installation instructions for better clarity
- Expanded examples for plugin configuration options
- Improved troubleshooting guidance in the help documentation

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