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

function! plugin_manager#utils#check_module_updates(module_path)
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
  
  " Get current commit hash (more reliable for submodules than branch)
  let l:current_commit = system('cd "' . a:module_path . '" && git rev-parse HEAD 2>/dev/null || echo "N/A"')
  let l:result.current_commit = substitute(l:current_commit, '\n', '', 'g')
  
  " Get current symbolic ref - might be a branch or HEAD
  let l:branch = system('cd "' . a:module_path . '" && git symbolic-ref --short HEAD 2>/dev/null || echo "detached"')
  let l:result.branch = substitute(l:branch, '\n', '', 'g')
  
  " Fetch updates from remote repository more aggressively
  call system('cd "' . a:module_path . '" && git fetch origin --all 2>/dev/null')
  
  " First try to find remote branch from .gitmodules
  let l:remote_info = system('cd "' . a:module_path . '" && git config -f ../.gitmodules submodule.' . fnamemodify(a:module_path, ':t') . '.branch 2>/dev/null || echo ""')
  let l:remote_branch = substitute(l:remote_info, '\n', '', 'g')
  
  " If not found in .gitmodules, try to determine from the current branch's upstream
  if empty(l:remote_branch) && l:result.branch != "detached"
    let l:upstream_info = system('cd "' . a:module_path . '" && git rev-parse --abbrev-ref ' . l:result.branch . '@{upstream} 2>/dev/null || echo ""')
    let l:remote_branch = substitute(l:upstream_info, '\n', '', 'g')
    " If upstream exists but doesn't include 'origin/', prepend it
    if !empty(l:remote_branch) && l:remote_branch !~ '^origin/'
      let l:remote_branch = 'origin/' . l:remote_branch
    endif
  endif
  
  " If still not found, try to determine from standard branches
  if empty(l:remote_branch)
    " Check if origin/main exists
    let l:main_exists = system('cd "' . a:module_path . '" && git show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; echo $?')
    if trim(l:main_exists) == "0"
      let l:remote_branch = 'origin/main'
    else
      " Check if origin/master exists
      let l:master_exists = system('cd "' . a:module_path . '" && git show-ref --verify --quiet refs/remotes/origin/master 2>/dev/null; echo $?')
      if trim(l:master_exists) == "0"
        let l:remote_branch = 'origin/master'
      endif
    endif
  endif
  
  " Default to origin/master if all attempts failed
  if empty(l:remote_branch)
    let l:remote_branch = 'origin/master'
  endif
  
  let l:result.remote_branch = l:remote_branch
  
  " Get the latest commit on the remote branch
  let l:remote_commit = system('cd "' . a:module_path . '" && git rev-parse ' . l:result.remote_branch . ' 2>/dev/null || echo "N/A"')
  let l:result.remote_commit = substitute(l:remote_commit, '\n', '', 'g')
  
  " Direct check if remote commit is different from current commit
  if l:result.current_commit != "N/A" && l:result.remote_commit != "N/A" && l:result.current_commit != l:result.remote_commit
    " Get the merge base to determine the common ancestor
    let l:merge_base = system('cd "' . a:module_path . '" && git merge-base HEAD ' . l:result.remote_branch . ' 2>/dev/null || echo "N/A"')
    let l:merge_base = substitute(l:merge_base, '\n', '', 'g')
    
    " Count commits ahead/behind
    let l:behind_check = system('cd "' . a:module_path . '" && git rev-list --count HEAD..' . l:result.remote_branch . ' 2>/dev/null || echo "0"')
    let l:behind = substitute(l:behind_check, '\n', '', 'g')
    if l:behind =~ '^\d\+$'
      let l:result.behind = str2nr(l:behind)
    endif
    
    let l:ahead_check = system('cd "' . a:module_path . '" && git rev-list --count ' . l:result.remote_branch . '..HEAD 2>/dev/null || echo "0"')
    let l:ahead = substitute(l:ahead_check, '\n', '', 'g')
    if l:ahead =~ '^\d\+$'
      let l:result.ahead = str2nr(l:ahead)
    endif
    
    " Force has_updates flag if the current and remote commits are different
    let l:result.has_updates = (l:result.behind > 0 || l:result.current_commit != l:result.remote_commit)
  endif
  
  " For submodules, we primarily care about commit differences, not branch names
  " If current branch is not detached and doesn't match remote branch name, note this
  let l:remote_branch_name = substitute(l:result.remote_branch, '^origin/', '', '')
  if l:result.branch != "detached" && l:result.branch != l:remote_branch_name
    let l:result.different_branch = 1
  endif
  
  " Check for local changes while ignoring helptags files
  let l:changes = system('cd "' . a:module_path . '" && git status -s -- . ":(exclude)doc/tags" ":(exclude)**/tags" 2>/dev/null')
  let l:result.has_changes = !empty(l:changes)
  
  return l:result
