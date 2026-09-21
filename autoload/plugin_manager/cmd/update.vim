" autoload/plugin_manager/cmd/update.vim - Simplified update command
" Maintainer: G.K.E. <gke@6admin.io>

" ------------------------------------------------------------------------------
" MAIN UPDATE COMMAND
" ------------------------------------------------------------------------------

function! plugin_manager#cmd#update#execute(module_name) abort
  try
    call plugin_manager#core#util#require_vim_directory('update')
    
    call plugin_manager#ui#open_header('Updating plugins:')
    
    " Check if plugins exist
    let l:modules = plugin_manager#git#parse_modules()
    if empty(l:modules)
      call plugin_manager#core#throw('update', 'NO_PLUGINS', 'No plugins to update')
    endif
    
    " Create context
    let l:ctx = s:create_update_context(a:module_name, l:modules)
    
    " Execute update strategy (async#start_job has its own sync fallback)
    if l:ctx.is_specific_plugin
      call s:update_specific_plugin(l:ctx)
    else
      call s:update_all_plugins(l:ctx)
    endif
    
    return 1
  catch
    call plugin_manager#core#handle_error(v:exception, "update")
    return 0
  endtry
endfunction

" ------------------------------------------------------------------------------
" CONTEXT CREATION
" ------------------------------------------------------------------------------

function! s:create_update_context(module_name, modules) abort
  let l:is_specific = a:module_name !=# 'all'
  " For 'update all', collect only modules whose directory exists on disk;
  " there is nothing to pull for a module with a missing working tree.
  let l:valid = []
  if !l:is_specific
    for l:mod in plugin_manager#git#valid_modules()
      if plugin_manager#core#util#dir_exists(get(l:mod, 'abs_path', get(l:mod, 'path', '')))
        call add(l:valid, l:mod)
      endif
    endfor
  endif
  return {
        \ 'module_name':        a:module_name,
        \ 'modules':            a:modules,
        \ 'is_specific_plugin': l:is_specific,
        \ 'valid_modules':      l:valid,
        \ 'pins':               s:build_pins(),
        \ }
endfunction

" ------------------------------------------------------------------------------
" SINGLE PLUGIN UPDATE
" ------------------------------------------------------------------------------

function! s:update_specific_plugin(ctx) abort
  let l:module_info = plugin_manager#git#find_module(a:ctx.module_name, 1)
  if empty(l:module_info)
    call plugin_manager#core#throw('update', 'MODULE_NOT_FOUND', 'Module "' . a:ctx.module_name . '" not found')
  endif
  
  let l:module = l:module_info.module
  let a:ctx.current_module = l:module
  let a:ctx.module_path = get(l:module, 'abs_path', l:module.path)
  let a:ctx.module_short_name = l:module.short_name
  
  if !plugin_manager#core#util#dir_exists(a:ctx.module_path)
    call plugin_manager#core#throw('update', 'PATH_NOT_FOUND', 'Module directory not found')
  endif
  
  call s:update_specific_plugin_async(a:ctx)
endfunction

" Async update for single plugin
function! s:update_specific_plugin_async(ctx) abort
  let l:op_id = plugin_manager#ui#start_operation(a:ctx.module_short_name, 'Updating')
  let a:ctx.op_id = l:op_id

  " Step 1: Fetch first, stash only if a pull turns out to be needed
  call plugin_manager#ui#update_operation(l:op_id, 'Fetching updates')
  call plugin_manager#async#git('git -C ' . shellescape(a:ctx.module_path) . ' fetch --tags --force origin', {
        \ 'callback': function('s:on_fetch_complete', [a:ctx])
        \ })
endfunction

function! s:on_fetch_complete(ctx, result) abort
  let l:op_id = a:ctx.op_id
  let l:module_path = a:ctx.module_path

  call plugin_manager#ui#update_operation(l:op_id, 'Checking status')

  " Fast local analysis now that fetch is done
  let l:update_status = plugin_manager#git#collect_status_local(l:module_path)
  let a:ctx.current_commit = l:update_status.current_commit

  " A declared tag/commit pin replaces the pull flow entirely
  if s:handle_pin(a:ctx, a:ctx.current_module, l:update_status, l:op_id)
    return
  endif

  " A custom branch or a detached HEAD without a declaration is never
  " pulled: the pull would fail noisily on the detached HEAD or destroy a
  " manually checked out revision. Declare a tag/commit to pin it instead.
  let l:skip = s:skip_status(l:update_status)
  if !empty(l:skip)
    call plugin_manager#ui#complete_operation(l:op_id, 'skip', l:skip)
    return
  endif

  if !l:update_status.has_updates
    call plugin_manager#ui#complete_operation(l:op_id, 'info', 'Up-to-date')
    return
  endif

  " Step 2: Stash local changes only now that we know a pull is needed
  let a:ctx.had_stash = s:stash_if_needed(l:module_path)

  " Step 3: Pull
  call plugin_manager#ui#update_operation(l:op_id, 'Pulling changes')
  call plugin_manager#async#git(s:pull_cmd(l:module_path, l:update_status.remote_branch), {
        \ 'callback': function('s:on_update_complete', [a:ctx])
        \ })
