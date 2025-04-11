" autoload/plugin_manager/cmd/update.vim - Asynchronous update command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3.4

" Update plugins - main command handler with async support
function! plugin_manager#cmd#update#execute(module_name) abort
  try
    if !plugin_manager#core#ensure_vim_directory()
      throw 'PM_ERROR:update:NOT_VIM_DIR:Not in Vim configuration directory'
    endif
    
    let l:header = ['Updating Plugins:', '-----------------', '']
    call plugin_manager#ui#open_sidebar(l:header)
    
    " Check for async support
    let l:use_async = plugin_manager#async#supported()
    
    " Check if a specific module was specified or 'all'
    if a:module_name ==# 'all'
      " Start async update for all plugins if supported
      if l:use_async
        call s:update_all_plugins_async()
      else
        call s:update_all_plugins_sync()
      endif
    else
      " Update specific plugin
      if l:use_async
        call s:update_specific_plugin_async(a:module_name)
      else
        call s:update_specific_plugin_sync(a:module_name)
      endif
    endif
    
    return 1
  catch
    call plugin_manager#core#handle_error(v:exception, "update")
    return 0
  endtry
endfunction

" Update a specific plugin synchronously (backup method)
function! s:update_specific_plugin_sync(module_name) abort
  " Find the module
  let l:module_info = plugin_manager#git#find_module(a:module_name)
  if empty(l:module_info)
    throw 'PM_ERROR:update:MODULE_NOT_FOUND:Module "' . a:module_name . '" not found'
  endif
  
  let l:module = l:module_info.module
  let l:module_path = l:module.path
  let l:module_name = l:module.short_name
  
  call plugin_manager#ui#update_sidebar(['Updating plugin: ' . l:module_name . ' (' . l:module_path . ')...'], 1)
  
  " Check if directory exists
  if !plugin_manager#core#dir_exists(l:module_path)
    throw 'PM_ERROR:update:PATH_NOT_FOUND:Module directory "' . l:module_path . '" not found. Try running "PluginManager restore"'
  endif
  
  " Stash local changes if any
  call s:stash_module_changes_sync(l:module_path)
  
  " Check update status
  let l:update_status = plugin_manager#git#check_updates(l:module_path)
  
  " Handle custom branch scenario
  if l:update_status.different_branch && l:update_status.branch != 'detached'
    call s:report_custom_branch(l:module_name, l:update_status)
    return
  endif
  
  " Check if module has updates
  if !l:update_status.has_updates
    call plugin_manager#ui#update_sidebar(['Plugin "' . l:module_name . '" is already up-to-date.'], 1)
    return
  endif
  
  " Update the module
  call plugin_manager#ui#update_sidebar(['Updates available. Updating plugin...'], 1)
  if plugin_manager#git#update_submodule(l:module_path)
    " Record the update in our list
    call s:show_update_details(l:module)
    
    " Generate helptags
    call plugin_manager#cmd#helptags#execute(0, l:module_name)
  else
    call plugin_manager#ui#update_sidebar(['Error updating plugin.'], 1)
  endif
endfunction

" Stash local changes in a module (sync method)
function! s:stash_module_changes_sync(module_path) abort
  call plugin_manager#ui#update_sidebar(['Checking for local changes...'], 1)
  
  let l:status = plugin_manager#git#execute('git status -s', a:module_path, 0, 0)
  if !empty(l:status.output)
    call plugin_manager#ui#update_sidebar(['Stashing local changes...'], 1)
    call plugin_manager#git#execute('git stash -q || true', a:module_path, 0, 0)
  else
    call plugin_manager#ui#update_sidebar(['No local changes to stash.'], 1)
  endif
endfunction

" Show update details for a module
function! s:show_update_details(module) abort
  let l:log = plugin_manager#git#execute('git log -1 --format="%h %s"', a:module.path, 0, 0)
  if l:log.success && !empty(l:log.output)
    let l:commit_info = substitute(l:log.output, '\n', '', 'g')
    call plugin_manager#ui#update_sidebar(['Updated ' . a:module.short_name . ' to: ' . l:commit_info], 1)
  else
    call plugin_manager#ui#update_sidebar(['Updated ' . a:module.short_name . ' successfully.'], 1)
  endif
endfunction

