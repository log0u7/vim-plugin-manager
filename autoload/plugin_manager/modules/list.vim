" autoload/plugin_manager/modules/list.vim - Functions for listing and displaying plugins

" Improved list function with fixed column formatting
function! plugin_manager#modules#list#all()
    if !plugin_manager#utils#ensure_vim_directory()
        return
    endif
    
    " Use the gitmodules cache
    let l:modules = plugin_manager#utils#parse_gitmodules()
    let l:header = 'Installed Plugins:' 
    
    if empty(l:modules)
        let l:lines = [l:header, repeat('-', len(l:header)), '', 'No plugins installed (.gitmodules not found)']
        call plugin_manager#ui#open_sidebar(l:lines)
        return
    endif
    
    let l:lines = [l:header, repeat('-', len(l:header)), '', 'Name'.repeat(' ', 20).'Path'.repeat(' ', 38).'URL']
    let l:lines += [repeat('-', 120)]
    
    " Sort modules by name
    let l:module_names = sort(keys(l:modules))
    
    for l:name in l:module_names
        let l:module = l:modules[l:name]
        if has_key(l:module, 'is_valid') && l:module.is_valid
        let l:short_name = l:module.short_name
        let l:path = l:module.path
    
        if len(l:short_name) > 22
            let l:short_name = l:short_name[0:21]
        endif
    
        if len(path) > 40
            let l:path = path[0:39]
        endif 
    
        " Format the output with properly aligned columns
        " Ensure fixed width columns with proper spacing
        let l:name_col = l:short_name . repeat(' ', max([0, 24 - len(l:short_name)]))
        let l:path_col = l:path . repeat(' ', max([0, 42 - len(l:path)]))
        
        let l:status = has_key(l:module, 'exists') && l:module.exists ? '' : ' [MISSING]'
        
        call add(l:lines, l:name_col . l:path_col . l:module.url . l:status)
        endif
    endfor
    
    call plugin_manager#ui#open_sidebar(l:lines)
endfunction
    
" Improved status function with fixed column formatting and better branch display
function! plugin_manager#modules#list#status()
    if !plugin_manager#utils#ensure_vim_directory()
        return
    endif
    
    " Use the gitmodules cache
    let l:modules = plugin_manager#utils#parse_gitmodules()
    let l:header = 'Submodule Status:'
    
    if empty(l:modules)
        let l:lines = [l:header, repeat('-', len(l:header)), '', 'No submodules found (.gitmodules not found)']
        call plugin_manager#ui#open_sidebar(l:lines)
        return
    endif
    
    let l:lines = [l:header, repeat('-', len(l:header)), '']
    call add(l:lines, 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 8).'Last Updated'.repeat(' ', 18).'Status')
    call add(l:lines, repeat('-', 120))
    
    " Fetch updates to ensure we have up-to-date status information
    call plugin_manager#ui#update_sidebar(['Fetching updates from remote repositories...'], 1)
    call system('git submodule foreach --recursive "git fetch -q origin 2>/dev/null || true"')
    call plugin_manager#ui#update_sidebar(['Status information:'], 1)
    
    " Sort modules by name
    let l:module_names = sort(keys(l:modules))
    
    for l:name in l:module_names
        let l:module = l:modules[l:name]
        if has_key(l:module, 'is_valid') && l:module.is_valid
        let l:short_name = l:module.short_name
        
        " Initialize status to 'OK' by default
        let l:status = 'OK'
        
        " Initialize other information as N/A in case checks fail
        let l:commit = 'N/A'
        let l:branch = 'N/A'
        let l:last_updated = 'N/A'
        
        " Check if module exists
        if !isdirectory(l:module.path)
            let l:status = 'MISSING'
        else
            " Continue with all checks for existing modules
            
            " Get current commit
            let l:commit = system('cd "' . l:module.path . '" && git rev-parse --short HEAD 2>/dev/null || echo "N/A"')
            let l:commit = substitute(l:commit, '\n', '', 'g')
            
            " Get last commit date
            let l:last_updated = system('cd "' . l:module.path . '" && git log -1 --format=%cd --date=relative 2>/dev/null || echo "N/A"')
            let l:last_updated = substitute(l:last_updated, '\n', '', 'g')
            
            " Use the utility function to check for updates
            let l:update_status = plugin_manager#utils#check_module_updates(l:module.path)
            
            " Use branch information from the utility function
            let l:branch = l:update_status.branch
            
            " Simplify branch display
            if l:branch == 'detached'
            let l:branch = 'HEAD'
            endif
            
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
        
        call add(l:lines, l:name_col . l:commit_col . l:branch_col . l:date_col . l:status)
        endif
    endfor
    
    call plugin_manager#ui#open_sidebar(l:lines)
endfunction
    
" Show a summary of submodule changes
function! plugin_manager#modules#list#summary()
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
    
    let l:output = system('git submodule summary')
    let l:lines = [l:header, repeat('-', len(l:header)), '']
    call extend(l:lines, split(l:output, "\n"))
    
    call plugin_manager#ui#open_sidebar(l:lines)
endfunction