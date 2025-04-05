" Utility functions for vim-plugin-manager

" Function to ensure we're in the Vim config directory
function! plugin_manager#utils#ensure_vim_directory()
    " Get current directory
    let l:current_dir = getcwd()
    
    " Check if we're already in the vim directory
    if l:current_dir == g:plugin_manager_vim_dir
      return 1
    endif
    
    " Check if the vim directory exists
    if !isdirectory(g:plugin_manager_vim_dir)
      let l:error_lines = ['Error:', '------', '', 'Vim directory not found: ' . g:plugin_manager_vim_dir, 
            \ 'Please set g:plugin_manager_vim_dir to your Vim configuration directory.']
      call plugin_manager#ui#open_sidebar(l:error_lines)
      return 0
    endif
    
    " Change to vim directory
    execute 'cd ' . g:plugin_manager_vim_dir
    
    " Check if it's a git repository
    if !isdirectory('.git')
      let l:error_lines = ['Error:', '------', '', 'The Vim directory is not a git repository.', 
            \ 'Please initialize it with: git init ' . g:plugin_manager_vim_dir]
      call plugin_manager#ui#open_sidebar(l:error_lines)
      return 0
    endif
    
    return 1
  endfunction
  
" Execute command with output in sidebar - redesigned for better efficiency
function! plugin_manager#utils#execute_with_sidebar(title, cmd)
    " Ensure we're in the Vim directory
    if !plugin_manager#utils#ensure_vim_directory()
      return ''
    endif
    
    " Create initial header only once
    let l:header = [a:title, repeat('-', len(a:title)), '']
    let l:initial_message = l:header + ['Executing operation, please wait...']
    
    " Create or update sidebar window with initial message
    call plugin_manager#ui#open_sidebar(l:initial_message)
    
    " Execute command and collect output
    let l:output = system(a:cmd)
    let l:output_lines = split(l:output, "\n")
    
    " Prepare final output - reuse header
    let l:final_output = l:header + l:output_lines + ['', 'Press q to close this window...']
    
    " Update sidebar with final content - replace entire contents
    call plugin_manager#ui#update_sidebar(l:final_output, 0)
    
    return l:output
endfunction
  
" Convert short name to full URL
function! plugin_manager#utils#convert_to_full_url(shortName)
    " If it's already a URL, return it as is
    if a:shortName =~ g:pm_urlRegexp
      return a:shortName
    endif
    
    " Check if it's a user/repo format
    if a:shortName =~ g:pm_shortNameRegexp
      return 'https://' . g:plugin_manager_default_git_host . '/' . a:shortName . '.git'
    endif
    
    " Return empty string for calling function to handle not a valid format
    return ''
endfunction
  
" Check if a repository exists
function! plugin_manager#utils#repository_exists(url)
    " Use git ls-remote to check if the repository exists
    let l:cmd = 'git ls-remote ' . a:url . ' > /dev/null 2>&1'
    let l:exitCode = system(l:cmd)
    
    " Return 0 if the command succeeded (repository exists), non-zero otherwise
    return v:shell_error == 0
endfunction

" Parse .gitmodules and return a dictionary of plugins
function! plugin_manager#utils#parse_gitmodules()
    " Ensure we're in the right directory
    if !plugin_manager#utils#ensure_vim_directory()
      return {}
    endif
    
    " Check if .gitmodules exists
    if !filereadable('.gitmodules')
      let g:pm_gitmodules_cache = {}
      return g:pm_gitmodules_cache
    endif
    
    " Check if file has been modified since last parse
    let l:mtime = getftime('.gitmodules')
    if !empty(g:pm_gitmodules_cache) && l:mtime == g:pm_gitmodules_mtime
      return g:pm_gitmodules_cache
    endif
    
    " Reset cache
    let g:pm_gitmodules_cache = {}
    let g:pm_gitmodules_mtime = l:mtime
    
    " Parse the file
    let l:lines = readfile('.gitmodules')
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
    
    " Validate the modules: each should have both path and url
    for [l:name, l:module] in items(g:pm_gitmodules_cache)
      if !has_key(l:module, 'path') || !has_key(l:module, 'url')
        " Mark invalid modules but don't remove them
        let g:pm_gitmodules_cache[l:name]['is_valid'] = 0
      else
        let g:pm_gitmodules_cache[l:name]['is_valid'] = 1
        
        " Check if the plugin directory exists
        let g:pm_gitmodules_cache[l:name]['exists'] = isdirectory(l:module.path)
      endif
    endfor
    
    return g:pm_gitmodules_cache
endfunction
  
" Utility function to find a module by name, path, or short name
function! plugin_manager#utils#find_module(query)
    let l:modules = plugin_manager#utils#parse_gitmodules()
    
    " First try exact match on module name
    if has_key(l:modules, a:query)
      return {'name': a:query, 'module': l:modules[a:query]}
    endif
    
    " Then try path and short name matches
    for [l:name, l:module] in items(l:modules)
      " Exact path match
      if has_key(l:module, 'path') && l:module.path ==# a:query
        return {'name': l:name, 'module': l:module}
      endif
      
      " Exact short name match
      if has_key(l:module, 'short_name') && l:module.short_name ==# a:query
        return {'name': l:name, 'module': l:module}
      endif
    endfor
    
    " Then try partial matches
    for [l:name, l:module] in items(l:modules)
      " Module name contains query
      if l:name =~ a:query
        return {'name': l:name, 'module': l:module}
      endif
      
      " Path contains query
      if has_key(l:module, 'path') && l:module.path =~ a:query
        return {'name': l:name, 'module': l:module}
      endif
      
      " Short name contains query
      if has_key(l:module, 'short_name') && l:module.short_name =~ a:query
        return {'name': l:name, 'module': l:module}
      endif
    endfor
    
    " No match found
    return {}