" Report on a custom branch
function! s:report_custom_branch(module_name, update_status) abort
  call plugin_manager#ui#update_sidebar([
        \ 'Plugin "' . a:module_name . '" is on a custom branch:', 
        \ '- Local branch: ' . a:update_status.branch,
        \ '- Target branch: ' . a:update_status.remote_branch,
        \ 'To preserve your branch choice, the plugin will not be updated automatically.',
        \ 'To update anyway, run: git submodule update --remote --force -- "[path]"'
        \ ], 1)
endfunction

" Update all plugins synchronously
function! s:update_all_plugins_sync() abort
  " Parse gitmodules
  let l:modules = plugin_manager#git#parse_modules()
  
  if empty(l:modules)
    throw 'PM_ERROR:update:NO_PLUGINS:No plugins to update (.gitmodules not found)'
  endif
  
  call plugin_manager#ui#update_sidebar(['Stashing any local changes in submodules...'], 1)
  call plugin_manager#git#execute('git submodule foreach --recursive "git stash -q || true"', '', 1, 0)
  
  call plugin_manager#ui#update_sidebar(['Fetching updates from remote repositories...'], 1)
  call plugin_manager#git#execute('git submodule foreach --recursive "git fetch origin"', '', 1, 0)
  
  " Find modules that need updates
  let l:modules_with_updates = []
  let l:modules_on_diff_branch = []
  
  call plugin_manager#ui#update_sidebar(['Checking plugins for available updates...'], 1)
  
  " Sort modules by name for consistent display
  let l:module_names = sort(keys(l:modules))
  
  " Process each module
  for l:name in l:module_names
    let l:module = l:modules[l:name]
    if has_key(l:module, 'is_valid') && l:module.is_valid && plugin_manager#core#dir_exists(l:module.path)
      " Check update status
      let l:update_status = plugin_manager#git#check_updates(l:module.path)
      
      " If module is on a different branch, add to special list
      if l:update_status.different_branch && l:update_status.branch != 'detached'
        call add(l:modules_on_diff_branch, {'module': l:module, 'status': l:update_status})
      " If module has updates, add to update list
      elseif l:update_status.has_updates
        call add(l:modules_with_updates, l:module)
      endif
    endif
  endfor
  
  " Report on modules with custom branches
  if !empty(l:modules_on_diff_branch)
    let l:branch_lines = ['', 'The following plugins are on custom branches:']
    for l:item in l:modules_on_diff_branch
      call add(l:branch_lines, '- ' . l:item.module.short_name . 
            \ ' (local: ' . l:item.status.branch . 
            \ ', target: ' . l:item.status.remote_branch . ')')
    endfor
    call add(l:branch_lines, 'These plugins will not be updated automatically to preserve your branch choice.')
    call plugin_manager#ui#update_sidebar(l:branch_lines, 1)
  endif
  
  " Update modules if needed
  if empty(l:modules_with_updates)
    call plugin_manager#ui#update_sidebar(['All plugins are up-to-date.'], 1)
  else
    call plugin_manager#ui#update_sidebar(['Found ' . len(l:modules_with_updates) . ' plugins with updates. Updating...'], 1)
    
    " Execute update command
    call plugin_manager#git#execute('git submodule sync', '', 1, 0)
    call plugin_manager#git#execute('git submodule update --remote --merge --force', '', 1, 1)
    
    " Check if commit is needed
    let l:status = plugin_manager#git#execute('git status -s', '', 0, 0)
    if !empty(l:status.output)
      call plugin_manager#git#execute('git commit -am "Update Modules"', '', 1, 0)
    endif
    
    " Show what was updated
    let l:update_lines = ['', 'Updated plugins:']
    for l:module in l:modules_with_updates
      let l:log = plugin_manager#git#execute('git log -1 --format="%h %s"', l:module.path, 0, 0)
      if l:log.success && !empty(l:log.output)
        let l:commit_info = substitute(l:log.output, '\n', '', 'g')
        call add(l:update_lines, l:module.short_name . ': ' . l:commit_info)
      else
        call add(l:update_lines, l:module.short_name)
      endif
    endfor
    
    call plugin_manager#ui#update_sidebar(l:update_lines, 1)
    call plugin_manager#ui#update_sidebar(['', 'Update completed successfully.'], 1)
    
    " Generate helptags
    call plugin_manager#cmd#helptags#execute(0)
  endif
