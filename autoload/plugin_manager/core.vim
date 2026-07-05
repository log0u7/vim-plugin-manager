" autoload/plugin_manager/core.vim - Error handling foundation for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>

" ------------------------------------------------------------------------------
" ERROR HANDLING SYSTEM
" ------------------------------------------------------------------------------

let s:error_types = {
    \ 'add': ['INVALID_URL', 'REPO_NOT_FOUND', 'TARGET_EXISTS', 'COPY_FAILED', 'MISSING_ARGS', 'INVALID_ARGS', 'INSTALLATION_FAILED', 'LOCAL_PATH_NOT_FOUND'],
    \ 'remove': ['MODULE_NOT_FOUND', 'DELETE_FAILED', 'CONFIRMATION_REQUIRED', 'MISSING_ARGS', 'NOT_VIM_DIR', 'AMBIGUOUS_MATCH'],
    \ 'update': ['MODULE_NOT_FOUND', 'FETCH_FAILED', 'UPDATE_FAILED', 'NO_PLUGINS', 'NOT_VIM_DIR', 'NOT_GIT_REPO', 'PATH_NOT_FOUND', 'AMBIGUOUS_MATCH'],
    \ 'backup': ['GIT_ERROR', 'NO_REMOTES', 'NOT_VIM_DIR', 'VIMRC_NOT_FOUND', 'COMMIT_FAILED'],
    \ 'restore': ['GITMODULES_NOT_FOUND', 'INIT_FAILED', 'NOT_VIM_DIR', 'UPDATE_FAILED'],
    \ 'git': ['COMMAND_FAILED', 'REPO_NOT_FOUND', 'MERGE_CONFLICT', 'NOT_VIM_DIR', 'SUBMODULE_EXISTS', 'PATH_NOT_FOUND', 'MODULE_NOT_FOUND', 'AMBIGUOUS_MATCH'],
    \ 'core': ['NOT_VIM_DIR', 'NOT_GIT_REPO', 'PATH_NOT_FOUND', 'PERMISSION_DENIED', 'CONFIG_ERROR', 'INVALID_PATH'],
    \ 'async': ['JOB_FAILED', 'TIMEOUT', 'NOT_SUPPORTED', 'INVALID_JOB_ID'],
    \ 'ui': ['RENDER_FAILED', 'BUFFER_ERROR', 'WINDOW_ERROR'],
    \ 'cmd': ['MISSING_ARGS', 'INVALID_COMMAND', 'EXECUTION_FAILED'],
    \ 'list': ['NO_PLUGINS', 'DISPLAY_ERROR', 'NOT_VIM_DIR'],
    \ 'helptags': ['DIRECTORY_NOT_FOUND', 'GENERATION_FAILED', 'NOT_VIM_DIR'],
    \ 'reload': ['MODULE_NOT_FOUND', 'NOT_VIM_DIR', 'SCRIPT_ERROR', 'AMBIGUOUS_MATCH'],
    \ 'status': ['NOT_VIM_DIR', 'NO_PLUGINS', 'MODULE_ERROR'],
    \ 'remote': ['INVALID_URL', 'REPO_NOT_FOUND', 'NOT_VIM_DIR', 'ADD_FAILED'],
    \ 'declare': ['NOT_VIM_DIR', 'INVALID_DECLARATION', 'BLOCK_ERROR'],
    \ 'check': ['NOT_VIM_DIR', 'NO_PLUGINS', 'FETCH_FAILED']
    \ }

" Create a standardized error with component and specific error code
function! plugin_manager#core#throw(component, error_code, message) abort
  if has_key(s:error_types, a:component) && index(s:error_types[a:component], a:error_code) == -1
    echohl WarningMsg
    echomsg 'Plugin Manager: Invalid error code ' . a:error_code . ' for component ' . a:component
    echohl None
    let l:error_code = 'UNKNOWN'
  else
    let l:error_code = a:error_code
  endif

  let l:error_string = 'PM_ERROR:' . a:component . ':' . l:error_code . ':' . a:message

  if get(g:, 'plugin_manager_enable_logging', 1)
    call plugin_manager#core#log_error_internal(l:error_string, a:component)
  endif

  throw l:error_string
