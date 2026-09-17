# Changelog

All notable changes to the Vim Plugin Manager will be documented in this file.

## [Unreleased]

### Added
- Contributor workflow: GitHub issue forms (bug report, feature request),
  pull request template, `copilot-instructions.md` for the automatic Copilot
  code review, and a stable `ci-green` CI check aggregating the whole suite.

### Changed
- CONTRIBUTING.md documents GitHub Flow + tags: one protected `main`
  (required checks, resolved conversations, no force push, squash merges),
  fork + PR for external contributors, `--no-ff` direct merges for
  maintainers, and an explicit test-first (TDD) guidance section.

## [2.2.3] - 2026-09-17

### Fixed
- **Fetch failures are no longer masked as "Up-to-date"**: `check` and
  `status` fetched with `2>/dev/null || true`, converting a network
  failure into a stale-ref comparison that reported a fake Up-to-date
  (also violating the single-invocation command rule). Fetch failures now
  surface as an explicit "Fetch failed" line plus a log entry
  (regression test in `tests/check.vader`).
- **`detail` logging actually logs**: `ui#log_detail` gated on
  `exists('*plugin_manager#core#log#debug')`, which returns 0 for a
  not-yet-loaded autoload function, silently disabling every detail log
  until log.vim happened to be loaded by something else. The call is now
  direct (calling an autoload function triggers its load). Surfaced by
  the fetch-failure and auto-commit regression tests.
- **Auto-commit failures are logged, never silent**: the pointer
  add/commit calls in both update flows ran with errors discarded; a
  failed commit (missing identity, failing hook) left `.gitmodules`
  modified with zero trace. Failures now go to the detail log
  (regression test in `tests/update.vader` with a failing pre-commit
  hook).
- **Backup honors its documentation**: the commit now stages untracked
  files too (`git add -A` instead of `commit -am`: new config files were
  silently never backed up), and the push goes to every configured
  remote instead of only `origin`, with a partial-push warning when some
  remotes fail (regression tests in `tests/backup.vader`).
- **Stash includes untracked files during update** (`git stash push -u`):
  an untracked file the incoming pull wants to write aborted the pull
  after the "protective" stash (regression test in `tests/update.vader`).
- **Bare `:PluginManager remove` reports MISSING_ARGS** instead of
  "Unknown command: remove" (the dispatcher required two args before
  routing; regression test in `tests/dispatch.vader`).
- **Lazy loading reports the real error**: `lazy#invoke` used a catch-all
  that mislabeled any runtime error inside the freshly loaded plugin as
  "command is not provided by plugin". Real errors now propagate; the
  missing-command case is detected with `exists()` (regression tests in
  `tests/lazy.vader`).
- **GC renders the orphan list in the sidebar** instead of `:messages`
  (the header went to the sidebar, the list to messages).
- **Remove treats user input literally**: partial module matching used
  the user string as a vim regex (`=~?`), throwing on malformed input
  mid-discovery; it now uses literal case-insensitive substring matching,
  consistent with `git#find_module` (regression test in
  `tests/remove.vader`).
- **Sidebar is a real scratch buffer**: opening it used
  `vnew PluginManager`, which loads an existing FILE named PluginManager
  from the cwd and hijacks its buffer; the buffer is now created unnamed
  and renamed (regression test in `tests/ui.vader`).
- **Escaped the vim dir in regex constructions**: `escape(..., '/.\')`
  missed `[`, `]`, `*`, `^`, `$`, `~`; a vim dir containing them broke
  path normalization matching (`core/util.vim`, `git.vim`). No dedicated
  test: purely additive escaping, exercising it requires a vim dir with
  regex metacharacters on disk.
- **health goes through `git#execute`** for the version probe instead of
  a raw `system()` call (consistency; `tests/health.vader` covers the
  output).

## [2.2.2] - 2026-09-17

### Fixed
- **Local installs with `on`/`for` are reachable again**: `:PluginAdd
  <path> {'on': [...]}` copied the plugin to `opt/` but never registered
  the lazy placeholders, leaving it silently unreachable. The local path
  now calls `lazy#register` like the remote path (regression test in
  `tests/add.vader`).
