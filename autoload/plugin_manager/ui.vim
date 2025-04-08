" autoload/plugin_manager/ui.vim - UI functions for vim-plugin-manager

" Terminal capability detection
let s:unicode_support = has('multi_byte') && &encoding ==# 'utf-8'
let s:fancy_ui = get(g:, 'plugin_manager_fancy_ui', 1) && s:unicode_support

" UI Constants
let s:symbols = {
      \ 'tick': s:fancy_ui ? '✓' : '+',
      \ 'cross': s:fancy_ui ? '✗' : 'x',
      \ 'arrow': s:fancy_ui ? '→' : '->',
      \ 'ellipsis': s:fancy_ui ? '…' : '...',
      \ 'separator': s:fancy_ui ? '⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯' : '-------------------',
      \ 'bullet': s:fancy_ui ? '•' : '*',
      \ 'warning': s:fancy_ui ? '⚠' : '!',
      \ 'info': s:fancy_ui ? 'ℹ' : 'i',
      \ }

" Spinner frames
let s:spinner_frames = s:fancy_ui 
      \ ? ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'] 
      \ : ['|', '/', '-', '\']

" Buffer name
let s:buffer_name = 'PluginManager'  
let s:spinner_active = 0
let s:spinner_job = 0
let s:spinner_pos = [0, 0]
let s:spinner_frame = 0
let s:progress_jobs = {}

" Open the sidebar window with optimized logic and error handling
function! plugin_manager#ui#open_sidebar(lines) abort
  try
    " Check if sidebar buffer already exists
    let l:buffer_exists = bufexists(s:buffer_name)
    let l:win_id = bufwinid(s:buffer_name)
    
    if l:win_id != -1
      " Sidebar window is already open, focus it
      call win_gotoid(l:win_id)
    else
      " Create a new window on the right
      execute 'silent! rightbelow ' . g:plugin_manager_sidebar_width . 'vnew ' . s:buffer_name
      " Set the filetype to trigger ftplugin and syntax files
      set filetype=pluginmanager
    endif
    
    " Update buffer content more efficiently
    call plugin_manager#ui#update_sidebar(a:lines, 0)
  catch
    " Handle errors during sidebar creation/update
    echohl ErrorMsg
    echomsg "Error creating sidebar: " . v:exception
    echohl None
  endtry
endfunction
  
" Update the sidebar content with better performance and error handling
function! plugin_manager#ui#update_sidebar(lines, append) abort
  try
    " Find the sidebar buffer window
    let l:win_id = bufwinid(s:buffer_name)
    if l:win_id == -1
      " If the window doesn't exist, create it
      call plugin_manager#ui#open_sidebar(a:lines)
      return
    endif
    
    " Focus the sidebar window
    call win_gotoid(l:win_id)
    
    " Only change modifiable state once
    setlocal modifiable
    
    " Update content based on append flag
    if a:append && !empty(a:lines)
      " More efficient append - don't write empty lines
      if line('$') > 0 && getline('$') != ''
        call append(line('$'), '')  " Add separator line
      endif
      call append(line('$'), a:lines)
    else
      " Replace existing content more efficiently
      silent! %delete _
      if !empty(a:lines)
        call setline(1, a:lines)
      endif
    endif
    
    " Set back to non-modifiable and move cursor to top
    setlocal nomodifiable
    call cursor(1, 1)
  catch
    " Handle errors safely
    echohl ErrorMsg
    echomsg "Error updating sidebar: " . v:exception
    echohl None
    
    " Try to ensure buffer is left in a stable state
    if exists('l:win_id') && l:win_id != -1
      try
        call win_gotoid(l:win_id)
        setlocal modifiable
        if !empty(a:lines)
          call setline(1, ["UI Error:", repeat('-', 9), "", "Error updating sidebar: " . v:exception])
        endif
        setlocal nomodifiable
      catch
        " Last resort error handling
        echohl ErrorMsg
        echomsg "Critical UI error: " . v:exception
        echohl None
      endtry
    endif
  endtry
endfunction

" Start a spinner at the current cursor position
function! plugin_manager#ui#start_spinner(message) abort
  if !s:fancy_ui || s:spinner_active || !exists('*timer_start')
    " Fallback for no spinner support
    call plugin_manager#ui#update_sidebar([a:message . '...'], 1)
    return
  endif
  
  " Check if sidebar exists
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1
    call plugin_manager#ui#open_sidebar([a:message])
  else
    call plugin_manager#ui#update_sidebar([a:message], 1)
  endif
  
  " Get current cursor position for spinner
  let s:spinner_pos = [line('.'), col('.') + len(a:message)]
  let s:spinner_active = 1
  let s:spinner_frame = 0
  
  " Start timer for spinner animation
  let s:spinner_job = timer_start(80, function('s:update_spinner'), {'repeat': -1})
endfunction

" Update spinner animation
function! s:update_spinner(timer) abort
  if !s:spinner_active || bufwinid(s:buffer_name) == -1
    call timer_stop(a:timer)
    let s:spinner_active = 0
    return
  endif
  
  let l:win_id = bufwinid(s:buffer_name)
  call win_gotoid(l:win_id)
  
  setlocal modifiable
  let l:line = getline(s:spinner_pos[0])
  
  " Advance spinner frame
  let s:spinner_frame = (s:spinner_frame + 1) % len(s:spinner_frames)
  let l:spinner_char = s:spinner_frames[s:spinner_frame]
  
  " Find the right position to place the spinner
  if s:spinner_pos[1] <= len(l:line)
    let l:new_line = strpart(l:line, 0, s:spinner_pos[1]) . ' ' . l:spinner_char . 
          \ strpart(l:line, s:spinner_pos[1] + 2)
    call setline(s:spinner_pos[0], l:new_line)
  endif
  
  setlocal nomodifiable
endfunction

" Stop spinner and indicate completion status
function! plugin_manager#ui#stop_spinner(success, result_message) abort
  if !s:spinner_active
    " If no spinner was active, just append the message
    call plugin_manager#ui#update_sidebar([a:result_message], 1)
    return
  endif
  
  " Stop spinner timer
  if s:spinner_job && exists('*timer_stop')
    call timer_stop(s:spinner_job)
  endif
  
  let s:spinner_active = 0
  
  " Get the win_id of the buffer
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1
    return
  endif
  
  call win_gotoid(l:win_id)
  setlocal modifiable
  
  " Replace spinner with status symbol
  let l:line = getline(s:spinner_pos[0])
  let l:status_symbol = a:success ? s:symbols.tick : s:symbols.cross
  
  if s:spinner_pos[1] <= len(l:line)
    let l:new_line = strpart(l:line, 0, s:spinner_pos[1]) . ' ' . l:status_symbol
    call setline(s:spinner_pos[0], l:new_line)
  endif
  
  " Add the result message
  call append(s:spinner_pos[0], ['', a:result_message])
  
  setlocal nomodifiable
endfunction

" Draw a progress bar
function! plugin_manager#ui#progress_bar(current, total, width, message) abort
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1
    return
  endif
  
  call win_gotoid(l:win_id)
  setlocal modifiable
  
  " Calculate progress percentage
  let l:percent = a:current * 100 / a:total
  let l:filled_width = a:current * a:width / a:total
  
  " Create progress bar
  let l:progress_bar = ''
  if s:fancy_ui
    let l:progress_bar = repeat('█', l:filled_width) . repeat('░', a:width - l:filled_width)
  else
    let l:progress_bar = repeat('#', l:filled_width) . repeat('-', a:width - l:filled_width)
  endif
  
  " Format the line with percentage
  let l:line = printf("%s [%s] %3d%%", a:message, l:progress_bar, l:percent)
  
  " Find or create the line for this progress bar
  let l:job_id = get(a:, 'job_id', '')
  
  if !empty(l:job_id) && has_key(s:progress_jobs, l:job_id)
    let l:line_num = s:progress_jobs[l:job_id]
    call setline(l:line_num, l:line)
  else
    " Append to the end and store the line number
    call append(line('$'), l:line)
    if !empty(l:job_id)
      let s:progress_jobs[l:job_id] = line('$')
    endif
  endif
  
  setlocal nomodifiable
endfunction

" Start a new task with progress tracking
function! plugin_manager#ui#start_task(message, total_items) abort
  let l:job_id = localtime() . '_' . rand()
  
  " Initialize progress bar at 0%
  call plugin_manager#ui#update_sidebar([a:message], 1)
  call plugin_manager#ui#progress_bar(0, a:total_items, 20, a:message, {'job_id': l:job_id})
  
  return l:job_id
endfunction

" Update task progress
function! plugin_manager#ui#update_task(job_id, current, message) abort
  if !has_key(s:progress_jobs, a:job_id)
    return
  endif
  
  let l:total = s:progress_jobs[a:job_id].total
  call plugin_manager#ui#progress_bar(a:current, l:total, 20, a:message, {'job_id': a:job_id})
endfunction

" Complete a task
function! plugin_manager#ui#complete_task(job_id, success, message) abort
  if !has_key(s:progress_jobs, a:job_id)
    return
  endif
  
  let l:line_num = s:progress_jobs[a:job_id]
  let l:win_id = bufwinid(s:buffer_name)
  
  if l:win_id == -1
    return
  endif
  
  call win_gotoid(l:win_id)
  setlocal modifiable
  
  " Update the line with completion status
  let l:status_symbol = a:success ? s:symbols.tick : s:symbols.cross
  let l:line = getline(l:line_num)
  let l:line .= ' ' . l:status_symbol
  call setline(l:line_num, l:line)
  
  " Add the completion message
  call append(l:line_num, ['', a:message])
  
  " Remove from tracking
  unlet s:progress_jobs[a:job_id]
  
  setlocal nomodifiable
endfunction

" Format a message with a symbol
function! plugin_manager#ui#format_message(message, symbol_key) abort
  if has_key(s:symbols, a:symbol_key)
    return s:symbols[a:symbol_key] . ' ' . a:message
  endif
  return a:message
endfunction

" Display success message with proper formatting
function! plugin_manager#ui#success(message) abort
  return plugin_manager#ui#format_message(a:message, 'tick')
endfunction

" Display error message with proper formatting
function! plugin_manager#ui#error(message) abort
  return plugin_manager#ui#format_message(a:message, 'cross')
endfunction

" Display warning message with proper formatting
function! plugin_manager#ui#warning(message) abort
  return plugin_manager#ui#format_message(a:message, 'warning')
endfunction

" Display info message with proper formatting
function! plugin_manager#ui#info(message) abort
  return plugin_manager#ui#format_message(a:message, 'info')
endfunction

" Display error message in sidebar with consistent formatting
function! plugin_manager#ui#display_error(component, message) abort
  try
    let l:header = 'Error in ' . a:component . ':'
    let l:lines = [l:header, repeat('-', len(l:header)), '', plugin_manager#ui#error(a:message)]
    call plugin_manager#ui#open_sidebar(l:lines)
  catch
    echohl ErrorMsg
    echomsg "Failed to display error: " . a:message . " (" . v:exception . ")"
    echohl None
  endtry
endfunction

" Display usage instructions
function! plugin_manager#ui#usage()
  try
    let l:lines = [
          \ "PluginManager Commands:",
          \ "---------------------",
          \ "add <plugin_url> [options]    - Add a new plugin with options",
          \ "                                Options: {'dir':'name', 'load':'start|opt', 'branch':'branch',",
          \ "                                          'tag':'tag', 'exec':'cmd'}",
          \ "remove [plugin_name] [-f]     - Remove a plugin",
          \ "backup                        - Backup configuration",
          \ "reload [plugin]               - Reload configuration",        
          \ "list                          - List installed plugins",
          \ "status                        - Show status of submodules",
          \ "update [plugin_name|all]      - Update all plugins or a specific one",
          \ "helptags [plugin_name]        - Generate plugins helptags, optionally for a specific plugin",
          \ "summary                       - Show summary of changes",
          \ "restore                       - Reinstall all modules",
          \ "",
          \ "Sidebar Keyboard Shortcuts:",
          \ "-------------------------",
          \ "q - Close the sidebar",
          \ "l - List installed plugins",
          \ "u - Update all plugins",
          \ "h - Generate helptags for all plugins",
          \ "s - Show status of submodules",
          \ "S - Show summary of changes",        
          \ "b - Backup configuration",
          \ "r - Restore all plugins",
          \ "R - Reload configuration",
          \ "? - Show this help",
          \ "",
          \ "Configuration:",
          \ "-------------",
          \ "g:plugin_manager_vim_dir = \"" . g:plugin_manager_vim_dir . "\"",
          \ "g:plugin_manager_plugins_dir = \"" . g:plugin_manager_plugins_dir . "\"",
          \ "g:plugin_manager_vimrc_path = \"" . expand(g:plugin_manager_vimrc_path) . "\""
          \ ]
    
    call plugin_manager#ui#open_sidebar(l:lines)
  catch
    echohl ErrorMsg
    echomsg "Error displaying usage information: " . v:exception
    echohl None
  endtry
endfunction
  
" Function to toggle the Plugin Manager sidebar
function! plugin_manager#ui#toggle_sidebar()
  try
    let l:win_id = bufwinid(s:buffer_name)
    if l:win_id != -1
      " Sidebar is visible, close it
      execute 'bd ' . bufnr(s:buffer_name)
    else
      " Open sidebar with usage info
      call plugin_manager#ui#usage()
    endif
  catch
    echohl ErrorMsg
    echomsg "Error toggling sidebar: " . v:exception
    echohl None
  endtry
endfunction