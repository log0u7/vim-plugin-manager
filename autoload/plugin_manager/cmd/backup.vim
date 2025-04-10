" autoload/plugin_manager/cmd/backup.vim - Backup command for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: refacto2 v1.3.3 d4f8fda

" Backup configuration to remote repositories
function! plugin_manager#cmd#backup#execute() abort
    try
      if !plugin_manager#core#ensure_vim_directory()
        throw 'PM_ERROR:backup:Not in Vim configuration directory'
      endif
      
      let l:header = ['Backup Configuration:', '--------------------', '', 'Starting backup process...']
      call plugin_manager#ui#open_sidebar(l:header)
      
      " Copy vimrc file if needed
      call s:backup_vimrc_file()
      
      " Commit local changes if any
      call s:commit_local_changes()
      
      " Push to remote repositories
      call s:push_to_remotes()
  
      call plugin_manager#ui#update_sidebar(['Backup completed successfully.'], 1)
    catch
      call plugin_manager#core#handle_error(v:exception, "backup")
    endtry
  endfunction
  
  " Helper function to backup vimrc file
  function! s:backup_vimrc_file() abort
    " Check if vimrc or init.vim exists in the vim directory
    let l:vim_dir = plugin_manager#core#get_config('vim_dir', '')
    let l:vimrc_path = plugin_manager#core#get_config('vimrc_path', '')
    let l:vimrc_basename = fnamemodify(l:vimrc_path, ':t')
    let l:local_vimrc = l:vim_dir . '/' . l:vimrc_basename
    
    " If vimrc doesn't exist in the vim directory or isn't a symlink, copy it
    if !plugin_manager#core#file_exists(l:local_vimrc) || 
          \ (!has('win32') && !has('win64') && getftype(l:local_vimrc) != 'link')
      if plugin_manager#core#file_exists(l:vimrc_path)
        call plugin_manager#ui#update_sidebar(['Copying ' . l:vimrc_basename . ' file to vim directory...'], 1)
        
        " Use git module to execute copy command
        let l:copy_cmd = 'cp ' . shellescape(l:vimrc_path) . ' ' . shellescape(l:local_vimrc)
        let l:result = plugin_manager#git#execute(l:copy_cmd, '', 0, 1)
        
        call plugin_manager#ui#update_sidebar([l:vimrc_basename . ' file copied successfully.'], 1)
        
        " Add the copied file to git
        call plugin_manager#git#execute('git add ' . shellescape(l:local_vimrc), '', 1, 0)
      else
        call plugin_manager#ui#update_sidebar(['Warning: ' . l:vimrc_basename . ' file not found at ' . l:vimrc_path], 1)
      endif
    else
      call plugin_manager#ui#update_sidebar([l:vimrc_basename . ' file already in vim directory.'], 1)
    endif
  endfunction
  
  " Helper function to commit local changes
  function! s:commit_local_changes() abort
    " Check if there are changes to commit
    let l:status = plugin_manager#git#execute('git status -s', '', 0, 0)
    
    if !empty(l:status.output)
      call plugin_manager#ui#update_sidebar(['Committing local changes...'], 1)
      let l:result = plugin_manager#git#execute('git commit -am "Automatic backup"', '', 1, 0)
      
      if l:result.success
        call plugin_manager#ui#update_sidebar(['Changes committed successfully.'], 1)
      else
        call plugin_manager#ui#update_sidebar(['Warning: Could not commit changes: ' . l:result.output], 1)
      endif
    else
      call plugin_manager#ui#update_sidebar(['No local changes to commit.'], 1)
    endif
  endfunction
  
  " Helper function to push to remote repositories
  function! s:push_to_remotes() abort
    call plugin_manager#ui#update_sidebar(['Pushing changes to remote repositories...'], 1)
    
    " Check if any remotes exist
    let l:remotes = plugin_manager#git#execute('git remote', '', 0, 0)
    if empty(l:remotes.output)
      throw 'PM_ERROR:backup:No remote repositories configured. Use PluginManagerRemote to add a remote repository.'
    endif
    
    let l:result = plugin_manager#git#execute('git push --all', '', 1, 1)
    
    if l:result.success
      call plugin_manager#ui#update_sidebar(['Successfully pushed to all remote repositories.'], 1)
    endif
  endfunction