- **One malformed lazy trigger no longer aborts the declare batch**:
  invalid `on`/`for` entries (wrong type, bad command name) were
  interpolated raw into `:command!`/`:autocmd!` and the resulting throw
  killed installation of every remaining plugin in the block. Invalid
  triggers are now skipped with a warning; valid ones still register
  (regression test in `tests/lazy.vader`).
- **Detached submodules are skipped, never pulled**: a detached HEAD
  without a tag/commit declaration fell through to the pull flow, which
  failed noisily or could fast-forward the pin away (the doc already
  claimed "skipped"). Both update paths now skip detached modules with an
  explicit message; regression test in `tests/pin.vader`.
- **GC can no longer aim the removal at the vim dir**: a corrupt
  `.gitmodules` entry with an empty `path` produced an orphan with an
  empty path, whose removal fallback resolved to the vim dir itself.
  Orphan collection skips empty name/path values and the batch removal
  entry point refuses empty arguments (`tests/gc.vader`).
- **Removal reports the truth**: `remove_module` completed with "ok"
  regardless of the actual outcome (failures were neither thrown nor
  logged), so batch summaries could count removals that never happened.
  The removal now verifies the directory is gone, returns the outcome,
  and only commits on success; GC counts real removals
  (`tests/gc.vader`).

## [2.2.1] - 2026-09-17

### Fixed
- **`update all` pin path now commits the pointer**: the all-plugins pin
  branch never recorded the pre-checkout commit, so a pin move reported
  "Up-to-date", was excluded from `updated_modules`, and left the parent
  repo with a dirty gitlink (no pointer commit, no helptags). The
  pre-checkout commit is now recorded like the pull path; regression test
  asserts a clean parent repo and the `Update Modules` commit after a pin
  move (`tests/pin.vader`).
- **Pin map collisions on shared basenames**: pins were keyed by short
  name first, so `orgA/vim-foo` and `orgB/vim-foo` (both extracting to
  `vim-foo`) made the last declaration's pin win for BOTH modules. Pin
  resolution now matches the module URL first (exact per-module match),
  falling back to the name key for URL drift. Regression test with two
  forges sharing a basename (`tests/pin_collision.vader`).
- **`file://` installs register the submodule again**: the file transport
  lift (git >= 2.38.1) was applied to the clone only, so `git submodule
  add file://...` failed after a successful clone and left an unregistered
  plugin dir invisible to update/gc. The lift now covers the registration
  (`git#add_submodule`). Regression test installs through a `file://`
  declaration without any fixture protocol config (`tests/declare.vader`).
- **Sync declare path probes the right pack dir for lazy plugins**: the
  synchronous fallback passed raw options to the exists() probe, which
  looked in `start/` while `on`/`for` declarations install to `opt/`:
  every vimrc re-source of a lazy declaration errored SUBMODULE_EXISTS.
  Options are normalized once at the top of `s:process_plugin` (same as
  the async path). Regression test re-declares an installed lazy local
  plugin and asserts a clean skip (`tests/declare.vader`).
- **Re-entrant `PluginEnd` runs keep in-flight installs**: `PluginBegin`
  wiped the pending-installs map, making the double-clone guard
  unreachable (a reload re-runs Begin first). The map now survives Begin
  and is pruned by the clone callbacks. Unit-tested via test-only helpers
  (`declare#_pending_test_set`/`_pending_names`, same pattern as
  `lazy#_reset`).

## [2.2.0] - 2026-09-17

### Security
- **Escaped remote names in `git#add_remote`**: the remote name was
  interpolated unescaped into `git remote add/set-url` commands; a name
  containing shell operators executed arbitrary commands. Remote names are
  now `shellescape`d like every other argument (regression test in
  `tests/remote.vader`).
- **Escaped module names in the single-plugin auto-commit**: the
  `update all` path committed pointer changes with three separate escaped
  calls, but the single-plugin path built one compound `&&` command with the
  module name interpolated raw into a double-quoted commit message. A module
  name containing `"` broke the quoting and the pointer commit silently
  failed; the name is now escaped and the compound command is gone
  (regression test in `tests/update.vader`).

