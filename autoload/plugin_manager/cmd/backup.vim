" autoload/plugin_manager/cmd/backup.vim - Simplified backup command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4.0

" Backup configuration to remote repositories
function! plugin_manager#cmd#backup#execute() abort
  try
    if !plugin_manager#core#ensure_vim_directory()
      call plugin_manager#core#throw('backup', 'NOT_VIM_DIR', 'Not in Vim configuration directory')
    endif
    
    let l:header = [
          \ 'Backup configuration:',
          \ plugin_manager#ui#get_symbol('separator'),
          \ ''
          \ ]
    call plugin_manager#ui#open_sidebar(l:header)
    
    " Step 1: Copy vimrc
    let l:op_id = plugin_manager#ui#start_operation('vimrc', 'Backing up')
    call plugin_manager#ui#update_operation(l:op_id, 'Copying vimrc')
    call s:backup_vimrc_file()
    call plugin_manager#ui#complete_operation(l:op_id, 1, 'Copied')
    
    " Step 2: Commit changes
    let l:op_id = plugin_manager#ui#start_operation('changes', 'Committing')
    call s:commit_local_changes(l:op_id)
    
    " Step 3: Push to remotes
    let l:op_id = plugin_manager#ui#start_operation('remotes', 'Pushing')
    call s:push_to_remotes(l:op_id)
    
    call plugin_manager#ui#update_sidebar(['', plugin_manager#ui#success('Backup completed')], 1)
  catch
    call plugin_manager#core#handle_error(v:exception, "backup")
  endtry
endfunction

" ------------------------------------------------------------------------------
" BACKUP STEPS
" ------------------------------------------------------------------------------

function! s:backup_vimrc_file() abort
  let l:vim_dir = plugin_manager#core#get_config('vim_dir', '')
  let l:vimrc_path = plugin_manager#core#get_config('vimrc_path', '')
  let l:vimrc_basename = fnamemodify(l:vimrc_path, ':t')
  let l:local_vimrc = l:vim_dir . '/' . l:vimrc_basename
  
  " Check if needs copying
  if plugin_manager#core#file_exists(l:local_vimrc)
    if !has('win32') && !has('win64') && getftype(l:local_vimrc) ==# 'link'
      return
    endif
  endif
  
  " Copy vimrc
  if plugin_manager#core#file_exists(l:vimrc_path)
    let l:copy_cmd = 'cp ' . shellescape(l:vimrc_path) . ' ' . shellescape(l:local_vimrc)
    call plugin_manager#git#execute(l:copy_cmd, '', 0, 1)
    call plugin_manager#git#execute('git add ' . shellescape(l:local_vimrc), '', 0, 0)
  endif
endfunction

function! s:commit_local_changes(op_id) abort
  call plugin_manager#ui#update_operation(a:op_id, 'Checking for changes')
  
  let l:status = plugin_manager#git#execute('git status -s', '', 0, 0)
  
  if empty(l:status.output)
    call plugin_manager#ui#complete_operation(a:op_id, 1, 'No changes to commit')
    return
  endif
  
  call plugin_manager#ui#update_operation(a:op_id, 'Committing changes')
  let l:result = plugin_manager#git#execute('git commit -am "Automatic backup"', '', 0, 0)
  
  if l:result.success
    call plugin_manager#ui#complete_operation(a:op_id, 1, 'Changes committed')
  else
    call plugin_manager#ui#complete_operation(a:op_id, 0, 'Commit failed')
  endif
endfunction

function! s:push_to_remotes(op_id) abort
  call plugin_manager#ui#update_operation(a:op_id, 'Checking remotes')
  
  " Check if remotes exist
  let l:remotes = plugin_manager#git#execute('git remote', '', 0, 0)
  if empty(l:remotes.output)
    call plugin_manager#ui#complete_operation(a:op_id, 0, 'No remotes configured')
    call plugin_manager#core#throw('backup', 'NO_REMOTES', 'No remote repositories configured')
  endif
  
  call plugin_manager#ui#update_operation(a:op_id, 'Pushing to remotes')
  let l:result = plugin_manager#git#execute('git push --all', '', 0, 1)
  
  if l:result.success
    call plugin_manager#ui#complete_operation(a:op_id, 1, 'Pushed successfully')
  else
    call plugin_manager#ui#complete_operation(a:op_id, 0, 'Push failed')
  endif
endfunction