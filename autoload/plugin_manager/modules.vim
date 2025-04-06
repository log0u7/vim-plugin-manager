" Fully asynchronous status function for plugin_manager/modules.vim

" Improved status function with non-blocking operation
  function! plugin_manager#modules#status()
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
    
    " Initialize display immediately
    let l:header = 'Submodule Status:'
    let l:lines = [l:header, repeat('-', len(l:header)), '', 'Retrieving status information...']
    call plugin_manager#ui#open_sidebar(l:lines)
    
    " Check if .gitmodules exists asynchronously
    if !filereadable('.gitmodules')
      call plugin_manager#ui#update_sidebar([l:header, repeat('-', len(l:header)), '', 'No submodules found (.gitmodules not found)'], 0)
      return
    endif
    
    " Create callbacks for asynchronous execution
    function! s:handle_status_fetch(status, output) closure
      " Now retrieve modules (we need to do this here to avoid concurrency issues)
      let l:modules = plugin_manager#utils#parse_gitmodules()
      
      " Create the table header
      let l:lines = [l:header, repeat('-', len(l:header)), '']
      call add(l:lines, 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 8).'Last Updated'.repeat(' ', 18).'Status')
      call add(l:lines, repeat('-', 120))
      
      " Update immediately to show the header and keep UI responsive
      call plugin_manager#ui#update_sidebar(l:lines, 0)
      
      " Create jobs for each module to check
      if !empty(l:modules)
        let l:module_names = sort(keys(l:modules))
        " Process only a few modules at a time to prevent overload
        call s:process_module_batch(l:modules, l:module_names, 0, 5, l:header)
      else
        call plugin_manager#ui#update_sidebar([l:header, repeat('-', len(l:header)), '', 'No valid modules found in .gitmodules'], 0)
      endif
    endfunction
    
    " Function to process modules in batches
    function! s:process_module_batch(modules, names, start_idx, batch_size, header)
      let l:end_idx = min([a:start_idx + a:batch_size, len(a:names)])
      let l:processed = 0
      
      for l:idx in range(a:start_idx, l:end_idx - 1)
        let l:name = a:names[l:idx]
        let l:module = a:modules[l:name]
        if has_key(l:module, 'is_valid') && l:module.is_valid
          call s:check_module_status(l:module, a:header)
          let l:processed += 1
        endif
      endfor
      
      " Schedule processing of the next batch
      if l:end_idx < len(a:names)
        call timer_start(100, {-> s:process_module_batch(a:modules, a:names, l:end_idx, a:batch_size, a:header)})
      endif
    endfunction
    
    " Function to check status of a specific module
    function! s:check_module_status(module, header)
      let l:short_name = a:module.short_name
      
      " Initialize status to 'OK' by default
      let l:status = 'OK'
      
      " Initialize other information as N/A in case checks fail
      let l:commit = 'N/A'
      let l:branch = 'N/A'
      let l:last_updated = 'N/A'
      
      " Check if module exists
      if !isdirectory(a:module.path)
        let l:status = 'MISSING'
      else
        " Continue with all checks for existing modules
        
        " Create callbacks to retrieve information
        let l:module_path = a:module.path
        let l:callbacks = {
              \ 'name': 'Checking ' . l:short_name,
              \ 'module': a:module,
              \ 'on_exit': function('s:handle_module_status_check', [a:header])
              \ }
        
        " Fetch data asynchronously
        let l:cmd = 'cd "' . l:module_path . '" && ' .
              \ 'git rev-parse --short HEAD 2>/dev/null || echo "N/A"; ' .
              \ 'git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A"; ' .
              \ 'git log -1 --format=%cd --date=relative 2>/dev/null || echo "N/A"'
        
        call plugin_manager#jobs#start(l:cmd, l:callbacks)
      endif
    endfunction
    
    " Handler to add a module to the status table
    function! s:handle_module_status_check(header, status, output) dict
      let l:lines = split(a:output, "\n")
      
      let l:commit = len(l:lines) > 0 ? l:lines[0] : 'N/A'
      let l:branch = len(l:lines) > 1 ? l:lines[1] : 'N/A'
      let l:last_updated = len(l:lines) > 2 ? l:lines[2] : 'N/A'
      
      " Get short name
      let l:short_name = self.module.short_name
      
      " Default to OK
      let l:status = 'OK'
      
      " Check for updates using the utility function
      let l:update_status = plugin_manager#utils#check_module_updates(self.module.path)
      
      " Get local changes status from the utility function
      let l:has_changes = l:update_status.has_changes
      
      " Determine status combining local changes and remote status
      if l:update_status.different_branch
        let l:status = 'CUSTOM BRANCH (local: ' . l:update_status.branch . ', target: ' . l:update_status.remote_branch . ')'
        if l:has_changes
          let l:status .= ' + LOCAL CHANGES'
        endif
      elseif l:update_status.behind > 0 && l:update_status.ahead > 0
        " DIVERGED state has highest priority after different branch
        let l:status = 'DIVERGED (BEHIND ' . l:update_status.behind . ', AHEAD ' . l:update_status.ahead . ')'
        if l:has_changes
          let l:status .= ' + LOCAL CHANGES'
        endif
      elseif l:update_status.behind > 0
        let l:status = 'BEHIND (' . l:update_status.behind . ')'
        if l:has_changes
          let l:status .= ' + LOCAL CHANGES'
        endif
      elseif l:update_status.ahead > 0
        let l:status = 'AHEAD (' . l:update_status.ahead . ')'
        if l:has_changes
          let l:status .= ' + LOCAL CHANGES'
        endif
      elseif l:has_changes
        let l:status = 'LOCAL CHANGES'
      endif
      
      if len(l:short_name) > 20
        let l:short_name = l:short_name[0:19]
      endif
  
      " Format the output with properly aligned columns
      " Ensure fixed width with proper spacing between columns 
      let l:name_col = l:short_name . repeat(' ', max([0, 22 - len(l:short_name)]))
      let l:commit_col = l:commit . repeat(' ', max([0, 20 - len(l:commit)]))
      let l:branch_col = l:branch . repeat(' ', max([0, 14 - len(l:branch)]))
      let l:date_col = l:last_updated . repeat(' ', max([0, 30 - len(l:last_updated)]))
      
      " Look for the table section
      let l:win_id = bufwinid(s:buffer_name)
      if l:win_id != -1
        " Check if the content exists, if not don't try to append
        let l:status_line = l:name_col . l:commit_col . l:branch_col . l:date_col . l:status
        
        " Focus on the window
        call win_gotoid(l:win_id)
        setlocal modifiable
        
        " Find the table section
        let l:header_line = -1
        let l:separator_line = -1
        let l:line_count = line('$')
        
        for i in range(1, l:line_count)
          if getline(i) =~ '^Submodule Status:$'
            let l:header_line = i
          elseif l:header_line > 0 && getline(i) =~ '^-\+$' && getline(i-1) =~ 'Plugin'
            let l:separator_line = i
            break
          endif
        endfor
        
        " If we found the table, append the module status
        if l:separator_line > 0
          call append(l:separator_line, l:status_line)
        endif
        
        setlocal nomodifiable
      endif
    endfunction
    
    " Start by fetching updates asynchronously
    let l:callbacks = {
          \ 'name': 'Fetching repository updates',
          \ 'on_exit': function('s:handle_status_fetch')
          \ }
    
    call plugin_manager#jobs#start('git submodule foreach --recursive "git fetch -q origin 2>/dev/null || true"', l:callbacks)
  endfunction