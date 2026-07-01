" autoload/plugin_manager/git.vim - Git operations abstraction for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.6.0

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
    " Strip CR so CRLF line endings (files edited on Windows) are handled cleanly
    let l:line = substitute(l:line, '\r$', '', '')
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

" Find a module by name, path, or short name.
"
" @param query   String to match against module name, path, or short_name.
" @param ...     Optional flag: pass 1 as the second argument to enable strict
"                mode. In strict mode a partial match that resolves to more than
"                one module throws AMBIGUOUS_MATCH instead of silently returning
"                the first hit. Exact matches always succeed regardless of the
"                flag. Default (0) preserves the historical first-hit behaviour.
function! plugin_manager#git#find_module(query, ...) abort
  let l:strict  = a:0 > 0 ? a:1 : 0
  let l:modules = plugin_manager#git#parse_modules()

  " Direct module name lookup - O(1) operation, keep this first
  if has_key(l:modules, a:query)
    return {'name': a:query, 'module': l:modules[a:query]}
  endif

  let l:exact_match  = {}
  let l:partials     = []   " list of {name, module} dicts for partial hits

  for [l:name, l:module] in items(l:modules)
    " Exact path match - unambiguous, return immediately
    if has_key(l:module, 'path') && l:module.path ==# a:query
      return {'name': l:name, 'module': l:module}
    endif

    " Exact short_name match - unambiguous, return immediately
    if has_key(l:module, 'short_name') && l:module.short_name ==# a:query
      return {'name': l:name, 'module': l:module}
    endif

    " Collect partial matches for post-loop analysis
    if l:name =~? a:query ||
          \ (has_key(l:module, 'path')       && l:module.path       =~? a:query) ||
          \ (has_key(l:module, 'short_name') && l:module.short_name =~? a:query)
      call add(l:partials, {'name': l:name, 'module': l:module})
    endif
  endfor

  " Strict mode: refuse ambiguous partial matches
  if l:strict && len(l:partials) > 1
    let l:names = join(map(copy(l:partials),
          \ {_, e -> get(e.module, 'short_name', e.name)}), ', ')
    call plugin_manager#core#throw('git', 'AMBIGUOUS_MATCH',
          \ 'Ambiguous name "' . a:query . '" matches multiple plugins: ' .
          \ l:names . '. Use the exact plugin name.')
  endif

  " Return first (or only) partial match; empty dict when nothing found
  return empty(l:partials) ? {} : l:partials[0]
endfunction

