# Test suite map (coverage by layer)

Layer conventions:
- **unit**: pure functions, no network, no side effects outside /tmp.
- **integration**: modules wired together (sidebar UI, git in a fixture
  repo, config honored end to end).
- **smoke**: the whole thing boots. `make test-ci` runs every vader file;
  `make test-async` exercises the real job/event-loop path
  (`tests/async_smoke.vim`); CI runs both across the distro matrix.

| Module | Tests | Layer |
|---|---|---|
| plugin/plugin_manager.vim (entry, defaults) | basic.vader | unit |
| core.vim (errors) | core.vader | unit |
| core/log.vim | log.vader | unit |
| core/cache.vim | cache.vader | unit |
| core/util.vim | util.vader + config.vader | unit |
| git.vim (.gitmodules parsing) | gitmodules.vader | unit |
| git.vim (repo ops) | cwd.vader | integration |
| async.vim | async.vader + async_smoke.vim | unit + smoke |
| ui.vim (format, header bars, width) | ui.vader + config.vader | unit + integration |
| syntax/pluginmanager.vim | syntax.vader | unit |
| cmd/add.vim | add.vader | integration |
| cmd/update.vim | update.vader | integration |
| cmd/remove.vim | remove.vader | integration |
| cmd/backup.vim | backup.vader | integration |
| cmd/restore.vim | restore.vader | integration |
| cmd/status.vim | status.vader | integration |
| cmd/dispatch.vim | dispatch.vader | integration |
| cmd/declare.vim | declare.vader | unit |
| cmd/check.vim | check.vader | integration |
| cmd/health.vim | health.vader | integration |
| cmd.vim (remotes) | remote.vader | integration |
| cmd/gc.vim | gc.vader | unit + integration |
| cmd/remove.vim (_force_remove) | gc.vader | integration |
| vimrc.vim (declarations parser) | vimrc.vader | unit |
| lazy.vim (on/for triggers) | lazy.vader | unit + integration |
| pin re-assertion (update + vimrc) | pin.vader | integration |
| pin collision across forges | pin_collision.vader | integration |
| cmd/declare.vim (sync path, file://, lazy re-declare) | declare.vader | integration |
| declare.vim (parallel install) | install_smoke.vim | smoke |
| cmd/list, cmd/helptags, cmd/reload | exercised via dispatch/health/basic tests | integration (indirect) |

Known indirect coverage (no dedicated file, acceptable): cmd/list,
cmd/helptags, cmd/reload — each is a thin wrapper around api calls already
asserted through dispatch/health/basic.