endfunction

" Update a specific plugin asynchronously
function! s:update_specific_plugin_async(module_name) abort
  " Find the module first
  let l:module_info = plugin_manager#git#find_module(a:module_name)
  if empty(l:module_info)
    throw 'PM_ERROR:update:MODULE_NOT_FOUND:Module "' . a:module_name . '" not found'
  endif
  
  let l:module = l:module_info.module
  let l:module_path = l:module.path
  let l:module_name = l:module.short_name
  
  " Create a task for this update
  let l:task_id = plugin_manager#ui#start_task('Updating plugin: ' . l:module_name, 4, {
        \ 'spinner': 0,
        \ 'progress': 1, 
        \ 'type': 'update'
        \ })
  
  " Update sidebar with current action
  let l:info_symbol = plugin_manager#ui#get_symbol('info')
  call plugin_manager#ui#update_sidebar(['Current action: Checking repository status ' . l:info_symbol], 1)
  let l:action_line = line('$')
  
  " Check if directory exists
  if !plugin_manager#core#dir_exists(l:module_path)
    call plugin_manager#ui#update_task(l:task_id, 4, '', 'Error: Directory not found')
    call plugin_manager#ui#complete_task(l:task_id, 0, 'Failed: Module directory not found')
    throw 'PM_ERROR:update:PATH_NOT_FOUND:Module directory "' . l:module_path . '" not found. Try running "PluginManager restore"'
  endif
  
  " Store context for callbacks
  let l:ctx = {
        \ 'task_id': l:task_id,
        \ 'module': l:module,
        \ 'module_path': l:module_path,
        \ 'module_name': l:module_name,
        \ 'action_line': l:action_line,
        \ 'progress': 0,
        \ 'has_updates': 0,
        \ 'update_status': {},
        \ }
  
  " Step 1: Stash changes
  call s:update_current_action(l:ctx, 'Stashing local changes')
  call plugin_manager#ui#update_task(l:task_id, 1, '', 'Stashing local changes...')
  
  call plugin_manager#async#git('git -C "' . l:module_path . '" stash -q || true', {
        \ 'callback': function('s:on_stash_complete', [l:ctx]),
        \ 'ui_message': ''
        \ })
endfunction

" Update the current action display
function! s:update_current_action(ctx, message) abort
  let l:win_id = bufwinid('PluginManager')
  if l:win_id == -1
    return
  endif
  
  " Focus the window to update the action line
  call win_gotoid(l:win_id)
  setlocal modifiable
  
  " Update the action line with info symbol
  let l:info_symbol = plugin_manager#ui#get_symbol('info')
  let l:action_text = 'Current action: ' . a:message . ' ' . l:info_symbol
  call setline(a:ctx.action_line, l:action_text)
  
  setlocal nomodifiable
endfunction

" After stashing changes - check for updates
function! s:on_stash_complete(ctx, result) abort
  let l:task_id = a:ctx.task_id
  let l:module_path = a:ctx.module_path
  let l:module_name = a:ctx.module_name
  
  " Step 2: Fetch updates
  call s:update_current_action(a:ctx, 'Fetching updates')
  call plugin_manager#ui#update_task(l:task_id, 2, '', 'Checking for updates...')
  
  call plugin_manager#async#git('git -C "' . l:module_path . '" fetch origin', {
        \ 'callback': function('s:on_fetch_complete', [a:ctx]),
        \ 'ui_message': ''
        \ })
endfunction

