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
  call plugin_manager#async#git('git -C ' . shellescape(a:ctx.module_path) . ' fetch origin', {
        \ 'callback': function('s:on_fetch_complete', [a:ctx])
        \ })
endfunction

function! s:on_fetch_complete(ctx, result) abort
  let l:op_id = a:ctx.op_id
  let l:module_path = a:ctx.module_path

  call plugin_manager#ui#update_operation(l:op_id, 'Checking status')

  " Fast local analysis now that fetch is done
  let l:update_status = plugin_manager#git#collect_status_local(l:module_path)

  if l:update_status.different_branch && l:update_status.branch !=# 'detached'
    call plugin_manager#ui#complete_operation(l:op_id, 'skip', 'On custom branch')
    return
  endif

  if !l:update_status.has_updates
    call plugin_manager#ui#complete_operation(l:op_id, 'info', 'Up-to-date')
    return
  endif

  " Step 2: Stash local changes only now that we know a pull is needed
  let a:ctx.current_commit = l:update_status.current_commit
  let a:ctx.had_stash = s:stash_if_needed(l:module_path)

  " Step 3: Pull
  call plugin_manager#ui#update_operation(l:op_id, 'Pulling changes')
  let l:pull_flag = plugin_manager#core#util#get_pull_flag()
  let l:branch = plugin_manager#git#remote_branch_name(l:update_status.remote_branch)
  call plugin_manager#async#git('git -C ' . shellescape(l:module_path) . ' pull origin ' . shellescape(l:branch) . ' ' . l:pull_flag, {
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
      call s:commit_update_async(l:module_name, l:module_path)
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
    call plugin_manager#ui#log_detail('update', l:detail)
  endif
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
          \ 'git -C ' . shellescape(l:module_path) . ' fetch origin', {
          \ 'callback': function('s:on_module_fetched', [a:ctx])
          \ })
  endfor
endfunction

function! s:on_module_fetched(ctx, ...) abort
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
    call s:analyze_and_update(a:ctx, l:module)
  endfor
endfunction

function! s:analyze_and_update(ctx, module) abort
  let l:op_id = a:ctx.ops[a:module.short_name]
  let l:module_path = get(a:module, 'abs_path', a:module.path)

  call plugin_manager#ui#update_operation(l:op_id, 'Analyzing')

  let l:update_status = plugin_manager#git#collect_status_local(l:module_path)

  if l:update_status.different_branch && l:update_status.branch !=# 'detached'
    call plugin_manager#ui#complete_operation(l:op_id, 'skip', 'On custom branch')
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
  let l:branch = plugin_manager#git#remote_branch_name(l:update_status.remote_branch)
  let l:pull_flag = plugin_manager#core#util#get_pull_flag()
  let l:update_cmd = 'git -C ' . shellescape(l:module_path) . ' pull origin ' . shellescape(l:branch) . ' ' . l:pull_flag
  call plugin_manager#async#git(l:update_cmd, {
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
  if !empty(a:ctx.updated_modules)
    if plugin_manager#core#util#should_auto_commit()
      let l:vd = plugin_manager#core#util#get_config('vim_dir', '')
      call plugin_manager#git#execute('git add .gitmodules', l:vd, 0, 0)
      for l:module in a:ctx.updated_modules
        call plugin_manager#git#execute(
              \ 'git add ' . shellescape(l:module.path), l:vd, 0, 0)
      endfor
      call plugin_manager#git#execute(
            \ 'git commit -m "Update Modules"', l:vd, 0, 0)
    endif
    for l:module in a:ctx.updated_modules
      call plugin_manager#cmd#helptags#execute(0, l:module.short_name, 1)
    endfor
  endif

  let l:n = len(a:ctx.updated_modules)
  let l:total = len(a:ctx.valid_modules)
  if l:n > 0
    call plugin_manager#ui#footer([plugin_manager#ui#success(l:n . ' of ' . l:total . ' plugins updated')])
  else
    call plugin_manager#ui#footer([plugin_manager#ui#info('All ' . l:total . ' plugins are up-to-date')])
  endif
endfunction

" ------------------------------------------------------------------------------
" HELPERS
" ------------------------------------------------------------------------------

" Stash local changes if any exist. Returns 1 if a stash was created, 0 otherwise.
" Only creates a stash when there are actual tracked or untracked changes to save.
function! s:stash_if_needed(module_path) abort
  let l:status = plugin_manager#git#execute('git status -s', a:module_path, 0, 0)
  if !l:status.success || empty(trim(l:status.output))
    return 0
  endif
  call plugin_manager#git#execute('git stash -q', a:module_path, 0, 0)
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
          \ 'stash pop failed in ' . a:module_path . ': ' . l:result.output)
  endif
endfunction

function! s:commit_update_async(module_name, module_path) abort
  if !plugin_manager#core#util#should_auto_commit()
    return
  endif
  let l:vim_dir = plugin_manager#core#util#get_config('vim_dir', '')
  let l:stage_cmd = 'git -C ' . shellescape(l:vim_dir) .
        \ ' add .gitmodules && git -C ' . shellescape(l:vim_dir) .
        \ ' add ' . shellescape(a:module_path) .
        \ ' && git -C ' . shellescape(l:vim_dir) .
        \ ' commit -m "Update Module: ' . a:module_name . '"'
  call plugin_manager#async#git(l:stage_cmd, {})
endfunction