### Added
- **Version pinning re-asserted on update**: `tag` and `commit` declarations
  in the vimrc are the source of truth. `:PluginManager update` fetches tags
  and checks out the declared revision for pinned plugins instead of pulling
  (stash/restore and pointer commit included); bumping the tag in the vimrc
  moves the submodule on the next update. New `commit` option (SHA pin) on
  `:PluginManager add` and in the declarative block. Version precedence:
  branch > commit > tag. Unresolvable pins now fail the install loudly
  (`CHECKOUT_FAILED`) instead of silently staying on the default branch.
  (`tests/pin.vader`)
- **On-demand (lazy) loading**: new `on` (command triggers) and `for`
  (filetype triggers) options, vim-plug style, on top of Vim 8 native
  packages. Placeholders `packadd` the plugin on first use and re-dispatch
  the invocation; both options imply `load: 'opt'`. (`tests/lazy.vader`)
- **Parallel background install**: the declarative block installs missing
  plugins with parallel `git clone` jobs through the existing concurrency
  queue; `PluginEnd` no longer blocks the first run. Each completed clone is
  registered as a submodule (pointer committed) from its callback;
  re-entrant `PluginEnd` runs skip in-flight installs. Sequential fallback
  without +job/+channel and under `g:plugin_manager_test_force_sync`.
  (`tests/install_smoke.vim`, new `make test-install-smoke` pty target)
- **`file://` remotes**: local bare repositories are accepted as plugin URLs
  (testing, air-gapped installs). The file-transport restriction is lifted
  for these trusted vimrc URLs on clone.
- **`:PluginManager gc`**: collects registered submodules that are no longer
  declared in the vimrc, with a single confirmation (`-f` to skip). Refuses
  to run when the vimrc has no Plugin declarations; never collects the
  manager itself or `g:plugin_manager_gc_exclude` entries. (`tests/gc.vader`)
- New `vimrc.vim` module: parses `Plugin` declarations from the vimrc
  (shared by update pin re-assertion and gc). (`tests/vimrc.vader`)

### Changed
- Tests: the async and install smoke sessions no longer load the developer's
  own `~/.vim` pack plugins (`packpath` isolation), which also unblocks
  `quit!` on developer machines.
- `tests/dispatch.vader` completion count updated for the `gc` sub-command.
- Test fixtures point the bare repo HEAD at `refs/heads/main` at setup:
  git >= 2.52 does not infer the default branch of a local bare clone, so
  `git submodule add` failed with "does not have a commit checked out"
  (found in an AlmaLinux 9 / Vim 8.2 / git 2.52 E2E pass).

### Documentation
- README and `:help`: declarative options (`on`/`for`/`commit`), pinning
  semantics, lazy loading, `gc`, parallel install; fixed the `dir`/`tag`
  usage examples that copied vim-plug semantics (`{'dir': '~/.fzf'}` would
  create a literal `~` directory, `{'tag': '*'}` would run
  `git checkout '*'`).

## [2.1.8] - 2026-09-16

### Changed
- ui usage: 'Check for available updates' -> 'Check for updates'

### Tests
- tests/log.vader: unit tests for core/log (entry format internal/EXTERNAL,
  debug gating, clear)
- tests/util.vader: unit tests for core/util (extract_plugin_name variants,
  convert_to_full_url, is_local_path semantics, ensure_directory,
  remove_path safety contract)
- tests/README.md: coverage map by layer (unit/integration/smoke)

## [2.1.7] - 2026-09-16

### Fixed
- **Config options silently ignored**: `ui.vim` called
  `get_config('plugin_manager_sidebar_width', ...)` and
  `get_config('plugin_manager_spinner_interval', ...)` with an already
  prefixed name. Since `get_config` prepends `plugin_manager_` itself, the
  lookups targeted `g:plugin_manager_plugin_manager_*` (never set) and
  always fell back to the defaults: user overrides of `sidebar_width` and
  `spinner_interval` were dead since the 2.x refactor. Call sites now pass
  bare names, and a static Vader guard forbids the pattern.

