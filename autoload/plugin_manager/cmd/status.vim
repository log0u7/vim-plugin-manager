" autoload/plugin_manager/cmd/status.vim - Status command with async support
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3.4

" Show detailed status of all plugins with async support
function! plugin_manager#cmd#status#execute() abort
  try
    if !plugin_manager#core#ensure_vim_directory()
      throw 'PM_ERROR:status:NOT_VIM_DIR:Not in Vim configuration directory'
    endif
    
    " Use git module to get plugin information
    let l:modules = plugin_manager#git#parse_modules()
    let l:header = 'Submodule Status:'
    
    if empty(l:modules)
      let l:lines = [l:header, repeat('-', len(l:header)), '', 'No submodules found (.gitmodules not found)']
      call plugin_manager#ui#open_sidebar(l:lines)
      return
    endif
    
    " Initial display with just the header - we'll add processing info after that
    let l:lines = [l:header, repeat('-', len(l:header)), '']
    call plugin_manager#ui#open_sidebar(l:lines)
    
    " Check if we can use async
    let l:use_async = plugin_manager#async#supported()
    
    if l:use_async
      call s:fetch_status_async(l:modules)
    else
      call s:fetch_status_sync(l:modules)
    endif
  catch
    call plugin_manager#core#handle_error(v:exception, "status")
  endtry
endfunction

" Synchronous status fetching (fallback method)
function! s:fetch_status_sync(modules) abort
  " Update UI to show we're fetching
  call plugin_manager#ui#update_sidebar(['Fetching updates from remote repositories...'], 1)
  
  " Fetch updates to ensure we have up-to-date status information
  call plugin_manager#git#execute('git submodule foreach --recursive "git fetch -q origin 2>/dev/null || true"', '', 1, 0)
  
  " Display table header
  call plugin_manager#ui#update_sidebar([
        \ 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 20).'Last Updated'.repeat(' ', 18).'Status',
        \ repeat('-', 120)
        \ ], 1)
  
  " Sort modules by name for consistent display
  let l:module_names = sort(keys(a:modules))
  
  " Process each module
  for l:name in l:module_names
    let l:module = a:modules[l:name]
    if has_key(l:module, 'is_valid') && l:module.is_valid
      let l:formatted_line = s:format_module_status_line(l:module)
      if !empty(l:formatted_line)
        call plugin_manager#ui#update_sidebar([l:formatted_line], 1)
      endif
    endif
  endfor
  
  call plugin_manager#ui#update_sidebar(['', 'Status check completed.'], 1)
endfunction

" Asynchronous status fetching with improved initialization
function! s:fetch_status_async(modules) abort
  " Sort modules by name for consistent display
  let l:module_names = sort(keys(a:modules))
  let l:total_modules = len(l:module_names)
  " Add a line for the current module with info symbol
  let l:info_symbol = plugin_manager#ui#get_symbol('info')
  " Create task for tracking overall progress first - this creates the progress bar immediately
  let l:task_id = plugin_manager#ui#start_task('Fetching status for ' . l:total_modules . ' plugins', l:total_modules, {
        \ 'type': 'status',
        \ 'progress': 1
        \ })
  
  " Update sidebar with fetching message
  "call plugin_manager#ui#update_sidebar(['Starting: Fetching updates from remote repositories...'], 1)
  call plugin_manager#ui#update_sidebar([l:info_symbol . ' Current module: Preparing...'], 1)
  
  " Store context for callbacks
  let l:ctx = {
        \ 'task_id': l:task_id,
        \ 'modules': a:modules,
        \ 'module_names': l:module_names,
        \ 'current_index': 0,
        \ 'total': l:total_modules,
        \ 'processed': 0,
        \ 'results': [],
        \ 'module_line': line('$'),
        \ }
  
  " Start fetching immediately instead of with a delay
  call s:start_fetch_async(l:ctx, 0)
  
  return l:task_id
endfunction

" Start the actual fetching process
function! s:start_fetch_async(ctx, timer) abort
  let l:task_id = a:ctx.task_id
  
  " Split the git fetch operation to be more responsive
  " First, do a quick check if any modules need updates
  call plugin_manager#ui#update_task(l:task_id, 0, 'Checking repository status')
  
  " Begin processing modules immediately without waiting for all fetches
  call s:on_fetch_complete(a:ctx, {'success': 1, 'output': ''})
  
  " Start the full fetch in background (will continue updating as modules are processed)
  call plugin_manager#async#git('git submodule foreach --recursive "git fetch -q origin 2>/dev/null || true"', {
        \ 'ui_message': ''
        \ })
