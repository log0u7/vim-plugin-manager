" autoload/plugin_manager/cmd/remote.vim - Remote repository management for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4-dev

" Add a remote repository for backup
    function! plugin_manager#cmd#remote#add(url) abort
        try
          if !plugin_manager#core#ensure_vim_directory()
            throw 'PM_ERROR:remote:Not in Vim configuration directory'
          endif
          
          let l:header = ['Add Remote Repository:', '---------------------', '', 'Adding remote repository: ' . a:url . '...']
          call plugin_manager#ui#open_sidebar(l:header)
          
          " Check if the repository exists
          if !plugin_manager#git#repository_exists(a:url)
            throw 'PM_ERROR:remote:Repository not found: ' . a:url
          endif
          
          " Add the remote using git module
          call plugin_manager#git#add_remote(a:url, '')
          
          call plugin_manager#ui#update_sidebar(['Remote repository added successfully.'], 1)
        catch
          call plugin_manager#core#handle_error(v:exception, "add_remote")
        endtry
      endfunction