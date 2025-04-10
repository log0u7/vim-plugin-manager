" autoload/plugin_manager/api.vim - Unified API for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4-dev

" ------------------------------------------------------------------------------
" PUBLIC API FUNCTIONS
" ------------------------------------------------------------------------------

" Add a plugin
function! plugin_manager#api#add(url, ...) abort
  let l:options = a:0 > 0 ? a:1 : {}
  return plugin_manager#cmd#add#execute(a:url, l:options)
endfunction

" Remove a plugin
function! plugin_manager#api#remove(module_name, ...) abort
  let l:force_flag = a:0 > 0 ? a:1 : ''
  return plugin_manager#cmd#remove#execute(a:module_name, l:force_flag)
endfunction

" List installed plugins
function! plugin_manager#api#list() abort
  return plugin_manager#cmd#list#all()
endfunction

" Show status of installed plugins
function! plugin_manager#api#status() abort
  return plugin_manager#cmd#status#execute()
endfunction

" Show summary of plugin changes
function! plugin_manager#api#summary() abort
  return plugin_manager#cmd#list#summary()
endfunction

" Update plugins
function! plugin_manager#api#update(...) abort
  let l:module_name = a:0 > 0 ? a:1 : 'all'
  return plugin_manager#cmd#update#execute(l:module_name)
endfunction

" Backup configuration
function! plugin_manager#api#backup() abort
  return plugin_manager#cmd#backup#execute()
endfunction

" Restore all plugins
function! plugin_manager#api#restore() abort
  return plugin_manager#cmd#restore#execute()
endfunction

" Generate helptags
function! plugin_manager#api#helptags(...) abort
  let l:create_header = 1
  let l:module_name = a:0 > 0 ? a:1 : ''
  return plugin_manager#cmd#helptags#execute(l:create_header, l:module_name)
endfunction

" Reload plugins
function! plugin_manager#api#reload(...) abort
  let l:module_name = a:0 > 0 ? a:1 : ''
  return plugin_manager#cmd#reload#execute(l:module_name)
endfunction

" Add a remote repository
function! plugin_manager#api#add_remote(url) abort
  return plugin_manager#cmd#remote#add(a:url)
endfunction

" ------------------------------------------------------------------------------
" DECLARATIVE PLUGIN CONFIGURATION API
" ------------------------------------------------------------------------------

" Begin a plugin declaration block
function! plugin_manager#api#begin() abort
  call plugin_manager#cmd#declare#begin()
endfunction

" Add a plugin declaration to the current block
function! plugin_manager#api#plugin(...) abort
  let l:url = a:0 > 0 ? a:1 : ''
  let l:options = a:0 > 1 ? a:2 : {}
  
  if a:0 > 2 && a:3 ==# 'opt'
    " Handle old format with third parameter for opt
    if type(l:options) == v:t_dict
      let l:options.load = 'opt'
    else
      let l:dir = l:options
      let l:options = {'dir': l:dir, 'load': 'opt'}
    endif
  endif
  
  call plugin_manager#cmd#declare#plugin(l:url, l:options)
endfunction

" End a plugin declaration block and process all declarations
function! plugin_manager#api#end() abort
  call plugin_manager#cmd#declare#end()
endfunction

" ------------------------------------------------------------------------------
" MAIN COMMAND DISPATCHER
" ------------------------------------------------------------------------------

" Main function to handle all plugin manager commands
function! plugin_manager#api#dispatch(...) abort
  try
    if !plugin_manager#core#ensure_vim_directory()
      return
    endif
    
    if a:0 < 1
      call plugin_manager#ui#usage()
      return
    endif
    
    let l:command = a:1
    
    " Use public API functions instead of direct command calls
    if l:command ==# 'add' && a:0 >= 2
      let l:url = a:2
      let l:options = a:0 > 2 ? a:3 : {}
      
      " Handle old style third argument
      if a:0 > 3 && a:4 ==# 'opt'
        if type(l:options) == v:t_dict
          let l:options.load = 'opt'
        else
          let l:dir = l:options
          let l:options = {'dir': l:dir, 'load': 'opt'}
        endif
      endif
      
      call plugin_manager#api#add(l:url, l:options)
    elseif l:command ==# 'remove' && a:0 >= 2
      let l:module_name = a:2
      let l:force_flag = a:0 > 2 ? a:3 : ''
      call plugin_manager#api#remove(l:module_name, l:force_flag)
    elseif l:command ==# 'list'
      call plugin_manager#api#list()
    elseif l:command ==# 'status'
      call plugin_manager#api#status()
    elseif l:command ==# 'update'
      let l:module_name = a:0 > 1 ? a:2 : 'all'
      call plugin_manager#api#update(l:module_name)
    elseif l:command ==# 'summary'
      call plugin_manager#api#summary()
    elseif l:command ==# 'backup'
      call plugin_manager#api#backup()
    elseif l:command ==# 'restore'
      call plugin_manager#api#restore()
    elseif l:command ==# 'helptags'
      let l:module_name = a:0 > 1 ? a:2 : ''
      call plugin_manager#api#helptags(l:module_name)
    elseif l:command ==# 'reload'
      let l:module_name = a:0 > 1 ? a:2 : ''
      call plugin_manager#api#reload(l:module_name)
    else
      call plugin_manager#ui#usage()
    endif
  catch
    " Handle errors properly
    call plugin_manager#core#handle_error(v:exception, "command:" . l:command)
  endtry
endfunction