endfunction

function! s:on_update_complete(ctx, result) abort
  let l:op_id = a:ctx.op_id
  let l:module_name = a:ctx.module_short_name
  let l:module_path = a:ctx.module_path
  let l:success = a:result.status == 0

  " Restore stashed local changes regardless of pull outcome
  if get(a:ctx, 'had_stash', 0)
    call s:stash_pop(l:module_path, l:op_id)
  endif

  if l:success
    " Compare HEAD before/after to determine if anything actually changed
    let l:before = get(a:ctx, 'current_commit', '')
    let l:changed = plugin_manager#git#head_changed(l:module_path, l:before)

    if l:changed
      call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Updated')
      call plugin_manager#cmd#helptags#execute(0, l:module_name, 1)
      let l:module_path = get(a:ctx.current_module, 'path', '')
      if s:commit_update_async(l:module_name, l:module_path)
        call plugin_manager#ui#complete_operation(l:op_id, 'warn',
              \ 'Updated (auto-commit failed: see log)')
      endif
    else
      call plugin_manager#ui#complete_operation(l:op_id, 'info', 'Up-to-date')
    endif
  else
    call plugin_manager#ui#complete_operation(l:op_id, 'fail', 'Update failed')
    call s:report_job_errors(a:result)
  endif
endfunction

" Surface detailed error output from a failed async job to the log

function! s:report_job_errors(result) abort
  let l:detail = ''
  if has_key(a:result, 'errors') && !empty(a:result.errors)
    let l:detail = a:result.errors
  elseif has_key(a:result, 'output') && !empty(a:result.output)
    let l:detail = a:result.output
  endif

  if !empty(l:detail)
    call plugin_manager#ui#log_detail('update', l:detail, 'warn')
  endif
endfunction

" ------------------------------------------------------------------------------
" PIN RE-ASSERTION (tag/commit declared in the vimrc)
" ------------------------------------------------------------------------------

