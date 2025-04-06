" UI functions for vim-plugin-manager

" Buffer name
let s:buffer_name = 'PluginManager'  

" Job status section
let s:job_progress_lines = {}
let s:job_progress_section_active = 0
let s:sidebar_update_timer = -1

" Open the sidebar window with optimized logic
function! plugin_manager#ui#open_sidebar(lines)
    " Check if sidebar buffer already exists
    let l:buffer_exists = bufexists(s:buffer_name)
    let l:win_id = bufwinid(s:buffer_name)
    
    if l:win_id != -1
      " Sidebar window is already open, focus it
      call win_gotoid(l:win_id)
    else
      " Remember the current window ID so we can return to it
      let l:current_win = win_getid()
      
      " Create a new window on the right
      execute 'silent! rightbelow ' . g:plugin_manager_sidebar_width . 'vnew ' . s:buffer_name
      " Set the filetype to trigger ftplugin and syntax files
      set filetype=pluginmanager
      
      " Return to the original window unless explicitly requested to stay in sidebar
      if get(g:, 'plugin_manager_focus_sidebar', 0) == 0
        call win_gotoid(l:current_win)
      endif
    endif
    
    " Update buffer content more efficiently
    call plugin_manager#ui#update_sidebar(a:lines, 0)
endfunction
  
" Schedule sidebar update to avoid UI blocking
function! s:do_update_sidebar(lines, append)
  " Save current window ID to restore later
  let l:current_win = win_getid()
  
  " Find the sidebar buffer window
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1
    " If the window doesn't exist, create it
    call plugin_manager#ui#open_sidebar(a:lines)
    return
  endif
  
  " Focus the sidebar window without disturbing user's window
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
  
  " Return to the original window
  call win_gotoid(l:current_win)
endfunction

" Update the sidebar content with better performance using scheduled update
function! plugin_manager#ui#update_sidebar(lines, append)
  if s:sidebar_update_timer != -1
    call timer_stop(s:sidebar_update_timer)
  endif
  
  " Schedule an immediate update (1ms timer to ensure async behavior)
  let s:sidebar_update_timer = timer_start(1, {-> s:do_update_sidebar(a:lines, a:append)})
endfunction

" Schedule job progress update to avoid UI blocking
function! s:do_update_job_progress(job_id, status_line)
  " Save current window ID to restore later
  let l:current_win = win_getid()
  
  " Store/update this job's status
  let s:job_progress_lines[a:job_id] = a:status_line
  
  " Check if the sidebar exists
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1
    " Not an error, just don't do anything if sidebar isn't open
    return
  endif
  
  " Focus the sidebar window
  call win_gotoid(l:win_id)
  setlocal modifiable
  
  " Find or create the job progress section
  let l:progress_section_start = -1
  let l:progress_section_end = -1
  
  " Look for existing section markers
  let l:line_count = line('$')
  for i in range(1, l:line_count)
    if getline(i) =~ '^Job Progress:$'
      let l:progress_section_start = i
    elseif l:progress_section_start > 0 && getline(i) =~ '^-\+$'
      if i == l:progress_section_start + 1
        " This is the line right after the header
        let l:progress_section_end = i
        break
      endif
    endif
  endfor
  
  " If no section exists yet, create it at the bottom
  if l:progress_section_start < 0
    call cursor(line('$'), 1)
    " Add some space if needed
    if getline('.') != ''
      call append(line('$'), ['', ''])
    endif
    call append(line('$'), ['Job Progress:', repeat('-', 12), ''])
    let l:progress_section_start = line('$') - 2
    let l:progress_section_end = line('$') - 1
    let s:job_progress_section_active = 1
  endif
  
  " Now find the end of the job progress section
  let l:content_end = l:progress_section_end + 1
  while l:content_end <= line('$') && getline(l:content_end) !~ '^[A-Z]'
    let l:content_end += 1
  endwhile
  let l:content_end -= 1
  
  " Delete existing progress lines
  if l:progress_section_end + 1 <= l:content_end
    execute (l:progress_section_end + 1) . ',' . l:content_end . 'delete _'
  endif
  
  " Add updated progress lines
  let l:progress_lines = []
  for [l:id, l:status] in items(s:job_progress_lines)
    call add(l:progress_lines, l:status)
  endfor
  
  " If no active jobs, add a placeholder
  if empty(l:progress_lines)
    if s:job_progress_section_active
      call add(l:progress_lines, 'No active jobs.')
    else
      " Remove the section entirely
      execute (l:progress_section_start) . ',' . (l:progress_section_end + 1) . 'delete _'
    endif
  else
    let s:job_progress_section_active = 1
  endif
  
  " Insert the progress lines
  if !empty(l:progress_lines) && s:job_progress_section_active
    call append(l:progress_section_end, l:progress_lines)
  endif
  
  " Restore modifiable state
  setlocal nomodifiable
  
  " Return to the original window
  call win_gotoid(l:current_win)