" After fetching updates - determine if updates are available
function! s:on_fetch_complete(ctx, result) abort
    let l:task_id = a:ctx.task_id
    let l:module_path = a:ctx.module_path
    let l:module_name = a:ctx.module_name
    
    call s:update_current_action(a:ctx, 'Comparing with remote')
    call plugin_manager#ui#update_task(l:task_id, 3, '', 'Determining update status...')
    
    " Check update status (this is sync but typically fast)
    let l:update_status = plugin_manager#git#check_updates(l:module_path)
    let a:ctx.update_status = l:update_status
    
    " Handle custom branch scenario
    if l:update_status.different_branch && l:update_status.branch != 'detached'
      call plugin_manager#ui#update_task(l:task_id, 4, '', 'Plugin is on a custom branch: ' . l:update_status.branch)
      call plugin_manager#ui#complete_task(l:task_id, 1, 'Plugin is on a custom branch (skipped)')
      call s:report_custom_branch(l:module_name, l:update_status)
      return
    endif
    
    " Check if module has updates
    if !l:update_status.has_updates
      call plugin_manager#ui#update_task(l:task_id, 4, '', 'No updates available')
      call plugin_manager#ui#complete_task(l:task_id, 1, 'Plugin is already up-to-date')
      
      " Show temporary message that will disappear after 1 seconds
      call plugin_manager#ui#show_temporary_message(a:ctx.action_line, 'No updates needed for ' . l:module_name, 1)
      return
    endif
    
    " Set flag for updates
    let a:ctx.has_updates = 1
    
    " Step 3: Update the module
    call s:update_current_action(a:ctx, 'Pulling updates')
    call plugin_manager#ui#update_task(l:task_id, 3, '', 'Updates available. Updating plugin...')
    
    " Execute the update command
    call plugin_manager#async#git('git -C "' . l:module_path . '" pull origin ' . l:update_status.remote_branch . ' --ff-only', {
          \ 'callback': function('s:on_update_complete', [a:ctx]),
          \ 'ui_message': ''
          \ })
endfunction

" After updating - finalize and generate helptags
function! s:on_update_complete(ctx, result) abort
  let l:task_id = a:ctx.task_id
  let l:module = a:ctx.module
  let l:module_path = a:ctx.module_path
  let l:module_name = a:ctx.module_name
  let l:success = a:result.status == 0
  
  if l:success
    call s:update_current_action(a:ctx, 'Generating helptags')
    call plugin_manager#ui#update_task(l:task_id, 4, '', 'Update successful. Generating helptags...')
    
    " Get the latest commit info for display
    let l:log = plugin_manager#git#execute('git log -1 --format="%h %s"', l:module_path, 0, 0)
    let l:commit_info = l:log.success ? substitute(l:log.output, '\n', '', 'g') : 'unknown'
    
    " Generate helptags in async mode
    call plugin_manager#cmd#helptags#execute(0, l:module_name)
    
    " Complete the task
    call plugin_manager#ui#complete_task(l:task_id, 1, 'Updated to: ' . l:commit_info)
    
    " Commit the changes to the main repository
    call s:commit_update_async(l:module_name)
  else
    call plugin_manager#ui#update_task(l:task_id, 4, '', 'Update failed: ' . a:result.output)
    call plugin_manager#ui#complete_task(l:task_id, 0, 'Failed to update plugin')
  endif
endfunction

" Commit updates to main repository asynchronously
function! s:commit_update_async(module_name) abort
  " Check if there are changes to commit
  let l:status_cmd = 'git status -s'
  call plugin_manager#async#git(l:status_cmd, {
        \ 'callback': function('s:on_status_check_complete', [a:module_name]),
        \ })
endfunction

" After checking status - commit if needed
function! s:on_status_check_complete(module_name, result) abort
  if !empty(a:result.output)
    " Commit the changes
    let l:commit_cmd = 'git commit -am "Update Module: ' . a:module_name . '"'
    call plugin_manager#async#git(l:commit_cmd, {
          \ 'ui_message': 'Committing changes for ' . a:module_name
          \ })
  endif
endfunction