" Canonical: check if a plugin path or short_name is already managed as a
" submodule (declared in .gitmodules OR with a directory on disk). Returns 1
" if found, 0 otherwise. This is the SINGLE source of truth shared by add#exists,
" add_submodule, and any other detection site.
function! plugin_manager#git#submodule_exists(plugin_path_or_name) abort
  let l:modules = plugin_manager#git#parse_modules()
  if empty(l:modules)
    return 0
  endif

  let l:search = plugin_manager#core#normalize_path(a:plugin_path_or_name)
  let l:short = fnamemodify(l:search, ':t')
  " Determine whether the caller supplied a bare name (no separators) or a
  " fuller identifier (org/repo, URL, path). Bare names may match by
  " short_name; fuller identifiers must also match the URL or full path to
  " avoid cross-organisation collisions (e.g. orgA/vim-foo vs orgB/vim-foo).
  let l:is_bare_name = (l:search ==# l:short)

  for [l:name, l:mod] in items(l:modules)
    let l:mod_path  = get(l:mod, 'path', '')
    let l:mod_short = get(l:mod, 'short_name', '')
    let l:mod_url   = get(l:mod, 'url', '')

    " Exact URL match - always unambiguous
    if !empty(l:mod_url) && l:mod_url ==# a:plugin_path_or_name
      return 1
    endif

    " Match by short_name only when the search is a bare name (no org/path
    " component), to prevent orgA/vim-foo matching orgB/vim-foo.
    if l:is_bare_name && !empty(l:mod_short) && l:mod_short ==# l:short
      return 1
    endif
    if l:is_bare_name && !empty(l:mod_short) && l:mod_short ==# l:search
      return 1
    endif

    " Match by normalized path
    let l:norm_mod_path = !empty(l:mod_path)
          \ ? plugin_manager#core#normalize_path(l:mod_path)
          \ : ''
    if !empty(l:norm_mod_path) && (l:norm_mod_path ==# l:search
          \ || l:norm_mod_path ==# l:short)
      return 1
    endif

    " Try absolute-vs-relative normalisation: strip vim_dir prefix from search
    " or add it to the module path, so an absolute install_dir matches a
    " relative entry in .gitmodules.
    let l:vim_dir = plugin_manager#core#get_config('vim_dir', '')
    if !empty(l:vim_dir) && !empty(l:norm_mod_path)
      let l:vim_dir_norm = plugin_manager#core#normalize_path(l:vim_dir)
      let l:abs_mod_path = l:vim_dir_norm . '/' . l:norm_mod_path
      if l:abs_mod_path ==# l:search
        return 1
      endif
      let l:rel_search = substitute(l:search, '^' . escape(l:vim_dir_norm, '/.\') . '/', '', '')
      if l:rel_search ==# l:norm_mod_path
        return 1
      endif
    endif
  endfor

  return 0
endfunction

" Strip the 'origin/' prefix from a remote branch name, e.g.
" 'origin/master' -> 'master'. Idempotent: 'master' -> 'master'.
function! plugin_manager#git#remote_branch_name(remote_branch) abort
  return substitute(a:remote_branch, '^origin/', '', '')
endfunction

" Return the current HEAD commit SHA for a repository, or '' on failure.
function! plugin_manager#git#head_commit(path) abort
  let l:res = plugin_manager#git#execute('git rev-parse HEAD', a:path, 0, 0)
  if !l:res.success
    return ''
  endif
  return substitute(l:res.output, '\n', '', 'g')
endfunction

" Return 1 if HEAD at a:path has moved past a:before (non-empty SHAs, differ).
function! plugin_manager#git#head_changed(path, before) abort
  if empty(a:before)
    return 0
  endif
  let l:after = plugin_manager#git#head_commit(a:path)
  return !empty(l:after) && l:after !=# a:before
endfunction

" ------------------------------------------------------------------------------
" GIT COMMAND EXECUTION
" ------------------------------------------------------------------------------

" Execute a git command with proper error handling
function! plugin_manager#git#execute(cmd, dir, ...) abort
  let l:output_to_ui = get(a:, 1, 0)
  let l:throw_on_error = get(a:, 2, 1)
  
  " Handle directory change if needed (shellescape for consistent quoting)
  let l:full_cmd = empty(a:dir) ? a:cmd : 'cd ' . shellescape(a:dir) . ' && ' . a:cmd
  
  " Trace the command to the debug log if enabled
  if get(g:, 'plugin_manager_trace_commands', 0)
    call plugin_manager#core#log_trace('git', 'exec: ' . l:full_cmd)
  endif
  
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


" ------------------------------------------------------------------------------
" REPOSITORY STATUS AND CHECKS
" ------------------------------------------------------------------------------

" Check if a repository exists
function! plugin_manager#git#repository_exists(url) abort
  " Use git ls-remote to check if the repository exists.
  " system() captures stdout/stderr; we only need the exit code.
  let l:cmd = 'git ls-remote --exit-code ' . shellescape(a:url) . ' HEAD'
  let l:result = plugin_manager#git#execute(l:cmd, '', 0, 0)
  return l:result.success
endfunction

" Check module update status (synchronous: fetches then collects).
" Kept for the no-async fallback and for tests. Prefer the async flow
" (fetch as a job, then collect_status_local) for non-blocking operations.
function! plugin_manager#git#check_updates(module_path) abort
  if !isdirectory(a:module_path)
    return s:empty_status()
  endif
  " Blocking network fetch, then fast local analysis
  call plugin_manager#git#execute('git fetch origin --all', a:module_path, 0, 0)
  return plugin_manager#git#collect_status_local(a:module_path)
endfunction

" Return an empty status dict
function! s:empty_status() abort
  return {
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
endfunction

" Collect module status using only fast, local git commands (no network).
" Call this AFTER a fetch (done synchronously or as an async job) so the
" remote-tracking refs are up to date.
function! plugin_manager#git#collect_status_local(module_path) abort
  let l:result = s:empty_status()
  
  " Check if the directory exists
  if !isdirectory(a:module_path)
    return l:result
  endif
  
  " Get current commit hash (more reliable for submodules than branch)
  let l:result.current_commit = plugin_manager#git#head_commit(a:module_path)
  
  " Get current symbolic ref - might be a branch or HEAD
  let l:res = plugin_manager#git#execute('git symbolic-ref --short HEAD', a:module_path, 0, 0)
  if l:res.success
    let l:result.branch = substitute(l:res.output, '\n', '', 'g')
  else
    let l:result.branch = 'detached'
  endif
  
  " First try to find remote branch from .gitmodules at the vim config root.
  " Use the relative path as the submodule section key (not just the basename).
  let l:vim_dir = plugin_manager#core#get_config('vim_dir', '')
  let l:gitmodules_path = l:vim_dir . '/.gitmodules'
  let l:rel_path = plugin_manager#core#make_relative_path(a:module_path)
  let l:res = plugin_manager#git#execute(
        \ 'git config -f ' . shellescape(l:gitmodules_path) .
        \ ' submodule.' . shellescape(l:rel_path) . '.branch',
        \ '', 0, 0)
  let l:remote_branch = l:res.success ? substitute(l:res.output, '\n', '', 'g') : ''
  
  " If not found in .gitmodules, try to determine from the current branch's upstream
  if empty(l:remote_branch) && l:result.branch !=# 'detached'
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
  
  " Ask the remote for its default HEAD branch
  if empty(l:remote_branch)
    let l:res = plugin_manager#git#execute(
          \ 'git rev-parse --abbrev-ref origin/HEAD', a:module_path, 0, 0)
    if l:res.success
      let l:remote_branch = substitute(l:res.output, '\n', '', 'g')
    endif
  endif

  " Last resort: try origin/<current-local-branch> when all else fails
  if empty(l:remote_branch) && l:result.branch !=# 'detached' && !empty(l:result.branch)
    let l:candidate = 'origin/' . l:result.branch
    let l:res = plugin_manager#git#execute(
          \ 'git show-ref --verify --quiet refs/remotes/' . l:candidate,
          \ a:module_path, 0, 0)
    if l:res.success
      let l:remote_branch = l:candidate
    endif
  endif

  " If no remote branch found at all, leave empty so rev-parse fails gracefully
  " rather than targeting a nonexistent branch
  
  let l:result.remote_branch = l:remote_branch

  " Get the latest commit on the remote branch (skip if branch unknown)
  if !empty(l:remote_branch)
    let l:res = plugin_manager#git#execute('git rev-parse ' . shellescape(l:result.remote_branch),
          \ a:module_path, 0, 0)
    if l:res.success
      let l:result.remote_commit = substitute(l:res.output, '\n', '', 'g')
    endif
  endif
  
  " Direct check if remote commit is different from current commit
  if l:result.current_commit != 'N/A' && l:result.remote_commit != 'N/A' && 
        \ l:result.current_commit != l:result.remote_commit
    
    " Count commits ahead/behind
    let l:res = plugin_manager#git#execute('git rev-list --count HEAD..' . shellescape(l:result.remote_branch),
          \ a:module_path, 0, 0)
    if l:res.success
      let l:behind = substitute(l:res.output, '\n', '', 'g')
      if l:behind =~ '^\d\+$'
        let l:result.behind = str2nr(l:behind)
      endif
    endif
    
    let l:res = plugin_manager#git#execute('git rev-list --count ' . shellescape(l:result.remote_branch) . '..HEAD',
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
  if l:result.branch !=# 'detached' && l:result.branch !=# l:remote_branch_name
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
  call plugin_manager#core#require_vim_directory('git')
  
  " Get relative install path
  let l:relative_path = plugin_manager#core#make_relative_path(a:install_dir)
  
  " Create parent directory if needed
  let l:parent_dir = fnamemodify(a:install_dir, ':h')
  call plugin_manager#core#ensure_directory(l:parent_dir)
  
  " Check if submodule already exists (canonical detection, handles both
  " relative and absolute paths as well as short_name matching)
  if plugin_manager#git#submodule_exists(a:install_dir)
    " Standardized error handling
    call plugin_manager#core#throw('git', 'SUBMODULE_EXISTS', 'Submodule already exists at this location: ' . l:relative_path)
  endif
  
  " Add the submodule
  let l:cmd = 'git submodule add'
  
  " Add branch option if specified
  if !empty(a:options.branch)
    let l:cmd .= ' -b ' . shellescape(a:options.branch)
  endif
  
  " Add URL and path
  let l:cmd .= ' ' . shellescape(a:url) . ' ' . shellescape(l:relative_path)
  
  " Execute the command
  let l:result = plugin_manager#git#execute(l:cmd, '', 1, 1)
  
  " Process version options (branch or tag) if needed
  if !empty(a:options.tag) && empty(a:options.branch)
    call s:checkout_version(l:relative_path, a:options.tag)
  endif
  
  " Execute post-install command if provided
  if !empty(a:options.exec)
    let l:exec_result = plugin_manager#git#execute(a:options.exec, l:relative_path, 1, 0)
    if !l:exec_result.success
      " Standardized error handling 
      call plugin_manager#core#throw('git', 'COMMAND_FAILED', 'Post-install command failed: ' . a:options.exec)
    endif
  endif
  
  " Commit changes
  let l:commit_msg = 'Add ' . a:url . ' plugin'
  if !empty(a:options.branch)
    let l:commit_msg .= ' (branch: ' . a:options.branch . ')'
  elseif !empty(a:options.tag)
    let l:commit_msg .= ' (tag: ' . a:options.tag . ')'
  endif
  
  call plugin_manager#git#execute('git commit -m ' . shellescape(l:commit_msg), '', 1, 0)
  
  return l:result.success
