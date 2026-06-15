# AGENTS.md

Guidance for AI agents and automated tooling working in this repository.
This file complements `CONTRIBUTING.md` (aimed at human contributors) with the
concrete commands, conventions, and guardrails an agent needs to make safe,
consistent changes.

## Project summary

Vim Plugin Manager is a lightweight Vim/Neovim plugin manager built on Git
submodules and Vim 8's native package system (`pack/plugins/{start,opt}`). The
codebase is pure VimScript, organized into small single-responsibility modules.

## Build, run, and test

There is no compilation step. The project is loaded directly by Vim/Neovim.

- Run the test suite (Vader):
  ```bash
  git clone https://github.com/junegunn/vader.vim.git
  make -f Makefile.test VADER=./vader.vim test
  ```
- The test target generates a throwaway `.vaderrc.vim` and runs
  `vim -Nu .vaderrc.vim -c 'Vader! tests/*.vader'`.
- Clean test artifacts:
  ```bash
  make -f Makefile.test clean
  ```
- CI runs the same target: `.github/workflows/test.yml` (GitHub Actions) and
  `.gitlab-ci.yml` (GitLab). Keep both green.

Requirements: Vim 8.0+ or Neovim, Git 2.40+.

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
  " Version: 1.4.0
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
  async.vim   Unified async jobs (Vim job/channel + Neovim jobstart)
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

Use the prefixes already established in the history:

- `feature:` new features
- `fix:` bug fixes
- `docs:` documentation changes
- `test:` test additions or changes
- `refactor:` code refactoring
- `style:` formatting changes
- `chore:` routine maintenance

Only commit when explicitly requested.
