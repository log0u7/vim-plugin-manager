" autoload/plugin_manager/cmd/status.vim - Simplified status command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.5.0

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
    
    " Render all plugin lines as a block with pending spinners (instantly, like list)
    for l:module in l:ctx.valid_modules
      let l:op_id = plugin_manager#ui#start_operation(l:module.short_name, 'Checking')
      let l:ctx.ops[l:module.short_name] = l:op_id
    endfor
    
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
  let l:valid_modules = []
  
  for l:name in l:module_names
    let l:module = a:modules[l:name]
    if has_key(l:module, 'is_valid') && l:module.is_valid
      call add(l:valid_modules, l:module)
    endif
  endfor
  
  let l:ctx = {
        \ 'modules': a:modules,
        \ 'module_names': l:module_names,
        \ 'valid_modules': l:valid_modules,
        \ 'ops': {}
        \ }
  
  return l:ctx
endfunction

" ------------------------------------------------------------------------------
" SYNCHRONOUS STATUS (fallback when +job is unavailable)
" ------------------------------------------------------------------------------

function! s:fetch_status_sync(ctx) abort
  call plugin_manager#git#execute('git submodule foreach --recursive "git fetch -q origin 2>/dev/null || true"', '', 0, 0)
  
  for l:module in a:ctx.valid_modules
    let l:info = s:get_module_status_info(l:module, 1)
    call s:complete_status_op(a:ctx, l:module, l:info)
  endfor
endfunction

" ------------------------------------------------------------------------------
" ASYNCHRONOUS STATUS — fan-out all fetches at once
" ------------------------------------------------------------------------------

function! s:fetch_status_async(ctx) abort
  " Launch all fetches in parallel. The async engine's concurrency queue
  " (g:plugin_manager_max_concurrent_jobs, default 4) limits simultaneous jobs.
  for l:module in a:ctx.valid_modules
    if !isdirectory(l:module.path)
      let l:info = s:get_module_status_info(l:module, 1)
      call s:complete_status_op(a:ctx, l:module, l:info)
    else
      call plugin_manager#async#git(
            \ 'git -C ' . shellescape(l:module.path) . ' fetch -q origin 2>/dev/null || true', {
            \ 'callback': function('s:on_status_fetched', [a:ctx, l:module])
            \ })
    endif
  endfor
endfunction

function! s:on_status_fetched(ctx, module, result) abort
  let l:info = s:get_module_status_info(a:module, 1)
  call s:complete_status_op(a:ctx, a:module, l:info)
endfunction

" ------------------------------------------------------------------------------
" SHARED HELPERS
" ------------------------------------------------------------------------------

" Complete a status operation in place (updates the pre-rendered line)
function! s:complete_status_op(ctx, module, info) abort
  let l:symbol = s:status_symbol(a:info.status)
  let l:status_text = a:info.status
  if !empty(a:info.details)
    let l:status_text .= ' (' . a:info.details . ')'
  endif
  call plugin_manager#ui#complete_operation_symbol(
        \ a:ctx.ops[a:info.name], l:symbol, l:status_text)
endfunction

" Map a status string to its rich glyph
function! s:status_symbol(status) abort
  let l:map = {
        \ 'Up-to-date': plugin_manager#ui#get_symbol('tick'),
        \ 'OK':          plugin_manager#ui#get_symbol('tick'),
        \ 'Behind':      plugin_manager#ui#get_symbol('warning'),
        \ 'Ahead':       plugin_manager#ui#get_symbol('info'),
        \ 'Modified':    plugin_manager#ui#get_symbol('warning'),
        \ 'Custom branch': plugin_manager#ui#get_symbol('info'),
        \ 'Missing':     plugin_manager#ui#get_symbol('cross'),
        \ }
  return get(l:map, a:status, plugin_manager#ui#get_symbol('info'))
endfunction

" ------------------------------------------------------------------------------
" STATUS INFO EXTRACTION
" ------------------------------------------------------------------------------

" @param local_only: when 1, assume a fetch already happened and only run
"   fast local analysis (non-blocking flow). When 0, do a blocking fetch.
function! s:get_module_status_info(module, ...) abort
  let l:local_only = a:0 > 0 ? a:1 : 0
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
  
  let l:update_status = l:local_only
        \ ? plugin_manager#git#collect_status_local(l:path)
        \ : plugin_manager#git#check_updates(l:path)
  
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
  let l:symbol = s:status_symbol(a:info.status)
  let l:status_text = a:info.status
  
  if !empty(a:info.details)
    let l:status_text .= ' (' . a:info.details . ')'
  endif
  
  return plugin_manager#ui#format_plugin_line(l:symbol, a:info.name, l:status_text)
endfunction