### Tests
- New `tests/config.vader` (unit: get_config contract; static guard: no
  double-prefixed call sites; integration: sidebar_width honored).
- `tests/ui.vader`: sidebar opens at the configured width (integration).

## [2.1.6] - 2026-09-16

### Fixed
- **CI: silent exit 1 in headless mode**: the generated `.vaderrc.vim` set
  `packpath=` (empty). On several Vim builds (Debian trixie 9.1.1230,
  Ubuntu 26.04, Gentoo) that made `vim -es` exit 1 without any error
  message, failing the test jobs even when the whole Vader suite passed
  (123/123). The vimrc now removes only the developer entry
  (`set packpath-=$HOME/.vim`), which keeps the test session isolated from
  the local `~/.vim` pack plugins without tripping the exit code.
- `.vaderrc.vim` regeneration: the rule now depends on `Makefile` and is
  `.PHONY`, so the file is always regenerated for the current environment
  (a container bind mount and a developer shell used to reuse each other's
  stale copy, pointing at the wrong paths).

### Documentation
- README "Custom Plugin Configurations" and "Example Plugin
  Configurations": use MyVim as the real-world illustration (real extracts
  from `plugin/plugin_nerdtree.vim`, `plugin/vim_mappings.vim` and the
  secrets pattern) instead of throwaway snippets.

## [2.1.5] - 2026-09-16

### Fixed
- **Header bars sized to the title**: the sidebar header separator was a
  fixed 20-character bar, shorter than titles such as
  `PluginManager Commands:` (23 chars). Header, usage and
  update-notification bars now repeat the separator glyph
  `strdisplaywidth(title)` times (multibyte-safe), restoring the dynamic
  underline behavior.

### Tests
- ui.vader: regressions for header/usage bar width (bar covers the whole
  title, uniform glyphs, wider than the old fixed bar).

## [2.1.4] - 2026-09-16

### Fixed
- **PMPath syntax pattern**: the sidebar `pluginmanager.vim` syntax matched
  an unescaped `~/` in the path pattern. In Vim patterns, `~` is the
  last-substitute atom: when no previous substitution existed, the
  `:syntax` command raised E33, aborting the whole syntax file and crashing
  `:PluginManager health` ("Unexpected error: Vim(syntax):E33"). The tilde
  is now escaped (`\~`).

### Changed
- **Test isolation**: the generated `.vaderrc.vim` now sets `packpath=`
  so the local test session no longer loads the developer's own
  `~/.vim` pack plugins (made `make test-ci` environment-dependent).

### Documentation
- README: real-world example section pointing to MyVim (configuration
  plugin managed with the manager, declared last in the declarative block).

## [2.1.3] - 2026-07-06

### Removed
- **vim-vint linting from CI**: the `vim-vint` linter is unmaintained and
  incompatible with Python 3.14 (`pkg_resources` removed from stdlib). The
  lint jobs in `.gitlab-ci.yml` (GitLab) and `.github/workflows/test.yml`
  (GitHub Actions) have been removed. `.vintrc.yaml` is kept for optional
  local use. The test suite (120/120, 239 assertions) and async smoke test
  (13/13) remain the canonical quality gate.

## [2.1.2] - 2026-07-05

### Changed
- **Directory scoping**: `git#execute` now injects `git -C <dir>` instead
  of `cd <dir> && <cmd>`. The codebase now uses a single idiom for
  scoping git commands (`git -C`), matching the async call sites and test
  fixtures. Non-git commands are rejected with `NOT_GIT_COMMAND`
  (use `core#util#run_in_dir` instead).
- `git#execute` is now git-only: any command not starting with `git `
  throws `PM_ERROR:git:NOT_GIT_COMMAND`. Four non-git callers (rsync,
  cp -R, cp, exec hooks) were migrated to `core#util#run_in_dir`.
- Added `core#util#run_in_dir(cmd, dir)` for scoping arbitrary shell
  commands via `cd <dir> && <cmd>`. Returns `{success, output}`.

