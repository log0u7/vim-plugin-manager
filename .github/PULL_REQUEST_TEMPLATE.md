### Summary

<!-- What does this PR change, and why? One or two sentences. -->

### Type of change

- [ ] feat (new feature)
- [ ] fix (bug fix)
- [ ] docs
- [ ] test
- [ ] refactor
- [ ] chore / ci

### Related issue

<!-- Fixes #123 (required for bug fixes; "Closes #123" for features). -->

### How was this tested?

<!-- State the Vim version and distro used. -->

- [ ] `make test-ci` passes
- [ ] `make test-async` passes
- [ ] `make test-install-smoke` passes (install/declare changes)
- [ ] Verified manually on Vim 8.2+ / Linux
- [ ] New logic covered by a Vader test, written test-first when possible
      (bug fixes: failing regression test before the fix)

### Checklist

- [ ] Commits follow Conventional Commits (`type(scope): subject`)
- [ ] README.md / doc/plugin_manager.txt / CHANGELOG.md updated if behavior changed
- [ ] No new network call at startup (opt-in only, behind a `g:plugin_manager_*` flag defaulting to off)
- [ ] Linux only, Vim 8.2 floor respected (no Vim 9+ features, guard `v:version < 802` untouched)