" Update all plugins asynchronously
function! s:update_all_plugins_async() abort
  " Parse gitmodules
  let l:modules = plugin_manager#git#parse_modules()
  
  if empty(l:modules)
    throw 'PM_ERROR:update:NO_PLUGINS:No plugins to update (.gitmodules not found)'
  endif
  
  " Sort modules by name for consistent display
  let l:module_names = sort(keys(l:modules))
  let l:total_modules = len(l:module_names)
  let l:valid_modules = []
  
  " Collect valid modules
  for l:name in l:module_names
    let l:module = l:modules[l:name]
    if has_key(l:module, 'is_valid') && l:module.is_valid && plugin_manager#core#dir_exists(l:module.path)
      call add(l:valid_modules, l:module)
    endif
  endfor
  
  " Create task for tracking progress
  let l:task_id = plugin_manager#ui#start_task('Updating ' . len(l:valid_modules) . ' plugins', len(l:valid_modules), {
        \ 'spinner': 0,
        \ 'progress': 1,
        \ 'type': 'update'
        \ })
  
  " Add line for current action
  let l:info_symbol = plugin_manager#ui#get_symbol('info')
  call plugin_manager#ui#update_sidebar(['Current plugin: Initializing... ' . l:info_symbol], 1)
  let l:action_line = line('$')
  
  " Store context for callbacks
  let l:ctx = {
        \ 'task_id': l:task_id,
        \ 'modules': l:valid_modules,
        \ 'total': len(l:valid_modules),
        \ 'current_index': 0,
        \ 'processed': 0,
        \ 'updated': 0,
        \ 'skipped': 0,
        \ 'skipped_custom_branch': [],
        \ 'updated_modules': [],
        \ 'action_line': l:action_line
        \ }
  
  " Start the process
  call s:update_current_plugin(l:ctx, 'Stashing local changes in all modules')
  call plugin_manager#ui#update_task(l:task_id, 0, 'Preparing repositories')
  
  " Stash local changes in all modules at once
  call plugin_manager#async#git('git submodule foreach --recursive "git stash -q || true"', {
        \ 'callback': function('s:on_all_stashed', [l:ctx]),
        \ 'ui_message': ''
        \ })
endfunction

" Update the current plugin display
function! s:update_current_plugin(ctx, message) abort
  let l:win_id = bufwinid('PluginManager')
  if l:win_id == -1
    return
  endif
  
  " Focus the window to update the action line
  call win_gotoid(l:win_id)
  setlocal modifiable
  
  " Update the action line with info symbol
  let l:info_symbol = plugin_manager#ui#get_symbol('info')
  let l:action_text = 'Current plugin: ' . a:message . ' ' . l:info_symbol
  call setline(a:ctx.action_line, l:action_text)
  
  setlocal nomodifiable
endfunction

" After stashing all modules - start processing immediately while fetch runs in background
function! s:on_all_stashed(ctx, result) abort
  " Start the fetch in background - don't wait for it to complete
  call plugin_manager#async#git('git submodule foreach --recursive "git fetch origin"', {
        \ 'ui_message': ''
        \ })
  
  " Begin processing modules immediately
  call s:update_current_plugin(a:ctx, 'Starting to process plugins')
  call plugin_manager#ui#update_task(a:ctx.task_id, 0, 'Processing plugins')
  
  " Start processing modules without waiting for fetch to complete
  call timer_start(50, {timer -> s:process_next_module_update(a:ctx)})
endfunction

" Process next module for update with parallel fetch
function! s:process_next_module_update(ctx) abort
  " Check if we're done
  if a:ctx.current_index >= len(a:ctx.modules)
    call s:finalize_update_all(a:ctx)
    return
  endif
  
  " Get current module
  let l:module = a:ctx.modules[a:ctx.current_index]
  let l:module_path = l:module.path
  let l:module_name = l:module.short_name
  
  " Update progress
  let l:progress_msg = 'Processed ' . a:ctx.processed . '/' . a:ctx.total . ' plugins'
  call plugin_manager#ui#update_task(a:ctx.task_id, a:ctx.processed, l:progress_msg)
  
  " Update current module display
  call s:update_current_plugin(a:ctx, 'Checking ' . l:module_name)
  
  " First make sure this module has been fetched
  " This ensures we don't try to make decisions before fetch completes for this module
  call plugin_manager#async#git('git -C "' . l:module_path . '" fetch origin', {
        \ 'callback': function('s:on_module_fetched', [a:ctx, l:module]),
        \ 'ui_message': ''
        \ })
endfunction

