" autoload/plugin_manager/cmd/add.vim - Simplified add command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.5.0

" Main function to add a plugin
function! plugin_manager#cmd#add#execute(...) abort
  try
    if a:0 < 1
      call plugin_manager#core#throw('add', 'MISSING_ARGS', 'Missing plugin argument')
    endif
    
    let l:plugin_input = a:1
    let l:module_url = plugin_manager#core#convert_to_full_url(l:plugin_input)
    
    if empty(l:module_url)
      call plugin_manager#core#throw('add', 'INVALID_URL', 'Invalid plugin format: ' . l:plugin_input)
    endif
    
    " Process options
    let l:options = {}
    if a:0 >= 2
      let l:options = plugin_manager#core#process_plugin_options(a:000[1:])
    endif
    
    " Check if local path
    let l:is_local = l:module_url =~# '^local:'
    
    " For remote plugins, check repository exists
    if !l:is_local && !plugin_manager#git#repository_exists(l:module_url)
      call plugin_manager#core#throw('add', 'REPO_NOT_FOUND', 'Repository not found: ' . l:module_url)
    endif
    
    " Install
    if l:is_local
      let l:local_path = substitute(l:module_url, '^local:', '', '')
      return s:install_local_plugin(l:local_path, l:options)
    else
      return s:install_remote_plugin(l:module_url, l:options)
    endif
  catch
    call plugin_manager#core#handle_error(v:exception, "add")
    return 0
  endtry
endfunction

" Check if plugin exists
function! plugin_manager#cmd#add#exists(plugin_name, options) abort
  let l:plugin_name = a:plugin_name
  let l:custom_name = get(a:options, 'dir', '')
  let l:plugin_dir_name = empty(l:custom_name) ? l:plugin_name : l:custom_name
  
  let l:plugin_type = get(a:options, 'load', 'start')
  let l:plugin_dir = plugin_manager#core#get_plugin_dir(l:plugin_type) . '/' . l:plugin_dir_name
  
  return isdirectory(l:plugin_dir)
        \ || plugin_manager#git#submodule_exists(l:plugin_dir)
endfunction

" ------------------------------------------------------------------------------
" REMOTE PLUGIN INSTALLATION
" ------------------------------------------------------------------------------

function! s:install_remote_plugin(url, options) abort
  let l:plugin_name = plugin_manager#core#extract_plugin_name(a:url)
  let l:custom_name = get(a:options, 'dir', '')
  let l:plugin_dir_name = empty(l:custom_name) ? l:plugin_name : l:custom_name
  
  let l:plugin_type = get(a:options, 'load', 'start')
  let l:plugin_dir = plugin_manager#core#get_plugin_dir(l:plugin_type) . '/' . l:plugin_dir_name
  
  let l:header = [
        \ 'Installing plugin:',
        \ plugin_manager#ui#get_symbol('separator'),
        \ ''
        \ ]
  call plugin_manager#ui#open_sidebar(l:header)
  
  " Start operation
  let l:op_id = plugin_manager#ui#start_operation(l:plugin_dir_name, 'Installing')
  
  try
    if plugin_manager#git#add_submodule(a:url, l:plugin_dir, a:options)
      let l:doc_path = l:plugin_dir . '/doc'
      if isdirectory(l:doc_path)
        silent execute 'helptags ' . fnameescape(l:doc_path)
      endif
      call plugin_manager#ui#complete_operation_symbol(l:op_id, plugin_manager#ui#get_symbol('tick'), 'Installed')
      return 1
    else
      call plugin_manager#ui#complete_operation_symbol(l:op_id, plugin_manager#ui#get_symbol('cross'), 'Failed')
      return 0
    endif
  catch
    call plugin_manager#ui#complete_operation_symbol(l:op_id, plugin_manager#ui#get_symbol('cross'), 'Failed')
    call plugin_manager#ui#log_detail('add', v:exception)
    call plugin_manager#core#handle_error(v:exception, "add")
    return 0
  endtry
endfunction

" ------------------------------------------------------------------------------
" LOCAL PLUGIN INSTALLATION
" ------------------------------------------------------------------------------