endfunction
  
" Force refresh the gitmodules cache
function! plugin_manager#utils#refresh_modules_cache()
    let g:pm_gitmodules_mtime = 0
    return plugin_manager#utils#parse_gitmodules()
endfunction

" Utility function to check if a module has updates available
" Returns a dictionary with comprehensive status information
function! plugin_manager#utils#check_module_updates(module_path)
  let l:result = {
    \ 'behind': 0, 
    \ 'ahead': 0, 
    \ 'has_updates': 0, 
    \ 'has_changes': 0,
    \ 'branch': 'N/A',
    \ 'remote_branch': 'N/A',
    \ 'different_branch': 0
  \ }
  
  " Check if the directory exists
  if !isdirectory(a:module_path)
    return l:result
  endif
  
  " Get current branch
  let l:branch = system('cd "' . a:module_path . '" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A"')
  let l:result.branch = substitute(l:branch, '\n', '', 'g')
  
  " Fetch updates from remote repository
  call system('cd "' . a:module_path . '" && git fetch origin 2>/dev/null')
  
  " Check if we have a configured upstream branch
  let l:has_upstream = system('cd "' . a:module_path . '" && git rev-parse --abbrev-ref @{upstream} 2>/dev/null')
  let l:has_upstream = v:shell_error == 0
  
  if l:has_upstream
    " Get the name of the upstream branch
    let l:upstream = system('cd "' . a:module_path . '" && git rev-parse --abbrev-ref @{upstream} 2>/dev/null')
    let l:result.remote_branch = substitute(l:upstream, '\n', '', 'g')
    
    " Check if local and remote branch names differ (excluding remote name)
    let l:remote_branch_name = substitute(l:result.remote_branch, '^[^/]\+/', '', '')
    let l:result.different_branch = (l:result.branch != l:remote_branch_name)
    
    " Check for updates using the upstream branch if branches match
    if !l:result.different_branch
      " Check how many commits we are behind
      let l:behind_check = system('cd "' . a:module_path . '" && git rev-list --count HEAD..@{upstream} 2>/dev/null || echo "0"')
      let l:behind = substitute(l:behind_check, '\n', '', 'g')
      
      " Check how many commits we are ahead
      let l:ahead_check = system('cd "' . a:module_path . '" && git rev-list --count @{upstream}..HEAD 2>/dev/null || echo "0"')
      let l:ahead = substitute(l:ahead_check, '\n', '', 'g')
      
      " Convert to numbers if possible
      if l:behind =~ '^\d\+$'
        let l:result.behind = str2nr(l:behind)
      endif
      
      if l:ahead =~ '^\d\+$'
        let l:result.ahead = str2nr(l:ahead)
      endif
    endif
  else
    " No upstream branch configured, use FETCH_HEAD as fallback
    " Get the default remote branch (what would be checked out on clone)
    let l:default_branch = system('cd "' . a:module_path . '" && git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo "unknown"')
    let l:default_branch = substitute(l:default_branch, '\n', '', 'g')
    let l:default_branch = substitute(l:default_branch, '^origin/', '', '')
    let l:result.remote_branch = 'origin/' . l:default_branch
    
    " Mark as different branch if not on default branch
    let l:result.different_branch = (l:result.branch != l:default_branch && l:default_branch != "unknown")
    
    " Only compare with FETCH_HEAD if on the default branch
    if !l:result.different_branch
      " Check how many commits we are behind
      let l:behind_check = system('cd "' . a:module_path . '" && git rev-list --count HEAD..FETCH_HEAD 2>/dev/null || echo "0"')
      let l:behind = substitute(l:behind_check, '\n', '', 'g')
      
      " Check how many commits we are ahead
      let l:ahead_check = system('cd "' . a:module_path . '" && git rev-list --count FETCH_HEAD..HEAD 2>/dev/null || echo "0"')
      let l:ahead = substitute(l:ahead_check, '\n', '', 'g')
      
      " Convert to numbers if possible
      if l:behind =~ '^\d\+$'
        let l:result.behind = str2nr(l:behind)
      endif
      
      if l:ahead =~ '^\d\+$'
        let l:result.ahead = str2nr(l:ahead)
      endif
    endif
  endif
  
  " Determine if there are updates
  let l:result.has_updates = (l:result.behind > 0)
  
  " Check for local changes while ignoring helptags files
  let l:changes = system('cd "' . a:module_path . '" && git status -s -- . ":(exclude)doc/tags" ":(exclude)**/tags" 2>/dev/null')
  let l:result.has_changes = !empty(l:changes)
  
  return l:result
endfunction