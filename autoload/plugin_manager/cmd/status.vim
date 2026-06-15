" autoload/plugin_manager/cmd/status.vim - Simplified status command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4.0

" Show detailed status of all plugins
function! plugin_manager#cmd#status#execute() abort
  try
    if !plugin_manager#core#ensure_vim_directory()
      call plugin_manager#core#throw('status', 'NOT_VIM_DIR', 'Not in Vim configuration directory')
    endif
    
    let l:modules = plugin_manager#git#parse_modules()
    
    if empty(l:modules)
      let l:lines = [
            \ 'Plugin status:',
            \ plugin_manager#ui#get_symbol('separator'),
            \ '',
            \ plugin_manager#ui#info('No plugins found')
            \ ]
      call plugin_manager#ui#open_sidebar(l:lines)
      return
    endif
    
    let l:lines = ['Plugin status:', plugin_manager#ui#get_symbol('separator'), '']
    call plugin_manager#ui#open_sidebar(l:lines)
    
    let l:ctx = s:create_status_context(l:modules)
    let l:use_async = plugin_manager#async#supported()
    
    if l:use_async
      call s:fetch_status_async(l:ctx)
    else
      call s:fetch_status_sync(l:ctx)
    endif
  catch
    call plugin_manager#core#handle_error(v:exception, "status")
  endtry
endfunction

" ------------------------------------------------------------------------------
" CONTEXT CREATION
" ------------------------------------------------------------------------------

function! s:create_status_context(modules) abort
  let l:module_names = sort(keys(a:modules))
  
  let l:ctx = {
        \ 'modules': a:modules,
        \ 'module_names': l:module_names,
        \ 'total': len(l:module_names),
        \ 'current_index': 0,
        \ 'valid_modules': []
        \ }
  
  for l:name in l:ctx.module_names
    let l:module = l:ctx.modules[l:name]
    if has_key(l:module, 'is_valid') && l:module.is_valid
      call add(l:ctx.valid_modules, l:module)
    endif
  endfor
  
  return l:ctx
endfunction

" ------------------------------------------------------------------------------
" SYNCHRONOUS STATUS
" ------------------------------------------------------------------------------

function! s:fetch_status_sync(ctx) abort
  call plugin_manager#git#execute('git submodule foreach --recursive "git fetch -q origin 2>/dev/null || true"', '', 0, 0)
  
  for l:name in a:ctx.module_names
    let l:module = a:ctx.modules[l:name]
    if has_key(l:module, 'is_valid') && l:module.is_valid
      let l:info = s:get_module_status_info(l:module)
      let l:line = s:format_status_line(l:info)
      call plugin_manager#ui#update_sidebar([l:line], 1)
    endif
  endfor
endfunction

" ------------------------------------------------------------------------------
" ASYNCHRONOUS STATUS
" ------------------------------------------------------------------------------

function! s:fetch_status_async(ctx) abort
  " Start fetch in background
  call plugin_manager#async#git('git submodule foreach --recursive "git fetch -q origin 2>/dev/null || true"', {})
  
  " Begin processing modules
  call timer_start(50, {timer -> s:process_next_module_status(a:ctx)})
endfunction

function! s:process_next_module_status(ctx) abort
  if a:ctx.current_index >= len(a:ctx.module_names)
    return
  endif
  
  let l:name = a:ctx.module_names[a:ctx.current_index]
  let l:module = a:ctx.modules[l:name]
  
  if !has_key(l:module, 'is_valid') || !l:module.is_valid
    let a:ctx.current_index += 1
    call s:process_next_module_status(a:ctx)
    return
  endif
  
  let l:info = s:get_module_status_info(l:module)
  let l:line = s:format_status_line(l:info)
  call plugin_manager#ui#update_sidebar([l:line], 1)
  
  let a:ctx.current_index += 1
  call timer_start(10, {timer -> s:process_next_module_status(a:ctx)})
endfunction

" ------------------------------------------------------------------------------
" STATUS INFO EXTRACTION
" ------------------------------------------------------------------------------

function! s:get_module_status_info(module) abort
  let l:short_name = a:module.short_name
  let l:path = a:module.path
  
  let l:info = {
        \ 'module': a:module,
        \ 'name': l:short_name,
        \ 'status': 'OK',
        \ 'details': ''
        \ }
  
  if !isdirectory(l:path)
    let l:info.status = 'Missing'
    let l:info.details = 'Directory not found'
    return l:info
  endif
  
  let l:update_status = plugin_manager#git#check_updates(l:path)
  
  if l:update_status.different_branch && l:update_status.branch != 'detached'
    let l:info.status = 'Custom branch'
    let l:info.details = l:update_status.branch
  elseif l:update_status.behind > 0
    let l:info.status = 'Behind'
    let l:info.details = l:update_status.behind . ' commits'
  elseif l:update_status.ahead > 0
    let l:info.status = 'Ahead'
    let l:info.details = l:update_status.ahead . ' commits'
  elseif l:update_status.has_changes
    let l:info.status = 'Modified'
    let l:info.details = 'Local changes'
  else
    let l:info.status = 'Up-to-date'
    
    " Get last commit info
    let l:result = plugin_manager#git#execute('git log -1 --format="%h %ar"', l:path, 0, 0)
    if l:result.success
      let l:info.details = substitute(l:result.output, '\n', '', 'g')
    endif
  endif
  
  return l:info
endfunction

" ------------------------------------------------------------------------------
" FORMATTING
" ------------------------------------------------------------------------------

function! s:format_status_line(info) abort
  let l:status_symbols = {
        \ 'OK': plugin_manager#ui#get_symbol('tick'),
        \ 'Up-to-date': plugin_manager#ui#get_symbol('tick'),
        \ 'Behind': plugin_manager#ui#get_symbol('warning'),
        \ 'Ahead': plugin_manager#ui#get_symbol('info'),
        \ 'Modified': plugin_manager#ui#get_symbol('warning'),
        \ 'Custom branch': plugin_manager#ui#get_symbol('info'),
        \ 'Missing': plugin_manager#ui#get_symbol('cross'),
        \ }
  
  let l:symbol = get(l:status_symbols, a:info.status, plugin_manager#ui#get_symbol('info'))
  let l:status_text = a:info.status
  
  if !empty(a:info.details)
    let l:status_text .= ' (' . a:info.details . ')'
  endif
  
  return plugin_manager#ui#format_plugin_line(l:symbol, a:info.name, l:status_text)
endfunction