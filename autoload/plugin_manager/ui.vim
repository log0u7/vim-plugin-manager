" autoload/plugin_manager/ui.vim - UI functions for vim-plugin-manager

" Buffer name
let s:buffer_name = 'PluginManager'  

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