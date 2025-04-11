" autoload/plugin_manager/git.vim - Git operations abstraction for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3.4

" ------------------------------------------------------------------------------
" GITMODULES CACHE AND PARSING
" ------------------------------------------------------------------------------

" Module cache
let s:gitmodules_cache = {}
let s:gitmodules_mtime = 0

" Parse .gitmodules and return a dictionary of plugins
function! plugin_manager#git#parse_modules() abort
  " Check if we're in the right directory
  if !plugin_manager#core#ensure_vim_directory()
    return {}
  endif
  
  " Check if .gitmodules exists
  if !filereadable('.gitmodules')
    let s:gitmodules_cache = {}
    let s:gitmodules_mtime = 0
    return s:gitmodules_cache
  endif
  
  " Check if file has been modified since last parse
  let l:mtime = getftime('.gitmodules')
  if !empty(s:gitmodules_cache) && l:mtime == s:gitmodules_mtime
    return s:gitmodules_cache
  endif
  
  " Reset cache
  let s:gitmodules_cache = {}
  let s:gitmodules_mtime = l:mtime
  
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
      let s:gitmodules_cache[l:current_module] = {'name': l:current_module}
    " Inside module section
    elseif l:in_module && !empty(l:current_module)
      " Path property
      if l:line =~ '\s*path\s*='
        let l:path = substitute(l:line, '\s*path\s*=\s*', '', '')
        let l:path = substitute(l:path, '^\s*\(.\{-}\)\s*$', '\1', '')  " Trim whitespace
        let s:gitmodules_cache[l:current_module]['path'] = l:path
        " Extract short name from path (last component)
        let s:gitmodules_cache[l:current_module]['short_name'] = fnamemodify(l:path, ':t')
      " URL property
      elseif l:line =~ '\s*url\s*='
        let l:url = substitute(l:line, '\s*url\s*=\s*', '', '')
        let l:url = substitute(l:url, '^\s*\(.\{-}\)\s*$', '\1', '')  " Trim whitespace
        let s:gitmodules_cache[l:current_module]['url'] = l:url
      " Branch property
      elseif l:line =~ '\s*branch\s*='
        let l:branch = substitute(l:line, '\s*branch\s*=\s*', '', '')
        let l:branch = substitute(l:branch, '^\s*\(.\{-}\)\s*$', '\1', '')  " Trim whitespace
        let s:gitmodules_cache[l:current_module]['branch'] = l:branch
      " New section starts - reset current module
      elseif l:line =~ '\['
        let l:in_module = 0
        let l:current_module = ''
      endif
    endif
  endfor
  
  " Validate the modules: each should have both path and url
  for [l:name, l:module] in items(s:gitmodules_cache)
    if !has_key(l:module, 'path') || !has_key(l:module, 'url')
      " Mark invalid modules but don't remove them
      let s:gitmodules_cache[l:name]['is_valid'] = 0
    else
      let s:gitmodules_cache[l:name]['is_valid'] = 1
      
      " Check if the plugin directory exists
      let s:gitmodules_cache[l:name]['exists'] = isdirectory(l:module.path)
    endif
  endfor
  
  return s:gitmodules_cache
endfunction

" Force refresh the gitmodules cache
function! plugin_manager#git#refresh_modules_cache() abort
  let s:gitmodules_mtime = 0
  return plugin_manager#git#parse_modules()
endfunction

" Find a module by name, path, or short name
function! plugin_manager#git#find_module(query) abort
  let l:modules = plugin_manager#git#parse_modules()
  
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

" ------------------------------------------------------------------------------
" GIT COMMAND EXECUTION
" ------------------------------------------------------------------------------

" Execute a git command with proper error handling
function! plugin_manager#git#execute(cmd, dir, ...) abort
  let l:output_to_ui = get(a:, 1, 0)
  let l:throw_on_error = get(a:, 2, 1)
  
  " Handle directory change if needed
  let l:full_cmd = empty(a:dir) ? a:cmd : 'cd "' . a:dir . '" && ' . a:cmd
  
  if l:output_to_ui && exists('*plugin_manager#ui#update_sidebar')
    call plugin_manager#ui#update_sidebar(['Executing: ' . a:cmd], 1)
  endif
  
  let l:output = system(l:full_cmd)
  let l:success = v:shell_error == 0
  
  if l:output_to_ui && exists('*plugin_manager#ui#update_sidebar')
    call plugin_manager#ui#update_sidebar(['Command ' . (l:success ? 'succeeded' : 'failed') . ':'], 1)
    if !empty(l:output)
      call plugin_manager#ui#update_sidebar(split(l:output, '\n'), 1)
    endif
  endif
  
  if !l:success && l:throw_on_error
    " Standardized error handling
    call plugin_manager#core#throw('git', 'COMMAND_FAILED', 'Command failed: ' . a:cmd . ' - ' . l:output)
  endif
  
  return {'success': l:success, 'output': l:output}
endfunction