endfunction

" Process plugin specification block from .vimrc
function! plugin_manager#utils#process_plugin_block(start_line, end_line)
  let l:header = ['Processing Plugin Block:', '----------------------', '']
  call plugin_manager#ui#open_sidebar(l:header)
  
  let l:vimrc_path = expand(g:plugin_manager_vimrc_path)
  if !filereadable(l:vimrc_path)
    call plugin_manager#ui#update_sidebar(['Error: vimrc file not found at ' . l:vimrc_path], 1)
    return
  endif
  
  let l:lines = readfile(l:vimrc_path)
  let l:process_lines = l:lines[a:start_line-1:a:end_line-1]
  
  let l:plugins_to_install = []
  let l:current_plugin = {}
  let l:in_plugin_def = 0
  
  for l:line in l:process_lines
    " Skip empty lines and comments
    if l:line =~ '^\s*$' || l:line =~ '^\s*"'
      continue
    endif
    
    " Check for PluginBegin
    if l:line =~ '^\s*PluginBegin'
      continue
    endif
    
    " Check for PluginEnd
    if l:line =~ '^\s*PluginEnd'
      continue
    endif
    
    " Check for Plugin definition
    let l:plugin_match = matchlist(l:line, '^\s*Plugin\s\+[''"].\{-}[''"]')
    if !empty(l:plugin_match)
      " Start new plugin definition
      if !empty(l:current_plugin)
        call add(l:plugins_to_install, l:current_plugin)
      endif
      
      let l:current_plugin = {'line': l:line, 'options': {}}
      let l:in_plugin_def = 1
      
      " Extract plugin URL or shortname
      let l:url_match = matchlist(l:line, '^\s*Plugin\s\+[''"]\(.\{-}\)[''"]')
      if !empty(l:url_match)
        let l:current_plugin.url = l:url_match[1]
      endif
      
      " Check for inline options
      let l:options_match = matchlist(l:line, '^\s*Plugin\s\+[''"].\{-}[''"],\s*{\(.\{-}\)}')
      if !empty(l:options_match)
        let l:options_str = l:options_match[1]
        let l:current_plugin.options = s:parse_plugin_options(l:options_str)
      endif
    endif
  endfor
  
  " Add last plugin if exists
  if !empty(l:current_plugin)
    call add(l:plugins_to_install, l:current_plugin)
  endif
  
  " Install plugins
  call plugin_manager#ui#update_sidebar(['Found ' . len(l:plugins_to_install) . ' plugins to install...'], 1)
  
  for l:plugin in l:plugins_to_install
    let l:url = l:plugin.url
    let l:options = l:plugin.options
    
    " Convert options to plugin_manager options
    let l:pm_options = {}
    
    " Handle 'dir' option
    if has_key(l:options, 'dir')
      let l:pm_options.dir = l:options.dir
    endif
    
    " Handle 'branch' option
    if has_key(l:options, 'branch')
      let l:pm_options.branch = l:options.branch
    endif
    
    " Handle 'tag' option
    if has_key(l:options, 'tag')
      let l:pm_options.tag = l:options.tag
    endif
    
    " Handle 'exec' option
    if has_key(l:options, 'exec')
      let l:exec_value = l:options.exec
      " Check if it's a string
      if type(l:exec_value) == v:t_string
        let l:pm_options.exec = l:exec_value
      endif
    endif
    
    " Handle 'load' option
    if has_key(l:options, 'load')
      let l:pm_options.load = l:options.load
    endif
    
    " Install the plugin
    call plugin_manager#ui#update_sidebar(['Installing: ' . l:url], 1)
    call plugin_manager#modules#add(l:url, l:pm_options)
  endfor
  
  call plugin_manager#ui#update_sidebar(['Plugin block processing completed.'], 1)
endfunction

" Parse options from string to dictionary
function! s:parse_plugin_options(options_str)
  let l:options = {}
  
  " Split by commas, but respect nested structures
  let l:option_parts = split(a:options_str, ',')
  
  for l:part in l:option_parts
    let l:kv_match = matchlist(l:part, '[''"]\?\(\w\+\)[''"]\?\s*:\s*\(.\{-}\)\s*$')
    if !empty(l:kv_match)
      let l:key = trim(l:kv_match[1])
      let l:value = trim(l:kv_match[2])
      
      " Remove quotes from string values
      if l:value =~ '^[''"].*[''"]$'
        let l:value = l:value[1:-2]
      endif
      
      let l:options[l:key] = l:value
    endif
  endfor
  
  return l:options
endfunction