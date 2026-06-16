" autoload/plugin_manager/ui.vim - Modern, non-blocking sidebar UI for Vim
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4.0

" Terminal capability detection (Vim 8.2+, UTF-8 aware)
let s:unicode_support = &encoding ==# 'utf-8'
let s:fancy_ui = get(g:, 'plugin_manager_fancy_ui', 1) && s:unicode_support
let s:has_timers = exists('*timer_start') && exists('*timer_stop')

" UI Constants
let s:symbols = {
      \ 'tick': s:fancy_ui ? '✓' : '+',
      \ 'cross': s:fancy_ui ? '✗' : 'x',
      \ 'arrow': s:fancy_ui ? '→' : '->',
      \ 'ellipsis': s:fancy_ui ? '…' : '...',
      \ 'separator': s:fancy_ui ? '━━━━━━━━━━━━━━━━━━━━' : '--------------------',
      \ 'bullet': s:fancy_ui ? '•' : '*',
      \ 'warning': s:fancy_ui ? '⚠' : '!',
      \ 'info': s:fancy_ui ? 'ℹ' : 'i',
      \ 'pending': s:fancy_ui ? '○' : 'o',
      \ 'chevron_right': s:fancy_ui ? '❯' : '>',
      \ 'chevron_down': s:fancy_ui ? '❮' : '<',
      \ 'vertical': s:fancy_ui ? '│' : '|',
      \ 'corner': s:fancy_ui ? '┌' : '+',
      \ 'horizontal': s:fancy_ui ? '─' : '-',
      \ }

