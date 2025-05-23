" Enhanced autoload/plugin_manager/ui.vim - Modern UI components
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3.5

" Terminal capability detection with more accurate feature checks
let s:unicode_support = has('multi_byte') && &encoding ==# 'utf-8'
let s:color_support = &t_Co >= 256 || has('gui_running') || has('termguicolors')
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

" Enhanced spinner frames with multiple styles
let s:spinner_styles = {
      \ 'dots': s:fancy_ui ? ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'] : ['|', '/', '-', '\'],
      \ 'line': s:fancy_ui ? ['⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷'] : ['|', '/', '-', '\'],
      \ 'circle': s:fancy_ui ? ['◐', '◓', '◑', '◒'] : ['|', '/', '-', '\'],
      \ 'triangle': s:fancy_ui ? ['◢', '◣', '◤', '◥'] : ['^', '>', 'v', '<'],
      \ 'box': s:fancy_ui ? ['▌', '▀', '▐', '▄'] : ['+', '+', '+', '+'],
      \ }

" Default spinner style
let s:active_spinner_style = get(g:, 'plugin_manager_spinner_style', 'dots')
let s:spinner_frames = s:spinner_styles[s:active_spinner_style]

" Progress bar styles
let s:progress_styles = {
      \ 'block': {'filled': '█', 'empty': '░', 'start': '[', 'end': ']'},
      \ 'simple': {'filled': '#', 'empty': '-', 'start': '[', 'end': ']'},
      \ 'arrow': {'filled': '>', 'empty': ' ', 'start': '[', 'end': ']'},
      \ 'dot': {'filled': '•', 'empty': '·', 'start': '[', 'end': ']'},
      \ }

" Default progress bar style
let s:active_progress_style = get(g:, 'plugin_manager_progress_style', 'block')

" Buffer name and state
let s:buffer_name = 'PluginManager'  
let s:spinners = {}
let s:spinner_timer = 0
let s:active_tasks = {}
let s:task_id_counter = 0
let s:log_messages = []
let s:max_log_messages = get(g:, 'plugin_manager_max_log', 100)

" Initialize UI - called when the plugin loads
function! plugin_manager#ui#init() abort
  " Initialize log array
  let s:log_messages = []
  
  " Start spinner animation timer if supported
  if s:has_timers && !s:spinner_timer
    let s:spinner_timer = timer_start(80, function('s:update_all_spinners'), {'repeat': -1})
  endif
  
  " Initialize any other UI components
  call s:detect_terminal_capabilities()
endfunction

" Detect terminal capabilities for better UI
function! s:detect_terminal_capabilities() abort
  " Check color capabilities
  if &termguicolors || &t_Co >= 256
    let s:color_support = 2  " Full color support
  elseif &t_Co >= 16
    let s:color_support = 1  " Basic color support
  else
    let s:color_support = 0  " Limited color support
  endif
  
  " Adjust UI elements based on capabilities
  if !s:fancy_ui && s:color_support == 0
    " Very basic terminal, use simplest UI elements
    let s:active_progress_style = 'simple'
    let s:active_spinner_style = 'dots'
    let s:spinner_frames = s:spinner_styles[s:active_spinner_style]
  endif
endfunction

" Function to retrieve a specific UI symbol
function! plugin_manager#ui#get_symbol(symbol_key) abort
  " Check if the requested symbol exists in the symbols dictionary
  if has_key(s:symbols, a:symbol_key)
    return s:symbols[a:symbol_key]
  endif
  " Return empty string if symbol not found
  return ''
endfunction

" Open the sidebar window with optimized UI
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
  
" Update the sidebar content with better performance
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
    
    " Save view to restore cursor position
    let l:view = winsaveview()
    
    " Only change modifiable state once
    setlocal modifiable
    
    " Update content based on append flag
    if a:append && !empty(a:lines)
      " Add timestamp to log messages
      let l:timestamped_lines = []
      
      for l:line in a:lines
        " Skip empty lines
        if l:line =~ '^\s*$'
          call add(l:timestamped_lines, '')
          continue
        endif
        
        " Add timestamp for log entries
        call add(l:timestamped_lines, l:line)
        
        " Store in log history (limited size)
        call add(s:log_messages, {'time': localtime(), 'text': l:line})
        if len(s:log_messages) > s:max_log_messages
          call remove(s:log_messages, 0)
        endif
      endfor
      
      " More efficient append - don't write empty lines
      if line('$') > 0 && getline('$') != ''
        call append(line('$'), '')  " Add separator line
      endif
      call append(line('$'), l:timestamped_lines)
    else
      " Replace existing content more efficiently
      silent! %delete _
      if !empty(a:lines)
        call setline(1, a:lines)
      endif
    endif
    
    " Set back to non-modifiable and restore view
    setlocal nomodifiable
    call winrestview(l:view)
    
    " Auto-scroll to bottom if we're appending
    if a:append
      normal! G
    endif
    
    " Refresh display
    redraw
  catch
    " Handle errors safely
    echohl ErrorMsg
    echomsg "Error updating sidebar: " . v:exception
    echohl None
  endtry
endfunction

" Display a message at a specific line, optionally with auto-removal after a delay
function! plugin_manager#ui#show_message(line_number, message, ...) abort
  " Optional third parameter for seconds (if provided)
  let l:is_temporary = a:0 > 0
  let l:seconds = l:is_temporary ? a:1 : 0
  
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1
    return
  endif
  
  " Show the message
  call win_gotoid(l:win_id)
  setlocal modifiable
  call setline(a:line_number, a:message)
  setlocal nomodifiable
  
  " If seconds are specified, schedule removal of the message
  if l:is_temporary && l:seconds > 0
    let l:timer_ctx = {
          \ 'line': a:line_number,
          \ 'buffer': bufnr(s:buffer_name)
          \ }
    
    call timer_start(l:seconds * 1000, function('s:clear_temporary_message', [l:timer_ctx]))
  endif
endfunction

" Callback to clear the temporary message
function! s:clear_temporary_message(ctx, timer) abort
  " Check if buffer still exists
  if !bufexists(a:ctx.buffer)
    return
  endif
  
  " Check if window is still visible
  let l:win_id = bufwinid(a:ctx.buffer)
  if l:win_id == -1
    return
  endif
  
  " Clear the message
  call win_gotoid(l:win_id)
  
  " Make sure the line still exists
  if a:ctx.line <= line('$')
    setlocal modifiable
    call setline(a:ctx.line, '')
    setlocal nomodifiable
  endif
endfunction

" Start a new asynchronous task with modern UI
function! plugin_manager#ui#start_task(message, total_items, ...) abort
  " Generate a unique ID for this task
  let s:task_id_counter += 1
  let l:task_id = 'task_' . s:task_id_counter
  
  " Get options
  let l:opts = a:0 > 0 ? a:1 : {}
  let l:task_type = get(l:opts, 'type', 'default')
  let l:use_spinner = get(l:opts, 'spinner', 1)
  let l:show_progress = get(l:opts, 'progress', (a:total_items > 0))
  
  " Create a new task entry
  let s:active_tasks[l:task_id] = {
        \ 'id': l:task_id,
        \ 'message': a:message,
        \ 'total': a:total_items,
        \ 'current': 0,
        \ 'type': l:task_type,
        \ 'started': localtime(),
        \ 'updated': localtime(),
        \ 'completed': 0,
        \ 'spinner': l:use_spinner ? {'active': 1, 'frame': 0, 'pos': [0, 0]} : {'active': 0},
        \ 'show_progress': l:show_progress,
        \ 'status': 'running',
        \ 'line': 0,
        \ }
  
  " Display initial task state
  call plugin_manager#ui#update_sidebar([a:message], 1)
  
  " Initialize progress bar if needed
  if l:show_progress && a:total_items > 0
    call s:render_progress_bar(l:task_id, 0)
  elseif l:use_spinner
    " Initialize spinner
    call s:start_spinner_for_task(l:task_id)
  endif
  
  return l:task_id
endfunction

" Update task progress with percentage
function! plugin_manager#ui#update_task(task_id, current, ...) abort
  if !has_key(s:active_tasks, a:task_id)
    return
  endif
  
  let l:task = s:active_tasks[a:task_id]
  let l:task.current = a:current
  let l:task.updated = localtime()
  
  " Update message if provided
  if a:0 > 0 && !empty(a:1)
    let l:task.message = a:1
  endif
  
  " Update progress bar
  if l:task.show_progress && l:task.total > 0
    call s:render_progress_bar(a:task_id, a:current)
  endif
  
  " Append log message if provided
  if a:0 > 1 && !empty(a:2)
    let l:indent = '  ' . s:symbols.vertical . ' '
    call plugin_manager#ui#update_sidebar([l:indent . a:2], 1)
  endif
endfunction

" Complete a task with success/fail status
function! plugin_manager#ui#complete_task(task_id, success, message) abort
  if !has_key(s:active_tasks, a:task_id)
    return
  endif
  
  let l:task = s:active_tasks[a:task_id]
  let l:task.status = a:success ? 'success' : 'failed'
  let l:task.completed = localtime()
  
  " Get task info
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1
    return
  endif
  
  " Final progress update if needed
  if l:task.show_progress && l:task.total > 0
    " Force to 100% for successful completion
    if a:success
      call s:render_progress_bar(a:task_id, l:task.total)
    endif
  endif
  
  " Disable spinner
  if get(l:task.spinner, 'active', 0)
    let l:task.spinner.active = 0
  endif
  
  " Update UI with completion status
  let l:status_symbol = a:success ? s:symbols.tick : s:symbols.cross
  let l:elapsed = s:format_elapsed_time(l:task.completed - l:task.started)
  let l:completion_line = l:status_symbol . ' ' . a:message . ' ' . l:elapsed
  
  call plugin_manager#ui#update_sidebar(['', l:completion_line], 1)
  
  " Keep the task data for reference
  " Could eventually clean up old tasks to prevent memory bloat
endfunction

" Start a spinner at the current position for a specific task
function! s:start_spinner_for_task(task_id) abort
  if !has_key(s:active_tasks, a:task_id) || !s:has_timers
    return
  endif
  
  let l:task = s:active_tasks[a:task_id]
  let l:win_id = bufwinid(s:buffer_name)
  
  if l:win_id == -1
    return
  endif
  
  " Store current position for the spinner
  call win_gotoid(l:win_id)
  let l:line = line('$')
  let l:col = len(l:task.message) + 2  " +2 for padding
  
  let l:task.spinner.active = 1
  let l:task.spinner.frame = 0
  let l:task.spinner.pos = [l:line, l:col]
  let l:task.line = l:line
  
  " Add initial spinner frame
  call s:update_spinner(a:task_id)
endfunction

" Update all active spinners
function! s:update_all_spinners(timer) abort
  " Skip if sidebar isn't visible
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1
    return
  endif
  
  " Focus the sidebar window
  call win_gotoid(l:win_id)
  
  " Update each active spinner
  for [l:id, l:task] in items(s:active_tasks)
    if get(l:task.spinner, 'active', 0)
      call s:update_spinner(l:id)
    endif
  endfor
endfunction

" Update a specific spinner with animation
function! s:update_spinner(task_id) abort
  if !has_key(s:active_tasks, a:task_id)
    return
  endif
  
  let l:task = s:active_tasks[a:task_id]
  
  " Skip if spinner is not active
  if !get(l:task.spinner, 'active', 0)
    return
  endif
  
  " Get spinner position
  let l:line = l:task.spinner.pos[0]
  let l:col = l:task.spinner.pos[1]
  
  " Advance spinner frame
  let l:task.spinner.frame = (l:task.spinner.frame + 1) % len(s:spinner_frames)
  let l:spinner_char = s:spinner_frames[l:task.spinner.frame]
  
  " Get current line content
  let l:content = getline(l:line)
  
  " Nothing to update if line doesn't exist
  if l:line > line('$')
    return
  endif
  
  " Only update if we can modify the buffer
  setlocal modifiable
  
  " Find the right position to place the spinner
  if l:col <= len(l:content)
    " Insert spinner at position, ensuring we don't overwrite too much
    let l:prefix = strpart(l:content, 0, l:col)
    let l:suffix = strpart(l:content, l:col + 2)  " +2 for spinner width
    let l:new_line = l:prefix . ' ' . l:spinner_char . l:suffix
    call setline(l:line, l:new_line)
  else
    " Line is too short, append spinner
    let l:new_line = l:content . repeat(' ', l:col - len(l:content)) . ' ' . l:spinner_char
    call setline(l:line, l:new_line)
  endif
  
  setlocal nomodifiable
endfunction

" Start a spinner for a given message (public interface)
  function! plugin_manager#ui#start_spinner(message) abort
    " Skip if UI isn't available or timers aren't supported
    if !s:has_timers
      return 0
    endif
    
    " Generate a unique ID for this spinner
    let l:spinner_id = 'standalone_' . localtime() . '_' . rand()
    
    " Find existing line containing this message
    let l:win_id = bufwinid(s:buffer_name)
    if l:win_id == -1
      " No UI window open yet, can't show spinner
      return 0
    endif
    
    " Focus the window to examine content
    call win_gotoid(l:win_id)
    
    let l:line_num = 0
    let l:total_lines = line('$')
    
    " Try to find the line with our message
    for l:i in range(1, l:total_lines)
      if getline(l:i) =~# a:message
        let l:line_num = l:i
        break
      endif
    endfor
    
    " If line not found, can't display spinner
    if l:line_num == 0
      return 0
    endif
    
    " Create a fake task entry for compatibility with existing spinner system
    let s:active_tasks[l:spinner_id] = {
          \ 'id': l:spinner_id,
          \ 'message': a:message,
          \ 'total': 0,
          \ 'current': 0,
          \ 'type': 'standalone',
          \ 'started': localtime(),
          \ 'updated': localtime(),
          \ 'completed': 0,
          \ 'spinner': {'active': 1, 'frame': 0, 'pos': [l:line_num, len(a:message) + 1]},
          \ 'show_progress': 0,
          \ 'status': 'running',
          \ 'line': l:line_num,
          \ }
    
    " Start the spinner using existing function
    call s:start_spinner_for_task(l:spinner_id)
    
    " If spinner timer isn't running yet, start it
    if s:spinner_timer == 0
      let s:spinner_timer = timer_start(80, function('s:update_all_spinners'), {'repeat': -1})
    endif
    
    return l:spinner_id
  endfunction
  
  " Stop a standalone spinner by ID
  function! plugin_manager#ui#stop_spinner(spinner_id, success) abort
    " Check if this is a task-managed spinner
    if !has_key(s:active_tasks, a:spinner_id)
      return
    endif
    
    " Deactivate the spinner
    let s:active_tasks[a:spinner_id].spinner.active = 0
    
    " Get window
    let l:win_id = bufwinid(s:buffer_name)
    if l:win_id == -1
      return
    endif
    
    " Focus window
    call win_gotoid(l:win_id)
    setlocal modifiable
    
    " Get line info
    let l:line_num = s:active_tasks[a:spinner_id].spinner.pos[0]
    let l:pos = s:active_tasks[a:spinner_id].spinner.pos[1]
    let l:line = getline(l:line_num)
    
    " Replace spinner with success/failure symbol
    let l:symbol = a:success ? s:symbols.tick : s:symbols.cross
    if l:pos <= len(l:line)
      " Update the spinner character with the status symbol
      let l:new_line = strpart(l:line, 0, l:pos) . ' ' . l:symbol
      
      " Keep the rest of the line if it exists
      if l:pos + 2 < len(l:line)
        let l:new_line .= strpart(l:line, l:pos + 2)
      endif
      
      call setline(l:line_num, l:new_line)
    endif
    
    setlocal nomodifiable
    
    " Clean up the task
    unlet s:active_tasks[a:spinner_id]
    
    " If no more active tasks/spinners, stop the timer
    if empty(s:active_tasks) && s:spinner_timer != 0
      call timer_stop(s:spinner_timer)
      let s:spinner_timer = 0
    endif
  endfunction

" Render a progress bar for a task
function! s:render_progress_bar(task_id, current) abort
  if !has_key(s:active_tasks, a:task_id)
    return
  endif
  
  let l:task = s:active_tasks[a:task_id]
  let l:win_id = bufwinid(s:buffer_name)
  
  if l:win_id == -1
    return
  endif
  
  " Focus the window
  call win_gotoid(l:win_id)
  
  " Calculate progress values
  let l:percent = l:task.total > 0 ? (a:current * 100) / l:task.total : 0
  let l:width = 20  " Fixed width for progress bar
  let l:filled_width = l:task.total > 0 ? (a:current * l:width) / l:task.total : 0
  
  " Get progress bar style
  let l:style = s:progress_styles[s:active_progress_style]
  
  " Create progress bar
  let l:progress_bar = l:style.start
  let l:progress_bar .= repeat(l:style.filled, l:filled_width)
  let l:progress_bar .= repeat(l:style.empty, l:width - l:filled_width)
  let l:progress_bar .= l:style.end
  
  " Format the line with percentage
  let l:progress_line = printf("  %s %3d%%", l:progress_bar, l:percent)
  
  " Update or create the progress line
  if l:task.line > 0 && l:task.line < line('$')
    " Try to update existing line
    setlocal modifiable
    call setline(l:task.line + 1, l:progress_line)
    setlocal nomodifiable
  else
    " Create new progress line
    call plugin_manager#ui#update_sidebar([l:progress_line], 1)
    let l:task.line = line('$') - 1  " Remember position
  endif
endfunction

" Format elapsed time in human-readable format
function! s:format_elapsed_time(seconds) abort
  if a:seconds < 60
    return printf("(%.1fs)", a:seconds)
  elseif a:seconds < 3600
    let l:mins = a:seconds / 60
    let l:secs = a:seconds % 60
    return printf("(%dm %ds)", l:mins, l:secs)
  else
    let l:hours = a:seconds / 3600
    let l:mins = (a:seconds % 3600) / 60
    return printf("(%dh %dm)", l:hours, l:mins)
  endif
endfunction

" Show task log - displays detailed log for debugging
function! plugin_manager#ui#show_log() abort
  if empty(s:log_messages)
    call plugin_manager#ui#update_sidebar(['Log Messages:', s:symbols.separator, '', 'No log messages recorded.'], 0)
    return
  endif
  
  let l:lines = ['Log Messages:', s:symbols.separator, '']
  
  " Format each log entry with timestamp
  for l:entry in s:log_messages
    let l:time_str = strftime('%H:%M:%S', l:entry.time)
    call add(l:lines, printf('[%s] %s', l:time_str, l:entry.text))
  endfor
  
  call plugin_manager#ui#update_sidebar(l:lines, 0)
endfunction

" Create a themed header - useful for section breaks
function! plugin_manager#ui#themed_header(title) abort
  let l:title_width = strdisplaywidth(a:title)
  let l:padding = 2  " Space on each side of title
  let l:border_width = g:plugin_manager_sidebar_width - l:title_width - (l:padding * 2)
  let l:left_border = l:border_width / 2
  let l:right_border = l:border_width - l:left_border
  
  let l:header = repeat(s:symbols.horizontal, l:left_border) . 
        \ repeat(' ', l:padding) . a:title . repeat(' ', l:padding) . 
        \ repeat(s:symbols.horizontal, l:right_border)
  
  return [l:header]
endfunction

" Create a formatted box around content
function! plugin_manager#ui#box(lines, title) abort
  let l:width = g:plugin_manager_sidebar_width - 4  " Border padding
  let l:boxed = []
  
  " Top border with title
  if !empty(a:title)
    let l:title_line = s:symbols.corner . ' ' . a:title . ' ' . 
          \ repeat(s:symbols.horizontal, l:width - strdisplaywidth(' ' . a:title . ' '))
    call add(l:boxed, l:title_line)
  else
    call add(l:boxed, s:symbols.corner . repeat(s:symbols.horizontal, l:width))
  endif
  
  " Content lines with border
  for l:line in a:lines
    " Ensure line doesn't exceed width
    let l:text = strdisplaywidth(l:line) > l:width ? 
          \ strcharpart(l:line, 0, l:width - 3) . s:symbols.ellipsis : l:line
    
    " Add vertical border
    call add(l:boxed, s:symbols.vertical . ' ' . l:text . 
          \ repeat(' ', l:width - strdisplaywidth(l:text)) . ' ' . s:symbols.vertical)
  endfor
  
  " Bottom border
  call add(l:boxed, s:symbols.vertical . repeat(s:symbols.horizontal, l:width) . s:symbols.vertical)
  
  return l:boxed
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
    let l:lines = [l:header, s:symbols.separator, '', plugin_manager#ui#error(a:message)]
    call plugin_manager#ui#open_sidebar(l:lines)
  catch
    echohl ErrorMsg
    echomsg "Failed to display error: " . a:message . " (" . v:exception . ")"
    echohl None
  endtry
endfunction

" Display usage instructions with improved formatting
function! plugin_manager#ui#usage()
  try
    let l:arrow = s:symbols.arrow
    let l:bullet = s:symbols.bullet
    
    let l:lines = [
          \ "PluginManager Commands:",
          \ s:symbols.separator,
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
          \ s:symbols.separator,
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
          \ s:symbols.separator,
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

" Togle sidebar
function! plugin_manager#ui#toggle_sidebar()
  try
    let l:win_id = bufwinid(s:buffer_name)
    if l:win_id != -1
      " Sidebar is visible, hide it
      execute 'hide'
    else
      " Check if the buffer exists and is loaded
      let l:buf_id = bufnr(s:buffer_name)
      
      if l:buf_id != -1 && bufloaded(l:buf_id)
        " Reopen the existing buffer
        execute 'vertical rightbelow sbuffer ' . l:buf_id
        " Ensure proper width
        execute 'vertical resize ' . g:plugin_manager_sidebar_width
      else
        " Create new sidebar with usage info - buffer doesn't exist or isn't loaded
        call plugin_manager#ui#usage()
      endif
    endif
  catch
    echohl ErrorMsg
    echomsg "Error toggling sidebar: " . v:exception
    echohl None
  endtry
endfunction