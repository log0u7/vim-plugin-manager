" autoload/plugin_manager/modules.vim - Module management functions for vim-plugin-manager
" This file serves as the public API that loads specialized submodules

" Initialize module loading
let s:plugin_dir = fnamemodify(resolve(expand('<sfile>:p')), ':h')

" Load all submodules
function! s:load_submodule(name) abort
  execute 'runtime! autoload/plugin_manager/modules/' . a:name . '.vim'
endfunction

call s:load_submodule('list')
call s:load_submodule('add')
call s:load_submodule('remove')
call s:load_submodule('update')
call s:load_submodule('backup')
call s:load_submodule('helptags')
call s:load_submodule('reload')

" Public API wrappers for backward compatibility

" List installed plugins
function! plugin_manager#modules#list()
  return plugin_manager#modules#list#all()
endfunction

" Show status of installed plugins
function! plugin_manager#modules#status()
  return plugin_manager#modules#list#status()
endfunction

" Show a summary of submodule changes
function! plugin_manager#modules#summary()
  return plugin_manager#modules#list#summary()
endfunction

" Add a new plugin
function! plugin_manager#modules#add(...)
  return call('plugin_manager#modules#add#plugin', a:000)
endfunction

" Add a remote backup repository
function! plugin_manager#modules#add_remote_backup(url)
  return plugin_manager#modules#backup#add_remote(a:url)
endfunction

" Remove a plugin
function! plugin_manager#modules#remove(...)
  return call('plugin_manager#modules#remove#plugin', a:000)
endfunction

" Update plugins
function! plugin_manager#modules#update(...)
  return call('plugin_manager#modules#update#plugins', a:000)
endfunction

" Generate helptags
function! plugin_manager#modules#generate_helptags(...)
  return call('plugin_manager#modules#helptags#generate', a:000)
endfunction

" Backup configuration to remote repositories
function! plugin_manager#modules#backup()
  return plugin_manager#modules#backup#execute()
endfunction

" Restore all plugins from .gitmodules
function! plugin_manager#modules#restore()
  return plugin_manager#modules#backup#restore()
endfunction

" Reload a specific plugin or all Vim configuration
function! plugin_manager#modules#reload(...)
  return call('plugin_manager#modules#reload#plugin', a:000)
endfunction