endfunction

" Callback after fetch begins - start processing modules immediately
function! s:on_fetch_complete(ctx, result) abort
  let l:task_id = a:ctx.task_id
  
  " Update progress to indicate we're starting module processing
  call plugin_manager#ui#update_task(l:task_id, 0, 'Processing plugins')
  
  " Update the module line to show we're starting with the first module
  if a:ctx.current_index < len(a:ctx.module_names)
    let l:first_module = a:ctx.module_names[a:ctx.current_index]
    let l:first_module_short_name = a:ctx.modules[l:first_module].short_name
    
    let l:win_id = bufwinid('PluginManager')
    if l:win_id != -1
      call win_gotoid(l:win_id)
      setlocal modifiable
      
      let l:info_symbol = plugin_manager#ui#get_symbol('info')
      let l:status_line = l:info_symbol . ' Current module: ' . l:first_module_short_name
      call setline(a:ctx.module_line, l:status_line)
      
      setlocal nomodifiable
    endif
  endif
  
  " Process modules one by one asynchronously
  call s:process_next_module_async(a:ctx)
endfunction

" Process next module in the queue - without spinner
function! s:process_next_module_async(ctx) abort
  " Check if we're done
  if a:ctx.current_index >= len(a:ctx.module_names)
    call s:finalize_status_async(a:ctx)
    return
  endif
  
  " Get current module
  let l:name = a:ctx.module_names[a:ctx.current_index]
  let l:module = a:ctx.modules[l:name]
  
  " Skip invalid modules
  if !has_key(l:module, 'is_valid') || !l:module.is_valid
    let a:ctx.current_index += 1
    call s:process_next_module_async(a:ctx)
    return
  endif
  
  let l:module_path = l:module.path
  let l:short_name = l:module.short_name
  
  " Update progress bar
  call plugin_manager#ui#update_task(a:ctx.task_id, a:ctx.processed, 'Processed ' . a:ctx.processed . '/' . a:ctx.total . ' plugins')
  
  " Update current module display (without spinner)
  let l:win_id = bufwinid('PluginManager')
  if l:win_id != -1
    call win_gotoid(l:win_id)
    setlocal modifiable
    " Directly update the module line with info symbol
    let l:info_symbol = plugin_manager#ui#get_symbol('info')
    let l:status_line = l:info_symbol . ' Current module: ' . l:short_name
    call setline(a:ctx.module_line, l:status_line)
    setlocal nomodifiable
  endif
  
  " Collect basic module info (these commands are fast)
  let l:info = {
        \ 'module': l:module,
        \ 'commit': 'N/A',
        \ 'branch': 'N/A',
        \ 'last_updated': 'N/A',
        \ 'status': 'OK'
        \ }
  
  " Check if module exists
  if !isdirectory(l:module_path)
    let l:info.status = 'MISSING'
    
    " Add to results
    call add(a:ctx.results, l:info)
    let a:ctx.processed += 1
    let a:ctx.current_index += 1
    
    " Continue with next module
    call timer_start(10, {timer -> s:process_next_module_async(a:ctx)})
    return
  endif
  
  " Process module status (these are usually fast enough to do synchronously)
  call s:process_module_info(l:info, l:module_path)
  
  " Add to results
  call add(a:ctx.results, l:info)
  let a:ctx.processed += 1
  
  " Continue with next module after a short delay
  let a:ctx.current_index += 1
  call timer_start(10, {timer -> s:process_next_module_async(a:ctx)})
endfunction

