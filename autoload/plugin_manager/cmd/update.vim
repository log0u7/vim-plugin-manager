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
    call plugin_manager#cmd#helptags#execute(0, l:module_name)
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
  
  " Check update status
  let l:update_status = plugin_manager#git#check_updates(l:module_path)
  
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
    call plugin_manager#cmd#helptags#execute(0, l:module_name)
    call s:commit_update_async(l:module_name)
  else
    call plugin_manager#ui#complete_operation(l:op_id, 0, 'Update failed')
    call s:report_job_errors(a:result)
  endif
endfunction

" Surface detailed error output from a failed async job
function! s:report_job_errors(result) abort
  let l:detail = ''
  if has_key(a:result, 'errors') && !empty(a:result.errors)
    let l:detail = a:result.errors
  elseif has_key(a:result, 'output') && !empty(a:result.output)
    let l:detail = a:result.output
  endif

  if !empty(l:detail)
    let l:lines = [plugin_manager#ui#error('Details:')]
    call extend(l:lines, split(l:detail, "\n"))
    call plugin_manager#ui#update_sidebar(l:lines, 1)
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
  
  " Find modules that need updates, tracking their operation IDs
  let l:modules_to_update = []
  let l:pending_ops = []
  
  for l:name in a:ctx.module_names
    let l:module = a:ctx.modules[l:name]
    if has_key(l:module, 'is_valid') && l:module.is_valid && plugin_manager#core#dir_exists(l:module.path)
      let l:update_status = plugin_manager#git#check_updates(l:module.path)
      
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
    endif
  endfor
  
  if empty(l:modules_to_update)
    return
  endif
  
  " Execute update
  let l:result = plugin_manager#git#execute('git submodule update --remote --merge --force', '', 0, 0)
  
  " Mark each pending operation as complete
  for l:op_id in l:pending_ops
    call plugin_manager#ui#complete_operation(l:op_id, l:result.success,
          \ l:result.success ? 'Updated successfully' : 'Update failed')
  endfor
  
  " Commit the updated submodule pointers if configured
  if l:result.success && plugin_manager#core#should_auto_commit()
    call plugin_manager#git#execute('git commit -am "Update Modules"', '', 0, 0)
  endif
  
  call plugin_manager#cmd#helptags#execute(0)
endfunction

" Async update all plugins
function! s:update_all_plugins_async(ctx) abort
  let a:ctx.current_index = 0
  let a:ctx.updated_modules = []
  
  " Stash all at once
  call plugin_manager#async#git('git submodule foreach --recursive "git stash -q || true"', {
        \ 'callback': function('s:on_all_stashed', [a:ctx])
        \ })
endfunction

function! s:on_all_stashed(ctx, result) abort
  " Start fetch in background
  call plugin_manager#async#git('git submodule foreach --recursive "git fetch origin"', {})
  
  " Start processing modules
  call timer_start(50, {timer -> s:process_next_module_update(a:ctx)})
endfunction

function! s:process_next_module_update(ctx) abort
  if a:ctx.current_index >= len(a:ctx.valid_modules)
    call s:finalize_update_all(a:ctx)
    return
  endif
  
  let l:module = a:ctx.valid_modules[a:ctx.current_index]
  let l:module_path = l:module.path
  let l:module_name = l:module.short_name
  
  " Start operation for this module with [i/N] progress
  let l:progress = '[' . (a:ctx.current_index + 1) . '/' . len(a:ctx.valid_modules) . ']'
  let l:op_id = plugin_manager#ui#start_operation(l:module_name, 'Checking ' . l:progress)
  
  " Fetch this module
  call plugin_manager#async#git('git -C "' . l:module_path . '" fetch origin', {
        \ 'callback': function('s:on_module_fetched', [a:ctx, l:module, l:op_id])
        \ })
endfunction

function! s:on_module_fetched(ctx, module, op_id, result) abort
  let l:module_path = a:module.path
  let l:module_name = a:module.short_name
  
  call plugin_manager#ui#update_operation(a:op_id, 'Analyzing')
  
  let l:update_status = plugin_manager#git#check_updates(l:module_path)
  
  if l:update_status.different_branch && l:update_status.branch != 'detached'
    call plugin_manager#ui#complete_operation(a:op_id, 1, 'On custom branch')
    let a:ctx.current_index += 1
    call s:process_next_module_update(a:ctx)
    return
  endif
  
  if !l:update_status.has_updates
    call plugin_manager#ui#complete_operation(a:op_id, 1, 'Up-to-date')
    let a:ctx.current_index += 1
    call s:process_next_module_update(a:ctx)
    return
  endif
  
  " Update this module
  call plugin_manager#ui#update_operation(a:op_id, 'Updating')
  let l:update_cmd = 'git submodule update --remote --merge --force -- ' . shellescape(l:module_path)
  call plugin_manager#async#git(l:update_cmd, {
        \ 'callback': function('s:on_module_updated', [a:ctx, a:module, a:op_id])
        \ })
endfunction

function! s:on_module_updated(ctx, module, op_id, result) abort
  let l:success = a:result.status == 0
  
  if l:success
    call plugin_manager#ui#complete_operation(a:op_id, 1, 'Updated successfully')
    call add(a:ctx.updated_modules, a:module)
  else
    call plugin_manager#ui#complete_operation(a:op_id, 0, 'Update failed')
    call s:report_job_errors(a:result)
  endif
  
  let a:ctx.current_index += 1
  call s:process_next_module_update(a:ctx)
endfunction

function! s:finalize_update_all(ctx) abort
  if !empty(a:ctx.updated_modules)
    if plugin_manager#core#should_auto_commit()
      call plugin_manager#git#execute('git commit -am "Update Modules"', '', 0, 0)
    endif
    call plugin_manager#cmd#helptags#execute(0)
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