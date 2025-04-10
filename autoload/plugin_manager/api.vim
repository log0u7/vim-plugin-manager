" autoload/plugin_manager/api.vim - Unified API for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3.4

" ------------------------------------------------------------------------------
" PUBLIC API FUNCTIONS
" ------------------------------------------------------------------------------

" Add a plugin
function! plugin_manager#api#add(url, options) abort
  return plugin_manager#cmd#add#execute(a:url, a:options)
endfunction

" Remove a plugin
function! plugin_manager#api#remove(module_name, force_flag) abort
  return plugin_manager#cmd#remove#execute(a:module_name, a:force_flag)
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
function! plugin_manager#api#update(module_name) abort
  return plugin_manager#cmd#update#execute(a:module_name)
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
function! plugin_manager#api#helptags(module_name) abort
  return plugin_manager#cmd#helptags#execute(1, a:module_name)
endfunction

" Reload plugins
function! plugin_manager#api#reload(module_name) abort
  return plugin_manager#cmd#reload#execute(a:module_name)
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
function! plugin_manager#api#plugin(url, options) abort
  call plugin_manager#cmd#declare#plugin(a:url, a:options)
endfunction

" End a plugin declaration block and process all declarations
function! plugin_manager#api#end() abort
  call plugin_manager#cmd#declare#end()
endfunction