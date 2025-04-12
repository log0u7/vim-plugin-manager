" autoload/plugin_manager/cmd/reload.vim - Reload command for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3.5

" Reload a specific plugin or all Vim configuration
function! plugin_manager#cmd#reload#execute(...) abort
    try
      if !plugin_manager#core#ensure_vim_directory()
        throw 'PM_ERROR:reload:Not in Vim configuration directory'
      endif
      
      let l:header = ['Reload:', '-------', '']
      
      " Check if a specific module was specified
      let l:specific_module = a:0 > 0 ? a:1 : ''
      
      if !empty(l:specific_module)
        call s:reload_specific_plugin(l:header, l:specific_module)
      else
        call s:reload_all_configuration(l:header)
      endif
    catch
      call plugin_manager#core#handle_error(v:exception, "reload")
    endtry
  endfunction
  
  " Helper function to reload a specific plugin
  function! s:reload_specific_plugin(header, module_name) abort
    call plugin_manager#ui#open_sidebar(a:header + ['Reloading plugin: ' . a:module_name . '...'])
    
    " Find the module
    let l:module_info = plugin_manager#git#find_module(a:module_name)
    if empty(l:module_info)
      throw 'PM_ERROR:reload:Module "' . a:module_name . '" not found'
    endif
    
    let l:module = l:module_info.module
    let l:module_path = l:module.path
    
    " Check if directory exists
    if !isdirectory(l:module_path)
      throw 'PM_ERROR:reload:Module directory "' . l:module_path . '" not found. Try running "PluginManager restore"'
    endif
    
    " Remove plugin from runtimepath
    call s:remove_from_runtimepath(l:module_path)
    
    " Unload plugin scripts
    call s:unload_plugin_scripts(l:module_path)
    
    " Add back to runtimepath
    call s:add_to_runtimepath(l:module_path)
    
    " Reload plugin runtime files
    call s:reload_plugin_runtime_files(l:module_path)
    
    call plugin_manager#ui#update_sidebar(['Plugin "' . a:module_name . '" reloaded successfully.', 
          \ 'Note: Some plugins may require restarting Vim for a complete reload.'], 1)
  endfunction
  
  " Helper function to reload all Vim configuration
  function! s:reload_all_configuration(header) abort
    call plugin_manager#ui#open_sidebar(a:header + ['Reloading entire Vim configuration...'])
    
    " Reload runtime files
    call s:reload_all_runtime_files()
    
    " Source vimrc file
    call s:source_vimrc()
    
    call plugin_manager#ui#update_sidebar(['Vim configuration reloaded successfully.', 
          \ 'Note: Some plugins may require restarting Vim for a complete reload.'], 1)
  endfunction
  
  " Helper function to remove plugin from runtimepath
  function! s:remove_from_runtimepath(module_path) abort
    execute 'set rtp-=' . a:module_path
    
    " Also remove after directory if it exists
    let l:after_path = a:module_path . '/after'
    if isdirectory(l:after_path)
      execute 'set rtp-=' . l:after_path
    endif
  endfunction
  
  " Helper function to add plugin to runtimepath
  function! s:add_to_runtimepath(module_path) abort
    execute 'set rtp+=' . a:module_path
    
    " Also add after directory if it exists
    let l:after_path = a:module_path . '/after'
    if isdirectory(l:after_path)
      execute 'set rtp+=' . l:after_path
    endif
  endfunction
  
  " Helper function to unload plugin scripts
  function! s:unload_plugin_scripts(module_path) abort
    let l:runtime_paths = split(globpath(a:module_path, '**/*.vim'), '\n')
    for l:rtp in l:runtime_paths
      " Only try to clear files that are in autoload, plugin, or ftplugin directories
      if l:rtp =~ '/autoload/' || l:rtp =~ '/plugin/' || l:rtp =~ '/ftplugin/'
        " Get the script ID if loaded
        let l:sid = 0
        redir => l:scriptnames
        silent scriptnames
        redir END
        
        for l:line in split(l:scriptnames, '\n')
          if l:line =~ l:rtp
            let l:sid = str2nr(matchstr(l:line, '^\s*\zs\d\+\ze:'))
            break
          endif
        endfor
        
        " If script is loaded, try to unload it
        if l:sid > 0
          " There's no direct way to unload a script in Vim, but we can
          " try to reset script-local variables by sourcing it again
          call plugin_manager#ui#update_sidebar(['Unloading script: ' . l:rtp], 1)
        endif
      endif
    endfor
  endfunction
  
  " Helper function to reload plugin runtime files
  function! s:reload_plugin_runtime_files(module_path) abort
    let l:runtime_paths = split(globpath(a:module_path, '**/*.vim'), '\n')
    for l:rtp in l:runtime_paths
      if l:rtp =~ '/plugin/' || l:rtp =~ '/ftplugin/'
        call plugin_manager#ui#update_sidebar(['Reloading: ' . l:rtp], 1)
        execute 'runtime! ' . l:rtp
      endif
    endfor
  endfunction
  
  " Helper function to reload all runtime files
  function! s:reload_all_runtime_files() abort
    call plugin_manager#ui#update_sidebar(['Reloading plugin runtime files...'], 1)
    execute 'runtime! plugin/**/*.vim'
    
    call plugin_manager#ui#update_sidebar(['Reloading filetype plugin files...'], 1)
    execute 'runtime! ftplugin/**/*.vim'
    
    call plugin_manager#ui#update_sidebar(['Reloading syntax files...'], 1)
    execute 'runtime! syntax/**/*.vim'
    
    call plugin_manager#ui#update_sidebar(['Reloading indent files...'], 1)
    execute 'runtime! indent/**/*.vim'
  endfunction
  
  " Helper function to source vimrc file
  function! s:source_vimrc() abort
    let l:vimrc_path = expand(plugin_manager#core#get_config('vimrc_path', ''))
    
    if !empty(l:vimrc_path) && filereadable(l:vimrc_path)
      call plugin_manager#ui#update_sidebar(['Sourcing ' . l:vimrc_path . '...'], 1)
      execute 'source ' . fnameescape(l:vimrc_path)
    else
      call plugin_manager#ui#update_sidebar(['Warning: Vimrc file not found at ' . l:vimrc_path], 1)
    endif
  endfunction