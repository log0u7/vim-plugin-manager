# AGENTS.md

Guidance for AI agents and automated tooling working in this repository.
This file complements `CONTRIBUTING.md` (aimed at human contributors) with the
concrete commands, conventions, and guardrails an agent needs to make safe,
consistent changes.

## Project summary

Vim Plugin Manager is a lightweight Vim plugin manager built on Git
submodules and Vim 8's native package system (`pack/plugins/{start,opt}`). The
codebase is pure VimScript, organized into small single-responsibility modules.

## Build, run, and test

There is no compilation step. The project is loaded directly by Vim.

- Run the test suite (Vader):
  ```bash
  make test      # Interactive TUI
  make test-ci   # Headless (same output as CI)
  ```
  vader.vim is cloned automatically at the pinned SHA on first run.
  To use an existing clone: `make test-ci VADER_DIR=./vader.vim`.
- The `test` target generates a throwaway `.vaderrc.vim` and runs
  `vim -Nu .vaderrc.vim -c 'Vader! tests/*.vader'` (interactive TUI).
- The `test-ci` target runs the same suite via `vim -es` (headless/ex mode)
  producing clean plain-text output with no ANSI sequences.
- Clean test artifacts:
  ```bash
  make clean
  ```
- Run VimScript linting (vim-vint):
  ```bash
  pip install vim-vint
  vint -e autoload/ plugin/ ftplugin/ ftdetect/ syntax/
  ```
  Configuration: `.vintrc.yaml` (correctness=error, style=off).
- CI runs `test-ci` AND `vint`: `.github/workflows/test.yml` (GitHub Actions)
  and `.gitlab-ci.yml` (GitLab). Keep both green.

Requirements: Vim 8.2+ (with +job and +channel), Git 2.40+. Neovim is not
supported (it has lazy.nvim, packer.nvim and vim-plug). Windows and macOS are
not supported: the project targets Linux only (Debian, Ubuntu, Arch, Gentoo,
RHEL/AlmaLinux/Rocky).

The minimum Vim version floor is 8.2 and must not be raised without a concrete
reason. It is set by RHEL 9 / AlmaLinux 9 / Rocky 9, which ship Vim 8.2.2637.
RHEL 9 is supported until 2032. The codebase uses no Vim 9.0+ features; a
vim9script migration is explicitly deferred (dominant cost is git/network I/O,
not script execution). The guard `if v:version < 802` in
`plugin/plugin_manager.vim` is intentional - do not raise it to 900.

## Coding conventions

For VimScript:

- 2-space indentation. Keep lines under 100 characters where practical.
- `snake_case` for functions and variables.
- Internal (script-local) functions and variables are prefixed with `s:`.
- Public functions follow `plugin_manager#<module>#<function>()`.
- Each file starts with a header comment:
  ```vim
  " path/to/file.vim - Short description
  " Maintainer: G.K.E. <gke@6admin.io>
  " Version: 1.6.0
  ```
- Document functions with a short comment above them.
- Prefer Vim script native idioms over shelling out when feasible.
- Keep the current version header consistent across files within a release.

## Architecture

```
plugin/plugin_manager.vim     Entry point: config defaults + command definitions
autoload/plugin_manager/
  core.vim    Error handling, logging, path/config utils, URL/option parsing
  git.vim     Git operations, .gitmodules cache, submodule status
  async.vim   Non-blocking async jobs (Vim job/channel) with a concurrency queue
  ui.vim      Sidebar rendering, spinners, operation tracking
  api.vim     Public API facade
  cmd.vim     Command dispatcher + legacy-format adapters
  cmd/*.vim   add, remove, update, status, list, helptags, reload,
              backup, restore, remote, declare, check
ftdetect/ ftplugin/ syntax/   Sidebar buffer (filetype=pluginmanager)
doc/                          :help documentation
tests/                        Vader tests
```

