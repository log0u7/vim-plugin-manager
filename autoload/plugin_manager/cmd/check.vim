" autoload/plugin_manager/cmd/check.vim - Update detection and notifications
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4.0

" ------------------------------------------------------------------------------
" PUBLIC ENTRY POINTS
" ------------------------------------------------------------------------------

" Run an update check.
" @param opts: dict with optional keys:
"   - 'silent'   : 1 to suppress the sidebar header/progress (background mode)
"   - 'on_done'  : Funcref called with the list of plugins behind once finished
"   - 'force'    : 1 to ignore the cache freshness (always fetch)
function! plugin_manager#cmd#check#execute(...) abort
  try
    if !plugin_manager#core#ensure_vim_directory()
      call plugin_manager#core#throw('check', 'NOT_VIM_DIR', 'Not in Vim configuration directory')
    endif

    let l:opts = a:0 > 0 ? a:1 : {}
    let l:silent = get(l:opts, 'silent', 0)

    let l:modules = plugin_manager#git#parse_modules()
    if empty(l:modules)
      if !l:silent
        call plugin_manager#ui#open_sidebar([
              \ 'Checking for updates:',
              \ plugin_manager#ui#get_symbol('separator'),
              \ '',
              \ plugin_manager#ui#info('No plugins installed')
              \ ])
      endif
      call s:finish([], l:opts)
      return []
    endif

    if !l:silent
      call plugin_manager#ui#open_sidebar([
            \ 'Checking for updates:',
            \ plugin_manager#ui#get_symbol('separator'),
            \ ''
            \ ])
    endif

    let l:ctx = {
          \ 'modules': l:modules,
          \ 'module_names': sort(keys(l:modules)),
          \ 'valid_modules': [],
          \ 'current_index': 0,
          \ 'behind': [],
          \ 'opts': l:opts,
          \ 'silent': l:silent,
          \ }

    for l:name in l:ctx.module_names
      let l:module = l:ctx.modules[l:name]
      if has_key(l:module, 'is_valid') && l:module.is_valid && plugin_manager#core#dir_exists(l:module.path)
        call add(l:ctx.valid_modules, l:module)
      endif
    endfor

    if plugin_manager#async#supported()
      call s:check_async(l:ctx)
      " Async path reports results via callback; return cached list for callers
      return get(plugin_manager#core#read_check_cache(), 'plugins', [])
    else
      return s:check_sync(l:ctx)
    endif
  catch
    call plugin_manager#core#handle_error(v:exception, 'check')
    return []
  endtry
endfunction

" Show the last cached check result without touching the network
function! plugin_manager#cmd#check#show_cached() abort
  let l:cache = plugin_manager#core#read_check_cache()
  let l:plugins = get(l:cache, 'plugins', [])
  call plugin_manager#ui#show_update_notification(l:plugins)
  return l:plugins
endfunction

" Startup orchestration: runs on VimEnter and on the periodic timer.
" Honors opt-in flags and the cache freshness to avoid needless network access.
function! plugin_manager#cmd#check#startup(...) abort
  " Re-entrancy guard: do nothing if checks are disabled
  if !plugin_manager#core#get_config('check_on_startup', 0)
    return
  endif

  " Bail out quietly if the vim dir is not usable (avoid noisy errors at startup)
  let l:vim_dir = plugin_manager#core#get_config('vim_dir', '')
  if empty(l:vim_dir) || !isdirectory(l:vim_dir . '/.git')
    return
  endif

  let l:interval = plugin_manager#core#get_config('check_interval', 24)
  let l:auto_update = plugin_manager#core#get_config('auto_update', 0)

  " If the cache is still fresh, just surface the cached result silently
  if !plugin_manager#core#check_due(l:interval)
    let l:cached = get(plugin_manager#core#read_check_cache(), 'plugins', [])
    if !empty(l:cached)
      call plugin_manager#ui#show_update_notification(l:cached)
    endif
    return
  endif

  " A fresh, silent (background) check; then notify or auto-update
  let l:opts = {'silent': 1}
  if l:auto_update
    let l:opts.on_done = function('s:on_startup_check_done_autoupdate')
  else
    let l:opts.on_done = function('s:on_startup_check_done_notify')
  endif

  call plugin_manager#cmd#check#execute(l:opts)
endfunction

function! s:on_startup_check_done_notify(plugins) abort
  if !empty(a:plugins)
    call plugin_manager#ui#show_update_notification(a:plugins)
  endif
endfunction

function! s:on_startup_check_done_autoupdate(plugins) abort
  if empty(a:plugins)
    return
  endif
  " Surface what is about to be updated, then run the standard update flow
  call plugin_manager#ui#show_update_notification(a:plugins)
  call plugin_manager#api#update('all')
endfunction

" ------------------------------------------------------------------------------
" SYNCHRONOUS CHECK
" ------------------------------------------------------------------------------

function! s:check_sync(ctx) abort
  let l:total = len(a:ctx.valid_modules)
  let l:index = 0

  for l:module in a:ctx.valid_modules
    let l:index += 1
    if !a:ctx.silent
      let l:op_id = plugin_manager#ui#start_operation(l:module.short_name, 'Checking [' . l:index . '/' . l:total . ']')
    endif

    call plugin_manager#git#execute('git fetch -q origin 2>/dev/null || true', l:module.path, 0, 0)
    let l:status = plugin_manager#git#collect_status_local(l:module.path)

    if !l:status.different_branch && l:status.behind > 0
      call add(a:ctx.behind, {'name': l:module.short_name, 'behind': l:status.behind})
      if !a:ctx.silent
        call plugin_manager#ui#complete_operation(l:op_id, 1, l:status.behind . ' commits behind')
      endif
    elseif !a:ctx.silent
      call plugin_manager#ui#complete_operation(l:op_id, 1, 'Up-to-date')
    endif
  endfor

  call s:finish(a:ctx.behind, a:ctx.opts)
  if !a:ctx.silent
    call plugin_manager#ui#show_update_notification(a:ctx.behind)
  endif
  return a:ctx.behind
endfunction

" ------------------------------------------------------------------------------
" ASYNCHRONOUS CHECK
" ------------------------------------------------------------------------------

function! s:check_async(ctx) abort
  let a:ctx.total = len(a:ctx.valid_modules)
  call timer_start(20, {timer -> s:process_next(a:ctx)})
endfunction

function! s:process_next(ctx) abort
  if a:ctx.current_index >= len(a:ctx.valid_modules)
    call s:finish(a:ctx.behind, a:ctx.opts)
    if !a:ctx.silent
      call plugin_manager#ui#show_update_notification(a:ctx.behind)
    endif
    return
  endif

  let l:module = a:ctx.valid_modules[a:ctx.current_index]
  let l:index = a:ctx.current_index + 1

  if !a:ctx.silent
    let l:op_id = plugin_manager#ui#start_operation(l:module.short_name, 'Checking [' . l:index . '/' . a:ctx.total . ']')
  else
    let l:op_id = ''
  endif

  call plugin_manager#async#git('git -C ' . shellescape(l:module.path) . ' fetch -q origin 2>/dev/null || true', {
        \ 'callback': function('s:on_fetched', [a:ctx, l:module, l:op_id])
        \ })
endfunction

function! s:on_fetched(ctx, module, op_id, result) abort
  " Fetch already done as an async job; only fast local analysis here
  let l:status = plugin_manager#git#collect_status_local(a:module.path)

  if !l:status.different_branch && l:status.behind > 0
    call add(a:ctx.behind, {'name': a:module.short_name, 'behind': l:status.behind})
    if !a:ctx.silent
      call plugin_manager#ui#complete_operation(a:op_id, 1, l:status.behind . ' commits behind')
    endif
  elseif !a:ctx.silent
    call plugin_manager#ui#complete_operation(a:op_id, 1, 'Up-to-date')
  endif

  let a:ctx.current_index += 1
  call s:process_next(a:ctx)
endfunction

" ------------------------------------------------------------------------------
" SHARED FINALIZATION
" ------------------------------------------------------------------------------

function! s:finish(plugins, opts) abort
  " Persist to cache so startup checks can skip the network next time
  call plugin_manager#core#write_check_cache(a:plugins)

  " Notify caller (e.g. auto-update flow)
  if has_key(a:opts, 'on_done') && !empty(a:opts.on_done)
    try
      call a:opts.on_done(a:plugins)
    catch
      " Do not let callback failures bubble up
    endtry
  endif
endfunction
