" autoload/plugin_manager/cmd/backup.vim - Simplified backup command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.6.0

" Backup configuration to remote repositories
function! plugin_manager#cmd#backup#execute() abort
  try
    call plugin_manager#core#require_vim_directory('backup')
    
    call plugin_manager#ui#open_header('Backup configuration:')
    
    " Step 1: Copy vimrc
    let l:op_id = plugin_manager#ui#start_operation('vimrc', 'Backing up')
    call s:backup_vimrc_file()
    call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Copied')
    
    " Step 2: Commit changes
    let l:op_id = plugin_manager#ui#start_operation('changes', 'Committing')
    call s:commit_local_changes(l:op_id)
    
    " Step 3: Push to remotes
    let l:op_id = plugin_manager#ui#start_operation('remotes', 'Pushing')
    call s:push_to_remotes(l:op_id)
    
    call plugin_manager#ui#footer([plugin_manager#ui#success('Backup completed')])
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
    if getftype(l:local_vimrc) ==# 'link'
      return
    endif
  endif
  
  " Copy vimrc
  if plugin_manager#core#file_exists(l:vimrc_path)
    let l:copy_cmd = 'cp ' . shellescape(l:vimrc_path) . ' ' . shellescape(l:local_vimrc)
    let l:vim_dir = plugin_manager#core#get_config('vim_dir', '')
    call plugin_manager#git#execute(l:copy_cmd, '', 0, 1)
    call plugin_manager#git#execute('git add ' . shellescape(l:local_vimrc), l:vim_dir, 0, 0)
  endif
endfunction

function! s:commit_local_changes(op_id) abort
  let l:vim_dir = plugin_manager#core#get_config('vim_dir', '')
  let l:status = plugin_manager#git#execute('git status -s', l:vim_dir, 0, 0)

  if empty(l:status.output)
    call plugin_manager#ui#complete_operation(a:op_id, 'info', 'No changes')
    return
  endif

  let l:result = plugin_manager#git#execute('git commit -am "Automatic backup"', l:vim_dir, 0, 0)

  if l:result.success
    call plugin_manager#ui#complete_operation(a:op_id, 'ok', 'Committed')
  else
    call plugin_manager#ui#complete_operation(a:op_id, 'fail', 'Commit failed')
    call plugin_manager#ui#log_detail('backup', l:result.output)
  endif
endfunction

function! s:push_to_remotes(op_id) abort
  let l:vim_dir = plugin_manager#core#get_config('vim_dir', '')
  let l:remotes = plugin_manager#git#execute('git remote', l:vim_dir, 0, 0)
  if empty(l:remotes.output)
    call plugin_manager#ui#complete_operation(a:op_id, 'warn', 'No remotes')
    call plugin_manager#core#throw('backup', 'NO_REMOTES', 'No remote repositories configured')
  endif

  let l:result = plugin_manager#git#execute('git push origin HEAD', l:vim_dir, 0, 0)

  if l:result.success
    call plugin_manager#ui#complete_operation(a:op_id, 'ok', 'Pushed')
  else
    call plugin_manager#ui#complete_operation(a:op_id, 'fail', 'Push failed')
    call plugin_manager#ui#log_detail('backup', l:result.output)
  endif
endfunction