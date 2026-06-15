" autoload/plugin_manager/ui.vim - Simplified modern UI inspired by vim-plug
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4.0

" Terminal capability detection
let s:unicode_support = has('multi_byte') && &encoding ==# 'utf-8'
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

" Enhanced spinner frames
let s:spinner_styles = {
      \ 'dots': s:fancy_ui ? ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'] : ['|', '/', '-', '\'],
      \ 'line': s:fancy_ui ? ['⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷'] : ['|', '/', '-', '\'],
      \ 'circle': s:fancy_ui ? ['◐', '◓', '◑', '◒'] : ['|', '/', '-', '\'],
      \ 'triangle': s:fancy_ui ? ['◢', '◣', '◤', '◥'] : ['^', '>', 'v', '<'],
      \ 'box': s:fancy_ui ? ['▌', '▀', '▐', '▄'] : ['+', '+', '+', '+'],
      \ }

let s:active_spinner_style = get(g:, 'plugin_manager_spinner_style', 'dots')
let s:spinner_frames = s:spinner_styles[s:active_spinner_style]

" Buffer state
let s:buffer_name = 'PluginManager'
let s:active_operations = {}
let s:spinner_timer = 0
let s:op_id_counter = 0

" ------------------------------------------------------------------------------
" PUBLIC API
" ------------------------------------------------------------------------------

" Initialize UI
function! plugin_manager#ui#init() abort
  if s:has_timers && !s:spinner_timer
    let s:spinner_timer = timer_start(80, function('s:update_all_spinners'), {'repeat': -1})
  endif
endfunction

" Get symbol
function! plugin_manager#ui#get_symbol(symbol_key) abort
  return get(s:symbols, a:symbol_key, '')
endfunction

" Open sidebar
function! plugin_manager#ui#open_sidebar(lines) abort
  " Ensure the spinner timer is running (lazy init, no startup cost)
  call plugin_manager#ui#init()
  
  let l:win_id = bufwinid(s:buffer_name)
  
  if l:win_id != -1
    call win_gotoid(l:win_id)
  else
    execute 'silent! rightbelow ' . g:plugin_manager_sidebar_width . 'vnew ' . s:buffer_name
    set filetype=pluginmanager
  endif
  
  setlocal modifiable
  silent! %delete _
  call setline(1, a:lines)
  setlocal nomodifiable
  redraw
endfunction

" Update sidebar
function! plugin_manager#ui#update_sidebar(lines, append) abort
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1
    call plugin_manager#ui#open_sidebar(a:lines)
    return
  endif
  
  call win_gotoid(l:win_id)
  setlocal modifiable
  
  if a:append && !empty(a:lines)
    call append(line('$'), a:lines)
  else
    silent! %delete _
    if !empty(a:lines)
      call setline(1, a:lines)
    endif
  endif
  
  setlocal nomodifiable
  normal! G
  redraw
endfunction

" Start an operation (returns operation ID)
function! plugin_manager#ui#start_operation(plugin_name, operation_type) abort
  let s:op_id_counter += 1
  let l:op_id = 'op_' . s:op_id_counter
  
  let s:active_operations[l:op_id] = {
        \ 'id': l:op_id,
        \ 'name': a:plugin_name,
        \ 'type': a:operation_type,
        \ 'line': 0,
        \ 'spinner_frame': 0,
        \ 'started': localtime()
        \ }
  
  " Display line with spinner
  let l:spinner = s:spinner_frames[0]
  let l:line = plugin_manager#ui#format_plugin_line(l:spinner, a:plugin_name, a:operation_type)
  call plugin_manager#ui#update_sidebar([l:line], 1)
  
  " Store line number
  let s:active_operations[l:op_id].line = line('$')
  
  return l:op_id
endfunction

" Update operation status (mid-operation)
function! plugin_manager#ui#update_operation(op_id, status_text) abort
  if !has_key(s:active_operations, a:op_id)
    return
  endif
  
  let l:op = s:active_operations[a:op_id]
  let l:line_num = l:op.line
  
  if l:line_num <= 0 || l:line_num > line('$')
    return
  endif
  
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1
    return
  endif
  
  call win_gotoid(l:win_id)
  setlocal modifiable
  
  let l:spinner = s:spinner_frames[l:op.spinner_frame]
  let l:new_line = plugin_manager#ui#format_plugin_line(l:spinner, l:op.name, a:status_text)
  call setline(l:line_num, l:new_line)
  
  setlocal nomodifiable
  redraw
endfunction

" Complete an operation
function! plugin_manager#ui#complete_operation(op_id, success, final_message) abort
  if !has_key(s:active_operations, a:op_id)
    return
  endif
  
  let l:op = s:active_operations[a:op_id]
  let l:line_num = l:op.line
  
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id != -1 && l:line_num > 0 && l:line_num <= line('$')
    call win_gotoid(l:win_id)
    setlocal modifiable
    
    let l:symbol = a:success ? s:symbols.tick : s:symbols.cross
    let l:final_line = plugin_manager#ui#format_plugin_line(l:symbol, l:op.name, a:final_message)
    call setline(l:line_num, l:final_line)
    
    setlocal nomodifiable
    redraw
  endif
  
  unlet s:active_operations[a:op_id]
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
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id != -1
    execute 'hide'
  else
    let l:buf_id = bufnr(s:buffer_name)
    if l:buf_id != -1 && bufloaded(l:buf_id)
      execute 'vertical rightbelow sbuffer ' . l:buf_id
      execute 'vertical resize ' . g:plugin_manager_sidebar_width
    else
      call plugin_manager#ui#usage()
    endif
  endif
endfunction

" ------------------------------------------------------------------------------
" INTERNAL FUNCTIONS
" ------------------------------------------------------------------------------

" Format a plugin line (vim-plug style) - PUBLIC for reuse
" Format: [spinner/status] plugin_name........ status_text
function! plugin_manager#ui#format_plugin_line(status, name, info) abort
  let l:max_name_len = 30
  let l:name = a:name
  
  if len(l:name) > l:max_name_len
    let l:name = l:name[:(l:max_name_len-4)] . s:symbols.ellipsis
  endif
  
  let l:dots = repeat('.', max([1, l:max_name_len - len(l:name) + 2]))
  return a:status . ' ' . l:name . l:dots . ' ' . a:info
endfunction

" Update all active spinners
function! s:update_all_spinners(timer) abort
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1 || empty(s:active_operations)
    return
  endif
  
  call win_gotoid(l:win_id)
  setlocal modifiable
  
  for [l:id, l:op] in items(s:active_operations)
    let l:line_num = l:op.line
    
    if l:line_num <= 0 || l:line_num > line('$')
      continue
    endif
    
    " Advance spinner frame
    let l:op.spinner_frame = (l:op.spinner_frame + 1) % len(s:spinner_frames)
    let l:spinner = s:spinner_frames[l:op.spinner_frame]
    
    " Get current line and update spinner only
    let l:current = getline(l:line_num)
    if !empty(l:current)
      let l:new_line = l:spinner . l:current[1:]
      call setline(l:line_num, l:new_line)
    endif
  endfor
  
  setlocal nomodifiable
  redraw
endfunction