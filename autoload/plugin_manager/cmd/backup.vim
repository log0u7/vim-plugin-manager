" autoload/plugin_manager/cmd/backup.vim - Simplified backup command
" Maintainer: G.K.E. <gke@6admin.io>

" Backup configuration to remote repositories
function! plugin_manager#cmd#backup#execute() abort
  try
    call plugin_manager#core#util#require_vim_directory('backup')
    
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
  let l:vim_dir = plugin_manager#core#util#get_config('vim_dir', '')
  let l:vimrc_path = plugin_manager#core#util#get_config('vimrc_path', '')
  let l:vimrc_basename = fnamemodify(l:vimrc_path, ':t')
  let l:local_vimrc = l:vim_dir . '/' . l:vimrc_basename
  
  " Check if needs copying
  if plugin_manager#core#util#file_exists(l:local_vimrc)
    if getftype(l:local_vimrc) ==# 'link'
      return
    endif
  endif
  
  " Copy vimrc
  if plugin_manager#core#util#file_exists(l:vimrc_path)
    let l:copy_cmd = 'cp ' . shellescape(l:vimrc_path) . ' ' . shellescape(l:local_vimrc)
    let l:copy_result = plugin_manager#core#util#run_in_dir(l:copy_cmd, '')
    if !l:copy_result.success
      call plugin_manager#ui#log_detail('backup',
            \ 'backup cp failed: ' . l:copy_result.output, 'warn')
    endif
    let l:add_result = plugin_manager#git#execute(
          \ 'git add ' . shellescape(l:local_vimrc), l:vim_dir, 0, 0)
    if !l:add_result.success
      call plugin_manager#ui#log_detail('backup',
            \ 'backup git add failed: ' . l:add_result.output, 'warn')
    endif
  endif
endfunction

function! s:commit_local_changes(op_id) abort
  let l:vim_dir = plugin_manager#core#util#get_config('vim_dir', '')
  let l:status = plugin_manager#git#execute('git status -s', l:vim_dir, 0, 0)

  if empty(l:status.output)
    call plugin_manager#ui#complete_operation(a:op_id, 'info', 'No changes')
    return
  endif

  " Stage everything (tracked modifications AND untracked files): the doc
  " promises custom files are backed up, and new config files are untracked.
  call plugin_manager#git#execute('git add -A', l:vim_dir, 0, 0)
  let l:result = plugin_manager#git#execute(
        \ 'git commit -m ' . shellescape('Automatic backup'), l:vim_dir, 0, 0)

  if l:result.success
    call plugin_manager#ui#complete_operation(a:op_id, 'ok', 'Committed')
  else
    call plugin_manager#ui#complete_operation(a:op_id, 'fail', 'Commit failed')
    call plugin_manager#ui#log_detail('backup', l:result.output, 'warn')
  endif
endfunction

function! s:push_to_remotes(op_id) abort
  let l:vim_dir = plugin_manager#core#util#get_config('vim_dir', '')
  let l:remotes = plugin_manager#git#execute('git remote', l:vim_dir, 0, 0)
  let l:remote_names = filter(map(split(l:remotes.output, '\n'), 'trim(v:val)'), '!empty(v:val)')
  if empty(l:remote_names)
    call plugin_manager#ui#complete_operation(a:op_id, 'warn', 'No remotes')
    call plugin_manager#core#throw('backup', 'NO_REMOTES', 'No remote repositories configured')
  endif

  " Push to every configured remote, matching the documented behavior.
  let l:failures = []
  for l:remote in l:remote_names
    let l:result = plugin_manager#git#execute(
          \ 'git push ' . shellescape(l:remote) . ' HEAD', l:vim_dir, 0, 0)
    if !l:result.success
      call add(l:failures, 'push to ' . l:remote . ' failed: ' . l:result.output)
    endif
  endfor

  if empty(l:failures)
    call plugin_manager#ui#complete_operation(a:op_id, 'ok', 'Pushed')
  else
    call plugin_manager#ui#log_detail('backup', join(l:failures, "\n"), 'warn')
    if len(l:failures) == len(l:remote_names)
      call plugin_manager#ui#complete_operation(a:op_id, 'fail', 'Push failed')
    else
      call plugin_manager#ui#complete_operation(a:op_id, 'warn',
            \ 'Partial push: ' . (len(l:remote_names) - len(l:failures))
            \ . '/' . len(l:remote_names) . ' remotes')
    endif
  endif
endfunction