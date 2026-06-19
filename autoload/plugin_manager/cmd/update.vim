" autoload/plugin_manager/cmd/update.vim - Simplified update command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4.0

" ------------------------------------------------------------------------------
" MAIN UPDATE COMMAND
" ------------------------------------------------------------------------------

function! plugin_manager#cmd#update#execute(module_name) abort
  try
    if !plugin_manager#core#ensure_vim_directory()
      call plugin_manager#core#throw('update', 'NOT_VIM_DIR', 'Not in Vim configuration directory')
    endif
    
    let l:header = ['Updating Plugins:', plugin_manager#ui#get_symbol('separator'), '']
    call plugin_manager#ui#open_sidebar(l:header)
    
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
  let l:module_info = plugin_manager#git#find_module(a:ctx.module_name)
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
  
  " Stash changes
  call plugin_manager#git#execute('git stash -q || true', l:module_path, 0, 0)
  
  " Check for updates
  let l:update_status = plugin_manager#git#check_updates(l:module_path)
  
  if l:update_status.different_branch && l:update_status.branch != 'detached'
    call plugin_manager#ui#complete_operation(l:op_id, 1, 'On custom branch')
    return
  endif
  
  if !l:update_status.has_updates
    call plugin_manager#ui#complete_operation(l:op_id, 1, 'Already up-to-date')
    return
  endif
  
  " Update
  if plugin_manager#git#update_submodule(l:module_path)
    call plugin_manager#ui#complete_operation(l:op_id, 1, 'Updated successfully')
    call plugin_manager#cmd#helptags#execute(0, l:module_name, 1)
  else
    call plugin_manager#ui#complete_operation(l:op_id, 0, 'Update failed')
  endif
endfunction

" Async update for single plugin
function! s:update_specific_plugin_async(ctx) abort
  let l:op_id = plugin_manager#ui#start_operation(a:ctx.module_short_name, 'Updating')
  let a:ctx.op_id = l:op_id
  
  " Step 1: Stash
  call plugin_manager#ui#update_operation(l:op_id, 'Stashing changes')
  call plugin_manager#async#git('git -C "' . a:ctx.module_path . '" stash -q || true', {
        \ 'callback': function('s:on_stash_complete', [a:ctx])
        \ })
endfunction

function! s:on_stash_complete(ctx, result) abort
  let l:op_id = a:ctx.op_id
  let l:module_path = a:ctx.module_path
  
  " Step 2: Fetch
  call plugin_manager#ui#update_operation(l:op_id, 'Fetching updates')
  call plugin_manager#async#git('git -C "' . l:module_path . '" fetch origin', {
        \ 'callback': function('s:on_fetch_complete', [a:ctx])
        \ })
endfunction

function! s:on_fetch_complete(ctx, result) abort
  let l:op_id = a:ctx.op_id
  let l:module_path = a:ctx.module_path
  let l:module_name = a:ctx.module_short_name
  
  call plugin_manager#ui#update_operation(l:op_id, 'Checking status')
  
  " Fetch already done as an async job; only fast local analysis here
  let l:update_status = plugin_manager#git#collect_status_local(l:module_path)
  
  if l:update_status.different_branch && l:update_status.branch != 'detached'
    call plugin_manager#ui#complete_operation(l:op_id, 1, 'On custom branch')
    return
  endif
  
  if !l:update_status.has_updates
    call plugin_manager#ui#complete_operation(l:op_id, 1, 'Already up-to-date')
    return
  endif
  
  " Step 3: Pull updates using the configured pull strategy
  call plugin_manager#ui#update_operation(l:op_id, 'Pulling changes')
  let l:pull_flag = plugin_manager#core#get_pull_flag()
  call plugin_manager#async#git('git -C "' . l:module_path . '" pull origin ' . l:update_status.remote_branch . ' ' . l:pull_flag, {
        \ 'callback': function('s:on_update_complete', [a:ctx])
        \ })
endfunction

