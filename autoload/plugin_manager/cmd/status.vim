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

" Asynchronous status fetching 
function! s:fetch_status_async(modules) abort
  " Sort modules by name for consistent display
  let l:module_names = sort(keys(a:modules))
  let l:total_modules = len(l:module_names)
  
  " Create task for tracking progress
  let l:task_id = plugin_manager#ui#start_task('Fetching status for ' . l:total_modules . ' plugins', l:total_modules, {
        \ 'type': 'status',
        \ 'progress': 1
        \ })
  
  " Store context for callbacks
  let l:ctx = {
        \ 'task_id': l:task_id,
        \ 'modules': a:modules,
        \ 'module_names': l:module_names,
        \ 'current_index': 0,
        \ 'total': l:total_modules,
        \ 'processed': 0,
        \ 'results': []
        \ }
  
  " Start fetching updates in background
  call plugin_manager#async#git('git submodule foreach --recursive "git fetch -q origin 2>/dev/null || true"', {
        \ 'callback': function('s:on_fetch_complete', [l:ctx]),
        \ 'ui_message': 'Fetching updates from remote repositories'
        \ })
endfunction

" Callback after fetch completes
function! s:on_fetch_complete(ctx, result) abort
  let l:task_id = a:ctx.task_id
  
  " Update progress
  call plugin_manager#ui#update_task(l:task_id, 0, 'Processing plugin status information')
  
  " Process modules one by one asynchronously
  call s:process_next_module_async(a:ctx)
endfunction

" Process next module in the queue
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
  
  " Update progress
  call plugin_manager#ui#update_task(a:ctx.task_id, a:ctx.processed, 'Checking status: ' . l:short_name)
  
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
    call s:process_next_module_async(a:ctx)
    return
  endif
  
  " Get current commit (fast operation)
  let l:result = plugin_manager#git#execute('git rev-parse --short HEAD', l:module_path, 0, 0)
  if l:result.success
    let l:info.commit = substitute(l:result.output, '\n', '', 'g')
  endif
  
  " Get last commit date (fast operation)
  let l:result = plugin_manager#git#execute('git log -1 --format=%cd --date=relative', l:module_path, 0, 0)
  if l:result.success
    let l:info.last_updated = substitute(l:result.output, '\n', '', 'g')
  endif
  
  " Get update status (more complex but still relatively fast)
  let l:update_status = plugin_manager#git#check_updates(l:module_path)
  let l:info.update_status = l:update_status
  
  " Extract branch information
  let l:info.branch = l:update_status.branch
  
  " Display target branch instead of HEAD for detached state
  if l:info.branch ==# 'detached'
    let l:remote_branch = l:update_status.remote_branch
    let l:remote_branch_name = substitute(l:remote_branch, '^origin/', '', '')
    let l:info.branch = 'detached@' . l:remote_branch_name
  endif
  
  " Determine status combining local changes and remote status
  if l:update_status.different_branch
    let l:info.status = 'CUSTOM BRANCH (local: ' . l:update_status.branch . ', target: ' . l:update_status.remote_branch . ')'
    if l:update_status.has_changes
      let l:info.status .= ' + LOCAL CHANGES'
    endif
  elseif l:update_status.behind > 0 && l:update_status.ahead > 0
    " DIVERGED state has highest priority after different branch
    let l:info.status = 'DIVERGED (BEHIND ' . l:update_status.behind . ', AHEAD ' . l:update_status.ahead . ')'
    if l:update_status.has_changes
      let l:info.status .= ' + LOCAL CHANGES'
    endif
  elseif l:update_status.behind > 0
    let l:info.status = 'BEHIND (' . l:update_status.behind . ')'
    if l:update_status.has_changes
      let l:info.status .= ' + LOCAL CHANGES'
    endif
  elseif l:update_status.ahead > 0
    let l:info.status = 'AHEAD (' . l:update_status.ahead . ')'
    if l:update_status.has_changes
      let l:info.status .= ' + LOCAL CHANGES'
    endif
  elseif l:update_status.has_changes
    let l:info.status = 'LOCAL CHANGES'
  endif
  
  " Add to results
  call add(a:ctx.results, l:info)
  let a:ctx.processed += 1
  
  " Continue with next module after a short delay to prevent UI freezes
  let a:ctx.current_index += 1
  call timer_start(10, {timer -> s:process_next_module_async(a:ctx)})
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
  
  " Display table header first
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

