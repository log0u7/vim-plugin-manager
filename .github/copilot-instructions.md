# Copilot review guidance

Project context for reviewing pull requests in this repository.

## Hard constraints (reject changes that violate these)

- **Linux only**: Windows/macOS code paths, `\r\n` handling or OS-specific
  tools are out of scope. Supported: Debian, Ubuntu, Arch, Gentoo,
  RHEL/AlmaLinux/Rocky.
- **Vim 8.2 floor**: no Vim 9+ features, no vim9script, no `def`/`var`.
  The guard `if v:version < 802` in `plugin/plugin_manager.vim` is
  intentional and must not change. Neovim is not supported.
- **No network at startup**: every network operation (`git fetch`, ls-remote,
  update checks) must be user-triggered or strictly opt-in behind a
  `g:plugin_manager_*` flag defaulting to off.
- **Structured errors**: raise with
  `plugin_manager#core#throw(component, CODE, message)` - never a bare
  `throw 'PM_ERROR:...'`. The component code must exist in `s:error_types`
  in `core.vim`.
- **Shell safety**: commands built for `plugin_manager#git#execute()` must be
  single invocations (no shell `&&`, `||`, `;`) with every user-controlled
  string passed through `shellescape()`. Arbitrary shell commands go through
  `core#util#run_in_dir`, never `:cd`/`:lcd` in plugin code.
- **Public API stability**: `api.vim`, the `:PluginManager*` commands and
  `g:plugin_manager_*` variables are public. Anything else (`core/*`,
  `git.vim`, `async.vim`, `cmd/*.vim` internals) may change freely.

## Conventions

- VimScript: 2-space indent, snake_case, `s:` prefix for script-local,
  `plugin_manager#<module>#<function>` for autoload functions, file header
  comment with short description.
- Conventional Commits: `type(scope): subject` - feat, fix, docs, test,
  refactor, style, chore, ci, build.
- **Test-first when possible**: new logic and bug fixes come with a Vader
  test (`tests/*.vader`, offline local git fixtures). Bug fixes should add
  the failing regression test before the fix. A PR changing behavior
  without a test must justify it in its "How was this tested?" section.
- Docs: behavior changes update all three of `README.md`,
  `doc/plugin_manager.txt` and `CHANGELOG.md`.
- Git operations go through `plugin_manager#git#execute` (injects
  `git -C <dir>`); async through `plugin_manager#async#start_job` /
  `async#git` (sync fallback must keep working); UI through the
  `plugin_manager#ui#start_operation/update/complete_operation` trio.