" Build the pin map from the vimrc Plugin declarations.
" Precedence: branch > commit > tag. A branch pin needs no special update
" handling (the pull flow tracks it via .gitmodules), so only commit/tag
" entries enter the map. Keyed by plugin short name (declared name or
" 'dir' option) and by normalized URL.
function! s:build_pins() abort
  let l:pins = {}
  for l:decl in plugin_manager#vimrc#parse_declarations()
    let l:pin = {}
    if !empty(l:decl.options.branch)
      let l:pin.branch = l:decl.options.branch
    elseif !empty(l:decl.options.commit)
      let l:pin.commit = l:decl.options.commit
    elseif !empty(l:decl.options.tag)
      let l:pin.tag = l:decl.options.tag
    endif
    if empty(l:pin)
      continue
    endif
    let l:pins['name:' . plugin_manager#core#util#extract_plugin_name(l:decl.url)] = l:pin
    if !empty(get(l:decl.options, 'dir', ''))
      let l:pins['name:' . l:decl.options.dir] = l:pin
    endif
    let l:url = plugin_manager#core#util#convert_to_full_url(l:decl.url)
    if !empty(l:url)
      let l:pins['url:' . l:url] = l:pin
    endif
  endfor
  return l:pins
endfunction

function! s:pin_for(pins, module) abort
  if empty(a:pins) || empty(a:module)
    return {}
  endif
  " URL first: exact per-module match, immune to short-name collisions
  " across forges (orgA/vim-foo and orgB/vim-foo both extract to
  " 'vim-foo'). The name key stays as fallback for URL drift (declared
  " https, installed through ssh).
  return get(a:pins, 'url:' . get(a:module, 'url', ''),
        \ get(a:pins, 'name:' . get(a:module, 'short_name', ''), {}))
endfunction

" Shared pinned-module handling (identical in the single-plugin and
" all-plugins paths): a declared tag/commit pin replaces the pull flow
" entirely.  Returns 1 when the module was handled by its pin.
function! s:handle_pin(ctx, module, update_status, op_id) abort
  let l:pin = s:pin_for(a:ctx.pins, a:module)
  if empty(l:pin) || !(has_key(l:pin, 'tag') || has_key(l:pin, 'commit'))
    return 0
  endif
  " Record the pre-checkout commit when the context tracks them
  " (all-plugins path): s:on_pin_checkout compares against it.
  " Without it a pin move reports Up-to-date and skips the pointer commit.
  if has_key(a:ctx, 'pre_commits')
    let a:ctx.pre_commits[a:module.short_name] = a:update_status.current_commit
  endif
  call s:sync_pinned(a:ctx, a:module, l:pin,
        \ a:update_status.current_commit, a:op_id)
  return 1
endfunction

" Shared skip text for a module on a detached HEAD or a custom branch
" (identical in both update paths; UI copy contract - see update.vader).
" Returns the skip message, or '' when the module is on a pullable branch.
function! s:skip_status(update_status) abort
  if a:update_status.different_branch || a:update_status.branch ==# 'detached'
    return a:update_status.branch ==# 'detached'
          \ ? 'Detached HEAD: skipped (declare a tag/commit to pin it)'
          \ : 'On custom branch'
  endif
  return ''
endfunction

" Shared pull command builder (identical in both update paths).
function! s:pull_cmd(module_path, remote_branch) abort
  return 'git -C ' . shellescape(a:module_path) . ' pull origin '
        \ . shellescape(plugin_manager#git#remote_branch_name(a:remote_branch))
        \ . ' ' . plugin_manager#core#util#get_pull_flag()
endfunction

" Resolve the pin target and checkout it when HEAD differs. Replaces the
" pull flow for pinned modules: a detached-at-tag submodule must never be
" pulled.
function! s:sync_pinned(ctx, module, pin, current_commit, op_id) abort
  let l:module_path = get(a:module, 'abs_path', a:module.path)
  let l:ref = has_key(a:pin, 'commit') ? a:pin.commit : a:pin.tag
  let l:res = plugin_manager#git#execute(
        \ 'git rev-parse ' . shellescape(l:ref . '^{commit}'), l:module_path, 0, 0)
  if !l:res.success
    " The sidebar alone hides this from :PluginManagerViewLog: warn too.
    call plugin_manager#core#log#warn('update',
          \ 'Pin target not found: ' . l:ref . ' in ' . l:module_path)
    call plugin_manager#ui#complete_operation(a:op_id, 'fail',
          \ 'Pin target not found: ' . l:ref)
    call s:pin_done(a:ctx, a:module, 0)
    return
  endif

  let l:target = substitute(l:res.output, '\n', '', 'g')
  if a:current_commit ==# l:target
    call plugin_manager#ui#complete_operation(a:op_id, 'info', 'Up-to-date')
    call s:pin_done(a:ctx, a:module, 0)
    return
  endif

  call plugin_manager#ui#update_operation(a:op_id, 'Checking out ' . l:ref)
  let l:had_stash = s:stash_if_needed(l:module_path)
  call plugin_manager#async#git('git -C ' . shellescape(l:module_path) . ' checkout ' . shellescape(l:ref), {
        \ 'callback': function('s:on_pin_checkout', [a:ctx, a:module, l:had_stash])
        \ })
endfunction

function! s:on_pin_checkout(ctx, module, had_stash, result) abort
  let l:op_id = s:op_id_for(a:ctx, a:module)
  let l:module_path = get(a:module, 'abs_path', a:module.path)

  if a:had_stash
    call s:stash_pop(l:module_path, l:op_id)
  endif

  if a:result.status != 0
    call plugin_manager#ui#complete_operation(l:op_id, 'fail', 'Pin checkout failed')
    call s:report_job_errors(a:result)
    call s:pin_done(a:ctx, a:module, 0)
    return
  endif

  let l:before = has_key(a:ctx, 'ops')
        \ ? get(get(a:ctx, 'pre_commits', {}), a:module.short_name, '')
        \ : get(a:ctx, 'current_commit', '')
  let l:changed = plugin_manager#git#head_changed(l:module_path, l:before)
  if l:changed
    call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Updated')
  else
    call plugin_manager#ui#complete_operation(l:op_id, 'info', 'Up-to-date')
  endif
  call s:pin_done(a:ctx, a:module, l:changed)
endfunction