" Process module information synchronously
function! s:process_module_info(info, module_path) abort
  " Get current commit (fast operation)
  let l:result = plugin_manager#git#execute('git rev-parse --short HEAD', a:module_path, 0, 0)
  if l:result.success
    let a:info.commit = substitute(l:result.output, '\n', '', 'g')
  endif
  
  " Get last commit date (fast operation)
  let l:result = plugin_manager#git#execute('git log -1 --format=%cd --date=relative', a:module_path, 0, 0)
  if l:result.success
    let a:info.last_updated = substitute(l:result.output, '\n', '', 'g')
  endif
  
  " Get update status (more complex but still relatively fast)
  let l:update_status = plugin_manager#git#check_updates(a:module_path)
  
  " Extract branch information
  let a:info.branch = l:update_status.branch
  
  " Display target branch instead of HEAD for detached state
  if a:info.branch ==# 'detached'
    let l:remote_branch = l:update_status.remote_branch
    let l:remote_branch_name = substitute(l:remote_branch, '^origin/', '', '')
    let a:info.branch = 'detached@' . l:remote_branch_name
  endif
  
  " Determine status combining local changes and remote status
  if l:update_status.different_branch
    let a:info.status = 'CUSTOM BRANCH (local: ' . l:update_status.branch . ', target: ' . l:update_status.remote_branch . ')'
    if l:update_status.has_changes
      let a:info.status .= ' + LOCAL CHANGES'
    endif
  elseif l:update_status.behind > 0 && l:update_status.ahead > 0
    " DIVERGED state has highest priority after different branch
    let a:info.status = 'DIVERGED (BEHIND ' . l:update_status.behind . ', AHEAD ' . l:update_status.ahead . ')'
    if l:update_status.has_changes
      let a:info.status .= ' + LOCAL CHANGES'
    endif
  elseif l:update_status.behind > 0
    let a:info.status = 'BEHIND (' . l:update_status.behind . ')'
    if l:update_status.has_changes
      let a:info.status .= ' + LOCAL CHANGES'
    endif
  elseif l:update_status.ahead > 0
    let a:info.status = 'AHEAD (' . l:update_status.ahead . ')'
    if l:update_status.has_changes
      let a:info.status .= ' + LOCAL CHANGES'
    endif
  elseif l:update_status.has_changes
    let a:info.status = 'LOCAL CHANGES'
  endif
endfunction

" Finalize and display all results
function! s:finalize_status_async(ctx) abort
  let l:results = []
  
  " Process each result into a formatted line
  for l:info in a:ctx.results
    let l:line = s:format_module_status_line_from_info(l:info)
    if !empty(l:line)
      call add(l:results, l:line)
    endif
  endfor
  
  " Replace the current module line with completion message
  let l:win_id = bufwinid('PluginManager')
  if l:win_id != -1
    call win_gotoid(l:win_id)
    setlocal modifiable
    " Directly update the module line
    call setline(a:ctx.module_line, '')
    setlocal nomodifiable
  endif
  
  " Display table header 
  call plugin_manager#ui#update_sidebar([
        \ 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 20).'Last Updated'.repeat(' ', 18).'Status',
        \ repeat('-', 120)
        \ ], 1)
  
  " Then display results without extra newlines between them
  if !empty(l:results)
    call plugin_manager#ui#update_sidebar(l:results, 1)
  else
    call plugin_manager#ui#update_sidebar(['No status information available.'], 1)
  endif
  
  " Complete the task
  call plugin_manager#ui#complete_task(a:ctx.task_id, 1, 'Status check completed for ' . a:ctx.processed . ' plugins')
endfunction

" Function for determining status with the appropriate UI symbol
function! s:determine_status_with_symbol(update_status) abort
  let l:status = 'OK'
  let l:symbol_key = 'tick'  " Default OK
  
  if a:update_status.different_branch
    " Plugin is on a different branch than target
    let l:status = 'CUSTOM BRANCH (local: ' . a:update_status.branch . ', target: ' . a:update_status.remote_branch . ')'
    let l:symbol_key = 'warning'
    if a:update_status.has_changes
      let l:status .= ' + LOCAL CHANGES'
    endif
  elseif a:update_status.behind > 0 && a:update_status.ahead > 0
    " Plugin has diverged from remote
    let l:status = 'DIVERGED (BEHIND ' . a:update_status.behind . ', AHEAD ' . a:update_status.ahead . ')'
    let l:symbol_key = 'warning'
    if a:update_status.has_changes
      let l:status .= ' + LOCAL CHANGES'
    endif
  elseif a:update_status.behind > 0
    " Plugin is behind remote
    let l:status = 'BEHIND (' . a:update_status.behind . ')'
    let l:symbol_key = 'info'
    if a:update_status.has_changes
      let l:status .= ' + LOCAL CHANGES'
    endif
  elseif a:update_status.ahead > 0
    " Plugin is ahead of remote
    let l:status = 'AHEAD (' . a:update_status.ahead . ')'
    let l:symbol_key = 'info'
    if a:update_status.has_changes
      let l:status .= ' + LOCAL CHANGES'
    endif
  elseif a:update_status.has_changes
    " Plugin has local changes
    let l:status = 'LOCAL CHANGES'
    let l:symbol_key = 'warning'
  endif
  
  " Get the symbol from UI module
  let l:symbol = plugin_manager#ui#get_symbol(l:symbol_key)
  
  return {'text': l:status, 'symbol': l:symbol}
