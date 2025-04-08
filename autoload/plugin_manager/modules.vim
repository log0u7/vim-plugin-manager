" autoload/plugin_manager/modules.vim - Module management functions for vim-plugin-manager
" This file serves as the public API that loads specialized submodules

" Global variables for async configuration
  let g:plugin_manager_use_async = get(g:, 'plugin_manager_use_async', 1)
  let g:plugin_manager_max_async_tasks = get(g:, 'plugin_manager_max_async_tasks', 4)
  
  " Initialize async task system if available
  function! s:init_async() abort
    if plugin_manager#async#has_async() && g:plugin_manager_use_async
      call plugin_manager#tasks#set_max_parallel(g:plugin_manager_max_async_tasks)
      return 1
    endif
    throw 'PM_ERROR:async:Async operations not supported'
  endfunction
  
  " Public API wrappers that try async first, then fall back to sync
  
  " List installed plugins
  function! plugin_manager#modules#list()
    " List operation is quick, no need for async
    return plugin_manager#modules#list#all()
  endfunction
  
  " Show status of installed plugins
  function! plugin_manager#modules#status()
    try
      call s:init_async()
      return plugin_manager#modules#list_async#status()
    catch
      " Fallback to synchronous method
      return plugin_manager#modules#list#status()
    endtry
  endfunction
  
  " Show a summary of submodule changes
  function! plugin_manager#modules#summary()
    return plugin_manager#modules#list#summary()
  endfunction
  
  " Add a new plugin
  function! plugin_manager#modules#add(...)
    try
      call s:init_async()
      return call('plugin_manager#modules#add_async#plugin', a:000)
    catch
      " Fallback to synchronous method
      return call('plugin_manager#modules#add#plugin', a:000)
    endtry
  endfunction
  
  " Add a remote backup repository
  function! plugin_manager#modules#add_remote_backup(url)
    return plugin_manager#modules#backup#add_remote(a:url)
  endfunction
  
  " Remove a plugin
  function! plugin_manager#modules#remove(...)
    try
      call s:init_async()
      return call('plugin_manager#modules#remove_async#plugin', a:000)
    catch
      " Fallback to synchronous method
      return call('plugin_manager#modules#remove#plugin', a:000)
    endtry
  endfunction
  
  " Update plugins
  function! plugin_manager#modules#update(...)
    try
      call s:init_async()
      return call('plugin_manager#modules#update_async#plugins', a:000)
    catch
      " Fallback to synchronous method
      return call('plugin_manager#modules#update#plugins', a:000)
    endtry
  endfunction
  
  " Generate helptags
  function! plugin_manager#modules#generate_helptags(...)
    " Helptags generation is quick, keep it synchronous
    return call('plugin_manager#modules#helptags#generate', a:000)
  endfunction
  
  " Backup configuration
  function! plugin_manager#modules#backup()
    try
      call s:init_async()
      return plugin_manager#modules#backup_async#execute()
    catch
      " Fallback to synchronous method
      return plugin_manager#modules#backup#execute()
    endtry
  endfunction
  
  " Restore all plugins from .gitmodules
  function! plugin_manager#modules#restore()
    try
      call s:init_async()
      return plugin_manager#modules#backup_async#restore()
    catch
      " Fallback to synchronous method
      return plugin_manager#modules#backup#restore()
    endtry
  endfunction
  
  " Reload a specific plugin or all Vim configuration
  function! plugin_manager#modules#reload(...)
    " Reload is primarily a Vim-internal operation, keep it synchronous
    return call('plugin_manager#modules#reload#plugin', a:000)
  endfunction
  
  " Task type constants - mirror those in tasks.vim
  let s:TYPE_SINGLE = 'single'
  let s:TYPE_SEQUENCE = 'sequence'
  let s:TYPE_PARALLEL = 'parallel'