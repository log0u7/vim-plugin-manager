" autoload/plugin_manager/cmd/restore.vim - Simplified restore command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.6.0

" Restore all plugins from .gitmodules
function! plugin_manager#cmd#restore#execute() abort
  try
    call plugin_manager#core#require_vim_directory('restore')
    
    call plugin_manager#ui#open_header('Restoring plugins:')

    if !plugin_manager#core#file_exists('.gitmodules')
      call plugin_manager#core#throw('restore', 'GITMODULES_NOT_FOUND', '.gitmodules file not found')
    endif

    let l:op_id = plugin_manager#ui#start_operation('submodules', 'Initializing')
    call plugin_manager#git#execute('git submodule init', '', 0, 0)
    call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Initialized')

    let l:op_id = plugin_manager#ui#start_operation('plugins', 'Restoring')
    call plugin_manager#git#execute('git submodule update --init --recursive', '', 0, 0)
    call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Restored')

    let l:op_id = plugin_manager#ui#start_operation('sync', 'Syncing')
    call plugin_manager#git#execute('git submodule sync', '', 0, 0)
    call plugin_manager#git#execute('git submodule update --init --recursive --force', '', 0, 0)
    call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Synced')

    call plugin_manager#ui#footer([plugin_manager#ui#info('Generating helptags')])
    call plugin_manager#cmd#helptags#execute(0)

    call plugin_manager#ui#footer([plugin_manager#ui#success('All plugins restored')])
  catch
    call plugin_manager#core#handle_error(v:exception, "restore")
  endtry
endfunction