" Execute a git command asynchronously if supported
function! plugin_manager#git#execute_async(cmd, dir, callback) abort
  " Check if async is available and loaded
  if exists('*plugin_manager#async#start_job')
    return plugin_manager#async#start_job(a:cmd, {'dir': a:dir, 'callback': a:callback})
  else
    " Fall back to synchronous execution
    let l:result = plugin_manager#git#execute(a:cmd, a:dir, 0, 0)
    call a:callback(l:result)
    return -1  " No job ID for sync execution
  endif
endfunction

" ------------------------------------------------------------------------------
" REPOSITORY STATUS AND CHECKS
" ------------------------------------------------------------------------------

" Check if a repository exists
function! plugin_manager#git#repository_exists(url) abort
  " Use git ls-remote to check if the repository exists
  let l:cmd = 'git ls-remote --exit-code "' . a:url . '" HEAD > /dev/null 2>&1'
  let l:result = plugin_manager#git#execute(l:cmd, '', 0, 0)
  return l:result.success
endfunction

" Check module update status
function! plugin_manager#git#check_updates(module_path) abort
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
  let l:res = plugin_manager#git#execute('git rev-parse HEAD', a:module_path, 0, 0)
  if l:res.success
    let l:result.current_commit = substitute(l:res.output, '\n', '', 'g')
  endif
  
  " Get current symbolic ref - might be a branch or HEAD
  let l:res = plugin_manager#git#execute('git symbolic-ref --short HEAD', a:module_path, 0, 0)
  if l:res.success
    let l:result.branch = substitute(l:res.output, '\n', '', 'g')
  else
    let l:result.branch = 'detached'
  endif
  
  " Fetch updates from remote repository more aggressively
  call plugin_manager#git#execute('git fetch origin --all', a:module_path, 0, 0)
  
  " First try to find remote branch from .gitmodules
  let l:res = plugin_manager#git#execute('git config -f ../.gitmodules submodule.' . 
        \ fnamemodify(a:module_path, ':t') . '.branch', a:module_path, 0, 0)
  let l:remote_branch = l:res.success ? substitute(l:res.output, '\n', '', 'g') : ''
  
  " If not found in .gitmodules, try to determine from the current branch's upstream
  if empty(l:remote_branch) && l:result.branch != 'detached'
    let l:res = plugin_manager#git#execute('git rev-parse --abbrev-ref ' . 
          \ l:result.branch . '@{upstream}', a:module_path, 0, 0)
    if l:res.success
      let l:remote_branch = substitute(l:res.output, '\n', '', 'g')
      " If upstream exists but doesn't include 'origin/', prepend it
      if !empty(l:remote_branch) && l:remote_branch !~ '^origin/'
        let l:remote_branch = 'origin/' . l:remote_branch
      endif
    endif
  endif
  
  " If still not found, try to determine from standard branches
  if empty(l:remote_branch)
    " Check if origin/main exists
    let l:res = plugin_manager#git#execute('git show-ref --verify --quiet refs/remotes/origin/main', 
          \ a:module_path, 0, 0)
    if l:res.success
      let l:remote_branch = 'origin/main'
    else
      " Check if origin/master exists
      let l:res = plugin_manager#git#execute('git show-ref --verify --quiet refs/remotes/origin/master', 
          \ a:module_path, 0, 0)
      if l:res.success
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
  let l:res = plugin_manager#git#execute('git rev-parse ' . l:result.remote_branch, 
        \ a:module_path, 0, 0)
  if l:res.success
    let l:result.remote_commit = substitute(l:res.output, '\n', '', 'g')
  endif
  
  " Direct check if remote commit is different from current commit
  if l:result.current_commit != 'N/A' && l:result.remote_commit != 'N/A' && 
        \ l:result.current_commit != l:result.remote_commit
    
    " Count commits ahead/behind
    let l:res = plugin_manager#git#execute('git rev-list --count HEAD..' . l:result.remote_branch, 
          \ a:module_path, 0, 0)
    if l:res.success
      let l:behind = substitute(l:res.output, '\n', '', 'g')
      if l:behind =~ '^\d\+$'
        let l:result.behind = str2nr(l:behind)
      endif
    endif
    
    let l:res = plugin_manager#git#execute('git rev-list --count ' . l:result.remote_branch . '..HEAD', 
          \ a:module_path, 0, 0)
    if l:res.success
      let l:ahead = substitute(l:res.output, '\n', '', 'g')
      if l:ahead =~ '^\d\+$'
        let l:result.ahead = str2nr(l:ahead)
      endif
    endif
    
    " Force has_updates flag if the current and remote commits are different
    let l:result.has_updates = (l:result.behind > 0 || l:result.current_commit != l:result.remote_commit)
  endif
  
  " For submodules, we primarily care about commit differences, not branch names
  " If current branch is not detached and doesn't match remote branch name, note this
  let l:remote_branch_name = substitute(l:result.remote_branch, '^origin/', '', '')
  if l:result.branch != 'detached' && l:result.branch != l:remote_branch_name
    let l:result.different_branch = 1
  endif
  
  " Check for local changes while ignoring helptags files
  let l:res = plugin_manager#git#execute('git status -s -- . ":(exclude)doc/tags" ":(exclude)**/tags"', 
        \ a:module_path, 0, 0)
  let l:result.has_changes = !empty(l:res.output)
  
  return l:result
