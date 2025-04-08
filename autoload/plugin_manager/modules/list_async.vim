" autoload/plugin_manager/modules/list_async.vim - Asynchronous functions for listing and displaying plugins

" Asynchronous version of plugin_manager#modules#list#status
function! plugin_manager#modules#list_async#status()
    " Ensure we're in the Vim directory
    if !plugin_manager#utils#ensure_vim_directory()
      return 0
    endif
    
    " Create header
    let l:header = 'Submodule Status:'
    
    " Show initial status message
    let l:lines = [l:header, repeat('-', len(l:header)), '', 'Fetching latest status information asynchronously...']
    call plugin_manager#ui#open_sidebar(l:lines)
    
    " First, fetch updates for all modules
    let l:fetch_cmd = 'git submodule foreach --recursive "git fetch -q origin 2>/dev/null || true"'
    
    " Create task for fetching updates
    function! s:on_fetch_complete(output, status) closure
      " Now fetch the module information
      call plugin_manager#utils_async#parse_gitmodules(function('s:on_gitmodules_parsed'))
    endfunction
    
    " Create task for showing modules list
    function! s:on_gitmodules_parsed(modules) closure
      " Check if any modules exist
      if empty(a:modules)
        let l:lines = [l:header, repeat('-', len(l:header)), '', 'No submodules found (.gitmodules not found)']
        call plugin_manager#ui#update_sidebar(l:lines, 0)
        return
      endif
      
      " Prepare the status header
      let l:lines = [l:header, repeat('-', len(l:header)), '']
      call add(l:lines, 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 20).'Last Updated'.repeat(' ', 18).'Status')
      call add(l:lines, repeat('-', 120))
      
      " Update sidebar with header
      call plugin_manager#ui#update_sidebar(l:lines, 0)
      
      " Sort modules by name for consistent display
      let l:module_names = sort(keys(a:modules))
      
      " Process each module asynchronously
      call s:process_next_module(a:modules, l:module_names, 0)
    endfunction
    
    " Process modules one at a time
    function! s:process_next_module(modules, module_names, index)
      " If we're done with all modules, finish up
      if a:index >= len(a:module_names)
        call plugin_manager#ui#update_sidebar(['', 'All modules checked.'], 1)
        return
      endif
      
      " Get the current module
      let l:name = a:module_names[a:index]
      let l:module = a:modules[l:name]
      
      " Skip invalid modules
      if !has_key(l:module, 'is_valid') || !l:module.is_valid
        call s:process_next_module(a:modules, a:module_names, a:index + 1)
        return
      endif
      
      let l:short_name = l:module.short_name
      
      " Format the first part of the line
      if len(l:short_name) > 20
        let l:short_name = l:short_name[0:19]
      endif
      
      " Check if module directory exists
      if !isdirectory(l:module.path)
        " Module is missing, display status immediately
        let l:name_col = l:short_name . repeat(' ', max([0, 22 - len(l:short_name)]))
        let l:line = l:name_col . repeat(' ', 20) . repeat(' ', 26) . repeat(' ', 30) . 'MISSING'
        call plugin_manager#ui#update_sidebar([l:line], 1)
        call s:process_next_module(a:modules, a:module_names, a:index + 1)
        return
      endif
      
      " Get status for this module asynchronously
      let l:callback = function('s:module_status_callback', [a:modules, a:module_names, a:index, l:short_name])
      call plugin_manager#utils_async#check_module_updates(l:module.path, l:callback)
    endfunction
    
    " Callback for module status check
    function! s:module_status_callback(modules, module_names, index, short_name, result)
      " Format name column
      let l:name_col = a:short_name . repeat(' ', max([0, 22 - len(a:short_name)]))
      
      " Format commit column
      let l:commit = a:result.current_commit
      if len(l:commit) > 8
        let l:commit = l:commit[0:7]
      endif
      let l:commit_col = l:commit . repeat(' ', max([0, 20 - len(l:commit)]))
      
      " Format branch column
      let l:branch = a:result.branch
      if l:branch == 'detached'
        let l:remote_branch = a:result.remote_branch
        let l:remote_branch_name = substitute(l:remote_branch, '^origin/', '', '')
        let l:branch = 'detached@' . l:remote_branch_name
      endif
      let l:branch_col = l:branch . repeat(' ', max([0, 26 - len(l:branch)]))
      
      " Get last updated info - would require another async call so use placeholder
      let l:last_updated = 'recent'
      let l:date_col = l:last_updated . repeat(' ', max([0, 30 - len(l:last_updated)]))
      
      " Determine status text
      let l:status = 'OK'
      if a:result.different_branch
        let l:status = 'CUSTOM BRANCH (local: ' . a:result.branch . ', target: ' . a:result.remote_branch . ')'
        if a:result.has_changes
          let l:status .= ' + LOCAL CHANGES'
        endif
      elseif a:result.behind > 0 && a:result.ahead > 0
        " DIVERGED state has highest priority after different branch
        let l:status = 'DIVERGED (BEHIND ' . a:result.behind . ', AHEAD ' . a:result.ahead . ')'
        if a:result.has_changes
          let l:status .= ' + LOCAL CHANGES'
        endif
      elseif a:result.behind > 0
        let l:status = 'BEHIND (' . a:result.behind . ')'
        if a:result.has_changes
          let l:status .= ' + LOCAL CHANGES'
        endif
      elseif a:result.ahead > 0
        let l:status = 'AHEAD (' . a:result.ahead . ')'
        if a:result.has_changes
          let l:status .= ' + LOCAL CHANGES'
        endif
      elseif a:result.has_changes
        let l:status = 'LOCAL CHANGES'
      endif
      
      " Combine all parts
      let l:line = l:name_col . l:commit_col . l:branch_col . l:date_col . l:status
      
      " Add line to the sidebar
      call plugin_manager#ui#update_sidebar([l:line], 1)
      
      " Process the next module
      call s:process_next_module(a:modules, a:module_names, a:index + 1)
    endfunction
    
    " Execute initial fetch command to update all repositories
    let l:job_id = plugin_manager#async#system(l:fetch_cmd, function('s:on_fetch_complete'))
    return l:job_id
  endfunction
  
  " Async version of the summary function (though it's already pretty fast)
  function! plugin_manager#modules#list_async#summary()
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
    
    let l:header = 'Submodule Summary'
    
    " Check if .gitmodules exists
    if !filereadable('.gitmodules')
      let l:lines = [l:header, repeat('-', len(l:header)), '', 'No submodules found (.gitmodules not found)']
      call plugin_manager#ui#open_sidebar(l:lines)
      return
    endif
    
    " Show initial message
    let l:lines = [l:header, repeat('-', len(l:header)), '', 'Generating summary...']
    call plugin_manager#ui#open_sidebar(l:lines)
    
    function! s:on_summary_complete(output, status)
      let l:lines = [l:header, repeat('-', len(l:header)), '']
      call extend(l:lines, split(a:output, "\n"))
      call plugin_manager#ui#update_sidebar(l:lines, 0)
    endfunction
    
    let l:job_id = plugin_manager#async#system('git submodule summary', function('s:on_summary_complete'))
    return l:job_id
  endfunction
  
  " This could be an async version of all(), but it's usually very fast
  " and doesn't need to be asynchronous
  function! plugin_manager#modules#list_async#all()
    return plugin_manager#modules#list#all()
  endfunction