function! s:install_local_plugin(path, options) abort
  let l:plugin_name = fnamemodify(a:path, ':t')
  let l:custom_name = get(a:options, 'dir', '')
  let l:plugin_dir_name = empty(l:custom_name) ? l:plugin_name : l:custom_name
  
  let l:plugin_type = get(a:options, 'load', 'start')
  let l:plugin_dir = plugin_manager#core#get_plugin_dir(l:plugin_type) . '/' . l:plugin_dir_name
  
  let l:header = [
        \ 'Installing local plugin:',
        \ plugin_manager#ui#get_symbol('separator'),
        \ ''
        \ ]
  call plugin_manager#ui#open_sidebar(l:header)
  
  " Start operation
  let l:op_id = plugin_manager#ui#start_operation(l:plugin_dir_name, 'Installing')
  
  try
    if !isdirectory(a:path)
      call plugin_manager#ui#complete_operation_symbol(l:op_id, plugin_manager#ui#get_symbol('warning'), 'Source not found')
      call plugin_manager#core#throw('add', 'LOCAL_PATH_NOT_FOUND', 'Local directory not found: ' . a:path)
    endif
    
    if isdirectory(l:plugin_dir)
      call plugin_manager#ui#complete_operation_symbol(l:op_id, plugin_manager#ui#get_symbol('warning'), 'Already exists')
      call plugin_manager#core#throw('add', 'TARGET_EXISTS', 'Destination already exists: ' . l:plugin_dir)
    endif
    
    let l:parent_dir = fnamemodify(l:plugin_dir, ':h')
    if !isdirectory(l:parent_dir)
      call mkdir(l:parent_dir, 'p')
    endif
    
    call mkdir(l:plugin_dir, 'p')
    call s:copy_local_files(a:path, l:plugin_dir)
    
    if !empty(get(a:options, 'exec', ''))
      let l:result = plugin_manager#git#execute(a:options.exec, l:plugin_dir, 0, 0)
      if !l:result.success
        call plugin_manager#ui#complete_operation_symbol(l:op_id, plugin_manager#ui#get_symbol('cross'), 'Exec failed')
        return 0
      endif
    endif
    
    let l:doc_path = l:plugin_dir . '/doc'
    if isdirectory(l:doc_path)
      silent execute 'helptags ' . fnameescape(l:doc_path)
    endif
    
    call plugin_manager#ui#complete_operation_symbol(l:op_id, plugin_manager#ui#get_symbol('tick'), 'Installed')
    return 1
  catch
    call plugin_manager#ui#complete_operation_symbol(l:op_id, plugin_manager#ui#get_symbol('cross'), 'Failed')
    call plugin_manager#ui#log_detail('add', v:exception)
    call plugin_manager#core#handle_error(v:exception, "add")
    return 0
  endtry
endfunction

" ------------------------------------------------------------------------------
" COPY HELPERS
" ------------------------------------------------------------------------------

function! s:copy_local_files(src_path, dest_path) abort
  let l:copy_success = 0
  
  " Try rsync first
  if executable('rsync')
    let l:rsync_command = 'rsync -a --exclude=".git" ' . shellescape(a:src_path . '/') . ' ' . shellescape(a:dest_path . '/')
    let l:result = plugin_manager#git#execute(l:rsync_command, '', 0, 0)
    let l:copy_success = l:result.success
    
    if l:copy_success
      return
    endif
  endif
  
  " Platform-specific fallbacks
  if has('win32') || has('win64')
    let l:copy_success = s:copy_files_windows(a:src_path, a:dest_path)
  else
    let l:copy_success = s:copy_files_unix(a:src_path, a:dest_path)
  endif
  
  if !l:copy_success
    call plugin_manager#core#throw('add', 'COPY_FAILED', 'Failed to copy files to destination')
  endif
endfunction

function! s:copy_files_windows(src_path, dest_path) abort
  if executable('robocopy')
    let l:result = plugin_manager#git#execute('robocopy ' . shellescape(a:src_path) . ' ' . 
          \ shellescape(a:dest_path) . ' /E /XD .git', '', 0, 0)
    return v:shell_error < 8
  endif
  
  if executable('xcopy')
    let l:result = plugin_manager#git#execute('xcopy ' . shellescape(a:src_path) . '\* ' . 
          \ shellescape(a:dest_path) . ' /E /I /Y /EXCLUDE:.git', '', 0, 0)
    return l:result.success
  endif
  
  return 0
endfunction

function! s:copy_files_unix(src_path, dest_path) abort
  let l:copy_cmd = 'cd ' . shellescape(a:src_path) . ' && find . -type d -name ".git" -prune -o -type f -print | ' .
        \ 'xargs -I{} cp --parents {} ' . shellescape(a:dest_path)
  let l:result = plugin_manager#git#execute(l:copy_cmd, '', 0, 0)
  let l:copy_success = l:result.success
  
  if !l:copy_success
    let l:result = plugin_manager#git#execute('cp -R ' . shellescape(a:src_path) . '/* ' . 
          \ shellescape(a:dest_path), '', 0, 0)
    let l:copy_success = l:result.success
    
    if l:copy_success && isdirectory(a:dest_path . '/.git')
      call plugin_manager#git#execute('rm -rf ' . shellescape(a:dest_path . '/.git'), '', 0, 0)
    endif
  endif
  
  return l:copy_success
endfunction