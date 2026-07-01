" autoload/plugin_manager/cmd/update.vim - Simplified update command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.6.0

" ------------------------------------------------------------------------------
" MAIN UPDATE COMMAND
" ------------------------------------------------------------------------------

function! plugin_manager#cmd#update#execute(module_name) abort
  try
    call plugin_manager#core#require_vim_directory('update')
    
    call plugin_manager#ui#open_header('Updating plugins:')
    
    " Check if plugins exist
    let l:modules = plugin_manager#git#parse_modules()
    if empty(l:modules)
      call plugin_manager#core#throw('update', 'NO_PLUGINS', 'No plugins to update')
    endif
    
    " Check for async support
    let l:use_async = plugin_manager#async#supported()
    
    " Create context
    let l:ctx = s:create_update_context(a:module_name, l:modules)
    
    " Execute appropriate update strategy
    if l:ctx.is_specific_plugin
      call s:update_specific_plugin(l:ctx, l:use_async)
    else
      call s:update_all_plugins(l:ctx, l:use_async)
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
  let l:ctx = {
        \ 'module_name': a:module_name,
        \ 'modules': a:modules,
        \ 'is_specific_plugin': a:module_name !=# 'all',
        \ 'valid_modules': [],
        \ 'module_names': sort(keys(a:modules)),
        \ }
  
  if !l:ctx.is_specific_plugin
    for l:name in l:ctx.module_names
      let l:module = l:ctx.modules[l:name]
      if has_key(l:module, 'is_valid') && l:module.is_valid && plugin_manager#core#dir_exists(l:module.path)
        call add(l:ctx.valid_modules, l:module)
      endif
    endfor
  endif
  
  return l:ctx
endfunction

" ------------------------------------------------------------------------------
" SINGLE PLUGIN UPDATE
" ------------------------------------------------------------------------------

function! s:update_specific_plugin(ctx, use_async) abort
  let l:module_info = plugin_manager#git#find_module(a:ctx.module_name, 1)
  if empty(l:module_info)
    call plugin_manager#core#throw('update', 'MODULE_NOT_FOUND', 'Module "' . a:ctx.module_name . '" not found')
  endif
  
  let l:module = l:module_info.module
  let a:ctx.current_module = l:module
  let a:ctx.module_path = l:module.path
  let a:ctx.module_short_name = l:module.short_name
  
  if !plugin_manager#core#dir_exists(a:ctx.module_path)
    call plugin_manager#core#throw('update', 'PATH_NOT_FOUND', 'Module directory not found')
  endif
  
  if a:use_async
    call s:update_specific_plugin_async(a:ctx)
  else
    call s:update_specific_plugin_sync(a:ctx)
  endif
endfunction

" Sync update for single plugin
function! s:update_specific_plugin_sync(ctx) abort
  let l:module_path = a:ctx.module_path
  let l:module_name = a:ctx.module_short_name

  " Start operation
  let l:op_id = plugin_manager#ui#start_operation(l:module_name, 'Updating')

  " Check for updates before touching local changes
  let l:update_status = plugin_manager#git#check_updates(l:module_path)

  if l:update_status.different_branch && l:update_status.branch !=# 'detached'
    call plugin_manager#ui#complete_operation(l:op_id, 'skip', 'On custom branch')
    return
  endif

  if !l:update_status.has_updates
    call plugin_manager#ui#complete_operation(l:op_id, 'info', 'Up-to-date')
    return
  endif

  " Stash local changes only when a pull is actually going to happen
  let l:had_stash = s:stash_if_needed(l:module_path)

  " Update
  let l:result = plugin_manager#git#update_submodule(l:module_path)

  " Always restore stashed changes, regardless of pull outcome
  if l:had_stash
    call s:stash_pop(l:module_path, l:op_id)
  endif

  if l:result.success
    call plugin_manager#ui#complete_operation(l:op_id, 'ok', l:result.message)
    if l:result.changed
      call plugin_manager#cmd#helptags#execute(0, l:module_name, 1)
      " Commit the updated submodule pointer, mirroring the async single-plugin
      " path (s:commit_update_async).  Only stage if there is actually something
      " pending (git status -s non-empty) so we never create an empty commit.
      if plugin_manager#core#should_auto_commit()
        let l:st = plugin_manager#git#execute('git status -s', '', 0, 0)
        if !empty(trim(l:st.output))
          call plugin_manager#git#execute(
                \ 'git commit -am "Update Module: ' . l:module_name . '"', '', 0, 0)
        endif
      endif
    endif
  else
    call plugin_manager#ui#complete_operation(l:op_id, 'fail', 'Update failed')
  endif
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
  let l:pull_flag = plugin_manager#core#get_pull_flag()
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
      call s:commit_update_async(l:module_name)
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

function! s:update_all_plugins(ctx, use_async) abort
  if a:use_async
    call s:update_all_plugins_async(a:ctx)
  else
    call s:update_all_plugins_sync(a:ctx)
  endif
endfunction

