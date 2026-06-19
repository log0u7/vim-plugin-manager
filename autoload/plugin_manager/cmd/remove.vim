" autoload/plugin_manager/cmd/remove.vim - Simplified remove command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4.0

" Execute the remove command
function! plugin_manager#cmd#remove#execute(module_name, force_flag) abort
  try
    if !plugin_manager#core#ensure_vim_directory()
      call plugin_manager#core#throw('remove', 'NOT_VIM_DIR', 'Not in Vim configuration directory')
    endif
    
    if empty(a:module_name)
      call plugin_manager#core#throw('remove', 'MISSING_ARGS', 'Missing plugin name argument')
    endif
    
    " Find module
    let l:module = s:find_module(a:module_name)
    
    " Confirm removal
    let l:force = a:force_flag ==# '-f'
    if !l:force && !s:confirm_removal(l:module.name, l:module.path)
      return 0
    endif
    
    " Remove module
    call s:remove_module(l:module.name, l:module.path)
    
    return 1
  catch
    call plugin_manager#core#handle_error(v:exception, "remove")
    return 0
  endtry
endfunction

" ------------------------------------------------------------------------------
" MODULE DISCOVERY
" ------------------------------------------------------------------------------

function! s:find_module(module_name) abort
  " Try .gitmodules first
  let l:module_info = plugin_manager#git#find_module(a:module_name)
  
  if !empty(l:module_info)
    return {
          \ 'name': l:module_info.module.short_name,
          \ 'path': l:module_info.module.path,
          \ 'url': get(l:module_info.module, 'url', '')
          \ }
  endif
  
  " Fallback to filesystem search
  let l:found = s:find_in_filesystem(a:module_name)
  
  if empty(l:found)
    call plugin_manager#core#throw('remove', 'MODULE_NOT_FOUND', 'Module not found: ' . a:module_name)
  endif
  
  return l:found
endfunction

function! s:find_in_filesystem(name) abort
  for l:dir_type in ['start', 'opt']
    let l:base_dir = plugin_manager#core#get_plugin_dir(l:dir_type)
    
    if !plugin_manager#core#dir_exists(l:base_dir)
      continue
    endif
    
    " Direct match
    let l:direct_path = l:base_dir . '/' . a:name
    if plugin_manager#core#dir_exists(l:direct_path)
      return {'name': a:name, 'path': l:direct_path, 'url': ''}
    endif
    
    " Fuzzy match
    let l:matches = glob(l:base_dir . '/*' . a:name . '*', 0, 1)
    if !empty(l:matches)
      let l:path = l:matches[0]
      return {'name': fnamemodify(l:path, ':t'), 'path': l:path, 'url': ''}
    endif
  endfor
  
  return {}
endfunction

" ------------------------------------------------------------------------------
" REMOVAL PROCESS
" ------------------------------------------------------------------------------

function! s:confirm_removal(module_name, module_path) abort
  let l:response = input("Remove " . a:module_name . " (" . a:module_path . ")? [y/N] ")
  return l:response =~? '^y\(es\)\?$'
endfunction

function! s:remove_module(module_name, module_path) abort
  let l:header = [
        \ 'Removing plugin:',
        \ plugin_manager#ui#get_symbol('separator'),
        \ ''
        \ ]
  call plugin_manager#ui#open_sidebar(l:header)
  
  let l:op_id = plugin_manager#ui#start_operation(a:module_name, 'Removing')
  
  let l:module_info = s:get_module_metadata(a:module_path)
  
  call plugin_manager#git#execute('git submodule deinit -f ' . shellescape(a:module_path), '', 0, 0)
  let l:result = plugin_manager#git#execute('git rm -f ' . shellescape(a:module_path), '', 0, 0)
  
  if !l:result.success
    call plugin_manager#ui#log_detail('remove', 'git rm failed, removing path manually: ' . a:module_path)
    call plugin_manager#core#remove_path(a:module_path)
  endif
  
  let l:git_modules_path = '.git/modules/' . a:module_path
  if plugin_manager#core#dir_exists(l:git_modules_path)
    call plugin_manager#core#remove_path(l:git_modules_path)
  endif
  
  call s:commit_removal(a:module_name, l:module_info)
  
  call plugin_manager#ui#complete_operation_symbol(l:op_id, plugin_manager#ui#get_symbol('tick'), 'Removed')
  
  call plugin_manager#git#refresh_modules_cache()
endfunction

" ------------------------------------------------------------------------------
" HELPERS
" ------------------------------------------------------------------------------

function! s:get_module_metadata(module_path) abort
  let l:modules = plugin_manager#git#parse_modules()
  
  for [l:name, l:module] in items(l:modules)
    if has_key(l:module, 'path') && l:module.path ==# a:module_path
      return l:module
    endif
  endfor
  
  return {}
endfunction

function! s:commit_removal(module_name, module_info) abort
  let l:commit_msg = "Remove " . a:module_name . " plugin"
  
  if !empty(a:module_info) && has_key(a:module_info, 'url')
    let l:commit_msg .= " (" . a:module_info.url . ")"
  endif
  
  call plugin_manager#git#execute('git add -A && git commit -m ' . shellescape(l:commit_msg) . 
        \ ' || git commit --allow-empty -m ' . shellescape(l:commit_msg), '', 0, 0)
endfunction