endfunction

" ------------------------------------------------------------------------------
" SUBMODULE OPERATIONS
" ------------------------------------------------------------------------------

" Add a git submodule
function! plugin_manager#git#add_submodule(url, install_dir, options) abort
  " Ensure we're in the vim directory
  if !plugin_manager#core#ensure_vim_directory()
    " Standardized error handling
    call plugin_manager#core#throw('git', 'NOT_VIM_DIR', 'Not in Vim configuration directory')
  endif
  
  " Get relative install path
  let l:relative_path = plugin_manager#core#make_relative_path(a:install_dir)
  
  " Create parent directory if needed
  let l:parent_dir = fnamemodify(a:install_dir, ':h')
  call plugin_manager#core#ensure_directory(l:parent_dir)
  
  " Check if submodule already exists
  let l:gitmodule_check = plugin_manager#git#execute('grep -c "' . l:relative_path . '" .gitmodules', '', 0, 0)
  if !empty(l:gitmodule_check.output) && l:gitmodule_check.output != '0'
    " Standardized error handling
    call plugin_manager#core#throw('git', 'SUBMODULE_EXISTS', 'Submodule already exists at this location: ' . l:relative_path)
  endif
  
  " Rest of the function remains the same...
endfunction

" Remove a git submodule
function! plugin_manager#git#remove_submodule(module_path) abort
  " Ensure we're in the vim directory
  if !plugin_manager#core#ensure_vim_directory()
    " Standardized error handling
    call plugin_manager#core#throw('git', 'NOT_VIM_DIR', 'Not in Vim configuration directory')
  endif
  
  " Rest of the function remains the same...
endfunction

" Update all git submodules
function! plugin_manager#git#update_all_submodules() abort
  " Ensure we're in the vim directory
  if !plugin_manager#core#ensure_vim_directory()
    " Standardized error handling
    call plugin_manager#core#throw('git', 'NOT_VIM_DIR', 'Not in Vim configuration directory')
  endif
  
  " Rest of the function remains the same...
endfunction

" Update a specific git submodule
function! plugin_manager#git#update_submodule(module_path) abort
  " Ensure we're in the vim directory
  if !plugin_manager#core#ensure_vim_directory()
    " Standardized error handling
    call plugin_manager#core#throw('git', 'NOT_VIM_DIR', 'Not in Vim configuration directory')
  endif
  
  " Check if directory exists
  if !isdirectory(a:module_path)
    " Standardized error handling
    call plugin_manager#core#throw('git', 'PATH_NOT_FOUND', 'Module directory not found: ' . a:module_path)
  endif
  
  " Rest of the function remains the same...
endfunction

" Restore all submodules from .gitmodules
function! plugin_manager#git#restore_all_submodules() abort
  " Ensure we're in the vim directory
  if !plugin_manager#core#ensure_vim_directory()
    " Standardized error handling
    call plugin_manager#core#throw('git', 'NOT_VIM_DIR', 'Not in Vim configuration directory')
  endif
  
  " Check if .gitmodules exists
  if !filereadable('.gitmodules')
    " Standardized error handling
    call plugin_manager#core#throw('restore', 'GITMODULES_NOT_FOUND', '.gitmodules file not found')
  endif
  
  " Rest of the function remains the same...
endfunction

" Backup configuration to remote repositories
function! plugin_manager#git#backup_config() abort
  " Ensure we're in the vim directory
  if !plugin_manager#core#ensure_vim_directory()
    " Standardized error handling
    call plugin_manager#core#throw('git', 'NOT_VIM_DIR', 'Not in Vim configuration directory')
  endif
  
  " Check if there are changes to commit
  let l:status = plugin_manager#git#execute('git status -s', '', 0, 0)
  
  if !empty(l:status.output)
    call plugin_manager#git#execute('git commit -am "Automatic backup"', '', 1, 0)
  endif
  
  " Check if any remotes exist
  let l:remotes = plugin_manager#git#execute('git remote', '', 0, 0)
  if empty(l:remotes.output)
    " Standardized error handling
    call plugin_manager#core#throw('backup', 'NO_REMOTES', 'No remote repositories configured.')
  endif
  
  " Rest of the function remains the same...
endfunction

" Add a remote repository
function! plugin_manager#git#add_remote(url, name) abort
  " Ensure we're in the vim directory
  if !plugin_manager#core#ensure_vim_directory()
    " Standardized error handling
    call plugin_manager#core#throw('git', 'NOT_VIM_DIR', 'Not in Vim configuration directory')
  endif
  
  " Check if the repository exists
  if !plugin_manager#git#repository_exists(a:url)
    " Standardized error handling
    call plugin_manager#core#throw('remote', 'REPO_NOT_FOUND', 'Repository not found: ' . a:url)
  endif
  
  " Rest of the function remains the same...
endfunction

" ------------------------------------------------------------------------------
" PRIVATE HELPER FUNCTIONS
" ------------------------------------------------------------------------------

" Helper function to checkout a specific version
function! s:checkout_version(module_path, version) abort
  return plugin_manager#git#execute('git checkout ' . shellescape(a:version), a:module_path, 1, 0)
endfunction