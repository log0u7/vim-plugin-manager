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

    " Each git#execute call uses throw_on_error=1 (last argument) so that
    " a failing git command surfaces as a structured PM_ERROR caught below,
    " rather than silently reporting 'ok' to the user.
    let l:op_id = plugin_manager#ui#start_operation('submodules', 'Initializing')
    call plugin_manager#git#execute('git submodule init', '', 0, 1)
    call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Initialized')

    let l:op_id = plugin_manager#ui#start_operation('plugins', 'Restoring')
    call plugin_manager#git#execute('git submodule update --init --recursive', '', 0, 1)
    call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Restored')

    let l:op_id = plugin_manager#ui#start_operation('sync', 'Syncing')
    call plugin_manager#git#execute('git submodule sync', '', 0, 1)
    call plugin_manager#git#execute('git submodule update --init --recursive --force', '', 0, 1)
    call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Synced')

    call plugin_manager#ui#footer([plugin_manager#ui#info('Generating helptags')])
    call plugin_manager#cmd#helptags#execute(0)

    call plugin_manager#ui#footer([plugin_manager#ui#success('All plugins restored')])
  catch
    call plugin_manager#core#handle_error(v:exception, 'restore')
  endtry
endfunction