endfunction


" Update a specific git submodule
function! plugin_manager#git#update_submodule(module_path) abort
  call plugin_manager#core#require_vim_directory('git')
  
  " Check if directory exists
  if !isdirectory(a:module_path)
    " Standardized error handling
    call plugin_manager#core#throw('git', 'PATH_NOT_FOUND', 'Module directory not found: ' . a:module_path)
  endif
  
  " Enter the module directory and fetch updates
  call plugin_manager#git#execute('git fetch origin', a:module_path, 1, 0)
  
  " Get update status
  let l:update_status = plugin_manager#git#check_updates(a:module_path)
  
  " Skip if already up to date
  if !l:update_status.has_updates
    return {'success': 1, 'changed': 0, 'message': 'Already up-to-date'}
  endif
  
  " Capture HEAD before update
  let l:before_commit = l:update_status.current_commit
  
  " Build pull command with stripped branch name (remove origin/ prefix)
  let l:branch = plugin_manager#git#remote_branch_name(l:update_status.remote_branch)
  let l:pull_flag = plugin_manager#core#get_pull_flag()
  let l:result = plugin_manager#git#execute('git pull origin ' . shellescape(l:branch) . ' ' . l:pull_flag,
        \ a:module_path, 1, 1)
  
  " Handle error
  if !l:result.success
    " Standardized error handling
    call plugin_manager#core#throw('update', 'UPDATE_FAILED', 'Failed to update module ' . a:module_path . ': ' . l:result.output)
  endif
  
  " Compare HEAD after pull to determine if anything actually changed
  let l:changed = plugin_manager#git#head_changed(a:module_path, l:before_commit)

  return {'success': 1, 'changed': l:changed, 'message': l:changed ? 'Updated' : 'Already up-to-date'}
