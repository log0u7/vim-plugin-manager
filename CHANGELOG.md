# Changelog

All notable changes to the Vim Plugin Manager will be documented in this file.

## [Unreleased]

### Features
- Tab completion for `:PluginManager`: sub-command names complete at position 1;
  installed plugin names (from `.gitmodules`) complete at position 2 for
  `remove`, `update`, `helptags`, and `reload`.

### Bug Fixes
- Fixed `:help plugin-manager` (hyphen form): the help tag `*plugin-manager*`
  was absent from `doc/plugin_manager.txt`; only `*plugin_manager.txt*`
  (underscore) existed, so `:help plugin-manager` silently failed after
  helptags generation.
- Fixed `cmd#complete()` calling the non-existent `git#get_modules()`;
  corrected to use `git#parse_modules()` and extract `short_name` from each
  valid module entry.
- Fixed `git#find_module()` silently returning the wrong plugin on ambiguous
  partial matches for `update` and `reload`. Both commands now pass `strict=1`
  so an ambiguous query throws `AMBIGUOUS_MATCH` and is shown as an error in
  the sidebar instead of silently operating on a random match.

### Changed
- Sidebar `?` shortcut list now shows all 10 mapped keys (`q l s S u c b r h R ?`);
  previously only 7 were listed and `S` (Summary), `b` (Backup), `r` (Restore),
  `R` (Reload) were omitted despite being mapped in `ftplugin/pluginmanager.vim`.
- `CONTRIBUTING.md`: Development Workflow steps were mis-ordered (steps
  `1. Ensure you're working...` through `7. Create a pull request` appeared
  after `## Releases` instead of under `## Development Workflow`). Section
  order is now: Development Workflow (description + steps) -> Releases -> Pull
  Request Process.
- `git#find_module()` now accepts an optional second argument `strict` (default
  0). In strict mode (`1`) a partial query matching more than one module throws
  `AMBIGUOUS_MATCH` instead of silently returning the first hit. Exact matches
  (by `short_name`, path, or submodule key) are always unambiguous and
  unaffected by the flag. The default of 0 preserves historical behaviour for
  all callers that have not opted in (`helptags`, `remove`'s internal
  `s:find_module` wrapper).

### Removed (dead code, YAGNI)
- `plugin_manager#core#format_error()`: 0 callers in the entire codebase.
- `plugin_manager#git#remove_submodule()`: 0 callers; `cmd/remove.vim`
  implements the removal flow directly.
- `plugin_manager#core#get_all_config()`: built a 15-key dict for a single
  caller that used only 3 values; replaced with 3 direct `get_config()` calls
  in `get_plugin_dir()`.
- Dead branch in `parse_error()`: the LEGACY path for bare `throw 'PM_ERROR'`
  strings was unreachable (all throws go through `core#throw`, which always
  emits the 4-part format).
- Dead branch in `handle_error()`: re-split and re-join of the error string
  after the LEGACY path was removed; now simply distinguishes internal vs
  external errors for logging.
- 6 unused glyphs from `s:symbols` in `ui.vim` (`bullet`, `chevron_right`,
  `chevron_down`, `vertical`, `corner`, `horizontal`): 0 references outside
  the table itself.
- 3 unused option keys in `async#git()` / `s:spawn_job()`: `dir`,
  `ui_message`, `ui_show_output` - none of the 8 call sites ever set them.

### Refactored (DRY)
- `core#parse_error()`: replaced fragile `split(':')[0:2]` + `join([3:])` with
  a single `matchlist()` regex, correctly capturing messages that contain `:`
  (e.g. URLs) without a split/rejoin dance.
- `core#require_vim_directory(component)`: new helper that combines
  `ensure_vim_directory()` with a structured `NOT_VIM_DIR` throw; replaces
  the identical 3-line pattern that appeared at 12 call sites.
- `git#head_commit(path)` / `git#head_changed(path, before)`: two small
  helpers that centralize the `rev-parse HEAD + substitute + compare` pattern
  previously duplicated 5 times across `update.vim` and `git.vim`.

### CI
- `release.yml` version header bumped from 1.5.0 to 1.6.0.

### Tests
- `tests/dispatch.vader`: 5 new cases covering `cmd#complete()` - position-1
  sub-command listing, prefix filtering, unmatched prefix, position-2 plugin
  name listing, and position-2 prefix filtering.
- `tests/check.vader`: 1 new case verifying that `check` in silent mode still
  writes the update-check cache (`write_check_cache` called via `s:finish()`
  regardless of the `silent` flag).

## [1.6.0] - 2026-06-30

### Bug Fixes
- Fixed `core.vim` SSH URL regex: `\\+` in single-quote string was a literal
  backslash+plus, making all `git@host:user/repo` URLs unrecognized and
  rejected. Corrected to `.\+` so SSH remotes work as expected.
- Fixed `async.vim` job argv: `['sh', '-c', cmd]` was hardcoded, breaking all
  async operations silently on Windows. The new `plugin_manager#async#shell_argv()`
  helper returns `['cmd.exe', '/c', cmd]` on win32/win64 and `['sh', '-c', cmd]`
  on all other platforms.

### Changed
- Unified sidebar UI across all commands: every command now uses the shared
  `plugin_manager#ui#header()` / `open_header()` helpers instead of
  duplicating the `[title, separator, '']` pattern inline.
- Added `plugin_manager#ui#footer()` helper for consistent summary lines at
  the end of each command (`update`, `status`, `check`, `add`, `remove`,
  `backup`, `restore`, `reload`, `helptags`, `remote`).