" Spinner frames
let s:spinner_styles = {
      \ 'dots': s:fancy_ui ? ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'] : ['|', '/', '-', '\'],
      \ 'line': s:fancy_ui ? ['⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷'] : ['|', '/', '-', '\'],
      \ 'circle': s:fancy_ui ? ['◐', '◓', '◑', '◒'] : ['|', '/', '-', '\'],
      \ 'triangle': s:fancy_ui ? ['◢', '◣', '◤', '◥'] : ['^', '>', 'v', '<'],
      \ 'box': s:fancy_ui ? ['▌', '▀', '▐', '▄'] : ['+', '+', '+', '+'],
      \ }

let s:active_spinner_style = get(g:, 'plugin_manager_spinner_style', 'dots')
let s:spinner_frames = has_key(s:spinner_styles, s:active_spinner_style)
      \ ? s:spinner_styles[s:active_spinner_style]
      \ : s:spinner_styles['dots']

" Buffer state
let s:buffer_name = 'PluginManager'
let s:active_operations = {}
let s:spinner_timer = 0
let s:op_id_counter = 0

" ------------------------------------------------------------------------------
" BUFFER HELPERS (non-blocking: never steal focus, never force global redraw)
" ------------------------------------------------------------------------------

" Return the sidebar buffer number, or -1 if it does not exist yet
function! s:bufnr() abort
  return bufnr(s:buffer_name)
endfunction

" Whether the sidebar buffer is shown in a window
function! s:bufwin() abort
  return bufwinid(s:buffer_name)
endfunction

" Set buffer lines safely without changing the current window/cursor
function! s:set_lines(buf, lnum, lines) abort
  if a:buf == -1
    return
  endif
  call setbufvar(a:buf, '&modifiable', 1)
  call setbufline(a:buf, a:lnum, a:lines)
  call setbufvar(a:buf, '&modifiable', 0)
endfunction

" Append lines at the end of the buffer
function! s:append_lines(buf, lines) abort
  if a:buf == -1
    return
  endif
  let l:last = s:line_count(a:buf)
  call setbufvar(a:buf, '&modifiable', 1)
  call appendbufline(a:buf, l:last, a:lines)
  call setbufvar(a:buf, '&modifiable', 0)
endfunction

" Replace the whole buffer content
function! s:replace_all(buf, lines) abort
  if a:buf == -1
    return
  endif
  call setbufvar(a:buf, '&modifiable', 1)
  call deletebufline(a:buf, 1, '$')
  call setbufline(a:buf, 1, a:lines)
  call setbufvar(a:buf, '&modifiable', 0)
endfunction

" Count lines in a buffer
function! s:line_count(buf) abort
  if a:buf == -1
    return 0
  endif
  return len(getbufline(a:buf, 1, '$'))
endfunction

" Redraw only when the sidebar is visible (avoids needless global redraws)
function! s:redraw_if_visible() abort
  if s:bufwin() != -1
    redraw
  endif
endfunction

" ------------------------------------------------------------------------------
" PUBLIC API
" ------------------------------------------------------------------------------

" Get symbol
function! plugin_manager#ui#get_symbol(symbol_key) abort
  return get(s:symbols, a:symbol_key, '')
endfunction

" Open (or focus) the sidebar and render the given lines
function! plugin_manager#ui#open_sidebar(lines) abort
  let l:win_id = s:bufwin()

  if l:win_id != -1
    " Already visible: just refresh content without moving the user's cursor
    let l:buf = s:bufnr()
    call s:replace_all(l:buf, a:lines)
    call s:redraw_if_visible()
    return
  endif

  " Create the sidebar window. This is an explicit user-facing open, so it is
  " acceptable to create/focus the window here.
  let l:width = get(g:, 'plugin_manager_sidebar_width', 60)
  execute 'silent! rightbelow ' . l:width . 'vnew ' . s:buffer_name
  setlocal filetype=pluginmanager
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
  setlocal nomodifiable

  let l:buf = s:bufnr()
  call s:replace_all(l:buf, a:lines)
  redraw
endfunction

" Update the sidebar content (append or replace) without stealing focus
function! plugin_manager#ui#update_sidebar(lines, append) abort
  let l:buf = s:bufnr()
  if l:buf == -1
    call plugin_manager#ui#open_sidebar(a:lines)
    return
  endif

  if a:append && !empty(a:lines)
    call s:append_lines(l:buf, a:lines)
  elseif !a:append
    call s:replace_all(l:buf, empty(a:lines) ? [''] : a:lines)
  endif

  call s:redraw_if_visible()
endfunction

" Start an operation (returns operation ID)
function! plugin_manager#ui#start_operation(plugin_name, operation_type) abort
  let s:op_id_counter += 1
  let l:op_id = 'op_' . s:op_id_counter

  let l:buf = s:bufnr()
  if l:buf == -1
    call plugin_manager#ui#open_sidebar([''])
    let l:buf = s:bufnr()
  endif

  " Append the operation line at the end of the buffer
  let l:spinner = s:spinner_frames[0]
  let l:line = plugin_manager#ui#format_plugin_line(l:spinner, a:plugin_name, a:operation_type)
  call s:append_lines(l:buf, [l:line])

  let s:active_operations[l:op_id] = {
        \ 'id': l:op_id,
        \ 'name': a:plugin_name,
        \ 'type': a:operation_type,
        \ 'line': s:line_count(l:buf),
        \ 'spinner_frame': 0,
        \ 'started': localtime()
        \ }

  " Start the spinner timer lazily, only while operations are active
  call s:ensure_spinner()
  call s:redraw_if_visible()

  return l:op_id
endfunction

" Update operation status (mid-operation)
function! plugin_manager#ui#update_operation(op_id, status_text) abort
  if !has_key(s:active_operations, a:op_id)
    return
  endif

  let l:op = s:active_operations[a:op_id]
  let l:buf = s:bufnr()
  if l:buf == -1 || l:op.line <= 0 || l:op.line > s:line_count(l:buf)
    return
  endif

  let l:spinner = s:spinner_frames[l:op.spinner_frame]
  let l:new_line = plugin_manager#ui#format_plugin_line(l:spinner, l:op.name, a:status_text)
  call s:set_lines(l:buf, l:op.line, [l:new_line])
  call s:redraw_if_visible()
endfunction

" Complete an operation
function! plugin_manager#ui#complete_operation(op_id, success, final_message) abort
  if !has_key(s:active_operations, a:op_id)
    return
  endif

  let l:op = s:active_operations[a:op_id]
  let l:buf = s:bufnr()
  if l:buf != -1 && l:op.line > 0 && l:op.line <= s:line_count(l:buf)
    let l:symbol = a:success ? s:symbols.tick : s:symbols.cross
    let l:final_line = plugin_manager#ui#format_plugin_line(l:symbol, l:op.name, a:final_message)
    call s:set_lines(l:buf, l:op.line, [l:final_line])
    call s:redraw_if_visible()
  endif

  unlet s:active_operations[a:op_id]

  " Stop the spinner timer when there is nothing left to animate
  call s:maybe_stop_spinner()
endfunction

" Format helper functions
function! plugin_manager#ui#success(msg) abort
  return s:symbols.tick . ' ' . a:msg
endfunction

function! plugin_manager#ui#error(msg) abort
  return s:symbols.cross . ' ' . a:msg
endfunction

function! plugin_manager#ui#warning(msg) abort
  return s:symbols.warning . ' ' . a:msg
endfunction

function! plugin_manager#ui#info(msg) abort
  return s:symbols.info . ' ' . a:msg
endfunction

" Show update notification with the list of plugins that have updates available
" @param plugins: list of dicts {name, behind}
function! plugin_manager#ui#show_update_notification(plugins) abort
  let l:lines = ['Update notification:', s:symbols.separator, '']

  if empty(a:plugins)
    call add(l:lines, plugin_manager#ui#success('All plugins are up-to-date'))
    call plugin_manager#ui#open_sidebar(l:lines)
    return
  endif

  let l:count = len(a:plugins)
  call add(l:lines, plugin_manager#ui#warning(l:count . (l:count > 1 ? ' plugins have' : ' plugin has') . ' updates available:'))
  call add(l:lines, '')

  for l:plugin in a:plugins
    let l:behind = get(l:plugin, 'behind', 0)
    let l:detail = l:behind > 0 ? (l:behind . ' commits behind') : 'update available'
    call add(l:lines, plugin_manager#ui#format_plugin_line(s:symbols.arrow, l:plugin.name, l:detail))
  endfor

  call add(l:lines, '')
  call add(l:lines, plugin_manager#ui#info('Run :PluginManager update to install'))
  call plugin_manager#ui#open_sidebar(l:lines)
endfunction

" Display error in sidebar
function! plugin_manager#ui#display_error(component, message) abort
  let l:lines = [
        \ 'Error in ' . a:component . ':',
        \ s:symbols.separator,
        \ '',
        \ s:symbols.cross . ' ' . a:message
        \ ]
  call plugin_manager#ui#open_sidebar(l:lines)
endfunction

" Usage display
function! plugin_manager#ui#usage() abort
  let l:lines = [
        \ 'PluginManager Commands:',
        \ s:symbols.separator,
        \ 'add <plugin> [options]  - Install plugin',
        \ 'remove <plugin> [-f]    - Remove plugin',
        \ 'update [plugin|all]     - Update plugins',
        \ 'check                   - Check for available updates',
        \ 'list                    - List installed plugins',
        \ 'status                  - Show plugin status',
        \ 'backup                  - Backup configuration',
        \ 'restore                 - Restore plugins',
        \ '',
        \ 'Shortcuts:',
        \ 'q - Close   u - Update   l - List   s - Status',
        \ ]
  call plugin_manager#ui#open_sidebar(l:lines)
endfunction

" Toggle sidebar
function! plugin_manager#ui#toggle_sidebar() abort
  let l:win_id = s:bufwin()
  if l:win_id != -1
    " Hide the window without destroying the buffer
    call win_execute(l:win_id, 'hide')
  else
    let l:buf_id = s:bufnr()
    if l:buf_id != -1 && bufloaded(l:buf_id)
      execute 'vertical rightbelow sbuffer ' . l:buf_id
      execute 'vertical resize ' . get(g:, 'plugin_manager_sidebar_width', 60)
    else
      call plugin_manager#ui#usage()
    endif
  endif
endfunction

" ------------------------------------------------------------------------------
" INTERNAL FUNCTIONS
" ------------------------------------------------------------------------------

" Format a plugin line (vim-plug style)
" Format: [spinner/status] plugin_name........ status_text
function! plugin_manager#ui#format_plugin_line(status, name, info) abort
  let l:max_name_len = 30
  let l:name = a:name

  if strchars(l:name) > l:max_name_len
    let l:name = l:name[:(l:max_name_len-4)] . s:symbols.ellipsis
  endif

  let l:dots = repeat('.', max([1, l:max_name_len - strchars(l:name) + 2]))
  return a:status . ' ' . l:name . l:dots . ' ' . a:info
endfunction

" Start the spinner timer if not already running and timers are available
function! s:ensure_spinner() abort
  if s:has_timers && !s:spinner_timer && !empty(s:active_operations)
    let l:interval = get(g:, 'plugin_manager_spinner_interval', 80)
    let s:spinner_timer = timer_start(l:interval, function('s:update_all_spinners'), {'repeat': -1})
  endif
endfunction

" Stop the spinner timer when no operations remain
function! s:maybe_stop_spinner() abort
  if s:spinner_timer && empty(s:active_operations)
    call timer_stop(s:spinner_timer)
    let s:spinner_timer = 0
  endif
endfunction

" Backwards-compatible initializer (now a no-op trigger for the spinner)
function! plugin_manager#ui#init() abort
  call s:ensure_spinner()
endfunction

" Advance and render all active spinners (only if the sidebar is visible)
function! s:update_all_spinners(timer) abort
  if empty(s:active_operations)
    call s:maybe_stop_spinner()
    return
  endif

  let l:buf = s:bufnr()
  if l:buf == -1
    return
  endif

  " Skip the expensive line rewrite when the sidebar is not on screen
  if s:bufwin() == -1
    " Still advance frames so they look fresh once reopened
    for l:op in values(s:active_operations)
      let l:op.spinner_frame = (l:op.spinner_frame + 1) % len(s:spinner_frames)
    endfor
    return
  endif

  let l:last = s:line_count(l:buf)
  for l:op in values(s:active_operations)
    if l:op.line <= 0 || l:op.line > l:last
      continue
    endif

    let l:op.spinner_frame = (l:op.spinner_frame + 1) % len(s:spinner_frames)
    let l:spinner = s:spinner_frames[l:op.spinner_frame]

    let l:current = get(getbufline(l:buf, l:op.line), 0, '')
    if !empty(l:current)
      " Replace only the leading status glyph, keep the rest of the line
      let l:rest = strcharpart(l:current, 1)
      call s:set_lines(l:buf, l:op.line, [l:spinner . l:rest])
    endif
  endfor

  redraw
endfunction