endfunction

" Format a status line for a module (synchronous method)
function! s:format_module_status_line(module) abort
  let l:short_name = a:module.short_name
  let l:path = a:module.path
  
  " Initialize default values
  let l:status = 'OK'
  let l:symbol = plugin_manager#ui#get_symbol('tick')
  
  let l:commit = 'N/A'
  let l:branch = 'N/A'
  let l:last_updated = 'N/A'
  
  " Check if module directory exists
  if !isdirectory(l:path)
    let l:status = 'MISSING'
    let l:symbol = plugin_manager#ui#get_symbol('cross')
  else
    " Get current commit hash
    let l:result = plugin_manager#git#execute('git rev-parse --short HEAD', l:path, 0, 0)
    if l:result.success
      let l:commit = substitute(l:result.output, '\n', '', 'g')
    endif
    
    " Get last commit date
    let l:result = plugin_manager#git#execute('git log -1 --format=%cd --date=relative', l:path, 0, 0)
    if l:result.success
      let l:last_updated = substitute(l:result.output, '\n', '', 'g')
    endif
    
    " Check for updates using git utility function
    let l:update_status = plugin_manager#git#check_updates(l:path)
    
    " Get branch information
    let l:branch = l:update_status.branch
    
    " Format detached HEAD state more clearly
    if l:branch ==# 'detached'
      let l:remote_branch = l:update_status.remote_branch
      let l:remote_branch_name = substitute(l:remote_branch, '^origin/', '', '')
      let l:branch = 'detached@' . l:remote_branch_name
    endif
    
    " Determine status and get the appropriate symbol
    let l:status_info = s:determine_status_with_symbol(l:update_status)
    let l:status = l:status_info.text
    let l:symbol = l:status_info.symbol
  endif
  
  " Trim long plugin names to fit in display
  if len(l:short_name) > 20
    let l:short_name = l:short_name[0:19]
  endif
  
  " Format columns with appropriate spacing
  let l:name_col = l:short_name . repeat(' ', max([0, 22 - len(l:short_name)]))
  let l:commit_col = l:commit . repeat(' ', max([0, 20 - len(l:commit)]))
  let l:branch_col = l:branch . repeat(' ', max([0, 26 - len(l:branch)]))
  let l:date_col = l:last_updated . repeat(' ', max([0, 30 - len(l:last_updated)]))
  
  " Return the formatted line with status and symbol
  "return l:name_col . l:commit_col . l:branch_col . l:date_col . l:status . ' ' . l:symbol
  return l:name_col . l:commit_col . l:branch_col . l:date_col . l:status . ' '
endfunction

" Format a status line from stored info (for asynchronous method)
function! s:format_module_status_line_from_info(info) abort
  let l:module = a:info.module
  let l:short_name = l:module.short_name
  
  " Determine the appropriate symbol based on status
  let l:symbol = plugin_manager#ui#get_symbol('tick')  " Default OK
  
  if a:info.status ==# 'MISSING'
    let l:symbol = plugin_manager#ui#get_symbol('cross')
  elseif a:info.status =~# 'CUSTOM BRANCH\|DIVERGED\|LOCAL CHANGES'
    let l:symbol = plugin_manager#ui#get_symbol('warning')
  elseif a:info.status =~# 'BEHIND\|AHEAD'
    let l:symbol = plugin_manager#ui#get_symbol('info')
  endif
  
  " Trim long plugin names to fit in display
  if len(l:short_name) > 20
    let l:short_name = l:short_name[0:19]
  endif
  
  " Format columns with appropriate spacing
  let l:name_col = l:short_name . repeat(' ', max([0, 22 - len(l:short_name)]))
  let l:commit_col = a:info.commit . repeat(' ', max([0, 20 - len(a:info.commit)]))
  let l:branch_col = a:info.branch . repeat(' ', max([0, 26 - len(a:info.branch)]))
  let l:date_col = a:info.last_updated . repeat(' ', max([0, 30 - len(a:info.last_updated)]))
  
  "return l:name_col . l:commit_col . l:branch_col . l:date_col . l:status . ' ' . l:symbol
  return l:name_col . l:commit_col . l:branch_col . l:date_col . l:status . ' '
endfunction