" autoload/plugin_manager/ui.vim - UI functions for vim-plugin-manager with async support
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4

" Buffer name
let s:buffer_name = 'PluginManager'
let s:job_status_lines = {}  " Store line numbers for job status updates

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

      " Reset job status line tracking when appending
      let s:job_status_lines = {}
    else
      " Replace existing content more efficiently
      silent! %delete _
      if !empty(a:lines)
        call setline(1, a:lines)
      endif

      " Reset job status line tracking
      let s:job_status_lines = {}
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

" Update job status in the sidebar
function! plugin_manager#ui#update_job_status(job_data) abort
  try
    " Find the sidebar buffer window
    let l:win_id = bufwinid(s:buffer_name)
    if l:win_id == -1
      return
    endif
    
    " Remember current window
    let l:current_win = win_getid()
    
    " Focus the sidebar window
    call win_gotoid(l:win_id)
    
    " Only change modifiable state once
    setlocal modifiable
    
    " Get job info
    let l:job_id = a:job_data.id
    let l:status = a:job_data.status
    let l:title = a:job_data.title
    
    " Get status indicator
    let l:status_indicator = ''
    if l:status ==# 'running'
      let l:status_indicator = plugin_manager#jobs#get_spinner_frame() . ' '
    elseif l:status ==# 'done'
      let l:status_indicator = plugin_manager#jobs#get_success_mark() . ' '
    elseif l:status ==# 'failed'
      let l:status_indicator = plugin_manager#jobs#get_failure_mark() . ' '
    elseif l:status ==# 'stopped'
      let l:status_indicator = '⏹ '
    endif
    
    " If this is a new job, add it to the end
    if !has_key(s:job_status_lines, l:job_id)
      " Check if we should add a separator
      if line('$') > 0 && getline('$') != ''
        call append(line('$'), '')
      endif
      
      " Add job status line
      call append(line('$'), l:status_indicator . l:title)
      let s:job_status_lines[l:job_id] = line('$')
      
      " Add initial output line if running
      if l:status ==# 'running'
        call append(line('$'), '  └─ Processing...')
      endif
    else
      " Update existing job status line
      let l:line_num = s:job_status_lines[l:job_id]
      if l:line_num > 0 && l:line_num <= line('$')
        call setline(l:line_num, l:status_indicator . l:title)
        
        " Update or add output depending on status
        let l:next_line = l:line_num + 1
        if l:status ==# 'running'
          " Show the latest output line if available
          if len(a:job_data.stdout) > 0
            let l:latest_output = a:job_data.stdout[-1]
            if l:next_line <= line('$')
              call setline(l:next_line, '  └─ ' . l:latest_output)
            else
              call append(l:line_num, '  └─ ' . l:latest_output)
            endif
          elseif l:next_line > line('$') || getline(l:next_line) !~ '^\s\+└─'
            call append(l:line_num, '  └─ Processing...')
          endif
        elseif l:status ==# 'done'
          " Show completion time
          let l:duration = get(a:job_data, 'end_time', localtime()) - get(a:job_data, 'start_time', localtime())
          if l:next_line <= line('$') && getline(l:next_line) =~ '^\s\+└─'
            call setline(l:next_line, '  └─ Completed in ' . l:duration . 's')
          else
            call append(l:line_num, '  └─ Completed in ' . l:duration . 's')
          endif
          
          " If job has output and it wasn't shown yet, append it
          if !has_key(a:job_data, 'output_shown') && !empty(a:job_data.stdout)
            let l:max_lines = 5  " Maximum number of output lines to show
            let l:start_idx = max([0, len(a:job_data.stdout) - l:max_lines])
            let l:output_summary = a:job_data.stdout[l:start_idx :]
            
            " Add output summary with indentation
            let l:insert_line = l:line_num + 2
            call append(l:line_num + 1, '  └─ Output:')
            for l:output_line in l:output_summary
              call append(l:insert_line, '     ' . l:output_line)
              let l:insert_line += 1
            endfor
            
            " Mark output as shown
            let a:job_data.output_shown = 1
          endif
        elseif l:status ==# 'failed'
          " Show failure details
          let l:duration = get(a:job_data, 'end_time', localtime()) - get(a:job_data, 'start_time', localtime())
          if l:next_line <= line('$') && getline(l:next_line) =~ '^\s\+└─'
            call setline(l:next_line, '  └─ Failed after ' . l:duration . 's (code: ' . a:job_data.exit_code . ')')
          else
            call append(l:line_num, '  └─ Failed after ' . l:duration . 's (code: ' . a:job_data.exit_code . ')')
          endif
          
          " If job has error output and it wasn't shown yet, append it
          if !has_key(a:job_data, 'output_shown') && (!empty(a:job_data.stderr) || !empty(a:job_data.stdout))
            let l:max_lines = 5  " Maximum number of output lines to show
            
            " Show stderr if available, otherwise stdout
            let l:output_lines = !empty(a:job_data.stderr) ? a:job_data.stderr : a:job_data.stdout
            let l:start_idx = max([0, len(l:output_lines) - l:max_lines])
            let l:output_summary = l:output_lines[l:start_idx :]
            
            " Add output summary with indentation
            let l:insert_line = l:line_num + 2
            call append(l:line_num + 1, '  └─ Error output:')
            for l:output_line in l:output_summary
              call append(l:insert_line, '     ' . l:output_line)
              let l:insert_line += 1
            endfor
            
            " Mark output as shown
            let a:job_data.output_shown = 1
          endif
        endif
      endif
    endif
    
    " Set back to non-modifiable
    setlocal nomodifiable
    
    " Restore previous window
    if win_id2win(l:current_win) > 0
      call win_gotoid(l:current_win)
    endif
  catch
    " Handle errors safely
    echohl ErrorMsg
    echomsg "Error updating job status: " . v:exception
    echohl None
    
    " Try to ensure buffer is left in a stable state
    if exists('l:win_id') && l:win_id != -1
      try
        call win_gotoid(l:win_id)
        setlocal nomodifiable
      catch
        " Ignore errors at this point
      endtry
    endif
    
    " Restore previous window
    if exists('l:current_win') && win_id2win(l:current_win) > 0
      call win_gotoid(l:current_win)
    endif
  endtry
endfunction

" Display error message in sidebar with consistent formatting
function! plugin_manager#ui#display_error(component, message) abort
  try
    let l:header = 'Error in ' . a:component . ':'
    let l:lines = [l:header, repeat('-', len(l:header)), '', a:message]
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
          \ "g:plugin_manager_vimrc_path = \"" . expand(g:plugin_manager_vimrc_path) . "\"",
          \ "",
          \ "Async Jobs Support: " . (plugin_manager#jobs#init() ? "Yes" : "No"),
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

" Display progress bar (if supported)
function! plugin_manager#ui#progress_bar(current, total, width) abort
  " Fall back to simpler output if terminal doesn't support Unicode
  if !plugin_manager#jobs#init() || !s:use_unicode
    let l:percent = a:current * 100 / (a:total > 0 ? a:total : 1)
    return printf("[%3d%%] %d/%d", l:percent, a:current, a:total)
  endif
  
  " Unicode progress bar
  let l:percent = a:current * 100 / (a:total > 0 ? a:total : 1)
  let l:completed_width = a:current * a:width / (a:total > 0 ? a:total : 1)
  
  let l:bar = ""
  let l:bar .= repeat('█', l:completed_width)
  let l:bar .= repeat('░', a:width - l:completed_width)
  
  return printf("[%s] %3d%% (%d/%d)", l:bar, l:percent, a:current, a:total)
endfunction