function! s:on_update_complete(ctx, result) abort
  let l:op_id = a:ctx.op_id
  let l:module_name = a:ctx.module_short_name
  let l:success = a:result.status == 0
  
  if l:success
    call plugin_manager#ui#complete_operation(l:op_id, 1, 'Updated successfully')
    call plugin_manager#cmd#helptags#execute(0, l:module_name, 1)
    call s:commit_update_async(l:module_name)
  else
    call plugin_manager#ui#complete_operation(l:op_id, 0, 'Update failed')
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
  call plugin_manager#git#execute('git submodule foreach --recursive "git stash -q || true"', '', 0, 0)
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
      let l:op_id = plugin_manager#ui#start_operation(l:module.short_name, 'Skipped')
      call plugin_manager#ui#complete_operation(l:op_id, 1, 'On custom branch')
    else
      let l:op_id = plugin_manager#ui#start_operation(l:module.short_name, 'Checking')
      call plugin_manager#ui#complete_operation(l:op_id, 1, 'Up-to-date')
    endif
  endfor
  
  if empty(l:modules_to_update)
    return
  endif
  
  let l:result = plugin_manager#git#execute('git submodule update --remote --merge --force', '', 0, 0)
  
  for l:op_id in l:pending_ops
    call plugin_manager#ui#complete_operation(l:op_id, l:result.success,
          \ l:result.success ? 'Updated successfully' : 'Update failed')
  endfor
  
  if l:result.success && plugin_manager#core#should_auto_commit()
    call plugin_manager#git#execute('git commit -am "Update Modules"', '', 0, 0)
  endif
  
  for l:module in l:modules_to_update
    call plugin_manager#cmd#helptags#execute(0, l:module.short_name, 1)
  endfor
endfunction

" Async update all plugins - block instant + parallel fan-out
function! s:update_all_plugins_async(ctx) abort
  let a:ctx.updated_modules = []
  let a:ctx.ops = {}
  let a:ctx.pending = 0
  
  " Pre-render all plugin lines as a block with pending spinners
  for l:module in a:ctx.valid_modules
    let l:op_id = plugin_manager#ui#start_operation(l:module.short_name, 'Pending')
    let a:ctx.ops[l:module.short_name] = l:op_id
  endfor
  
  " Stash all at once
  call plugin_manager#async#git('git submodule foreach --recursive "git stash -q || true"', {
        \ 'callback': function('s:on_all_stashed', [a:ctx])
        \ })
endfunction

function! s:on_all_stashed(ctx, result) abort
  " Fetch all at once, then fan-out when done
  call plugin_manager#async#git('git submodule foreach --recursive "git fetch origin"', {
        \ 'callback': function('s:on_batch_fetched', [a:ctx])
        \ })
endfunction

function! s:on_batch_fetched(ctx, result) abort
  let a:ctx.pending = len(a:ctx.valid_modules)
  
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
  
  if l:update_status.different_branch && l:update_status.branch != 'detached'
    call plugin_manager#ui#complete_operation(l:op_id, 1, 'On custom branch')
    let a:ctx.pending -= 1
    call s:maybe_finalize(a:ctx)
    return
  endif
  
  if !l:update_status.has_updates
    call plugin_manager#ui#complete_operation(l:op_id, 1, 'Up-to-date')
    let a:ctx.pending -= 1
    call s:maybe_finalize(a:ctx)
    return
  endif
  
  " Needs update: run submodule update
  call plugin_manager#ui#update_operation(l:op_id, 'Updating')
  let l:update_cmd = 'git submodule update --remote --merge --force -- ' . shellescape(l:module_path)
  call plugin_manager#async#git(l:update_cmd, {
        \ 'callback': function('s:on_module_updated', [a:ctx, a:module])
        \ })
endfunction

function! s:on_module_updated(ctx, module, result) abort
  let l:op_id = a:ctx.ops[a:module.short_name]
  let l:success = a:result.status == 0
  
  if l:success
    call plugin_manager#ui#complete_operation(l:op_id, 1, 'Updated successfully')
    call add(a:ctx.updated_modules, a:module)
  else
    call plugin_manager#ui#complete_operation(l:op_id, 0, 'Update failed')
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
endfunction

" ------------------------------------------------------------------------------
" HELPERS
" ------------------------------------------------------------------------------

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
