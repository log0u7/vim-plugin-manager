" Modifications for status.vim to improve UI flow

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