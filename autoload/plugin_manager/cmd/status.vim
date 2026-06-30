" autoload/plugin_manager/cmd/status.vim - Simplified status command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.6.0

" Show detailed status of all plugins
function! plugin_manager#cmd#status#execute() abort
  try
    call plugin_manager#core#require_vim_directory('status')
    
    let l:modules = plugin_manager#git#parse_modules()
    
    if empty(l:modules)
      call plugin_manager#ui#open_sidebar(
            \ plugin_manager#ui#header('Plugin status:') +
            \ [plugin_manager#ui#info('No plugins found')])
      return
    endif

    call plugin_manager#ui#open_header('Plugin status:')
    
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
        \ 'ops': {},
        \ 'pending': len(l:valid_modules)
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
    let a:ctx.pending -= 1
  endfor

  call s:maybe_finalize_status(a:ctx)
endfunction

" ------------------------------------------------------------------------------
" ASYNCHRONOUS STATUS - fan-out all fetches at once
" ------------------------------------------------------------------------------

function! s:fetch_status_async(ctx) abort
  " Launch all fetches in parallel. The async engine's concurrency queue
  " (g:plugin_manager_max_concurrent_jobs, default 4) limits simultaneous jobs.
  for l:module in a:ctx.valid_modules
    if !isdirectory(l:module.path)
      let l:info = s:get_module_status_info(l:module, 1)
      call s:complete_status_op(a:ctx, l:module, l:info)
      let a:ctx.pending -= 1
      call s:maybe_finalize_status(a:ctx)
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
  let a:ctx.pending -= 1
  call s:maybe_finalize_status(a:ctx)
endfunction

function! s:maybe_finalize_status(ctx) abort
  if a:ctx.pending == 0
    call plugin_manager#ui#footer([
          \ plugin_manager#ui#info(len(a:ctx.valid_modules) . ' plugins checked')])
  endif
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

" Map a status string to its rich glyph.
" Uses the centralized status-keyword table where possible so glyphs remain
" consistent with complete_operation() calls across commands.
function! s:status_symbol(status) abort
  " Map business-level status labels to UI keyword keys
  let l:keyword_map = {
        \ 'Up-to-date':    'ok',
        \ 'OK':            'ok',
        \ 'Behind':        'warn',
        \ 'Modified':      'warn',
        \ 'Missing':       'fail',
        \ 'Ahead':         'info',
        \ 'Custom branch': 'info',
        \ }
  let l:key = get(l:keyword_map, a:status, 'info')
  return plugin_manager#ui#get_status_glyph(l:key)
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
  
  if l:update_status.different_branch && l:update_status.branch !=# 'detached'
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

