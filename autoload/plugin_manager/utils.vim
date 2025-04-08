" autoload/plugin_manager/utils.vim - Utility functions for vim-plugin-manager
" Updated with asynchronous versions of key functions

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

" Exception helpers
function! plugin_manager#utils#throw(component, message)
throw 'PM_ERROR:' . a:component . ':' . a:message
endfunction

function! plugin_manager#utils#is_pm_error(error)
return a:error =~# '^PM_ERROR:'
endfunction

function! plugin_manager#utils#format_error(error)
if plugin_manager#utils#is_pm_error(a:error)
  let l:parts = split(a:error, ':')
  return l:parts[2:]->join(':')
endif
return a:error
endfunction

" Execute command with output in sidebar - redesigned for better efficiency and async support
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
  
  " Check if we can use async
  if plugin_manager#async#has_async() && g:plugin_manager_use_async
    " Use UI function for async execution
    let l:options = {
          \ 'use_async': 1,
          \ }
    return plugin_manager#ui#execute_with_sidebar(a:title, a:cmd, l:options)
  else
    " Synchronous fallback
    let l:output = system(a:cmd)
    let l:output_lines = split(l:output, "\n")
    
    " Prepare final output - reuse header
    let l:final_output = l:header + l:output_lines + ['', 'Press q to close this window...']
    
    " Update sidebar with final content - replace entire contents
    call plugin_manager#ui#update_sidebar(l:final_output, 0)
    
    return l:output
  endif
endfunction

" Function to detect if a path is a local path
function! plugin_manager#utils#is_local_path(path)
" Starts with '~' (home path)
if a:path =~ '^\~\/'
  return 1
endif
  
" Absolute path (starts with '/' or drive letter on Windows)
if a:path =~ '^\/\|^[A-Za-z]:[\\\/]'
  return 1
endif
  
" Relative path that exists locally
let l:expanded_path = expand(a:path)
if isdirectory(l:expanded_path)
  return 1
endif
  
return 0
endfunction

" Modified version of convert_to_full_url to handle local paths
function! plugin_manager#utils#convert_to_full_url(shortName)
  " If it's a local path
  if plugin_manager#utils#is_local_path(a:shortName)
    return 'local:' . expand(a:shortName)
  endif
    
  " If it's already a URL, return as is
  if a:shortName =~ g:pm_urlRegexp
    return a:shortName
  endif
    
  " If it's a user/repo format
  if a:shortName =~ g:pm_shortNameRegexp
    return 'https://' . g:plugin_manager_default_git_host . '/' . a:shortName . '.git'
  endif
    
  " Return empty string for unrecognized format
  return ''
endfunction

" Check if a repository exists
" Synchronous version
function! plugin_manager#utils#repository_exists(url)
  " Use git ls-remote to check if the repository exists
  let l:cmd = 'git ls-remote --exit-code "' . a:url . '" HEAD > /dev/null 2>&1'
  call system(l:cmd)
  
  " Return true if command succeeded (repository exists), false otherwise
  return v:shell_error == 0
endfunction

" Asynchronous version with callback
function! plugin_manager#utils#repository_exists_async(url, callback)
  " Use git ls-remote to check if the repository exists
  let l:cmd = 'git ls-remote --exit-code "' . a:url . '" HEAD > /dev/null 2>&1'
  
  " Check if we can use async
  if plugin_manager#async#has_async() && g:plugin_manager_use_async
    " Create completion callback
    function! s:on_repo_check_complete(output, status) closure
      " Call the provided callback with result (true if repo exists, false otherwise)
      call a:callback(a:status == 0)
    endfunction
    
    " Execute command asynchronously
    let l:job_id = plugin_manager#async#system(l:cmd, function('s:on_repo_check_complete'))
    return l:job_id
  else
    " Synchronous fallback
    let l:exists = plugin_manager#utils#repository_exists(a:url)
    call a:callback(l:exists)
    return 0
  endif
endfunction

" Parse .gitmodules and return a dictionary of plugins
" Synchronous version
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

" Asynchronous version with callback 
function! plugin_manager#utils#parse_gitmodules_async(callback)
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
  
  " For sync-only environments
  if !plugin_manager#async#has_async() || !g:plugin_manager_use_async
    let l:modules = plugin_manager#utils#parse_gitmodules()
    call a:callback(l:modules)
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
  
  let l:task_id = plugin_manager#tasks#create(s:TYPE_SINGLE, l:task_options)
  call plugin_manager#tasks#start(l:task_id)
  
  return l:task_id
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

" Then try partial matches with case insensitivity
for [l:name, l:module] in items(l:modules)
  " Module name, path or short_name contains query
  if l:name =~? a:query || 
        \ (has_key(l:module, 'path') && l:module.path =~? a:query) ||
        \ (has_key(l:module, 'short_name') && l:module.short_name =~? a:query)
    return {'name': l:name, 'module': l:module}
  endif
endfor

" No match found
return {}
endfunction

" Asynchronous version with callback
function! plugin_manager#utils#find_module_async(query, callback)
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

return plugin_manager#utils#parse_gitmodules_async(function('s:on_parse_complete'))
endfunction

" Force refresh the gitmodules cache
function! plugin_manager#utils#refresh_modules_cache()
let g:pm_gitmodules_mtime = 0
return plugin_manager#utils#parse_gitmodules()
endfunction

" Force refresh the gitmodules cache asynchronously
function! plugin_manager#utils#refresh_modules_cache_async(callback)
let g:pm_gitmodules_mtime = 0
return plugin_manager#utils#parse_gitmodules_async(a:callback)
endfunction

" Check module update status
" Synchronous version
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

" Asynchronous version with callback
function! plugin_manager#utils#check_module_updates_async(module_path, callback)
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
  
  " Since we need to execute multiple commands, create a sequence of commands
  " Each command returns the necessary info and is tagged so we can parse it in the success callback
  
  " 1. Current commit
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

" For sync-only environments
if !plugin_manager#async#has_async() || !g:plugin_manager_use_async
  let l:result = plugin_manager#utils#check_module_updates(a:module_path)
  call a:callback(l:result)
  return 0
endif

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
  if l:line =~ '^\s*' || l:line =~ '^\s*"'
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

" Process plugins - now asynchronously if possible
if plugin_manager#async#has_async() && g:plugin_manager_use_async
  call s:process_plugins_async(l:plugins_to_install)
else
  call s:process_plugins_sync(l:plugins_to_install)
endif
endfunction

" Process plugins synchronously
function! s:process_plugins_sync(plugins_to_install)
" Install plugins
call plugin_manager#ui#update_sidebar(['Found ' . len(a:plugins_to_install) . ' plugins to install...'], 1)

for l:plugin in a:plugins_to_install
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