### Fixed
- `remove.vim`: split `git commit -m X || git commit --allow-empty -m X`
  compound command into two sequential calls, enabling the `git -C`
  injection (a single `-C` prefix would scope only the first invocation).

## [2.1.1] - 2026-07-05

### Fixed
- **Sync/async duplication**: removed dedicated `*_sync` functions from
  update.vim, status.vim, and check.vim. `async#start_job` has a built-in
  synchronous `system()` fallback when `+job` is unavailable or
  `g:plugin_manager_test_force_sync` is set (headless test support).
- **`submodule foreach` protocol restriction**: replaced
  `submodule foreach --recursive "git fetch origin"` with per-module
  `git -C <path> fetch origin` calls to avoid CVE-2022-39253 blocking
  file:// transport on git >= 2.38.1.
- **Multi-byte truncation**: replaced byte-slicing `l:name[:(max-4)]`
  with `strcharpart(l:name, 0, max-4)` in `format_plugin_line`.
- **Missing argument guard**: added explicit `MISSING_ARGS` check in
  cmd.vim for `add` without a URL.
- **Auto-commit scope**: update commands now stage only `.gitmodules` +
  updated module paths instead of `git commit -am`, avoiding sweeping
  unrelated tracked changes in vim_dir.
- **Test runtime path collision**: changed `runtime!` (all matches) to
  `runtime` (single match) for async.vim loading in tests. An installed
  copy at `~/.vim/pack/.../vim-plugin-manager/` was shadowing the
  project version's `async#supported()` function (missing the
  `g:plugin_manager_test_force_sync` check), preventing the sync
  fallback from activating in headless mode.

## [2.1.0] - 2026-07-05

> **Semver note**: this tag adds public API (`api#view_log()`, `api#clear_log()`,
> three new autoload namespaces). Per Semantic Versioning 2.0.0 the correct level was
> MINOR, not PATCH. The initial v2.0.1 tag was retracted and replaced by v2.1.0
> (note: per semver spec, published releases should not be modified but superseded;
> this exception is acknowledged and future tags will not be retracted). The `core#*`
> functions were removed without a compat shim because they are internal (see
> public API definition in AGENTS.md). For a true deprecation of public API, a shim
> would be kept for at least one MINOR.

### Added
- Public API methods `api#view_log()` and `api#clear_log()`, wired to
  `:PluginManagerViewLog` and `:PluginManagerClearLog` commands.
- `core/log.vim` sub-module for log management (write, get_path, clear,
  view, debug, trace, rotation).
- `core/cache.vim` sub-module for update check cache (read, write, TTL).
- `core/util.vim` sub-module for paths, config, URL parsing, filesystem
  ops, and plugin options.

### Changed
- Split `core.vim` into `core/{log,cache,util}.vim` following single
  responsibility. `core.vim` now contains only error handling (`throw`,
  `handle_error`, `parse_error`, `is_pm_error`, `log_error_internal`).
- Reindented `plugin/plugin_manager.vim` to 2-space project standard.

### Fixed
- **Async completion race**: jobs now complete only after both `exit_cb`
  (process exited) and `close_cb` (channel closed) fire. Previously,
  `exit_cb` alone could trigger completion before all output was read,
  causing truncated results. A safety net falls back to exit-only when
  no channel is available. (Reported as intermittent truncation in
  large-output jobs.)
- Removed dead `s:exited_with_callback` state dict (written and cleaned
  but never read).

### Removed
- Per-file `Version:` headers from all 23 `.vim`/`.txt` files.
- `make update-version` Makefile target (no longer needed).
- Outdated legacy UI helpers `start_task`, `update_task`, `complete_task`.

### Removed (internal refactor)
- `core#<function>` direct calls (non-error functions moved to
  `core/{log,cache,util}#*`). These were internal functions; no compat
  shim was provided because the public API surface (`api.vim`, commands,
  `g:plugin_manager_*` variables) is unchanged. External code that
  relied on internal functions should migrate to `api.vim`.

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