" After an individual module fetch completes, check its status
function! s:on_module_fetched(ctx, module, result) abort
  let l:module_path = a:module.path
  let l:module_name = a:module.short_name
  
  " Update current module display
  call s:update_current_plugin(a:ctx, 'Analyzing ' . l:module_name)
  
  " Check update status
  let l:update_status = plugin_manager#git#check_updates(l:module_path)
  
  " Handle custom branch scenario
  if l:update_status.different_branch && l:update_status.branch != 'detached'
    call add(a:ctx.skipped_custom_branch, {
          \ 'module': a:module,
          \ 'status': l:update_status
          \ })
    
    " Move to next module
    let a:ctx.current_index += 1
    let a:ctx.processed += 1
    let a:ctx.skipped += 1
    call s:process_next_module_update(a:ctx)
    return
  endif
  
  " Check if module has updates
  if !l:update_status.has_updates
    " No updates needed
    let a:ctx.current_index += 1
    let a:ctx.processed += 1
    call s:process_next_module_update(a:ctx)
    return
  endif
  
  " Module needs update
  call s:update_current_plugin(a:ctx, 'Updating ' . l:module_name)
  
  " Update this module
  let l:update_cmd = 'git submodule update --remote --merge --force -- ' . shellescape(l:module_path)
  call plugin_manager#async#git(l:update_cmd, {
        \ 'callback': function('s:on_module_updated', [a:ctx, a:module]),
        \ 'ui_message': ''
        \ })
endfunction

" After a module update completes
function! s:on_module_updated(ctx, module, result) abort
  let l:success = a:result.status == 0
  
  if l:success
    " Get update info
    let l:log = plugin_manager#git#execute('git log -1 --format="%h %s"', a:module.path, 0, 0)
    let l:commit_info = l:log.success ? substitute(l:log.output, '\n', '', 'g') : 'unknown'
    
    " Record the updated module
    call add(a:ctx.updated_modules, {
          \ 'module': a:module,
          \ 'commit_info': l:commit_info
          \ })
    
    let a:ctx.updated += 1
  endif
  
  " Move to next module
  let a:ctx.current_index += 1
  let a:ctx.processed += 1
  call s:process_next_module_update(a:ctx)
endfunction

" Finalize the update all process
function! s:finalize_update_all(ctx) abort
  " Check if any modules were updated
  if empty(a:ctx.updated_modules)
    " No updates were performed
    call plugin_manager#ui#update_task(a:ctx.task_id, a:ctx.total, 'All plugins are up-to-date')
    call plugin_manager#ui#complete_task(a:ctx.task_id, 1, 'All plugins are up-to-date')
    
    " Show temporary message that will disappear after 1 seconds
    call plugin_manager#ui#show_temporary_message(a:ctx.action_line, 'No updates were needed', 1)
    
    return
  endif
  
  " Commit changes if needed
  call plugin_manager#ui#update_task(a:ctx.task_id, a:ctx.total, 'Finalizing updates')
  call s:update_current_plugin(a:ctx, 'Committing changes')
  
  " Check if commit is needed
  let l:status = plugin_manager#git#execute('git status -s', '', 0, 0)
  if !empty(l:status.output)
    call plugin_manager#git#execute('git commit -am "Update Modules"', '', 0, 0)
  endif
  
  " Report on modules with custom branches
  if !empty(a:ctx.skipped_custom_branch)
    let l:branch_lines = ['', 'The following plugins were on custom branches (skipped):']
    for l:item in a:ctx.skipped_custom_branch
      call add(l:branch_lines, '- ' . l:item.module.short_name . 
            \ ' (local: ' . l:item.status.branch . 
            \ ', target: ' . l:item.status.remote_branch . ')')
    endfor
    call plugin_manager#ui#update_sidebar(l:branch_lines, 1)
  endif
  
  " Show what was updated
  let l:update_lines = ['', 'Updated plugins:']
  for l:item in a:ctx.updated_modules
    call add(l:update_lines, l:item.module.short_name . ': ' . l:item.commit_info)
  endfor
  
  call plugin_manager#ui#update_sidebar(l:update_lines, 1)
  
  " Generate helptags for all updated modules
  call plugin_manager#cmd#helptags#execute(0)
  
  " Complete the task
  let l:summary = 'Updated ' . a:ctx.updated . ' plugins'
  if a:ctx.skipped > 0
    let l:summary .= ', skipped ' . a:ctx.skipped . ' on custom branches'
  endif
  
  call plugin_manager#ui#complete_task(a:ctx.task_id, 1, l:summary)
  let l:win_id = bufwinid('PluginManager')
  if l:win_id != -1
    call win_gotoid(l:win_id)
    setlocal modifiable
    call setline(a:ctx.action_line, 'Update completed successfully')
    setlocal nomodifiable
  endif
endfunction