" Completion bookkeeping for the pin path: the all-plugins run tracks
" pending modules and batches helptags/commits in the finalize step; the
" single-plugin run does both inline, mirroring the pull path.
function! s:pin_done(ctx, module, changed) abort
  if has_key(a:ctx, 'pending')
    if a:changed
      call add(a:ctx.updated_modules, a:module)
    endif
    let a:ctx.pending -= 1
    call s:maybe_finalize(a:ctx)
  elseif a:changed
    call plugin_manager#cmd#helptags#execute(0, a:module.short_name, 1)
    let l:module_path = get(get(a:ctx, 'current_module', {}), 'path', '')
    if s:commit_update_async(a:module.short_name, l:module_path)
      call plugin_manager#ui#complete_operation(s:op_id_for(a:ctx, a:module),
            \ 'warn', 'Updated (auto-commit failed: see log)')
    endif
  endif
endfunction

function! s:op_id_for(ctx, module) abort
  if has_key(a:ctx, 'ops')
    return a:ctx.ops[a:module.short_name]
  endif
  return a:ctx.op_id
endfunction

" ------------------------------------------------------------------------------
" ALL PLUGINS UPDATE
" ------------------------------------------------------------------------------

function! s:update_all_plugins(ctx) abort
  call s:update_all_plugins_async(a:ctx)
endfunction

" Async update all plugins - block instant + parallel fan-out
function! s:update_all_plugins_async(ctx) abort
  let a:ctx.updated_modules = []
  let a:ctx.ops = {}
  let a:ctx.pre_commits = {}
  " Modules whose fetch failed: the op is completed as a failure by
  " s:on_module_fetched and the module is excluded from the pull batch.
  let a:ctx.fetch_failed = {}
  
  " Pre-render all plugin lines as a block with pending spinners
  for l:module in a:ctx.valid_modules
    let l:op_id = plugin_manager#ui#start_operation(l:module.short_name, 'Pending')
    let a:ctx.ops[l:module.short_name] = l:op_id
  endfor
  
  " Fetch each module individually instead of using 'submodule foreach',
  " which blocks the file:// transport protocol on git >= 2.38.1 (CVE-2022-39253).
  " Individual module fetch does not trigger the restriction.
  let a:ctx.pending_fetches = len(a:ctx.valid_modules)
  if a:ctx.pending_fetches == 0
    call s:finalize_update_all(a:ctx)
    return
  endif
  for l:module in a:ctx.valid_modules
    let l:module_path = get(l:module, 'abs_path', l:module.path)
    call plugin_manager#async#git(
          \ 'git -C ' . shellescape(l:module_path) . ' fetch --tags --force origin', {
          \ 'callback': function('s:on_module_fetched', [a:ctx, l:module])
          \ })
  endfor
endfunction

function! s:on_module_fetched(ctx, module, result) abort
  if get(a:result, 'status', 0) != 0
    " A failed/killed fetch must surface as a module failure, not as a
    " silent success: the analyze/pull batch would run on stale refs.
    call plugin_manager#ui#complete_operation(
          \ a:ctx.ops[a:module.short_name], 'fail', 'Fetch failed')
    " git writes the reason on stderr: result.errors carries it in async
    " mode (the sync fallback merges it into output).
    call plugin_manager#ui#log_detail('update',
          \ 'fetch failed in ' . get(a:module, 'abs_path', a:module.path)
          \ . ': ' . get(a:result, 'errors', get(a:result, 'output', '')), 'warn')
    let a:ctx.fetch_failed[a:module.short_name] = 1
  endif
  let a:ctx.pending_fetches -= 1
  if a:ctx.pending_fetches == 0
    call s:on_batch_fetched(a:ctx)
  endif
endfunction

function! s:on_batch_fetched(ctx) abort
  let a:ctx.pending = len(a:ctx.valid_modules)

  if empty(a:ctx.valid_modules)
    call s:finalize_update_all(a:ctx)
    return
  endif

  " Fan-out: analyze and update each module in parallel
  for l:module in a:ctx.valid_modules
    if has_key(a:ctx.fetch_failed, l:module.short_name)
      " The op is already completed as a failure; release its slot.
      let a:ctx.pending -= 1
      continue
    endif
    call s:analyze_and_update(a:ctx, l:module)
  endfor

  " Every module failed at fetch: nothing left to analyze, finalize now.
  if a:ctx.pending == 0
    call s:finalize_update_all(a:ctx)
  endif
endfunction

