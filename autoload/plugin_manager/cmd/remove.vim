" autoload/plugin_manager/cmd/remove.vim - Simplified remove command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.6.0

" Execute the remove command
function! plugin_manager#cmd#remove#execute(module_name, force_flag) abort
  try
    call plugin_manager#core#require_vim_directory('remove')
    
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
  " Check for ambiguity in .gitmodules before attempting any match.
  " An exact match (short_name or path) is unambiguous; a partial match that
  " hits more than one module must be refused to prevent wrong-plugin deletion.
  let l:modules = plugin_manager#git#parse_modules()
  let l:exact = {}
  let l:partials = []

  for [l:name, l:module] in items(l:modules)
    if !get(l:module, 'is_valid', 0)
      continue
    endif
    let l:sn = get(l:module, 'short_name', '')
    let l:path = get(l:module, 'path', '')
    " Exact match: short_name or path
    if l:sn ==# a:module_name || l:path ==# a:module_name || l:name ==# a:module_name
      let l:exact = {'name': l:sn, 'path': l:path, 'url': get(l:module, 'url', '')}
      break
    endif
    " Partial match
    if l:sn =~? a:module_name || l:path =~? a:module_name || l:name =~? a:module_name
      call add(l:partials, l:sn)
    endif
  endfor

  " Exact match: safe
  if !empty(l:exact)
    return l:exact
  endif

  " Ambiguous partial match: refuse
  if len(l:partials) > 1
    call plugin_manager#core#throw('remove', 'AMBIGUOUS_MATCH',
          \ 'Ambiguous name "' . a:module_name . '" matches multiple plugins: ' .
          \ join(l:partials, ', ') . '. Use the exact plugin name.')
  endif

  " Single partial match in .gitmodules
  if len(l:partials) == 1
    let l:module_info = plugin_manager#git#find_module(a:module_name)
    if !empty(l:module_info)
      return {
            \ 'name': l:module_info.module.short_name,
            \ 'path': l:module_info.module.path,
            \ 'url': get(l:module_info.module, 'url', '')
            \ }
    endif
  endif

  " Fallback to filesystem search (handles modules not in .gitmodules)
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

    " Direct (exact) match - unambiguous, always safe
    let l:direct_path = l:base_dir . '/' . a:name
    if plugin_manager#core#dir_exists(l:direct_path)
      return {'name': a:name, 'path': l:direct_path, 'url': ''}
    endif

    " Fuzzy match: refuse if more than one candidate to avoid removing the
    " wrong plugin. Even -f does not override this safety check.
    let l:matches = glob(l:base_dir . '/*' . a:name . '*', 0, 1)
    if len(l:matches) == 1
      let l:path = l:matches[0]
      return {'name': fnamemodify(l:path, ':t'), 'path': l:path, 'url': ''}
    elseif len(l:matches) > 1
      let l:names = join(map(copy(l:matches), 'fnamemodify(v:val, ":t")'), ', ')
      call plugin_manager#core#throw('remove', 'AMBIGUOUS_MATCH',
            \ 'Ambiguous name "' . a:name . '" matches multiple plugins: ' . l:names .
            \ '. Use the exact plugin name.')
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
  call plugin_manager#ui#open_header('Removing plugin:')

  let l:op_id = plugin_manager#ui#start_operation(a:module_name, 'Removing')

  let l:vim_dir  = plugin_manager#core#get_config('vim_dir', '')
  let l:module_info = s:get_module_metadata(a:module_path)

  " git submodule deinit and git rm take the repo-relative path as argument
  " but must run inside the repo root (vim_dir).
  call plugin_manager#git#execute(
        \ 'git submodule deinit -f ' . shellescape(a:module_path), l:vim_dir, 0, 0)
  let l:result = plugin_manager#git#execute(
        \ 'git rm -f ' . shellescape(a:module_path), l:vim_dir, 0, 0)

  if !l:result.success
    " Fallback: delete the working tree directory directly using absolute path
    let l:abs_path = empty(l:vim_dir) ? a:module_path : (l:vim_dir . '/' . a:module_path)
    call plugin_manager#ui#log_detail('remove', 'git rm failed, removing path manually: ' . l:abs_path)
    call plugin_manager#core#remove_path(l:abs_path)
  endif

  " Remove the cached git metadata for this submodule (absolute path)
  let l:git_modules_path = l:vim_dir . '/.git/modules/' . a:module_path
  if plugin_manager#core#dir_exists(l:git_modules_path)
    call plugin_manager#core#remove_path(l:git_modules_path)
  endif

  call s:commit_removal(a:module_name, l:module_info)
  
  call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Removed')
  call plugin_manager#ui#footer([plugin_manager#ui#success('Plugin removed')])

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

  " Stage only .gitmodules (updated by git rm) rather than 'git add -A' which
  " would stage all unrelated pending changes in the worktree.
  call plugin_manager#git#execute('git add .gitmodules', '', 0, 0)
  call plugin_manager#git#execute('git commit -m ' . shellescape(l:commit_msg) .
        \ ' || git commit --allow-empty -m ' . shellescape(l:commit_msg), '', 0, 0)
endfunction