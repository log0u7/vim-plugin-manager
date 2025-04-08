" autoload/plugin_manager/utils_async.vim - Asynchronous utility functions for vim-plugin-manager
" This file contains asynchronous versions of utility functions

" Check if a repository exists asynchronously
    function! plugin_manager#utils_async#repository_exists(url, callback)
        " Use git ls-remote to check if the repository exists
        let l:cmd = 'git ls-remote --exit-code "' . a:url . '" HEAD > /dev/null 2>&1'
        
        " Create completion callback
        function! s:on_repo_check_complete(output, status) closure
          " Call the provided callback with result (true if repo exists, false otherwise)
          call a:callback(a:status == 0)
        endfunction
        
        " Execute command asynchronously
        let l:job_id = plugin_manager#async#system(l:cmd, function('s:on_repo_check_complete'))
        return l:job_id
      endfunction
      
      " Parse .gitmodules and return a dictionary of plugins asynchronously
      function! plugin_manager#utils_async#parse_gitmodules(callback)
        " Ensure we're in the right directory
        if !plugin_manager#utils#ensure_vim_directory()
          call a:callback({})
          return 0
        endif
        
        " If .gitmodules doesn't exist, return empty cache
        if !filereadable('.gitmodules')
          let g:pm_gitmodules_cache = {}
          call a:callback(g:pm_gitmodules_cache)
          return 0
        endif
        
        " Check if file has been modified since last parse
        let l:mtime = getftime('.gitmodules')
        if !empty(g:pm_gitmodules_cache) && l:mtime == g:pm_gitmodules_mtime
          call a:callback(g:pm_gitmodules_cache)
          return 0
        endif
        
        " Create task to parse gitmodules
        function! s:parse_gitmodules_task() closure
          " Reading the file is quick, so we do it directly
          let l:lines = readfile('.gitmodules')
          let g:pm_gitmodules_cache = {}
          let g:pm_gitmodules_mtime = l:mtime
          
          let l:current_module = ''
          let l:in_module = 0
          
          for l:line in l:lines
            " Skip empty lines and comments
            if l:line =~ '^\s*$' || l:line =~ '^\s*#'
              continue
            endif
            
            " Start of module section
            if l:line =~ '\[submodule "'
              let l:in_module = 1
              " Extract module name from [submodule "name"] format
              let l:current_module = substitute(l:line, '\[submodule "\(.\{-}\)"\]', '\1', '')
              let g:pm_gitmodules_cache[l:current_module] = {'name': l:current_module}
            " Inside module section
            elseif l:in_module && !empty(l:current_module)
              " Path property
              if l:line =~ '\s*path\s*='
                let l:path = substitute(l:line, '\s*path\s*=\s*', '', '')
                let l:path = substitute(l:path, '^\s*\(.\{-}\)\s*$', '\1', '')  " Trim whitespace
                let g:pm_gitmodules_cache[l:current_module]['path'] = l:path
                " Extract short name from path (last component)
                let g:pm_gitmodules_cache[l:current_module]['short_name'] = fnamemodify(l:path, ':t')
              " URL property
              elseif l:line =~ '\s*url\s*='
                let l:url = substitute(l:line, '\s*url\s*=\s*', '', '')
                let l:url = substitute(l:url, '^\s*\(.\{-}\)\s*$', '\1', '')  " Trim whitespace
                let g:pm_gitmodules_cache[l:current_module]['url'] = l:url
              " New section starts - reset current module
              elseif l:line =~ '\['
                let l:in_module = 0
                let l:current_module = ''
              endif
            endif
          endfor
          
          " Use git ls-files to verify existence of directories in parallel
          return 'git ls-files --directory ' . join(values(g:pm_gitmodules_cache)->map({_, v -> has_key(v, 'path') ? '"' . v.path . '"' : ''}), ' ')
        endfunction
        
        function! s:on_parse_success(task_id, result, status) closure
          " Validate the modules: each should have both path and url
          for [l:name, l:module] in items(g:pm_gitmodules_cache)
            if !has_key(l:module, 'path') || !has_key(l:module, 'url')
              " Mark invalid modules but don't remove them
              let g:pm_gitmodules_cache[l:name]['is_valid'] = 0
            else
              let g:pm_gitmodules_cache[l:name]['is_valid'] = 1
              
              " Check if the plugin directory exists
              " We can determine this from the git ls-files output or with isdirectory
              let g:pm_gitmodules_cache[l:name]['exists'] = isdirectory(l:module.path)
            endif
          endfor
          
          " Call the callback with the result
          call a:callback(g:pm_gitmodules_cache)
        endfunction
        
        " Create and start task
        let l:task_options = {
              \ 'name': 'Parse gitmodules',
              \ 'commands': function('s:parse_gitmodules_task'),
              \ 'on_success': function('s:on_parse_success'),
              \ 'use_async': 1,
              \ }
        
        let l:task_id = plugin_manager#tasks#create('single', l:task_options)
        call plugin_manager#tasks#start(l:task_id)
        
        return l:task_id
      endfunction
      
      " Find a module by name, path, or short name asynchronously
      function! plugin_manager#utils_async#find_module(query, callback)
        " Parse modules asynchronously first
        function! s:on_parse_complete(modules) closure
          " First try exact match on module name
          if has_key(a:modules, a:query)
            call a:callback({'name': a:query, 'module': a:modules[a:query]})
            return
          endif
          
          " Then try path and short name matches
          for [l:name, l:module] in items(a:modules)
            " Exact path match
            if has_key(l:module, 'path') && l:module.path ==# a:query
              call a:callback({'name': l:name, 'module': l:module})
              return
            endif
            
            " Exact short name match
            if has_key(l:module, 'short_name') && l:module.short_name ==# a:query
              call a:callback({'name': l:name, 'module': l:module})
              return
            endif
          endfor
          
          " Then try partial matches with case insensitivity
          for [l:name, l:module] in items(a:modules)
            " Module name, path or short_name contains query
            if l:name =~? a:query || 
                  \ (has_key(l:module, 'path') && l:module.path =~? a:query) ||
                  \ (has_key(l:module, 'short_name') && l:module.short_name =~? a:query)
              call a:callback({'name': l:name, 'module': l:module})
              return
            endif
        endfor
          
          " No match found
          call a:callback({})
        endfunction
        
        return plugin_manager#utils_async#parse_gitmodules(function('s:on_parse_complete'))
      endfunction
      
      " Refresh the gitmodules cache asynchronously
      function! plugin_manager#utils_async#refresh_modules_cache(callback)
        let g:pm_gitmodules_mtime = 0
        return plugin_manager#utils_async#parse_gitmodules(a:callback)
      endfunction
      
      " Check module updates asynchronously
      function! plugin_manager#utils_async#check_module_updates(module_path, callback)
        " Create task to check module updates
        function! s:check_updates_task() closure
          " Prepare initial result structure
          let l:result = {
            \ 'behind': 0, 
            \ 'ahead': 0, 
            \ 'has_updates': 0, 
            \ 'has_changes': 0,
            \ 'branch': 'N/A',
            \ 'remote_branch': 'N/A',
            \ 'different_branch': 0,
            \ 'current_commit': 'N/A',
            \ 'remote_commit': 'N/A'
          \ }
          
          " Check if the directory exists
          if !isdirectory(a:module_path)
            return l:result
          endif
          
          " Execute multiple commands in sequence to get all necessary info
          return 'cd "' . a:module_path . '" && echo "PM_CURRENT_COMMIT:$(git rev-parse HEAD 2>/dev/null || echo "N/A")" && ' .
                 \ 'echo "PM_BRANCH:$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")" && ' .
                 \ 'git fetch origin --all 2>/dev/null && ' .
                 \ 'echo "PM_REMOTE_BRANCH:$(git config -f ../.gitmodules submodule.' . fnamemodify(a:module_path, ':t') . '.branch 2>/dev/null || echo "")" && ' .
                 \ 'git rev-parse --abbrev-ref HEAD@{upstream} 2>/dev/null || echo "PM_UPSTREAM:" && ' .
                 \ 'echo "PM_MAIN_EXISTS:$(git show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; echo $?)" && ' .
                 \ 'echo "PM_MASTER_EXISTS:$(git show-ref --verify --quiet refs/remotes/origin/master 2>/dev/null; echo $?)" && ' .
                 \ 'echo "PM_HAS_CHANGES:$(git status -s -- . ":(exclude)doc/tags" ":(exclude)**/tags" 2>/dev/null | wc -l)"'
        endfunction
        
        function! s:on_check_success(task_id, output, status) closure
          " Parse the output to fill in the result structure
          let l:result = {
            \ 'behind': 0, 
            \ 'ahead': 0, 
            \ 'has_updates': 0, 
            \ 'has_changes': 0,
            \ 'branch': 'N/A',
            \ 'remote_branch': 'N/A',
            \ 'different_branch': 0,
            \ 'current_commit': 'N/A',
            \ 'remote_commit': 'N/A'
          \ }
          
          " Parse output lines
          let l:lines = split(a:output, "\n")
          let l:remote_branch = ''
          
          for l:line in l:lines
            " Parse each tagged line
            if l:line =~ '^PM_CURRENT_COMMIT:'
              let l:result.current_commit = substitute(l:line, '^PM_CURRENT_COMMIT:', '', '')
            elseif l:line =~ '^PM_BRANCH:'
              let l:result.branch = substitute(l:line, '^PM_BRANCH:', '', '')
            elseif l:line =~ '^PM_REMOTE_BRANCH:'
              let l:remote_branch = substitute(l:line, '^PM_REMOTE_BRANCH:', '', '')
            elseif l:line =~ '^PM_UPSTREAM:'
              let l:upstream = substitute(l:line, '^PM_UPSTREAM:', '', '')
              if !empty(l:upstream) && l:upstream != 'PM_UPSTREAM'
                if l:upstream !~ '^origin/'
                  let l:remote_branch = 'origin/' . l:upstream
                else
                  let l:remote_branch = l:upstream
                endif
              endif
            elseif l:line =~ '^PM_MAIN_EXISTS:'
              let l:main_exists = substitute(l:line, '^PM_MAIN_EXISTS:', '', '')
              if trim(l:main_exists) == "0" && empty(l:remote_branch)
                let l:remote_branch = 'origin/main'
              endif
            elseif l:line =~ '^PM_MASTER_EXISTS:'
              let l:master_exists = substitute(l:line, '^PM_MASTER_EXISTS:', '', '')
              if trim(l:master_exists) == "0" && empty(l:remote_branch)
                let l:remote_branch = 'origin/master'
              endif
            elseif l:line =~ '^PM_HAS_CHANGES:'
              let l:changes_count = substitute(l:line, '^PM_HAS_CHANGES:', '', '')
              let l:result.has_changes = str2nr(l:changes_count) > 0
            endif
          endfor
          
          " Default to origin/master if all attempts failed
          if empty(l:remote_branch)
            let l:remote_branch = 'origin/master'
          endif
          
          let l:result.remote_branch = l:remote_branch
          
          " Start a second task to get additional Git info
          function! s:get_more_git_info() closure
            return 'cd "' . a:module_path . '" && ' .
                   \ 'echo "PM_REMOTE_COMMIT:$(git rev-parse ' . l:result.remote_branch . ' 2>/dev/null || echo "N/A")" && ' .
                   \ 'echo "PM_BEHIND:$(git rev-list --count HEAD..' . l:result.remote_branch . ' 2>/dev/null || echo "0")" && ' .
                   \ 'echo "PM_AHEAD:$(git rev-list --count ' . l:result.remote_branch . '..HEAD 2>/dev/null || echo "0")"'
          endfunction
          
          function! s:on_more_info_success(inner_task_id, inner_output, inner_status) closure
            " Parse output lines for additional info
            let l:lines = split(a:inner_output, "\n")
            
            for l:line in l:lines
              if l:line =~ '^PM_REMOTE_COMMIT:'
                let l:result.remote_commit = substitute(l:line, '^PM_REMOTE_COMMIT:', '', '')
              elseif l:line =~ '^PM_BEHIND:'
                let l:behind = substitute(l:line, '^PM_BEHIND:', '', '')
                if l:behind =~ '^\d\+$'
                  let l:result.behind = str2nr(l:behind)
                endif
              elseif l:line =~ '^PM_AHEAD:'
                let l:ahead = substitute(l:line, '^PM_AHEAD:', '', '')
                if l:ahead =~ '^\d\+$'
                  let l:result.ahead = str2nr(l:ahead)
                endif
              endif
            endfor
            
            " Set has_updates flag if appropriate
            if l:result.current_commit != "N/A" && l:result.remote_commit != "N/A" && l:result.current_commit != l:result.remote_commit
              let l:result.has_updates = (l:result.behind > 0 || l:result.current_commit != l:result.remote_commit)
            endif
            
            " Check for different branch
            let l:remote_branch_name = substitute(l:result.remote_branch, '^origin/', '', '')
            if l:result.branch != "detached" && l:result.branch != l:remote_branch_name
              let l:result.different_branch = 1
            endif
            
            " Call the original callback with the complete result
            call a:callback(l:result)
          endfunction
          
          " Create and start task for additional info
          let l:task_options = {
                \ 'name': 'Get more git info for ' . a:module_path,
                \ 'commands': function('s:get_more_git_info'),
                \ 'on_success': function('s:on_more_info_success'),
                \ 'use_async': 1,
                \ }
          
          let l:task_id = plugin_manager#tasks#create('single', l:task_options)
          call plugin_manager#tasks#start(l:task_id)
        endfunction
        
        " Create and start task
        let l:task_options = {
              \ 'name': 'Checking updates for ' . a:module_path,
              \ 'commands': function('s:check_updates_task'),
              \ 'on_success': function('s:on_check_success'),
              \ 'use_async': 1,
              \ }
        
        let l:task_id = plugin_manager#tasks#create('single', l:task_options)
        call plugin_manager#tasks#start(l:task_id)
        
        return l:task_id
      endfunction
      
      " Task type constants - mirror those in tasks.vim
      let s:TYPE_SINGLE = 'single'
      let s:TYPE_SEQUENCE = 'sequence'
      let s:TYPE_PARALLEL = 'parallel'