function! s:analyze_and_update(ctx, module) abort
  let l:op_id = a:ctx.ops[a:module.short_name]
  let l:module_path = get(a:module, 'abs_path', a:module.path)

  call plugin_manager#ui#update_operation(l:op_id, 'Analyzing')

  let l:update_status = plugin_manager#git#collect_status_local(l:module_path)

  " A declared tag/commit pin replaces the pull flow entirely.
  " Record the pre-checkout commit when the all-plugins context tracks
  " them: s:on_pin_checkout compares against it (the single-plugin path
  " keeps its own current_commit).  Without it a pin move reports
  " Up-to-date and skips the pointer commit.
  if s:handle_pin(a:ctx, a:module, l:update_status, l:op_id)
    return
  endif

  let l:skip = s:skip_status(l:update_status)
  if !empty(l:skip)
    call plugin_manager#ui#complete_operation(l:op_id, 'skip', l:skip)
    let a:ctx.pending -= 1
    call s:maybe_finalize(a:ctx)
    return
  endif

  if !l:update_status.has_updates
    call plugin_manager#ui#complete_operation(l:op_id, 'info', 'Up-to-date')
    let a:ctx.pending -= 1
    call s:maybe_finalize(a:ctx)
    return
  endif

  " Stash local changes per-module, only for modules that will be pulled
  let a:ctx.pre_commits[a:module.short_name] = l:update_status.current_commit
  if !has_key(a:ctx, 'stashed')
    let a:ctx.stashed = {}
  endif
  let a:ctx.stashed[a:module.short_name] = s:stash_if_needed(l:module_path)

  " Pull with the correct remote branch (use -C with absolute path)
  call plugin_manager#ui#update_operation(l:op_id, 'Updating')
  call plugin_manager#async#git(s:pull_cmd(l:module_path, l:update_status.remote_branch), {
        \ 'callback': function('s:on_module_updated', [a:ctx, a:module])
        \ })
endfunction

function! s:on_module_updated(ctx, module, result) abort
  let l:op_id = a:ctx.ops[a:module.short_name]
  let l:module_path = get(a:module, 'abs_path', a:module.path)
  let l:success = a:result.status == 0

  " Restore stashed local changes regardless of pull outcome
  if get(get(a:ctx, 'stashed', {}), a:module.short_name, 0)
    call s:stash_pop(l:module_path, l:op_id)
  endif

  if l:success
    let l:before = get(a:ctx.pre_commits, a:module.short_name, '')
    let l:changed = plugin_manager#git#head_changed(l:module_path, l:before)

    if l:changed
      call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Updated')
      call add(a:ctx.updated_modules, a:module)
    else
      call plugin_manager#ui#complete_operation(l:op_id, 'info', 'Up-to-date')
    endif
  else
    call plugin_manager#ui#complete_operation(l:op_id, 'fail', 'Update failed')
    call s:report_job_errors(a:result)
  endif

  let a:ctx.pending -= 1
  call s:maybe_finalize(a:ctx)
endfunction

function! s:maybe_finalize(ctx) abort
  if a:ctx.pending == 0
    call s:finalize_update_all(a:ctx)
  endif
endfunction

function! s:finalize_update_all(ctx) abort
  let l:commit_failed = 0
  if !empty(a:ctx.updated_modules)
    if plugin_manager#core#util#should_auto_commit()
      let l:vd = plugin_manager#core#util#get_config('vim_dir', '')
      let l:commit_failed = s:log_silent_failure('git add .gitmodules',
            \ plugin_manager#git#execute('git add .gitmodules', l:vd, 0, 0))
      for l:module in a:ctx.updated_modules
        let l:commit_failed = s:log_silent_failure('git add ' . l:module.path,
              \ plugin_manager#git#execute(
              \   'git add ' . shellescape(l:module.path), l:vd, 0, 0))
              \ || l:commit_failed
      endfor
      let l:commit_failed = s:log_silent_failure('commit',
            \ plugin_manager#git#execute(
            \   'git commit -m "Update Modules"', l:vd, 0, 0))
            \ || l:commit_failed
    endif
    for l:module in a:ctx.updated_modules
      call plugin_manager#cmd#helptags#execute(0, l:module.short_name, 1)
    endfor
  endif

  " Truthful completion: the plugins updated, but the pointer commit is the
  " part that persists the update - a failure must not read as a clean win.
  if l:commit_failed
    for l:module in a:ctx.updated_modules
      call plugin_manager#ui#complete_operation(a:ctx.ops[l:module.short_name],
            \ 'warn', 'Updated (auto-commit failed: see log)')
    endfor
  endif

  let l:n = len(a:ctx.updated_modules)
  let l:total = len(a:ctx.valid_modules)
  let l:failed = len(get(a:ctx, 'fetch_failed', {}))
  let l:footer = []
  if l:n > 0
    call add(l:footer, plugin_manager#ui#success(l:n . ' of ' . l:total . ' plugins updated'))
  elseif l:failed == 0
    call add(l:footer, plugin_manager#ui#info('All ' . l:total . ' plugins are up-to-date'))
  else
    call add(l:footer, plugin_manager#ui#warning(
          \ l:failed . ' of ' . l:total . ' plugins failed to fetch'))
  endif
  if l:failed > 0 && l:n > 0
    call add(l:footer, plugin_manager#ui#warning(
          \ l:failed . ' of ' . l:total . ' plugins failed to fetch'))
  endif
  if l:commit_failed
    call add(l:footer, plugin_manager#ui#warning(
          \ 'auto-commit failed (see log): the update is not recorded in git'))
  endif
  call plugin_manager#ui#footer(l:footer)