endfunction

" Public internal logging bridge.  Parses the error string and delegates
" the actual file I/O to core#log#write().
function! plugin_manager#core#log_error_internal(error_string, component) abort
  let l:parsed = plugin_manager#core#parse_error(a:error_string)
  call plugin_manager#core#log#write(l:parsed)
endfunction

" Check whether a string is a structured plugin manager message
function! plugin_manager#core#is_pm_error(error) abort
  if type(a:error) != v:t_string
    return 0
  endif
  return a:error =~# '^PM_ERROR:' || a:error =~# '^DEBUG:' || a:error =~# '^TRACE:'
endfunction

" Parse a PM_ERROR:component:code:message string into a structured dict.
function! plugin_manager#core#parse_error(error) abort
  if !plugin_manager#core#is_pm_error(a:error)
    return {'type': 'external', 'component': 'vim', 'code': 'EXTERNAL', 'message': a:error}
  endif

  let l:m = matchlist(a:error, '^PM_ERROR:\([^:]*\):\([^:]*\):\(.*\)$')
  if empty(l:m)
    return {'type': 'external', 'component': 'vim', 'code': 'EXTERNAL', 'message': a:error}
  endif

  return {
  \ 'type': 'internal',
  \ 'component': l:m[1],
  \ 'code':      l:m[2],
  \ 'message':   l:m[3],
  \ }
endfunction

" Handle errors consistently throughout the plugin with better diagnostics
function! plugin_manager#core#handle_error(error, component) abort
  " Internal PM_ERRORs are already logged by core#throw when created.
  if get(g:, 'plugin_manager_enable_logging', 1)
    if !plugin_manager#core#is_pm_error(a:error)
      call plugin_manager#core#log_error_internal(a:error, a:component)
    endif
  endif

  let l:parsed = plugin_manager#core#parse_error(a:error)

  if l:parsed.type ==# 'internal'
    let l:title = 'Error in ' . l:parsed.component
    let l:message = l:parsed.message
    let l:tips = []

    if l:parsed.component ==# 'git' && l:parsed.code ==# 'COMMAND_FAILED'
      call add(l:tips, 'Make sure Git is installed and in your PATH')
      call add(l:tips, 'Verify you have permission to access the repository')
    elseif l:parsed.component ==# 'add' && l:parsed.code ==# 'REPO_NOT_FOUND'
      call add(l:tips, 'Check the repository URL for typos')
      call add(l:tips, 'Verify the repository exists and is publicly accessible')
    elseif l:parsed.component ==# 'core' && l:parsed.code ==# 'NOT_GIT_REPO'
      call add(l:tips, 'Initialize your Vim config as a Git repository first:')
      call add(l:tips, '  cd ' . plugin_manager#core#util#get_config('vim_dir', '~/.vim'))
      call add(l:tips, '  git init')
    endif
  else
    let l:title = 'Error in ' . a:component
    let l:message = 'Unexpected error: ' . l:parsed.message
    let l:tips = ['This may be a bug in the plugin. Consider reporting it.']
  endif

  if exists('*plugin_manager#ui#open_sidebar')
    let l:lines = [l:title, repeat('-', len(l:title)), '', l:message]

    if !empty(l:tips)
      call add(l:lines, '')
      call add(l:lines, 'Suggestions:')
      call extend(l:lines, map(l:tips, {idx, val -> '- ' . val}))
    endif

    if get(g:, 'plugin_manager_enable_logging', 1)
      let l:log_file = plugin_manager#core#log#get_path()
      call add(l:lines, '')
      call add(l:lines, 'Error logged to: ' . l:log_file)
      call add(l:lines, 'View logs with: :PluginManagerViewLog')
    endif

    call plugin_manager#ui#open_sidebar(l:lines)
  else
    echohl ErrorMsg
    echomsg l:message
    if !empty(l:tips)
      for l:tip in l:tips
        echomsg '- ' . l:tip
      endfor
    endif
    echohl None
  endif

  return l:message
endfunction
