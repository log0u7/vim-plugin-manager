" autoload/plugin_manager/modules/backup.vim - Functions for backup and restore

" Backup configuration to remote repositories
function! plugin_manager#modules#backup#execute()
    try
      if !plugin_manager#utils#ensure_vim_directory()
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
      
    catch
      let l:error = plugin_manager#utils#is_pm_error(v:exception) 
            \ ? plugin_manager#utils#format_error(v:exception)
            \ : 'Unexpected error during backup: ' . v:exception
      
      call plugin_manager#ui#update_sidebar(['Error: ' . l:error], 1)
    endtry
  endfunction
  
  " Helper function to backup vimrc file
  function! s:backup_vimrc_file()
    " Check if vimrc or init.vim exists in the vim directory
    let l:vimrc_basename = fnamemodify(g:plugin_manager_vimrc_path, ':t')
    let l:local_vimrc = g:plugin_manager_vim_dir . '/' . l:vimrc_basename
    
    " If vimrc doesn't exist in the vim directory or isn't a symlink, copy it
    if !filereadable(l:local_vimrc) || (!has('win32') && !has('win64') && getftype(l:local_vimrc) != 'link')
      if filereadable(g:plugin_manager_vimrc_path)
        call plugin_manager#ui#update_sidebar(['Copying ' . l:vimrc_basename . ' file to vim directory...'], 1)
        
        " Create a backup copy of the vimrc file
        let l:copy_cmd = 'cp "' . g:plugin_manager_vimrc_path . '" "' . l:local_vimrc . '"'
        let l:copy_result = system(l:copy_cmd)
        
        if v:shell_error != 0
          throw 'PM_ERROR:backup:Error copying vimrc file: ' . l:copy_result
        endif
        
        call plugin_manager#ui#update_sidebar([l:vimrc_basename . ' file copied successfully.'], 1)
        
        " Add the copied file to git
        let l:git_add = system('git add "' . l:local_vimrc . '"')
        if v:shell_error != 0
          call plugin_manager#ui#update_sidebar(['Warning: Could not add ' . l:vimrc_basename . ' to git: ' . l:git_add], 1)
        endif
      else
        call plugin_manager#ui#update_sidebar(['Warning: ' . l:vimrc_basename . ' file not found at ' . g:plugin_manager_vimrc_path], 1)
      endif
    endif
  endfunction
  
  " Helper function to commit local changes
  function! s:commit_local_changes()
    " Check if there are changes to commit
    let l:gitStatus = system('git status -s')
    
    if !empty(l:gitStatus)
      call plugin_manager#ui#update_sidebar(['Committing local changes...'], 1)
      let l:commitResult = system('git commit -am "Automatic backup"')
      call plugin_manager#ui#update_sidebar(split(l:commitResult, "\n"), 1)
    else
      call plugin_manager#ui#update_sidebar(['No local changes to commit.'], 1)
    endif
  endfunction
  
  " Helper function to push to remote repositories
  function! s:push_to_remotes()
    call plugin_manager#ui#update_sidebar(['Pushing changes to remote repositories...'], 1)
    
    " Check if any remotes exist
    let l:remotesExist = system('git remote')
    if empty(l:remotesExist)
      throw 'PM_ERROR:backup:No remote repositories configured. Use PluginManagerRemote to add a remote repository.'
    endif
    
    let l:pushResult = system('git push --all')
    if v:shell_error != 0
      throw 'PM_ERROR:backup:Error pushing to remote: ' . l:pushResult
    endif
    
    call plugin_manager#ui#update_sidebar(['Backup completed successfully.'], 1)
  endfunction
  
  " Add a remote backup repository
  function! plugin_manager#modules#backup#add_remote(url)
    try
      if !plugin_manager#utils#ensure_vim_directory()
        throw 'PM_ERROR:remote:Not in Vim configuration directory'
      endif
      
      let l:header = ['Add Remote Repository:', '---------------------', '', 'Adding remote repository: ' . a:url . '...']
      call plugin_manager#ui#open_sidebar(l:header)
      
      " Check if the repository exists
      if !plugin_manager#utils#repository_exists(a:url)
        throw 'PM_ERROR:remote:Repository not found: ' . a:url
      endif
      
      " Add the remote
      let l:remoteName = 'backup_' . substitute(localtime(), '^\d*\(\d\{4}\)$', '\1', '')
      let l:result = system('git remote add ' . l:remoteName . ' ' . a:url)
      
      if v:shell_error != 0
        throw 'PM_ERROR:remote:Error adding remote: ' . l:result
      endif
      
      " Add the remote as a push URL for origin
      let l:result = system('git remote set-url --add --push origin ' . a:url)
      
      if v:shell_error != 0
        call plugin_manager#ui#update_sidebar(['Warning: Could not add remote as push URL for origin: ' . l:result], 1)
      endif
      
      call plugin_manager#ui#update_sidebar(['Remote repository added successfully.'], 1)
    catch
      let l:error = plugin_manager#utils#is_pm_error(v:exception) 
            \ ? plugin_manager#utils#format_error(v:exception)
            \ : 'Unexpected error adding remote: ' . v:exception
      
      call plugin_manager#ui#open_sidebar(['Add Remote Error:', repeat('-', 17), '', l:error])
    endtry
  endfunction
  
  " Restore all plugins from .gitmodules
  function! plugin_manager#modules#backup#restore()
    try
      if !plugin_manager#utils#ensure_vim_directory()
        throw 'PM_ERROR:restore:Not in Vim configuration directory'
      endif
      
      let l:header = ['Restore Plugins:', '---------------', '', 'Starting plugin restoration...']
      call plugin_manager#ui#open_sidebar(l:header)
      
      call s:check_gitmodules_exists()
      call s:initialize_submodules()
      call s:update_submodules()
      call s:finalize_submodules()
      
      call plugin_manager#ui#update_sidebar(['All plugins have been restored successfully.', '', 'Generating helptags:'], 1)
      call plugin_manager#modules#helptags#generate(0)
      
    catch
      let l:error = plugin_manager#utils#is_pm_error(v:exception) 
            \ ? plugin_manager#utils#format_error(v:exception)
            \ : 'Unexpected error during restore: ' . v:exception
      
      call plugin_manager#ui#update_sidebar(['Error: ' . l:error], 1)
    endtry
  endfunction
  
  " Helper function to check if .gitmodules exists
  function! s:check_gitmodules_exists()
    if !filereadable('.gitmodules')
      throw 'PM_ERROR:restore:.gitmodules file not found'
    endif
    
    call plugin_manager#ui#update_sidebar(['Found .gitmodules file.'], 1)
  endfunction
  
  " Helper function to initialize submodules
  function! s:initialize_submodules()
    call plugin_manager#ui#update_sidebar(['Initializing submodules...'], 1)
    
    let l:result = system('git submodule init')
    if v:shell_error != 0
      throw 'PM_ERROR:restore:Error initializing submodules: ' . l:result
    endif
  endfunction
  
  " Helper function to update submodules
  function! s:update_submodules()
    call plugin_manager#ui#update_sidebar(['Fetching and updating all submodules...'], 1)
    
    let l:result = system('git submodule update --init --recursive')
    if v:shell_error != 0
      throw 'PM_ERROR:restore:Error updating submodules: ' . l:result
    endif
  endfunction
  
  " Helper function to finalize submodule restoration
  function! s:finalize_submodules()
    call plugin_manager#ui#update_sidebar(['Ensuring all submodules are at the correct commit...'], 1)
    
    call system('git submodule sync')
    let l:result = system('git submodule update --init --recursive --force')
    if v:shell_error != 0
      throw 'PM_ERROR:restore:Error during final submodule update: ' . l:result
    endif
  endfunction