endfunction

" ------------------------------------------------------------------------------
" HELPERS
" ------------------------------------------------------------------------------

" Log silent git failures (git#execute with throw_on_error=0): a failed
" pointer add/commit must leave a trace in the log, not vanish.
" Returns 1 when the step failed, 0 otherwise.
function! s:log_silent_failure(step, res) abort
  if !a:res.success
    call plugin_manager#ui#log_detail('update',
          \ 'auto-commit ' . a:step . ' failed: ' . a:res.output, 'warn')
    return 1
  endif
  return 0
endfunction

" Stash local changes if any exist. Returns 1 if a stash was created, 0 otherwise.
" Only creates a stash when there are actual tracked or untracked changes to save.
" -u includes untracked files: an untracked file that the incoming pull
" wants to write would otherwise abort the pull after the "protected" stash.
function! s:stash_if_needed(module_path) abort
  let l:status = plugin_manager#git#execute('git status -s', a:module_path, 0, 0)
  if !l:status.success || empty(trim(l:status.output))
    return 0
  endif
  let l:stash_result = plugin_manager#git#execute('git stash push -u -q', a:module_path, 0, 0)
  if !l:stash_result.success
    " Never claim a stash exists when the push failed: the caller would
    " otherwise pop an unrelated stash after the pull.
    call plugin_manager#ui#log_detail('update',
          \ 'stash push failed in ' . a:module_path . ': ' . l:stash_result.output, 'warn')
    return 0
  endif
  return 1
endfunction

" Pop the most recent stash. If the pop creates a conflict, leave the stash
" in place and warn the user so their changes are never silently lost.
function! s:stash_pop(module_path, op_id) abort
  let l:result = plugin_manager#git#execute('git stash pop -q', a:module_path, 0, 0)
  if !l:result.success
    " Pop failed (conflict or empty stash). Preserve stash and warn.
    call plugin_manager#ui#complete_operation(a:op_id, 'warn',
          \ 'Local changes preserved in stash (run: git stash pop)')
    call plugin_manager#ui#log_detail('update',
          \ 'stash pop failed in ' . a:module_path . ': ' . l:result.output, 'warn')
  endif
endfunction

" Auto-commit the pointer for a single updated module (mirror of
" s:finalize_update_all).  Returns 1 when any step failed so the caller can
" re-complete the operation with a truthful warn.
function! s:commit_update_async(module_name, module_path) abort
  if !plugin_manager#core#util#should_auto_commit()
    return 0
  endif
  let l:vim_dir = plugin_manager#core#util#get_config('vim_dir', '')
  " Three separate calls (mirrors s:finalize_update_all): a compound command
  " would only scope the first git -C, and the module name must stay escaped
  " so it can never break out of the commit message quoting.
  let l:failed = s:log_silent_failure('git add .gitmodules',
        \ plugin_manager#git#execute('git add .gitmodules', l:vim_dir, 0, 0))
  let l:failed = s:log_silent_failure('git add ' . a:module_path,
        \ plugin_manager#git#execute(
        \   'git add ' . shellescape(a:module_path), l:vim_dir, 0, 0))
        \ || l:failed
  let l:failed = s:log_silent_failure('commit',
        \ plugin_manager#git#execute(
        \   'git commit -m ' . shellescape('Update Module: ' . a:module_name),
        \   l:vim_dir, 0, 0))
        \ || l:failed
  return l:failed
endfunction
