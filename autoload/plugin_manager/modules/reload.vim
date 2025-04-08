" autoload/plugin_manager/modules/reload.vim - Functions for reloading plugins

" Reload a specific plugin or all Vim configuration
function! plugin_manager#modules#reload#plugin(...)
    try
      if !plugin_manager#utils#ensure_vim_directory()
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
      let l:error = plugin_manager#utils#is_pm_error(v:exception) 
            \ ? plugin_manager#utils#format_error(v:exception)
            \ : 'Unexpected error during reload: ' . v:exception
      
      call plugin_manager#ui#open_sidebar(['Reload Error:', repeat('-', 13), '', l:error])
    endtry
  endfunction
  
  " Helper function to reload a specific plugin
  function! s:reload_specific_plugin(header, module_name)
    call plugin_manager#ui#open_sidebar(a:header + ['Reloading plugin: ' . a:module_name . '...'])
    
    " Find the module path
    let l:module_path = s:find_plugin_path(a:module_name)
    if empty(l:module_path)
      throw 'PM_ERROR:reload:Module "' . a:module_name . '" not found'
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
  function! s:reload_all_configuration(header)
    call plugin_manager#ui#open_sidebar(a:header + ['Reloading entire Vim configuration...'])
    
    " Unload all plugins
    call plugin_manager#ui#update_sidebar(['Unloading plugins...'], 1)
    
    " Reload runtime files
    call s:reload_all_runtime_files()
    
    " Source vimrc file
    call s:source_vimrc()
    
    call plugin_manager#ui#update_sidebar(['Vim configuration reloaded successfully.', 
          \ 'Note: Some plugins may require restarting Vim for a complete reload.'], 1)
  endfunction
  
  " Helper function to find plugin path
  function! s:find_plugin_path(module_name)
    let l:grep_cmd = 'grep -A1 "path = .*' . a:module_name . '" .gitmodules | grep "path =" | cut -d "=" -f2 | tr -d " "'
    let l:module_path = system(l:grep_cmd)
    let l:module_path = substitute(l:module_path, '\n$', '', '')
    
    return l:module_path
  endfunction
  
  " Helper function to remove plugin from runtimepath
  function! s:remove_from_runtimepath(module_path)
    execute 'set rtp-=' . a:module_path
  endfunction
  
  " Helper function to add plugin to runtimepath
  function! s:add_to_runtimepath(module_path)
    execute 'set rtp+=' . a:module_path
  endfunction
  
  " Helper function to unload plugin scripts
  function! s:unload_plugin_scripts(module_path)
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
          " Attempt to clear script variables (doesn't work for all plugins)
          execute 'runtime! ' . l:rtp
        endif
      endif
    endfor
  endfunction
  
  " Helper function to reload plugin runtime files
  function! s:reload_plugin_runtime_files(module_path)
    let l:runtime_paths = split(globpath(a:module_path, '**/*.vim'), '\n')
    for l:rtp in l:runtime_paths
      if l:rtp =~ '/plugin/' || l:rtp =~ '/ftplugin/'
        execute 'runtime! ' . l:rtp
      endif
    endfor
  endfunction
  
  " Helper function to reload all runtime files
  function! s:reload_all_runtime_files()
    execute 'runtime! plugin/**/*.vim'
    execute 'runtime! ftplugin/**/*.vim'
    execute 'runtime! syntax/**/*.vim'
    execute 'runtime! indent/**/*.vim'
  endfunction
  
  " Helper function to source vimrc file
  function! s:source_vimrc()
    if filereadable(expand(g:plugin_manager_vimrc_path))
      call plugin_manager#ui#update_sidebar(['Sourcing ' . g:plugin_manager_vimrc_path . '...'], 1)
      execute 'source ' . g:plugin_manager_vimrc_path
    else
      call plugin_manager#ui#update_sidebar(['Warning: Vimrc file not found at ' . g:plugin_manager_vimrc_path], 1)
    endif
  endfunction