- `plugin_manager#ui#complete_operation()` is now backwards-compatible: it
  accepts either a legacy boolean (0/1) or a semantic keyword (`'ok'`,
  `'fail'`, `'warn'`, `'info'`, `'skip'`, `'pending'`), all mapped to their
  glyph via the new `s:status_glyphs` table (single source of truth).
- Completion semantics are now consistent across commands: "Up-to-date" and
  "On custom branch" use `info`/`skip` glyphs (previously rendered with a
  success tick), "Missing" and "N commits behind" use the warning glyph in
  `check`, and `update`/`check`/`status` agree on the same visual language.
- `status.vim` `s:status_symbol()` now delegates to the centralized
  `plugin_manager#ui#get_status_glyph()` instead of maintaining a separate
  local glyph map.
- `remote.vim` rewritten to the project standard: 2-space indentation,
  `open_header()`, `start_operation()` / `complete_operation()`, footer.
- `syntax/pluginmanager.vim` resynchronized with the actual output of the UI:
  removed dead rules (`[DONE]`/`[FAILED]`/`[RUNNING]`, progress bars,
  `BEHIND`/`AHEAD`/`DIVERGED`); added rules matching real glyphs
  (✓ ✗ ⚠ ℹ ○ →), status labels ("Up-to-date", "Missing",
  "On custom branch", ...), and footer lines.
- `core.vim` `remove_path()` now uses Vim's native `delete()` instead of
  shelling out to `rm -rf`/`rmdir`, removing the OS-shell dependency.
- `git.vim` `execute()` now uses `shellescape()` for the `cd` directory
  prefix, consistent with the async path (`async.vim`).
- `git.vim` `repository_exists()` no longer appends `> /dev/null 2>&1`;
  `system()` already captures output, so only the exit code matters.
- `add.vim` copy helpers: replaced GNU-only `cp --parents` / broken
  `xcopy /EXCLUDE:.git` with `cp -R` (BSD/GNU portable) + `delete(.git, 'rf')`,
  and a properly-written xcopy exclusion file for Windows.
- `async.vim` `cd` prefix is now `cd /d ...` on Windows and `cd ...` on POSIX.
- `sidebar_width` fallback defaults aligned to 80 throughout (`ui.vim`,
  `core.vim`) matching the entry-point declaration.
- Copyright year updated to 2026 in `doc/plugin_manager.txt`.
- `ftplugin/pluginmanager.vim` indentation normalized to 2 spaces.

### Removed
- `plugin_manager#ui#display_error()`: was never called anywhere in the
  codebase; errors go through `core#handle_error()`.
- `plugin_manager#ui#init()`: was a no-op kept for backwards compatibility;
  callers that relied on it can remove the call safely.
- `plugin_manager#git#execute_async()`: had no callers; async dispatch goes
  directly through `plugin_manager#async#start_job()`.
- `plugin_manager#git#update_all_submodules()`: had no callers; the update
  command uses per-module `update_submodule()` with concurrency control.
- `plugin_manager#git#restore_all_submodules()`: had no callers; `cmd/restore.vim`
  implements the restore flow directly.
- `plugin_manager#git#backup_config()`: had no callers; `cmd/backup.vim`
  implements the backup flow directly.
- `plugin_manager#cmd#check#show_cached()`: had no callers in the dispatch
  or API layer.
- `s:format_status_line()` in `cmd/status.vim`: had no callers.
- `plugin_manager#core#parse_options()`: was unwired (no callers); option
  parsing goes through `process_plugin_options()`.

### Bug Fixes (continued)
- Fixed `check.vim` `s:check_sync`: `l:op_id` was conditionally assigned
  (`!silent`) but unconditionally referenced one line later, causing `E121`
  in silent+sync mode.
- Fixed `status.vim` async path: a missing plugin directory was resolved
  without decrementing `ctx.pending`, so `s:maybe_finalize_status` was never
  called and the footer was never appended.

### Documentation
- Documented three previously-undocumented live config options:
  `g:plugin_manager_debug_mode`, `g:plugin_manager_trace_commands`, and
  `g:plugin_manager_show_deprecation_warnings` (in `doc/plugin_manager.txt`
  and `README.md`).
- Updated `AGENTS.md` example header from `1.4.0` to `1.5.0`.
- Fixed Makefile help text to mention `README.md` alongside `*.vim`/`*.txt`.

### Tests
- Added `tests/async.vader`: covers `shell_argv()`, `start_job()` sync
  fallback, and concurrency queue serialization (guarded for headless mode).
- Added `tests/update.vader`: covers update-all and update-specific against
  a local bare repo fixture (no network); sync path forced deterministically
  via `async#supported()` stub; assertions validate real submodule HEAD commit,
  not just sidebar text; stash pop correctness tested (local changes survive).
- Added `tests/dispatch.vader`: covers `cmd#dispatch()` routing, unknown
  command handling, empty-plugin-set commands, and legacy arg translation
  (stubs `api#add` to assert dict shape, not just absence of MISSING_ARGS).
- Added `tests/remove.vader`: covers ambiguous fuzzy match refusal (both
  plugins preserved), exact-name removal, and unknown-plugin no-crash.
- Added `tests/backup.vader`: covers no-change push, change-commit-push,
  and no-remote graceful handling via local bare repo fixture.
- Added `tests/restore.vader`: covers submodule re-initialization from
  `.gitmodules` (missing working-tree) and missing-`.gitmodules` fallback.
- Extended `tests/core.vader`: added SSH URL passthrough and
  `extract_plugin_name` cases for `git@` remotes.
- Extended `tests/basic.vader`: added `shell_argv` shape assertion.

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