" autoload/plugin_manager/cmd/remote.vim - Remote repository management for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.6.0

" Add a remote repository for backup
function! plugin_manager#cmd#remote#add(url) abort
  try
    call plugin_manager#core#require_vim_directory('remote')

    call plugin_manager#ui#open_header('Add remote repository:')

    let l:op_id = plugin_manager#ui#start_operation('remote', 'Checking')

    if !plugin_manager#git#repository_exists(a:url)
      call plugin_manager#ui#complete_operation(l:op_id, 'fail', 'Repository not found')
      call plugin_manager#core#throw('remote', 'REPO_NOT_FOUND', 'Repository not found: ' . a:url)
    endif

    call plugin_manager#ui#update_operation(l:op_id, 'Adding')
    call plugin_manager#git#add_remote(a:url, '')
    call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Added')

    call plugin_manager#ui#footer([plugin_manager#ui#success('Remote repository added')])
  catch
    call plugin_manager#core#handle_error(v:exception, 'remote')
  endtry
endfunction
