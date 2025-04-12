" autoload/plugin_manager/cmd.vim - Command dispatcher for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3.5

" ------------------------------------------------------------------------------
" COMMAND ADAPTERS FOR PLUGIN API
" ------------------------------------------------------------------------------

" Add command adapter - handles legacy argument formats
function! s:cmd_add(...)
  if a:0 < 1
    call plugin_manager#core#throw('cmd', 'MISSING_ARGS', 'Missing plugin argument')
  endif
  
  let l:url = a:1
  let l:options = {}
  
  " Handle old format: add user/repo custom_name opt
  if a:0 >= 2
    if type(a:2) == v:t_dict
      " New format with options dictionary
      let l:options = a:2
    else
      " Old format with separate arguments
      let l:options = {'dir': a:2}
      
      if a:0 >= 3 && a:3 ==# 'opt'
        let l:options.load = 'opt'
      endif
    endif
  endif
  
  " Forward to API
  return plugin_manager#api#add(l:url, l:options)
endfunction

" Remove command adapter - handles force flag
function! s:cmd_remove(...)
  if a:0 < 1
    call plugin_manager#core#throw('cmd', 'MISSING_ARGS', 'Missing plugin name argument')
  endif
  
  let l:module_name = a:1
  let l:force_flag = a:0 >= 2 ? a:2 : ''
  
  " Forward to API
  return plugin_manager#api#remove(l:module_name, l:force_flag)
endfunction

" Update command adapter - handles 'all' default
function! s:cmd_update(...)
  let l:module_name = a:0 >= 1 ? a:1 : 'all'
  
  " Forward to API
  return plugin_manager#api#update(l:module_name)
endfunction

" Helptags command adapter
function! s:cmd_helptags(...)
  let l:module_name = a:0 >= 1 ? a:1 : ''
  
  " Forward to API
  return plugin_manager#api#helptags(l:module_name)
endfunction

" Reload command adapter
function! s:cmd_reload(...)
  let l:module_name = a:0 >= 1 ? a:1 : ''
  
  " Forward to API
  return plugin_manager#api#reload(l:module_name)
endfunction

" ------------------------------------------------------------------------------
" COMMAND DISPATCHER
" ------------------------------------------------------------------------------

" Main function to handle all plugin manager commands
function! plugin_manager#cmd#dispatch(...) abort
  try
    if !plugin_manager#core#ensure_vim_directory()
      return
    endif
    
    if a:0 < 1
      call plugin_manager#ui#usage()
      return
    endif
    
    let l:command = a:1
    let l:args = a:000[1:]
    
    " Route command to appropriate adapter function
    if l:command ==# 'add' && a:0 >= 2
      call call('s:cmd_add', l:args)
    elseif l:command ==# 'remove' && a:0 >= 2
      call call('s:cmd_remove', l:args)
    elseif l:command ==# 'list'
      call plugin_manager#api#list()
    elseif l:command ==# 'status'
      call plugin_manager#api#status()
    elseif l:command ==# 'update'
      call call('s:cmd_update', l:args)
    elseif l:command ==# 'summary'
      call plugin_manager#api#summary()
    elseif l:command ==# 'backup'
      call plugin_manager#api#backup()
    elseif l:command ==# 'restore'
      call plugin_manager#api#restore()
    elseif l:command ==# 'helptags'
      call call('s:cmd_helptags', l:args)
    elseif l:command ==# 'reload'
      call call('s:cmd_reload', l:args)
    else
      call plugin_manager#core#throw('cmd', 'INVALID_COMMAND', 'Unknown command: ' . l:command)
    endif
  catch
    " Handle errors properly using the standardized error handling system
    call plugin_manager#core#handle_error(v:exception, "command:" . (exists('l:command') ? l:command : 'unknown'))
  endtry
endfunction