endfunction

" Update job progress indicators in the sidebar
function! plugin_manager#ui#update_job_progress(job_id, status_line)
  " Schedule job progress update (1ms timer to ensure async behavior)
  call timer_start(1, {-> s:do_update_job_progress(a:job_id, a:status_line)})
endfunction

" Schedule clear job progress to avoid UI blocking
function! s:do_clear_job_progress()
  " Save current window ID to restore later
  let l:current_win = win_getid()
  
  let s:job_progress_lines = {}
  let s:job_progress_section_active = 0
  
  " Check if the sidebar exists
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1
    return
  endif
  
  " Focus the sidebar window
  call win_gotoid(l:win_id)
  setlocal modifiable
  
  " Find the job progress section
  let l:progress_section_start = -1
  let l:progress_section_end = -1
  
  " Look for existing section markers
  let l:line_count = line('$')
  for i in range(1, l:line_count)
    if getline(i) =~ '^Job Progress:$'
      let l:progress_section_start = i
    elseif l:progress_section_start > 0 && getline(i) =~ '^-\+$'
      if i == l:progress_section_start + 1
        " This is the line right after the header
        let l:progress_section_end = i
        break
      endif
    endif
  endfor
  
  " If section exists, remove it
  if l:progress_section_start > 0
    " Find the end of the job progress section
    let l:content_end = l:progress_section_end + 1
    while l:content_end <= line('$') && getline(l:content_end) !~ '^[A-Z]'
      let l:content_end += 1
    endwhile
    let l:content_end -= 1
    
    " Delete the entire section
    execute l:progress_section_start . ',' . l:content_end . 'delete _'
  endif
  
  " Restore modifiable state
  setlocal nomodifiable
  
  " Return to the original window
  call win_gotoid(l:current_win)
endfunction

" Clear the job progress section
function! plugin_manager#ui#clear_job_progress()
  " Schedule clear job progress (1ms timer to ensure async behavior)
  call timer_start(1, {-> s:do_clear_job_progress()})
endfunction

" Display a progress bar in the sidebar
function! plugin_manager#ui#show_progress_bar(percent, msg)
  " Calculate progress bar width (50% of sidebar width)
  let l:bar_width = g:plugin_manager_sidebar_width / 2
  
  " Calculate filled portion
  let l:filled_width = float2nr(l:bar_width * (a:percent / 100.0))
  
  " Create progress bar string
  let l:progress_bar = '[' . repeat('=', l:filled_width) . repeat(' ', l:bar_width - l:filled_width) . ']'
  
  " Format percentage display
  let l:percent_str = printf("%3d%%", float2nr(a:percent))
  
  " Create complete progress line
  let l:progress_line = l:progress_bar . ' ' . l:percent_str . ' ' . a:msg
  
  " Update the sidebar with the progress
  call plugin_manager#ui#update_sidebar([l:progress_line], 1)
endfunction
  
" Display usage instructions
function! plugin_manager#ui#usage()
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
  
  " Set focus mode for welcome screen
  let l:old_focus_mode = get(g:, 'plugin_manager_focus_sidebar', 0)
  let g:plugin_manager_focus_sidebar = 1
  
  call plugin_manager#ui#open_sidebar(l:lines)
  
  " Restore focus setting
  let g:plugin_manager_focus_sidebar = l:old_focus_mode
endfunction
  
" Function to toggle the Plugin Manager sidebar
function! plugin_manager#ui#toggle_sidebar()
   let l:win_id = bufwinid(s:buffer_name)
   if l:win_id != -1
     " Sidebar is visible, close it
     execute 'bd ' . bufnr(s:buffer_name)
   else
     " Open sidebar with usage info
     call plugin_manager#ui#usage()
   endif
endfunction