" Sync update all plugins
function! s:update_all_plugins_sync(ctx) abort
  " Fetch all modules first (no stash yet - only stash if a pull is needed)
  call plugin_manager#git#execute('git submodule foreach --recursive "git fetch origin"', '', 0, 0)

  let l:modules_to_update = []
  let l:pending_ops = []

  for l:module in a:ctx.valid_modules
    let l:update_status = plugin_manager#git#collect_status_local(l:module.path)

    if !l:update_status.different_branch && l:update_status.has_updates
      let l:op_id = plugin_manager#ui#start_operation(l:module.short_name, 'Updating')
      call add(l:modules_to_update, l:module)
      call add(l:pending_ops, l:op_id)
    elseif l:update_status.different_branch
      let l:op_id = plugin_manager#ui#start_operation(l:module.short_name, 'Checking')
      call plugin_manager#ui#complete_operation(l:op_id, 'skip', 'On custom branch')
    else
      let l:op_id = plugin_manager#ui#start_operation(l:module.short_name, 'Checking')
      call plugin_manager#ui#complete_operation(l:op_id, 'info', 'Up-to-date')
    endif
  endfor

  if empty(l:modules_to_update)
    return
  endif

  let l:updated_modules = []

  for l:i in range(len(l:modules_to_update))
    let l:module = l:modules_to_update[l:i]
    let l:op_id = l:pending_ops[l:i]
    let l:update_status = plugin_manager#git#collect_status_local(l:module.path)
    let l:before_commit = l:update_status.current_commit
    let l:branch = plugin_manager#git#remote_branch_name(l:update_status.remote_branch)
    let l:pull_flag = plugin_manager#core#get_pull_flag()

    " Stash per-module, only for modules that will actually be pulled
    let l:had_stash = s:stash_if_needed(l:module.path)

    call plugin_manager#ui#update_operation(l:op_id, 'Updating')
    let l:result = plugin_manager#git#execute('git pull origin ' . shellescape(l:branch) . ' ' . l:pull_flag, l:module.path, 0, 0)

    " Restore stashed changes regardless of pull outcome
    if l:had_stash
      call s:stash_pop(l:module.path, l:op_id)
    endif

    if l:result.success
      let l:changed = plugin_manager#git#head_changed(l:module.path, l:before_commit)

      if l:changed
        call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Updated')
        call add(l:updated_modules, l:module)
      else
        call plugin_manager#ui#complete_operation(l:op_id, 'info', 'Up-to-date')
      endif
    else
      call plugin_manager#ui#complete_operation(l:op_id, 'fail', 'Update failed')
      call plugin_manager#ui#log_detail('update', l:result.output)
    endif
  endfor

  if !empty(l:updated_modules) && plugin_manager#core#should_auto_commit()
    call plugin_manager#git#execute('git commit -am "Update Modules"', '', 0, 0)
  endif

  for l:module in l:updated_modules
    call plugin_manager#cmd#helptags#execute(0, l:module.short_name, 1)
  endfor

  let l:n = len(l:updated_modules)
  let l:total = len(a:ctx.valid_modules)
  if l:n > 0
    call plugin_manager#ui#footer([plugin_manager#ui#success(l:n . ' of ' . l:total . ' plugins updated')])
  else
    call plugin_manager#ui#footer([plugin_manager#ui#info('All ' . l:total . ' plugins are up-to-date')])
  endif
endfunction

" Async update all plugins - block instant + parallel fan-out
function! s:update_all_plugins_async(ctx) abort
  let a:ctx.updated_modules = []
  let a:ctx.ops = {}
  let a:ctx.pending = 0
  let a:ctx.pre_commits = {}
  
  " Pre-render all plugin lines as a block with pending spinners
  for l:module in a:ctx.valid_modules
    let l:op_id = plugin_manager#ui#start_operation(l:module.short_name, 'Pending')
    let a:ctx.ops[l:module.short_name] = l:op_id
  endfor
  
  " Fetch all at once first - stash will happen per-module only if a pull is needed
  call plugin_manager#async#git('git submodule foreach --recursive "git fetch origin"', {
        \ 'callback': function('s:on_batch_fetched', [a:ctx])
        \ })
endfunction

function! s:on_batch_fetched(ctx, result) abort
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
  let l:module_path = a:module.path

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

  " Pull with the correct remote branch
  call plugin_manager#ui#update_operation(l:op_id, 'Updating')
  let l:branch = plugin_manager#git#remote_branch_name(l:update_status.remote_branch)
  let l:pull_flag = plugin_manager#core#get_pull_flag()
  let l:update_cmd = 'git -C ' . shellescape(l:module_path) . ' pull origin ' . l:branch . ' ' . l:pull_flag
  call plugin_manager#async#git(l:update_cmd, {
        \ 'callback': function('s:on_module_updated', [a:ctx, a:module])
        \ })
endfunction

function! s:on_module_updated(ctx, module, result) abort
  let l:op_id = a:ctx.ops[a:module.short_name]
  let l:module_path = a:module.path
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
    if plugin_manager#core#should_auto_commit()
      call plugin_manager#git#execute('git commit -am "Update Modules"', '', 0, 0)
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

function! s:commit_update_async(module_name) abort
  " Respect the auto-commit configuration
  if !plugin_manager#core#should_auto_commit()
    return
  endif
  let l:status_cmd = 'git status -s'
  call plugin_manager#async#git(l:status_cmd, {
        \ 'callback': function('s:on_status_check_complete', [a:module_name])
        \ })
endfunction

function! s:on_status_check_complete(module_name, result) abort
  if !empty(a:result.output)
    let l:commit_cmd = 'git commit -am "Update Module: ' . a:module_name . '"'
    call plugin_manager#async#git(l:commit_cmd, {})
  endif
endfunction
