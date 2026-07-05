" autoload/plugin_manager/core/log.vim - Log management for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>

" ------------------------------------------------------------------------------
" INTERNAL LOG WRITING (used by core#log_error_internal, debug, trace)
" ------------------------------------------------------------------------------

" Write a parsed error dict to the log file.  Handles directory creation,
" rotation, and file I/O silently.
function! plugin_manager#core#log#write(parsed) abort
  let l:vim_dir = plugin_manager#core#util#get_config('vim_dir', '')
  if empty(l:vim_dir)
    return
  endif

  let l:log_dir  = l:vim_dir . '/logs'
  let l:log_file = l:log_dir . '/plugin_manager.log'
  let l:timestamp = strftime('%Y-%m-%d %H:%M:%S')

  let l:entry = l:timestamp . ' | ' .
  \ a:parsed.component . ' | ' .
  \ (a:parsed.type ==# 'internal' ? a:parsed.code : 'EXTERNAL') . ' | ' .
  \ a:parsed.message

  if !isdirectory(l:log_dir)
    try
      call mkdir(l:log_dir, 'p')
    catch
      return
    endtry
  endif

  if filereadable(l:log_file)
    try
      call s:check_rotation(l:log_file)
    catch
    endtry
  endif

  try
    call writefile([l:entry], l:log_file, 'a')
  catch
    try
      call writefile([l:entry], l:log_file)
    catch
    endtry
  endtry
endfunction

" Rotate the log file if it exceeds max_log_size (in KB).
function! s:check_rotation(log_file) abort
  let l:max_size_kb = plugin_manager#core#util#get_config('max_log_size', 1024)
  let l:history     = plugin_manager#core#util#get_config('log_history_count', 3)

  let l:size = getfsize(a:log_file)
  if l:size < 0 || l:size < l:max_size_kb * 1024
    return
  endif

  let l:last_file = a:log_file . '.' . l:history
  if filereadable(l:last_file)
    call delete(l:last_file)
  endif

  for l:i in range(l:history - 1, 1, -1)
    let l:old = a:log_file . '.' . l:i
    let l:new = a:log_file . '.' . (l:i + 1)
    if filereadable(l:old)
      call rename(l:old, l:new)
    endif
  endfor

  call rename(a:log_file, a:log_file . '.1')
endfunction

" ------------------------------------------------------------------------------
" PUBLIC API
" ------------------------------------------------------------------------------

function! plugin_manager#core#log#get_path() abort
  let l:vim_dir = plugin_manager#core#util#get_config('vim_dir', '')
  return l:vim_dir . '/logs/plugin_manager.log'
endfunction

function! plugin_manager#core#log#clear() abort
  let l:log_path = plugin_manager#core#log#get_path()

  try
    if filereadable(l:log_path)
      call delete(l:log_path)
      let l:timestamp = strftime('%Y-%m-%d %H:%M:%S')
      call writefile([l:timestamp . ' | system | INFO | Log file cleared'], l:log_path)
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

function! plugin_manager#core#log#view() abort
  let l:log_path = plugin_manager#core#log#get_path()

  if !filereadable(l:log_path)
    if exists('*plugin_manager#ui#open_sidebar')
      call plugin_manager#ui#open_sidebar(['Log File:', '--------', '', 'Log file not found. No errors have been logged yet.'])
    else
      echomsg 'Log file not found. No errors have been logged yet.'
    endif
    return
  endif

  try
    let l:log_contents = readfile(l:log_path)

    if exists('*plugin_manager#ui#open_sidebar')
      let l:lines = ['Log File:', '--------', '']
      let l:max_entries = 200
      if len(l:log_contents) > l:max_entries
        call add(l:lines, '(Showing last ' . l:max_entries . ' entries of ' . len(l:log_contents) . ' total)')
        call add(l:lines, '')
        " vint: -ProhibitUsingUndeclaredVariable
        call extend(l:lines, l:log_contents[-l:max_entries:])
        " vint: +ProhibitUsingUndeclaredVariable
      else
        call extend(l:lines, l:log_contents)
      endif
      call add(l:lines, '')
      call add(l:lines, 'To clear the log, use: :PluginManagerClearLog')
      call plugin_manager#ui#open_sidebar(l:lines)
    else
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

" Write a debug entry.  Only writes when both logging and debug_mode are on.
function! plugin_manager#core#log#debug(component, message) abort
  if get(g:, 'plugin_manager_enable_logging', 1) && get(g:, 'plugin_manager_debug_mode', 0)
    let l:parsed = {'type': 'external', 'component': a:component, 'code': 'DEBUG', 'message': 'DEBUG:' . a:component . ':DEBUG:' . a:message}
    call plugin_manager#core#log#write(l:parsed)
  endif
endfunction

" Write a trace entry.  Gated by enable_logging only (callers gate on
" g:plugin_manager_trace_commands before calling).
function! plugin_manager#core#log#trace(component, message) abort
  if get(g:, 'plugin_manager_enable_logging', 1)
    let l:parsed = {'type': 'external', 'component': a:component, 'code': 'TRACE', 'message': 'TRACE:' . a:component . ':TRACE:' . a:message}
    call plugin_manager#core#log#write(l:parsed)
  endif
endfunction
