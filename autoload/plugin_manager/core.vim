" autoload/plugin_manager/core.vim - Core utilities and error handling for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.6.0

" ------------------------------------------------------------------------------
" ERROR HANDLING SYSTEM
" ------------------------------------------------------------------------------

" Improved error types - comprehensive standard error codes for all components
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
  " Validate the error type if possible
  if has_key(s:error_types, a:component) && index(s:error_types[a:component], a:error_code) == -1
    " Invalid error code - create a special meta-error but don't crash
    echohl WarningMsg
    echomsg 'Plugin Manager: Invalid error code ' . a:error_code . ' for component ' . a:component
    echohl None
    let l:error_code = 'UNKNOWN'
  else
    let l:error_code = a:error_code
  endif

  " Create the formatted error message
  let l:error_string = 'PM_ERROR:' . a:component . ':' . l:error_code . ':' . a:message

  " Log the error before throwing it (only if logging is enabled)
  if get(g:, 'plugin_manager_enable_logging', 1)
    call s:log_error_internally(l:error_string, a:component)
  endif

  " Throw the formatted error
  throw l:error_string
endfunction

" Internal function to log errors before throwing them
" This avoids circular reference issues when called from plugin_manager#core#throw
function! s:log_error_internally(error_string, component) abort
  " Parse error first
  let l:parsed = plugin_manager#core#parse_error(a:error_string)

  " Get vim directory and verify it's not empty
  let l:vim_dir = plugin_manager#core#get_config('vim_dir', '')
  if empty(l:vim_dir)
    " Can't log without a valid vim directory
    return
  endif

  let l:log_dir = l:vim_dir . '/logs'
  let l:log_file = l:log_dir . '/plugin_manager.log'
  let l:timestamp = strftime('%Y-%m-%d %H:%M:%S')

  " Format the log entry
  let l:entry = l:timestamp . ' | ' .
  \ l:parsed.component . ' | ' .
  \ (l:parsed.type ==# 'internal' ? l:parsed.code : 'EXTERNAL') . ' | ' .
  \ l:parsed.message

  " Ensure log directory exists with proper error handling
  if !isdirectory(l:log_dir)
    try
      " Create directory with parent directories if needed
      call mkdir(l:log_dir, 'p')
    catch
      " Just silently continue if we can't create the log directory
      return
    endtry
  endif

  " Skip log rotation check if file doesn't exist yet
  if filereadable(l:log_file)
    " Check if log rotation is needed
    try
      call s:check_log_rotation(l:log_file)
    catch
      " Silently continue even if rotation fails
    endtry
  endif

  " Append to log file - use silent to prevent additional errors
  try
    " Try to append mode first
    call writefile([l:entry], l:log_file, 'a')
  catch
    " If append fails, try to create a new file as fallback
    try
      call writefile([l:entry], l:log_file)
    catch
      " Silent failure - we don't want to throw errors while handling errors
    endtry
  endtry
endfunction

" Check whether a string is a structured plugin manager message
" Recognizes error (PM_ERROR:) as well as DEBUG:/TRACE: log entries
function! plugin_manager#core#is_pm_error(error) abort
  if type(a:error) != v:t_string
    return 0
  endif
  return a:error =~# '^PM_ERROR:' || a:error =~# '^DEBUG:' || a:error =~# '^TRACE:'
endfunction

" Parse a PM_ERROR:component:code:message string into a structured dict.
" Uses a single regex so messages containing ':' (e.g. URLs) are captured whole.
function! plugin_manager#core#parse_error(error) abort
  if !plugin_manager#core#is_pm_error(a:error)
    return {'type': 'external', 'component': 'vim', 'code': 'EXTERNAL', 'message': a:error}
  endif

  let l:m = matchlist(a:error, '^PM_ERROR:\([^:]*\):\([^:]*\):\(.*\)$')
  if empty(l:m)
    " Malformed PM_ERROR string - treat as external
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
  " Only log external (non-PM_ERROR) exceptions here to avoid double-logging.
  if get(g:, 'plugin_manager_enable_logging', 1)
    if !plugin_manager#core#is_pm_error(a:error)
      call s:log_error_internally(a:error, a:component)
    endif
  endif

  let l:parsed = plugin_manager#core#parse_error(a:error)

  " Generate a detailed error message
  if l:parsed.type ==# 'internal'
    let l:title = 'Error in ' . l:parsed.component
    let l:message = l:parsed.message

    " Add specific tips based on error code
    let l:tips = []

    if l:parsed.component ==# 'git' && l:parsed.code ==# 'COMMAND_FAILED'
      call add(l:tips, 'Make sure Git is installed and in your PATH')
      call add(l:tips, 'Verify you have permission to access the repository')
    elseif l:parsed.component ==# 'add' && l:parsed.code ==# 'REPO_NOT_FOUND'
      call add(l:tips, 'Check the repository URL for typos')
      call add(l:tips, 'Verify the repository exists and is publicly accessible')
    elseif l:parsed.component ==# 'core' && l:parsed.code ==# 'NOT_GIT_REPO'
      call add(l:tips, 'Initialize your Vim config as a Git repository first:')
      call add(l:tips, '  cd ' . plugin_manager#core#get_config('vim_dir', '~/.vim'))
      call add(l:tips, '  git init')
    endif
  else
    let l:title = 'Error in ' . a:component
    let l:message = 'Unexpected error: ' . l:parsed.message
    let l:tips = ['This may be a bug in the plugin. Consider reporting it.']
  endif

  " Display error in UI if loaded
  if exists('*plugin_manager#ui#open_sidebar')
    let l:lines = [l:title, repeat('-', len(l:title)), '', l:message]

    " Add diagnostic information
    if !empty(l:tips)
      call add(l:lines, '')
      call add(l:lines, 'Suggestions:')
      call extend(l:lines, map(l:tips, {idx, val -> '- ' . val}))
    endif

    " Add information about the error log, if logging is enabled
    if get(g:, 'plugin_manager_enable_logging', 1)
      let l:log_file = plugin_manager#core#get_log_path()
      call add(l:lines, '')
      call add(l:lines, 'Error logged to: ' . l:log_file)
      call add(l:lines, 'View logs with: :PluginManagerViewLog')
    endif

    call plugin_manager#ui#open_sidebar(l:lines)
  else
    " Fallback if UI isn't loaded
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

" ------------------------------------------------------------------------------
" LOG MANAGEMENT FUNCTIONS
" ------------------------------------------------------------------------------

" Get the path to the log file
function! plugin_manager#core#get_log_path() abort
  let l:log_dir = plugin_manager#core#get_config('vim_dir', '') . '/logs'
  return l:log_dir . '/plugin_manager.log'
endfunction

" Rotate the log file if it exceeds max_log_size (in KB).
" Keeps up to log_history_count rotated copies (.1, .2, ...).
function! s:check_log_rotation(log_file) abort
  let l:max_size_kb = plugin_manager#core#get_config('max_log_size', 1024)
  let l:history = plugin_manager#core#get_config('log_history_count', 3)

  let l:size = getfsize(a:log_file)
  if l:size < 0 || l:size < l:max_size_kb * 1024
    return
  endif

  " Remove the oldest file if it exists
  let l:last_file = a:log_file . '.' . l:history
  if filereadable(l:last_file)
    call delete(l:last_file)
  endif

  " Shift .(n-1) -> .n
  for l:i in range(l:history - 1, 1, -1)
    let l:old = a:log_file . '.' . l:i
    let l:new = a:log_file . '.' . (l:i + 1)
    if filereadable(l:old)
      call rename(l:old, l:new)
    endif
  endfor

  " Rename current log to .1
  call rename(a:log_file, a:log_file . '.1')
endfunction

" Clear the error log
function! plugin_manager#core#clear_log() abort
  let l:log_file = plugin_manager#core#get_log_path()

  try
    " Check if file exists first
    if filereadable(l:log_file)
      " Delete the log file
      call delete(l:log_file)

      " Add header to the new log file
      let l:timestamp = strftime('%Y-%m-%d %H:%M:%S')
      let l:header = l:timestamp . ' | system | INFO | Log file cleared'
      call writefile([l:header], l:log_file)

      return 1
    endif
    return 0
  catch
    echohl WarningMsg
    echomsg 'Failed to clear log file: ' . v:exception
    echohl None
    return 0
  endtry
endfunction

" View the error log
function! plugin_manager#core#view_log() abort
  let l:log_file = plugin_manager#core#get_log_path()

  " Check if log file exists
  if !filereadable(l:log_file)
    if exists('*plugin_manager#ui#open_sidebar')
      call plugin_manager#ui#open_sidebar(['Log File:', '--------', '', 'Log file not found. No errors have been logged yet.'])
    else
      echomsg 'Log file not found. No errors have been logged yet.'
    endif
    return
  endif

  " Read the log file
  try
    let l:log_contents = readfile(l:log_file)

    " Display in sidebar if UI is available
    if exists('*plugin_manager#ui#open_sidebar')
      let l:lines = ['Log File:', '--------', '']

      " Add log entries, limiting if there are too many
      let l:max_entries = 200  " Avoid showing thousands of entries
      if len(l:log_contents) > l:max_entries
        call add(l:lines, '(Showing last ' . l:max_entries . ' entries of ' . len(l:log_contents) . ' total)')
        call add(l:lines, '')
        call extend(l:lines, l:log_contents[-l:max_entries:])
      else
        call extend(l:lines, l:log_contents)
      endif

      " Add instructions for clearing
      call add(l:lines, '')
      call add(l:lines, 'To clear the log, use: :PluginManagerClearLog')

      call plugin_manager#ui#open_sidebar(l:lines)
    else
      " Fallback to echo
      if len(l:log_contents) > 20
        echomsg '(Log file has ' . len(l:log_contents) . ' entries. Showing last 20.)'
        for l:line in l:log_contents[-20:]
          echomsg l:line
        endfor
      else
        for l:line in l:log_contents
          echomsg l:line
        endfor
      endif
    endif
  catch
    echohl ErrorMsg
    echomsg 'Error reading log file: ' . v:exception
    echohl None
  endtry
endfunction

" Log an arbitrary message for debugging
" Only logs when both logging and debug_mode are enabled
function! plugin_manager#core#log_debug(component, message) abort
  if get(g:, 'plugin_manager_enable_logging', 1) && get(g:, 'plugin_manager_debug_mode', 0)
    let l:error_string = 'DEBUG:' . a:component . ':DEBUG:' . a:message
    call s:log_error_internally(l:error_string, a:component)
  endif
endfunction

" Trace a low-level command to the log
" Independent of debug_mode: gated by enable_logging only, callers gate on
" g:plugin_manager_trace_commands
function! plugin_manager#core#log_trace(component, message) abort
  if get(g:, 'plugin_manager_enable_logging', 1)
    let l:error_string = 'TRACE:' . a:component . ':TRACE:' . a:message
    call s:log_error_internally(l:error_string, a:component)
  endif
endfunction

" ------------------------------------------------------------------------------
" UPDATE CHECK CACHE
" ------------------------------------------------------------------------------

" Get the path to the update-check cache file
function! plugin_manager#core#get_check_cache_path() abort
  let l:vim_dir = plugin_manager#core#get_config('vim_dir', '')
  return l:vim_dir . '/logs/update_check.json'
endfunction

" Read the cached update-check result
" Returns a dict: {'timestamp': <int>, 'plugins': [ {name, behind}, ... ]}
" Returns an empty dict if no valid cache exists
function! plugin_manager#core#read_check_cache() abort
  let l:path = plugin_manager#core#get_check_cache_path()
  if !filereadable(l:path)
    return {}
  endif
  try
    let l:content = join(readfile(l:path), "\n")
    if empty(l:content)
      return {}
    endif
    let l:data = json_decode(l:content)
    if type(l:data) != v:t_dict
      return {}
    endif
    return l:data
  catch
    return {}
  endtry
endfunction

" Write the update-check result to the cache
" @param plugins: list of dicts {name, behind}
function! plugin_manager#core#write_check_cache(plugins) abort
  let l:path = plugin_manager#core#get_check_cache_path()
  let l:dir = fnamemodify(l:path, ':h')
  if !isdirectory(l:dir)
    try
      call mkdir(l:dir, 'p')
    catch
      return 0
    endtry
  endif
  let l:data = {'timestamp': localtime(), 'plugins': a:plugins}
  try
    call writefile([json_encode(l:data)], l:path)
    return 1
  catch
    return 0
  endtry
endfunction

" Decide whether a fresh check is due based on the configured interval
" @param interval_hours: hours that must elapse before a new check
" Returns 1 if a check should run, 0 if the cache is still fresh
function! plugin_manager#core#check_due(interval_hours) abort
  let l:cache = plugin_manager#core#read_check_cache()
  if empty(l:cache) || !has_key(l:cache, 'timestamp')
    return 1
  endif
  let l:age = localtime() - l:cache.timestamp
  return l:age >= (a:interval_hours * 3600)
endfunction

" ------------------------------------------------------------------------------
" DIRECTORY AND PATH MANAGEMENT
" ------------------------------------------------------------------------------

" Ensure we're in the Vim config directory
function! plugin_manager#core#ensure_vim_directory() abort
  " Get current directory
  let l:current_dir = getcwd()

  " Get configured vim directory
  let l:vim_dir = plugin_manager#core#get_config('vim_dir', '')

  " Check if we're already in the vim directory
  if l:current_dir ==# l:vim_dir
    return 1
  endif

  " Check if the vim directory exists
  if !isdirectory(l:vim_dir)
    let l:error_lines = ['Error:', '------', '', 'Vim directory not found: ' . l:vim_dir,
    \ 'Please set g:plugin_manager_vim_dir to your Vim configuration directory.']

    if exists('*plugin_manager#ui#open_sidebar')
      call plugin_manager#ui#open_sidebar(l:error_lines)
    else
      echohl ErrorMsg
      for l:line in l:error_lines
        echomsg l:line
      endfor
      echohl None
    endif
    return 0
  endif

  " Change to vim directory
  try
    execute 'cd ' . fnameescape(l:vim_dir)
  catch
    let l:error_lines = ['Error:', '------', '', 'Could not change to Vim directory: ' . l:vim_dir,
    \ 'Error: ' . v:exception]

    if exists('*plugin_manager#ui#open_sidebar')
      call plugin_manager#ui#open_sidebar(l:error_lines)
    else
      echohl ErrorMsg
      for l:line in l:error_lines
        echomsg l:line
      endfor
      echohl None
    endif
    return 0
  endtry

  " Check if it's a git repository
  if !isdirectory('.git')
    let l:error_lines = ['Error:', '------', '', 'The Vim directory is not a git repository.',
    \ 'Please initialize it with: git init ' . l:vim_dir]

    if exists('*plugin_manager#ui#open_sidebar')
      call plugin_manager#ui#open_sidebar(l:error_lines)
    else
      echohl ErrorMsg
      for l:line in l:error_lines
        echomsg l:line
      endfor
      echohl None
    endif
    return 0
  endif

  return 1
endfunction

" Guard that combines ensure_vim_directory() with a structured throw.
" Use this in cmd/*#execute functions that want to abort via PM_ERROR on
" failure. Functions that prefer a silent 'return' should keep using
" ensure_vim_directory() directly.
function! plugin_manager#core#require_vim_directory(component) abort
  if !plugin_manager#core#ensure_vim_directory()
    call plugin_manager#core#throw(a:component, 'NOT_VIM_DIR', 'Not in Vim configuration directory')
  endif
endfunction

" Check if a path is a local filesystem path
function! plugin_manager#core#is_local_path(path) abort
  " Starts with '~' (home path)
  if a:path =~ '^\~\/'
    return 1
  endif

  " Absolute path (starts with '/' on Unix or drive letter on Windows)
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

" Clean and normalize a path
function! plugin_manager#core#normalize_path(path) abort
  " Convert backslashes to forward slashes on Windows
  let l:path = a:path
  if has('win32') || has('win64')
    let l:path = substitute(l:path, '\\', '/', 'g')
  endif

  " Expand ~ in paths
  if l:path =~ '^\~\/'
    let l:path = expand(l:path)
  endif

  " Remove trailing slash
  let l:path = substitute(l:path, '\/\+$', '', '')

  " Remove duplicate slashes
  let l:path = substitute(l:path, '\/\+', '/', 'g')

  return l:path
endfunction

" Make a path relative to vim directory if possible
function! plugin_manager#core#make_relative_path(path) abort
  let l:vim_dir = plugin_manager#core#get_config('vim_dir', '')
  let l:norm_path = plugin_manager#core#normalize_path(a:path)
  let l:norm_vim_dir = plugin_manager#core#normalize_path(l:vim_dir)

  " Check if the path starts with vim_dir
  if l:norm_path =~# '^' . escape(l:norm_vim_dir, '/.\') . '\/'
    return substitute(l:norm_path, '^' . escape(l:norm_vim_dir, '/.\') . '\/', '', '')
  endif

  return l:norm_path
endfunction

" Ensure a directory exists, creating it if necessary
function! plugin_manager#core#ensure_directory(dir) abort
  let l:dir = plugin_manager#core#normalize_path(a:dir)

  if !isdirectory(l:dir)
    try
      call mkdir(l:dir, 'p')
      return 1
    catch
      return 0
    endtry
  endif

  return 1
endfunction

" ------------------------------------------------------------------------------
" CONFIGURATION MANAGEMENT
" ------------------------------------------------------------------------------

" Get a configuration value with fallback
function! plugin_manager#core#get_config(name, default) abort
  return get(g:, 'plugin_manager_' . a:name, a:default)
endfunction


" Translate the configured pull strategy into a git pull flag
" Options: ff-only (default), merge, rebase
function! plugin_manager#core#get_pull_flag() abort
  let l:strategy = plugin_manager#core#get_config('pull_strategy', 'ff-only')
  if l:strategy ==# 'merge'
    return '--no-rebase'
  elseif l:strategy ==# 'rebase'
    return '--rebase'
  endif
  " Default and any unknown value: fast-forward only
  return '--ff-only'
endfunction

" Whether updates should be auto-committed
function! plugin_manager#core#should_auto_commit() abort
  return plugin_manager#core#get_config('auto_commit_on_update', 1)
endfunction

" Get plugin directory for a specific load type ('start' or 'opt').
function! plugin_manager#core#get_plugin_dir(type) abort
  let l:plugins_dir = plugin_manager#core#get_config('plugins_dir', '')
  let l:start_dir   = plugin_manager#core#get_config('start_dir', 'start')
  let l:opt_dir     = plugin_manager#core#get_config('opt_dir', 'opt')

  if a:type ==# 'opt'
    return l:plugins_dir . '/' . l:opt_dir
  endif
  return l:plugins_dir . '/' . l:start_dir
endfunction

" ------------------------------------------------------------------------------
" URL AND PLUGIN NAME UTILITIES
" ------------------------------------------------------------------------------

" Regular expressions for URL and plugin short name validation
let s:url_regexp = '^https\?://.\+\|^git@.\+:.\+$'
let s:short_name_regexp = '^[a-zA-Z0-9_.-]\+/[a-zA-Z0-9_.-]\+$'

" Convert a shortname like 'user/repo' to a full URL
function! plugin_manager#core#convert_to_full_url(shortname) abort
  " If it's a local path
  if plugin_manager#core#is_local_path(a:shortname)
    return 'local:' . expand(a:shortname)
  endif

  " If it's already a URL, return as is
  if a:shortname =~ s:url_regexp
    return a:shortname
  endif

  " If it's a user/repo format
  if a:shortname =~ s:short_name_regexp
    let l:host = plugin_manager#core#get_config('default_git_host', 'github.com')
    return 'https://' . l:host . '/' . a:shortname . '.git'
  endif

  " Return empty string for unrecognized format
  return ''
endfunction

" Extract plugin name from various formats
function! plugin_manager#core#extract_plugin_name(input) abort
  " For local paths
  if a:input =~ '^local:'
    let l:path = substitute(a:input, '^local:', '', '')
    return fnamemodify(l:path, ':t')
  endif

  " For URLs
  if a:input =~ s:url_regexp
    " Extract repo name from URL, preserving dots in the name
    let l:name = matchstr(a:input, '[^/]*$')  " Get everything after the last /
    return substitute(l:name, '\.git$', '', '')  " Remove .git extension if present
  endif

  " For user/repo format
  if a:input =~ s:short_name_regexp
    return matchstr(a:input, '[^/]*$')  " Get everything after the last /
  endif

  return a:input  " Return as is if format not recognized
endfunction

" ------------------------------------------------------------------------------
" FILE SYSTEM OPERATIONS
" ------------------------------------------------------------------------------

" Platform-independent file existence check
function! plugin_manager#core#file_exists(path) abort
  return filereadable(expand(a:path))
endfunction

" Platform-independent directory existence check
function! plugin_manager#core#dir_exists(path) abort
  return isdirectory(expand(a:path))
endfunction

" Platform-independent file or directory removal.
" Uses Vim's native delete() to avoid shell dependencies.
"
" Safety contract: refuses to delete if the resolved path is:
"   - empty or filesystem roots (/, C:\)
"   - the user home directory (expand('~'))
"   - equal to or a parent of the configured vim_dir
"   - contains traversal components (..)
function! plugin_manager#core#remove_path(path) abort
  let l:path = expand(a:path)

  " Reject empty or filesystem roots
  if empty(l:path) || l:path ==# '/' || l:path =~# '^[A-Za-z]:[\\/]*$'
    return 0
  endif

  " Reject home directory
  let l:home = expand('~')
  if l:path ==# l:home
    return 0
  endif

  " Reject traversal components (..)
  if l:path =~# '\.\.'
    return 0
  endif

  " Reject anything at or above the vim_dir to prevent wiping config root
  let l:vim_dir = expand(plugin_manager#core#get_config('vim_dir', ''))
  if !empty(l:vim_dir)
    " Path must be strictly inside vim_dir (not equal to it)
    if l:path ==# l:vim_dir || stridx(l:path, l:vim_dir . '/') != 0
      return 0
    endif
  endif

  if plugin_manager#core#dir_exists(l:path)
    " delete(path, 'rf') removes a directory tree (Vim 8+), returns 0 on success
    return delete(l:path, 'rf') == 0
  elseif plugin_manager#core#file_exists(l:path)
    return delete(l:path) == 0
  endif

  " Path doesn't exist, so "removal" is considered successful
  return 1
endfunction

" ------------------------------------------------------------------------------
" PLUGIN OPTIONS PARSING
" ------------------------------------------------------------------------------

" Process plugin options with defaults
" @param args: Either a dictionary of options or a list of positional arguments (legacy format)
" @return: Dictionary of options with defaults applied
function! plugin_manager#core#process_plugin_options(args) abort
  " Define default options
  let l:options = {
  \ 'dir': '',
  \ 'load': 'start',
  \ 'branch': '',
  \ 'tag': '',
  \ 'exec': ''
  \ }

  " Return defaults if no args provided
  if empty(a:args)
    return l:options
  endif

  " CASE 1: New format - options provided as a dictionary
  if type(a:args[0]) == v:t_dict
    " Validate and merge options
    for [l:key, l:val] in items(a:args[0])
      " Only accept known options
      if has_key(l:options, l:key)
        " Validate specific option values
        if l:key ==# 'load' && l:val !=# 'start' && l:val !=# 'opt'
          " Invalid load value, warn but use default
          echohl WarningMsg
          echomsg "Invalid 'load' value: " . l:val . ". Using default: 'start'"
          echohl None
        else
          " Valid option, apply it
          let l:options[l:key] = l:val
        endif
      else
        " Unknown option, warn user
        echohl WarningMsg
        echomsg "Unknown option '" . l:key . "' ignored"
        echohl None
      endif
    endfor

    " CASE 2: Legacy format - positional arguments
  elseif len(a:args) >= 1 && type(a:args[0]) == v:t_string
    " First argument is the custom directory name
    let l:options.dir = a:args[0]

    " If second argument exists and equals 'opt', set load to 'opt'
    if len(a:args) >= 2 && a:args[1] ==# 'opt'
      let l:options.load = 'opt'
    endif

    " Show deprecation warning for legacy format
    if get(g:, 'plugin_manager_show_deprecation_warnings', 1)
      echohl WarningMsg
      echomsg "Warning: Using deprecated format for plugin options."
      echomsg "Please use dictionary format: {'dir':'name', 'load':'start|opt', ...}"
      echohl None
    endif
  endif

  return l:options
endfunction