" autoload/plugin_manager/cmd/status.vim - Status command for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: refacto2 v1.3.3 d4f8fda

" Show detailed status of all plugins
function! plugin_manager#cmd#status#execute() abort
    try
      if !plugin_manager#core#ensure_vim_directory()
        return
      endif
      
      " Use git module to get plugin information
      let l:modules = plugin_manager#git#parse_modules()
      let l:header = 'Submodule Status:'
      
      if empty(l:modules)
        let l:lines = [l:header, repeat('-', len(l:header)), '', 'No submodules found (.gitmodules not found)']
        call plugin_manager#ui#open_sidebar(l:lines)
        return
      endif
      
      let l:lines = [l:header, repeat('-', len(l:header)), '']
      call add(l:lines, 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 20).'Last Updated'.repeat(' ', 18).'Status')
      call add(l:lines, repeat('-', 120))
      
      " Fetch updates to ensure we have up-to-date status information
      call plugin_manager#ui#update_sidebar(['Fetching updates from remote repositories...'], 1)
      call plugin_manager#git#execute('git submodule foreach --recursive "git fetch -q origin 2>/dev/null || true"', '', 1, 0)
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
            let l:result = plugin_manager#git#execute('git rev-parse --short HEAD', l:module.path, 0, 0)
            if l:result.success
              let l:commit = substitute(l:result.output, '\n', '', 'g')
            endif
            
            " Get last commit date
            let l:result = plugin_manager#git#execute('git log -1 --format=%cd --date=relative', l:module.path, 0, 0)
            if l:result.success
              let l:last_updated = substitute(l:result.output, '\n', '', 'g')
            endif
            
            " Use the git utility function to check for updates
            let l:update_status = plugin_manager#git#check_updates(l:module.path)
            
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
          
          call add(l:lines, l:name_col . l:commit_col . l:branch_col . l:date_col . l:status)
        endif
      endfor
      
      call plugin_manager#ui#open_sidebar(l:lines)
    catch
      call plugin_manager#core#handle_error(v:exception, "status")
    endtry
  endfunction