endfunction


" Add a remote repository
function! plugin_manager#git#add_remote(url, name) abort
  call plugin_manager#core#require_vim_directory('git')
  
  " Check if the repository exists
  if !plugin_manager#git#repository_exists(a:url)
    " Standardized error handling
    call plugin_manager#core#throw('remote', 'REPO_NOT_FOUND', 'Repository not found: ' . a:url)
  endif
  
  " Generate remote name if not provided
  let l:remote_name = empty(a:name) ? 'origin' : a:name
  
  " Check if remote already exists
  let l:remotes = plugin_manager#git#execute('git remote', '', 0, 0)
  let l:remote_exists = 0
  
  for l:remote in split(l:remotes.output, "\n")
    if l:remote ==# l:remote_name
      let l:remote_exists = 1
      break
    endif
  endfor
  
  if l:remote_exists
    " Set URL for existing remote
    let l:result = plugin_manager#git#execute('git remote set-url ' . l:remote_name . ' ' . shellescape(a:url), '', 1, 1)
    
    " Add push URL
    call plugin_manager#git#execute('git remote set-url --add --push ' . l:remote_name . ' ' . shellescape(a:url), '', 0, 0)
  else
    " Add new remote
    let l:result = plugin_manager#git#execute('git remote add ' . l:remote_name . ' ' . shellescape(a:url), '', 1, 1)
  endif
  
  " Handle error
  if !l:result.success
    " Standardized error handling
    call plugin_manager#core#throw('remote', 'ADD_FAILED', 'Failed to add remote repository: ' . l:result.output)
  endif
  
  return l:result.success
endfunction

" ------------------------------------------------------------------------------
" PRIVATE HELPER FUNCTIONS
" ------------------------------------------------------------------------------

" Helper function to checkout a specific version
function! s:checkout_version(module_path, version) abort
  return plugin_manager#git#execute('git checkout ' . shellescape(a:version), a:module_path, 1, 0)
endfunction