" autoload/plugin_manager/modules.vim - Module management functions for vim-plugin-manager
" This file serves as the public API that loads specialized submodules

" Initialize module loading
let s:plugin_dir = fnamemodify(resolve(expand('<sfile>:p')), ':h')

" Global variables for async configuration
let g:plugin_manager_use_async = get(g:, 'plugin_manager_use_async', 1)
let g:plugin_manager_max_async_tasks = get(g:, 'plugin_manager_max_async_tasks', 4)

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

" Initialize async task system if available
function! s:init_async() abort
  if plugin_manager#async#has_async() && g:plugin_manager_use_async
    call plugin_manager#tasks#set_max_parallel(g:plugin_manager_max_async_tasks)
    return 1
  endif
  return 0
endfunction

" Public API wrappers enhanced with async support

" List installed plugins
function! plugin_manager#modules#list()
  " List operation is quick, no need for async
  return plugin_manager#modules#list#all()
endfunction

" Show status of installed plugins
function! plugin_manager#modules#status()
  if !s:init_async()
    " Fallback to synchronous method
    return plugin_manager#modules#list#status()
  endif
  
  " Create async task for status
  function! s:status_task() abort
    return 'git submodule foreach --recursive "git fetch -q origin 2>/dev/null || true"'
  endfunction
  
  function! s:on_status_complete(task_id, success, result, status) abort
    " Call the normal status function after fetching updates
    call plugin_manager#modules#list#status()
  endfunction
  
  " Create and start task
  let l:task_options = {
        \ 'name': 'Fetching plugin status',
        \ 'commands': function('s:status_task'),
        \ 'on_complete': function('s:on_status_complete'),
        \ 'use_async': 1,
        \ }
  
  let l:task_id = plugin_manager#tasks#create(s:TYPE_SINGLE, l:task_options)
  call plugin_manager#tasks#start(l:task_id)
  
  " Display initial status message while fetching
  let l:header = 'Submodule Status:'
  let l:lines = [l:header, repeat('-', len(l:header)), '', 'Fetching latest status information asynchronously...']
  call plugin_manager#ui#open_sidebar(l:lines)
  
  return l:task_id
endfunction

" Show a summary of submodule changes
function! plugin_manager#modules#summary()
  return plugin_manager#modules#list#summary()
endfunction

" Add a new plugin with async support
function! plugin_manager#modules#add(...)
  " Check if we have at least a URL/plugin name
  if a:0 < 1
    throw 'PM_ERROR:modules:Missing plugin argument'
  endif
  
  " Extract plugin URL and options
  let l:plugin_url = a:1
  let l:options = a:0 >= 2 ? a:2 : {}
  
  " If not an async-capable Vim or async disabled, fall back to synchronous method
  if !s:init_async()
    return call('plugin_manager#modules#add#plugin', a:000)
  endif
  
  " Create add task
  function! s:on_add_complete(task_id, success, result, status) abort
    if a:success
      let l:plugin_name = fnamemodify(split(l:plugin_url, '/')[-1], ':r')
      " Generate helptags after successful add
      call plugin_manager#modules#generate_helptags(1, l:plugin_name)
    endif
  endfunction
  
  " Create async task options
  let l:task_options = {
        \ 'name': 'Adding plugin: ' . l:plugin_url,
        \ 'on_complete': function('s:on_add_complete', [l:plugin_url]),
        \ }
  
  " Call through to module but pass async task options 
  return plugin_manager#modules#add#plugin_async(l:plugin_url, l:options, l:task_options)
endfunction

" Add a remote backup repository
function! plugin_manager#modules#add_remote_backup(url)
  return plugin_manager#modules#backup#add_remote(a:url)
endfunction

" Remove a plugin with async support
function! plugin_manager#modules#remove(...)
  " Check if we have at least a plugin name
  if a:0 < 1
    throw 'PM_ERROR:modules:Missing plugin name argument'
  endif
  
  " Extract parameters
  let l:plugin_name = a:1
  let l:force_flag = a:0 >= 2 ? a:2 : ''
  
  " If not an async-capable Vim or async disabled, fall back to synchronous method
  if !s:init_async()
    return call('plugin_manager#modules#remove#plugin', a:000)
  endif
  
  " Create remove task options
  let l:task_options = {
        \ 'name': 'Removing plugin: ' . l:plugin_name,
        \ }
        
  " Call through to module but pass async task options
  return plugin_manager#modules#remove#plugin_async(l:plugin_name, l:force_flag, l:task_options)
endfunction

" Update plugins with async support
function! plugin_manager#modules#update(...)
  " Extract parameters
  let l:specific_module = a:0 > 0 ? a:1 : 'all'
  
  " If not an async-capable Vim or async disabled, fall back to synchronous method
  if !s:init_async()
    return call('plugin_manager#modules#update#plugins', a:000)
  endif
  
  " Create update task options
  let l:task_options = {
        \ 'name': 'Updating ' . (l:specific_module == 'all' ? 'all plugins' : 'plugin: ' . l:specific_module),
        \ }
        
  " Call through to module but pass async task options
  return plugin_manager#modules#update#plugins_async(l:specific_module, l:task_options)
endfunction

" Generate helptags with async support
function! plugin_manager#modules#generate_helptags(...)
  " Extract parameters
  let l:create_header = a:0 > 0 ? a:1 : 1
  let l:specific_module = a:0 > 1 ? a:2 : ''
  
  " Helptags generation is quick, keep it synchronous
  return call('plugin_manager#modules#helptags#generate', a:000)
endfunction

" Backup configuration with async support
function! plugin_manager#modules#backup()
  " If not an async-capable Vim or async disabled, fall back to synchronous method
  if !s:init_async()
    return plugin_manager#modules#backup#execute()
  endif
  
  " Create backup task options
  let l:task_options = {
        \ 'name': 'Backing up configuration',
        \ }
        
  " Call through to module but pass async task options
  return plugin_manager#modules#backup#execute_async(l:task_options)
endfunction

" Restore all plugins from .gitmodules with async support
function! plugin_manager#modules#restore()
  " If not an async-capable Vim or async disabled, fall back to synchronous method
  if !s:init_async()
    return plugin_manager#modules#backup#restore()
  endif
  
  " Create restore task options
  let l:task_options = {
        \ 'name': 'Restoring plugins',
        \ }
        
  " Call through to module but pass async task options
  return plugin_manager#modules#backup#restore_async(l:task_options)
endfunction

" Reload a specific plugin or all Vim configuration
function! plugin_manager#modules#reload(...)
  " Extract parameters
  let l:plugin_name = a:0 > 0 ? a:1 : ''
  
  " Reload is primarily a Vim-internal operation, keep it synchronous
  return call('plugin_manager#modules#reload#plugin', a:000)
endfunction

" Task type constants - mirror those in tasks.vim
let s:TYPE_SINGLE = 'single'
let s:TYPE_SEQUENCE = 'sequence'
let s:TYPE_PARALLEL = 'parallel'