Control flow: `:PluginManager <cmd>` -> `plugin_manager#cmd#dispatch()` ->
`plugin_manager#api#*` -> `plugin_manager#cmd#<cmd>#execute()`. UI feedback goes
through `ui.vim`; Git through `git.vim`; background work through `async.vim`.

## Error handling

Internal errors use a structured, 4-field format:

```
PM_ERROR:<component>:<CODE>:<message>
```

- Raise errors with `plugin_manager#core#throw(component, code, message)`, not a
  bare `throw 'PM_ERROR:...'`. The valid codes per component live in
  `s:error_types` in `core.vim`.
- Catch and present errors with `plugin_manager#core#handle_error(v:exception, component)`.
- Logging is handled centrally; do not write to the log file directly.

## UI conventions

- Use the operation API: `plugin_manager#ui#start_operation()`,
  `#update_operation()`, `#complete_operation()`.
- Use `plugin_manager#ui#get_symbol()` for glyphs (never reference the
  script-local `s:symbols` from outside `ui.vim`).
- Do not reintroduce the removed legacy UI helpers (`start_task`, `update_task`,
  `complete_task`, `box`, `themed_header`, `show_message`, `format_message`).

## Guardrails for agents

- Never add network access (e.g. `git fetch`) on startup or on a timer unless it
  is strictly opt-in behind a `g:plugin_manager_*` flag defaulting to off.
- Do not auto-commit or auto-push without honoring the relevant config flags
  (`g:plugin_manager_auto_commit_on_update`).
- Keep changes minimal and within the most relevant module; create a new module
  only when needed.
- When adding a config option, declare it in `plugin/plugin_manager.vim` with a
  sensible default and read it via `plugin_manager#core#get_config()`.
- Add or update Vader tests for new logic; prefer tests that do not require
  network access (mock with local fixtures).
- Update documentation (`README.md`, `doc/plugin_manager.txt`, `CHANGELOG.md`)
  when behavior changes.
- Never use the em dash character. Use `:`, `,`, parentheses `()`, or a plain
  hyphen `-` instead. This applies to files and commit messages.

## Commit conventions

Use Conventional Commits: `type(scope): subject`.

Valid types:
- `feat:` new features (prefer over historical `feature:`)
- `fix:` bug fixes
- `docs:` documentation changes
- `test:` test additions or changes
- `refactor:` code refactoring
- `style:` formatting changes
- `chore:` routine maintenance
- `ci:` CI/CD workflow changes
- `build:` build system or dependency changes

Scopes (optional but recommended when relevant):
`core`, `async`, `ui`, `git`, `cmd`, `api`, `github`, `gitlab`, `deps`.

Examples:
```
feat(git): add non-blocking status via async fetch
fix(core): implement missing s:check_log_rotation function
ci(github): bump checkout to v6 and cache to v5 for Node 24
test: add headless test-ci target with clean Vader output
docs: document GitFlow branching and Conventional Commits
```

Only commit when explicitly requested.

## Branching model

The project uses a simplified workflow with Conventional Commit prefixes.
There is no `develop` branch. All changes branch from and merge into `main`:

- `main` -- stable code, tagged `vX.Y.Z` for releases.
- `feature/*` -- new features, branched from `main`, merged back with `--no-ff`.
- `fix/*` -- bug fixes, branched from `main`.
- `chore/*` -- maintenance tasks, branched from `main`.
- `hotfix/*` -- urgent fixes on the current release, branched from `main`.

All merges use `--no-ff` to preserve branch topology.

## Releases

Releases are automated via `.github/workflows/release.yml`:
- Bump versions: `make update-version VERSION=x.y.z` (updates `Version:`
  headers across `*.vim`, `*.txt`, `README.md`).
- Update `CHANGELOG.md` for the new version.
- Tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`.
- Pushing a `vX.Y.Z` tag to GitHub triggers a job that runs `make archive`
  and publishes a GitHub Release with the `.tar.gz` asset and auto-generated
  notes.
