" autoload/plugin_manager/cmd/status.vim - Status command with async support
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3.4

" ------------------------------------------------------------------------------
" MAIN STATUS COMMAND ENTRY POINT
" ------------------------------------------------------------------------------

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
    
    " Create status context
    let l:ctx = s:create_status_context(l:modules)
    
    " Check if we can use async
    let l:use_async = plugin_manager#async#supported()
    
    if l:use_async
      call s:fetch_status_async(l:ctx)
    else
      call s:fetch_status_sync(l:ctx)
    endif
  catch
    call plugin_manager#core#handle_error(v:exception, "status")
  endtry
endfunction

" ------------------------------------------------------------------------------
" CONTEXT CREATION AND MANAGEMENT
" ------------------------------------------------------------------------------

" Create the status context with all necessary data
function! s:create_status_context(modules) abort
  " Sort modules by name for consistent display
  let l:module_names = sort(keys(a:modules))
  
  let l:ctx = {
        \ 'modules': a:modules,
        \ 'module_names': l:module_names,
        \ 'total': len(l:module_names),
        \ 'module_line': 0,
        \ 'task_id': '',
        \ 'current_index': 0,
        \ 'processed': 0,
        \ 'results': [],
        \ 'valid_modules': []
        \ }
  
  " Prepare valid modules list
  for l:name in l:ctx.module_names
    let l:module = l:ctx.modules[l:name]
    if has_key(l:module, 'is_valid') && l:module.is_valid
      call add(l:ctx.valid_modules, l:module)
    endif
  endfor
  
  return l:ctx
endfunction

" ------------------------------------------------------------------------------
" STATUS DISPLAY LOGIC
" ------------------------------------------------------------------------------

" Show status table header
function! s:display_status_header() abort
  call plugin_manager#ui#update_sidebar([
        \ 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).
        \ 'Branch'.repeat(' ', 20).'Last Updated'.repeat(' ', 18).'Status',
        \ repeat('-', 120)
        \ ], 1)
endfunction

" Format a status line based on module info
function! s:format_status_line(info) abort
  let l:module = a:info.module
  let l:short_name = l:module.short_name
  
  " Trim long plugin names to fit in display
  if len(l:short_name) > 20
    let l:short_name = l:short_name[0:19]
  endif
  
  " Format columns with appropriate spacing
  let l:name_col = l:short_name . repeat(' ', max([0, 22 - len(l:short_name)]))
  let l:commit_col = a:info.commit . repeat(' ', max([0, 20 - len(a:info.commit)]))
  let l:branch_col = a:info.branch . repeat(' ', max([0, 26 - len(a:info.branch)]))
  let l:date_col = a:info.last_updated . repeat(' ', max([0, 30 - len(a:info.last_updated)]))
  
  " Return the formatted line with status
  return l:name_col . l:commit_col . l:branch_col . l:date_col . a:info.status
endfunction

" ------------------------------------------------------------------------------
" SYNCHRONOUS STATUS FETCHING
" ------------------------------------------------------------------------------

" Synchronous status fetching implementation
function! s:fetch_status_sync(ctx) abort
  " Update UI to show we're fetching
  call plugin_manager#ui#update_sidebar(['Fetching updates from remote repositories...'], 1)
  
  " Fetch updates to ensure we have up-to-date status information
  call plugin_manager#git#execute('git submodule foreach --recursive "git fetch -q origin 2>/dev/null || true"', '', 1, 0)
  
  " Display table header
  call s:display_status_header()
  
  " Process each module
  for l:name in a:ctx.module_names
    let l:module = a:ctx.modules[l:name]
    if has_key(l:module, 'is_valid') && l:module.is_valid
      let l:info = s:get_module_status_info(l:module)
      let l:formatted_line = s:format_status_line(l:info)
      call plugin_manager#ui#update_sidebar([l:formatted_line], 1)
    endif
  endfor
  
  call plugin_manager#ui#update_sidebar(['', 'Status check completed.'], 1)
endfunction

" ------------------------------------------------------------------------------
" ASYNCHRONOUS STATUS FETCHING
" ------------------------------------------------------------------------------

" Asynchronous status fetching with improved initialization
function! s:fetch_status_async(ctx) abort
  " Add a line for the current module with info symbol
  let l:info_symbol = plugin_manager#ui#get_symbol('info')
  
  " Create task for tracking overall progress
  let l:task_id = plugin_manager#ui#start_task('Fetching status for ' . a:ctx.total . ' plugins', a:ctx.total, {
        \ 'type': 'status',
        \ 'progress': 1
        \ })
  
  " Store task ID in context
  let a:ctx.task_id = l:task_id
  
  " Update sidebar with fetching message
  call plugin_manager#ui#update_sidebar([l:info_symbol . ' Current module: Preparing...'], 1)
  let a:ctx.module_line = line('$')
  
  " Start fetching immediately instead of with a delay
  call s:start_fetch_async(a:ctx)
  
  return l:task_id
endfunction