" Format a module status line from stored info
function! s:format_module_status_line_from_info(info) abort
  let l:module = a:info.module
  let l:short_name = l:module.short_name
  
  if len(l:short_name) > 20
    let l:short_name = l:short_name[0:19]
  endif
  
  " Format the output with properly aligned columns  
  let l:name_col = l:short_name . repeat(' ', max([0, 22 - len(l:short_name)]))
  let l:commit_col = a:info.commit . repeat(' ', max([0, 20 - len(a:info.commit)]))
  let l:branch_col = a:info.branch . repeat(' ', max([0, 26 - len(a:info.branch)]))
  let l:date_col = a:info.last_updated . repeat(' ', max([0, 30 - len(a:info.last_updated)]))
  
  return l:name_col . l:commit_col . l:branch_col . l:date_col . a:info.status
endfunction

" Format a module status line directly from a module
function! s:format_module_status_line(module) abort
  let l:short_name = a:module.short_name
  let l:path = a:module.path
  
  " Initialize status to 'OK' by default
  let l:status = 'OK'
  
  " Initialize other information as N/A in case checks fail
  let l:commit = 'N/A'
  let l:branch = 'N/A'
  let l:last_updated = 'N/A'
  
  " Check if module exists
  if !isdirectory(l:path)
    let l:status = 'MISSING'
  else
    " Continue with all checks for existing modules
    
    " Get current commit
    let l:result = plugin_manager#git#execute('git rev-parse --short HEAD', l:path, 0, 0)
    if l:result.success
      let l:commit = substitute(l:result.output, '\n', '', 'g')
    endif
    
    " Get last commit date
    let l:result = plugin_manager#git#execute('git log -1 --format=%cd --date=relative', l:path, 0, 0)
    if l:result.success
      let l:last_updated = substitute(l:result.output, '\n', '', 'g')
    endif
    
    " Use the git utility function to check for updates
    let l:update_status = plugin_manager#git#check_updates(l:path)
    
    " Use branch information from the utility function
    let l:branch = l:update_status.branch
    
    " Display target branch instead of HEAD for detached state
    if l:branch ==# 'detached'
      let l:remote_branch = l:update_status.remote_branch
      let l:remote_branch_name = substitute(l:remote_branch, '^origin/', '', '')
      let l:branch = 'detached@' . l:remote_branch_name
    endif
    
    " Determine status combining local changes and remote status
    if l:update_status.different_branch
      let l:status = 'CUSTOM BRANCH (local: ' . l:update_status.branch . ', target: ' . l:update_status.remote_branch . ')'
      if l:update_status.has_changes
        let l:status .= ' + LOCAL CHANGES'
      endif
    elseif l:update_status.behind > 0 && l:update_status.ahead > 0
      " DIVERGED state has highest priority after different branch
      let l:status = 'DIVERGED (BEHIND ' . l:update_status.behind . ', AHEAD ' . l:update_status.ahead . ')'
      if l:update_status.has_changes
        let l:status .= ' + LOCAL CHANGES'
      endif
    elseif l:update_status.behind > 0
      let l:status = 'BEHIND (' . l:update_status.behind . ')'
      if l:update_status.has_changes
        let l:status .= ' + LOCAL CHANGES'
      endif
    elseif l:update_status.ahead > 0
      let l:status = 'AHEAD (' . l:update_status.ahead . ')'
      if l:update_status.has_changes
        let l:status .= ' + LOCAL CHANGES'
      endif
    elseif l:update_status.has_changes
      let l:status = 'LOCAL CHANGES'
    endif
  endif
  
  if len(l:short_name) > 20
    let l:short_name = l:short_name[0:19]
  endif
  
  " Format the output with properly aligned columns
  let l:name_col = l:short_name . repeat(' ', max([0, 22 - len(l:short_name)]))
  let l:commit_col = l:commit . repeat(' ', max([0, 20 - len(l:commit)]))
  let l:branch_col = l:branch . repeat(' ', max([0, 26 - len(l:branch)]))
  let l:date_col = l:last_updated . repeat(' ', max([0, 30 - len(l:last_updated)]))
  
  return l:name_col . l:commit_col . l:branch_col . l:date_col . l:status
endfunction