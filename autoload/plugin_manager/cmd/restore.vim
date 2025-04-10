" autoload/plugin_manager/cmd/restore.vim - Restore command for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3.4

" Restore all plugins from .gitmodules
function! plugin_manager#cmd#restore#execute() abort
    try
      if !plugin_manager#core#ensure_vim_directory()
        throw 'PM_ERROR:restore:Not in Vim configuration directory'
      endif
      
      let l:header = ['Restore Plugins:', '---------------', '', 'Starting plugin restoration...']
      call plugin_manager#ui#open_sidebar(l:header)
      
      call s:check_gitmodules_exists()
      call s:restore_all_plugins()
      call s:generate_helptags()
      
    catch
      call plugin_manager#core#handle_error(v:exception, "restore")
    endtry
  endfunction
  
  " Helper function to check if .gitmodules exists
  function! s:check_gitmodules_exists() abort
    if !plugin_manager#core#file_exists('.gitmodules')
      throw 'PM_ERROR:restore:.gitmodules file not found'
    endif
    
    call plugin_manager#ui#update_sidebar(['Found .gitmodules file.'], 1)
  endfunction
  
  " Helper function to restore all plugins
  function! s:restore_all_plugins() abort
    " Use git module to handle restoration
    call plugin_manager#ui#update_sidebar(['Restoring all plugins...'], 1)
    
    " Initialize submodules
    call plugin_manager#ui#update_sidebar(['Initializing submodules...'], 1)
    call plugin_manager#git#execute('git submodule init', '', 1, 1)
    
    " Update submodules
    call plugin_manager#ui#update_sidebar(['Fetching and updating all submodules...'], 1)
    let l:result = plugin_manager#git#execute('git submodule update --init --recursive', '', 1, 1)
    
    " Final sync and update to ensure everything is at the correct state
    call plugin_manager#ui#update_sidebar(['Ensuring all submodules are at the correct commit...'], 1)
    call plugin_manager#git#execute('git submodule sync', '', 1, 0)
    call plugin_manager#git#execute('git submodule update --init --recursive --force', '', 1, 1)
    
    call plugin_manager#ui#update_sidebar(['All plugins have been restored successfully.'], 1)
  endfunction
  
  " Helper function to generate helptags for all plugins
  function! s:generate_helptags() abort
    call plugin_manager#ui#update_sidebar(['Generating helptags for all plugins:'], 1)
    
    " Use the helptags module
    call plugin_manager#cmd#helptags#execute(0)
  endfunction