" Start the actual fetching process
function! s:start_fetch_async(ctx) abort
  let l:task_id = a:ctx.task_id
  
  " Split the git fetch operation to be more responsive
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
  
  " Update progress bar
  call plugin_manager#ui#update_task(a:ctx.task_id, a:ctx.processed, 'Processed ' . a:ctx.processed . '/' . a:ctx.total . ' plugins')
  
  " Update current module display
  let l:info_symbol = plugin_manager#ui#get_symbol('info')
  let l:status_line = l:info_symbol . ' Current module: ' . l:short_name
  call plugin_manager#ui#show_message(a:ctx.module_line, l:status_line)
  
  " Process module status and create info object
  let l:info = s:get_module_status_info(l:module)
  
  " Add to results
  call add(a:ctx.results, l:info)
  let a:ctx.processed += 1
  
  " Continue with next module after a short delay
  let a:ctx.current_index += 1
  call timer_start(10, {timer -> s:process_next_module_async(a:ctx)})
endfunction

" Finalize and display all results
function! s:finalize_status_async(ctx) abort
  let l:results = []
  
  " Process each result into a formatted line
  for l:info in a:ctx.results
    let l:line = s:format_status_line(l:info)
    if !empty(l:line)
      call add(l:results, l:line)
    endif
  endfor
  
  " Show temporary message that will disappear after 1 seconds
  call plugin_manager#ui#show_message(a:ctx.module_line, 'Completed processing all modules', 1)
  
  " Display table header 
  call s:display_status_header()
  
  " Then display results without extra newlines between them
  if !empty(l:results)
    call plugin_manager#ui#update_sidebar(l:results, 1)
  else
    call plugin_manager#ui#update_sidebar(['No status information available.'], 1)
  endif
  
  " Complete the task
  call plugin_manager#ui#complete_task(a:ctx.task_id, 1, 'Status check completed for ' . a:ctx.processed . ' plugins')
endfunction

" ------------------------------------------------------------------------------
" SHARED MODULE STATUS FUNCTIONS
" ------------------------------------------------------------------------------

" Extract module status information (works for both sync and async)
function! s:get_module_status_info(module) abort
  let l:short_name = a:module.short_name
  let l:path = a:module.path
  
  " Initialize default values
  let l:info = {
        \ 'module': a:module,
        \ 'commit': 'N/A',
        \ 'branch': 'N/A',
        \ 'last_updated': 'N/A',
        \ 'status': 'OK'
        \ }
  
  " Check if module directory exists
  if !isdirectory(l:path)
    let l:info.status = 'MISSING'
    return l:info
  endif
  
  " Collect data about the module
  call s:collect_module_info(l:info, l:path)
  
  return l:info
endfunction

" Collect data about a module to fill the info structure
function! s:collect_module_info(info, module_path) abort
  " Get current commit hash
  let l:result = plugin_manager#git#execute('git rev-parse --short HEAD', a:module_path, 0, 0)
  if l:result.success
    let a:info.commit = substitute(l:result.output, '\n', '', 'g')
  endif
  
  " Get last commit date
  let l:result = plugin_manager#git#execute('git log -1 --format=%cd --date=relative', a:module_path, 0, 0)
  if l:result.success
    let a:info.last_updated = substitute(l:result.output, '\n', '', 'g')
  endif
  
  " Check for updates using git utility function
  let l:update_status = plugin_manager#git#check_updates(a:module_path)
  
  " Get branch information
  let a:info.branch = l:update_status.branch
  
  " Format detached HEAD state more clearly
  if a:info.branch ==# 'detached'
    let l:remote_branch = l:update_status.remote_branch
    let l:remote_branch_name = substitute(l:remote_branch, '^origin/', '', '')
    let a:info.branch = 'detached@' . l:remote_branch_name
  endif
  
  " Determine status based on update information
  call s:determine_module_status(a:info, l:update_status)
endfunction

" Determine module status based on update information
function! s:determine_module_status(info, update_status) abort
  if a:update_status.different_branch
    " Plugin is on a different branch than target
    let a:info.status = 'CUSTOM BRANCH (local: ' . a:update_status.branch . 
          \ ', target: ' . a:update_status.remote_branch . ')'
    if a:update_status.has_changes
      let a:info.status .= ' + LOCAL CHANGES'
    endif
  elseif a:update_status.behind > 0 && a:update_status.ahead > 0
    " Plugin has diverged from remote
    let a:info.status = 'DIVERGED (BEHIND ' . a:update_status.behind . 
          \ ', AHEAD ' . a:update_status.ahead . ')'
    if a:update_status.has_changes
      let a:info.status .= ' + LOCAL CHANGES'
    endif
  elseif a:update_status.behind > 0
    " Plugin is behind remote
    let a:info.status = 'BEHIND (' . a:update_status.behind . ')'
    if a:update_status.has_changes
      let a:info.status .= ' + LOCAL CHANGES'
    endif
  elseif a:update_status.ahead > 0
    " Plugin is ahead of remote
    let a:info.status = 'AHEAD (' . a:update_status.ahead . ')'
    if a:update_status.has_changes
      let a:info.status .= ' + LOCAL CHANGES'
    endif
  elseif a:update_status.has_changes
    " Plugin has local changes
    let a:info.status = 'LOCAL CHANGES'
  endif
endfunction