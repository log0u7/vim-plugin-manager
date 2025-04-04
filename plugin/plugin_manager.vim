" vim-plugin-manager.vim - Manage Vim plugins with git submodules
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3

if exists('g:loaded_plugin_manager') || &cp
  finish
endif
let g:loaded_plugin_manager = 1

" Load initialization and configuration
runtime autoload/plugin_manager/init.vim

" Define commands
command! -nargs=* PluginManager call plugin_manager#main(<f-args>)
command! -nargs=1 PluginManagerRemote call plugin_manager#modules#add_remote_backup(<f-args>)
command! PluginManagerToggle call plugin_manager#ui#toggle_sidebar()

" Main function to handle PluginManager commands
function! plugin_manager#main(...)
  if a:0 < 1
    call plugin_manager#ui#usage()
    return
  endif
  
  let l:command = a:1
  
  if l:command == "add" && a:0 >= 2
    call plugin_manager#modules#add(a:2, get(a:, 3, ""), get(a:, 4, ""))
  elseif l:command == "remove" && a:0 >= 2
    call plugin_manager#modules#remove(a:2, get(a:, 3, ""))
  elseif l:command == "list"
    call plugin_manager#modules#list()
  elseif l:command == "status"
    call plugin_manager#modules#status()
  elseif l:command == "update"
    " Pass the optional module name if provided
    if a:0 >= 2
      call plugin_manager#modules#update(a:2)
    else
      call plugin_manager#modules#update('all')
    endif
  elseif l:command == "summary"
    call plugin_manager#modules#summary()
  elseif l:command == "backup"
    call plugin_manager#modules#backup()
  elseif l:command == "restore"
    call plugin_manager#modules#restore()
  elseif l:command == "helptags"
    " Pass the optional module name if provided
    if a:0 >= 2
      call plugin_manager#modules#generate_helptags(1, a:2)
    else 
      call plugin_manager#modules#generate_helptags()
    endif
  elseif l:command == "reload"
    " Pass the optional module name if provided
    if a:0 >= 2
      call plugin_manager#modules#reload(a:2)
    else
      call plugin_manager#modules#reload()
    endif
  else
    call plugin_manager#ui#usage()
  endif
endfunction