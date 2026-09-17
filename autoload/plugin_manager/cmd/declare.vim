" autoload/plugin_manager/cmd/declare.vim - Simplified declarative configuration
" Maintainer: G.K.E. <gke@6admin.io>

" State tracking
let s:plugin_block_active = 0
let s:plugin_declarations = []
" Names with a background install in flight (async batch path): a re-run
" of PluginEnd (reload) must not double-install them.
let s:pending_installs = {}

" Begin a plugin declaration block
function! plugin_manager#cmd#declare#begin() abort
  let s:plugin_block_active = 1
  let s:plugin_declarations = []
  let s:pending_installs = {}
endfunction

" Add a plugin declaration
function! plugin_manager#cmd#declare#plugin(url, ...) abort
  if !s:plugin_block_active
    try
      call plugin_manager#core#throw('declare', 'BLOCK_ERROR',
            \ 'Plugin called outside PluginBegin/PluginEnd block')
    catch
      call plugin_manager#core#handle_error(v:exception, 'declare')
    endtry
    return
  endif

  let l:options = a:0 > 0 ? a:1 : {}
  call add(s:plugin_declarations, {'url': a:url, 'options': l:options})
endfunction

" End declaration block and process
function! plugin_manager#cmd#declare#end() abort
  if !s:plugin_block_active
    try
      call plugin_manager#core#throw('declare', 'BLOCK_ERROR',
            \ 'PluginEnd called without matching PluginBegin')
    catch
      call plugin_manager#core#handle_error(v:exception, 'declare')
    endtry
    return
  endif
  
  call s:process_declarations()
  
  let s:plugin_block_active = 0
  let s:plugin_declarations = []
endfunction

" ------------------------------------------------------------------------------
" PROCESSING
" ------------------------------------------------------------------------------

function! s:process_declarations() abort
  try
    call plugin_manager#core#util#require_vim_directory('declare')

    if empty(s:plugin_declarations)
      return
    endif

    " Fast path: background parallel install through the async queue.
    " PluginEnd returns immediately; each clone completion registers the
    " submodule. The synchronous loop below remains the fallback for
    " builds without +job/+channel and for deterministic tests
    " (g:plugin_manager_test_force_sync).
    if plugin_manager#async#supported() && !get(g:, 'plugin_manager_test_force_sync', 0)
      call s:process_declarations_async()
      return
    endif

    let l:installed = 0
    let l:skipped = 0
    let l:errors = 0

    for l:plugin in s:plugin_declarations
      let l:result = s:process_plugin(l:plugin.url, l:plugin.options)

      if l:result ==# 'installed'
        let l:installed += 1
      elseif l:result ==# 'skipped'
        let l:skipped += 1
      elseif l:result ==# 'error'
        let l:errors += 1
      endif
    endfor

    " Open sidebar only if work actually happened
    if l:installed == 0 && l:errors == 0
      return
    endif

    " Summary footer
    let l:summary = []
    if l:installed > 0
      call add(l:summary, plugin_manager#ui#success(l:installed . ' plugins installed'))
    endif
    if l:errors > 0
      call add(l:summary, plugin_manager#ui#error(l:errors . ' errors'))
    endif
    if l:skipped > 0
      call add(l:summary, plugin_manager#ui#info(l:skipped . ' plugins skipped (already installed)'))
    endif

    call plugin_manager#ui#footer(l:summary)
  catch
    call plugin_manager#core#handle_error(v:exception, "declare")
  endtry
endfunction

" ------------------------------------------------------------------------------
" PARALLEL (BACKGROUND) BATCH INSTALL
" ------------------------------------------------------------------------------

" Install every missing declared plugin: git clone in parallel through the
" async queue (g:plugin_manager_max_concurrent_jobs), then register each
" pre-cloned directory as a submodule from the completion callback. Vim
" callbacks are single-threaded, so the registrations serialize naturally:
" no .gitmodules or index contention.
"
" The clone IS the repository probe: a failed clone reports the git error,
" replacing the separate ls-remote check of the synchronous path.
" Re-entrance: a reload re-running PluginEnd while installs are pending
" skips the in-flight plugins (s:pending_installs).
function! s:process_declarations_async() abort
  let l:ctx = {'pending': 0, 'installed': 0, 'errors': 0, 'total': 0, 'ops': {}}

  for l:plugin in s:plugin_declarations
    let l:full_url = plugin_manager#core#util#convert_to_full_url(l:plugin.url)
    " Normalize through the shared parser so every option key exists
    " (add_submodule and lazy#register expect the full shape)
    let l:options = plugin_manager#core#util#process_plugin_options([l:plugin.options])
    let l:name = empty(get(l:options, 'dir', ''))
          \ ? plugin_manager#core#util#extract_plugin_name(l:full_url)
          \ : l:options.dir

    if empty(l:full_url) || empty(l:name)
      let l:op_id = plugin_manager#ui#start_operation(
            \ empty(l:name) ? fnamemodify(l:plugin.url, ':t') : l:name, 'Processing')
      call plugin_manager#ui#complete_operation(l:op_id, 'fail', 'Invalid URL format')
      let l:ctx.errors += 1
      continue
    endif

    " Lazy triggers must exist immediately, like the synchronous path
    call plugin_manager#lazy#register(l:name, l:options)

    if l:full_url =~# '^local:'
      " Local plugins are filesystem copies, not submodules: reuse the
      " synchronous single-plugin path (no network involved).
      if s:process_plugin(l:plugin.url, l:options) ==# 'error'
        let l:ctx.errors += 1
      endif
      continue
    endif

    if has_key(s:pending_installs, l:name)
      continue
    endif
    if plugin_manager#cmd#add#exists(l:name, l:options)
      continue
    endif

    let l:target = plugin_manager#core#util#get_plugin_dir(
          \ get(l:options, 'load', 'start')) . '/' . l:name
    let l:op_id = plugin_manager#ui#start_operation(l:name, 'Installing')

    let l:ctx.total += 1
    let l:ctx.pending += 1
    let l:ctx.ops[l:name] = l:op_id
    let s:pending_installs[l:name] = 1

    " file:// remotes are local paths: the URL is trusted vimrc input, so
    " the file transport restriction (git >= 2.38.1) is lifted for the
    " top-level clone. Network URLs keep the git defaults.
    let l:clone_cmd = 'git clone '
    if l:full_url =~# '^file://'
      let l:clone_cmd .= '-c protocol.file.allow=always '
    endif
    let l:clone_cmd .= shellescape(l:full_url) . ' ' . shellescape(l:target)

    call plugin_manager#async#start_job(l:clone_cmd, {
          \ 'callback': function('s:on_clone_done',
          \   [l:ctx, l:name, l:full_url, l:options, l:target])
          \ })
  endfor

  if l:ctx.total == 0 && l:ctx.errors == 0
    return
  endif
  if l:ctx.total == 0
    call plugin_manager#ui#footer([plugin_manager#ui#error(l:ctx.errors . ' errors')])
  endif
endfunction

function! s:on_clone_done(ctx, name, url, options, target, result) abort
  let l:op_id = get(a:ctx.ops, a:name, 0)
  if has_key(s:pending_installs, a:name)
    call remove(s:pending_installs, a:name)
  endif

  if a:result.status != 0
    call plugin_manager#ui#complete_operation(l:op_id, 'fail', 'Clone failed')
    call plugin_manager#ui#log_detail('declare',
          \ empty(a:result.errors) ? a:result.output : a:result.errors)
    let a:ctx.errors += 1
    call s:maybe_finish_async(a:ctx)
    return
  endif

  try
    if plugin_manager#git#add_submodule(a:url, a:target, a:options)
      let l:doc_path = a:target . '/doc'
      if isdirectory(l:doc_path)
        silent execute 'helptags ' . fnameescape(l:doc_path)
      endif
      call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Installed')
      let a:ctx.installed += 1
    else
      call plugin_manager#ui#complete_operation(l:op_id, 'fail', 'Failed')
      let a:ctx.errors += 1
    endif
  catch
    call plugin_manager#ui#complete_operation(l:op_id, 'fail', 'Install failed')
    call plugin_manager#ui#log_detail('declare', v:exception)
    let a:ctx.errors += 1
  endtry
  call s:maybe_finish_async(a:ctx)
endfunction

function! s:maybe_finish_async(ctx) abort
  let a:ctx.pending -= 1
  if a:ctx.pending > 0
    return
  endif
  call plugin_manager#git#refresh_modules_cache()
  let l:summary = []
  if a:ctx.installed > 0
    call add(l:summary, plugin_manager#ui#success(
          \ a:ctx.installed . ' of ' . a:ctx.total . ' plugins installed'))
  endif
  if a:ctx.errors > 0
    call add(l:summary, plugin_manager#ui#error(a:ctx.errors . ' errors'))
  endif
  if !empty(l:summary)
    call plugin_manager#ui#footer(l:summary)
  endif
endfunction

function! s:process_plugin(url, options) abort
  " Convert to full URL
  let l:full_url = plugin_manager#core#util#convert_to_full_url(a:url)
  if empty(l:full_url)
    let l:plugin_name = fnamemodify(a:url, ':t')
    let l:op_id = plugin_manager#ui#start_operation(l:plugin_name, 'Processing')
    call plugin_manager#ui#complete_operation(l:op_id, 'fail', 'Invalid URL format')
    return 'error'
  endif
  
  " Extract plugin name
  let l:plugin_name = plugin_manager#core#util#extract_plugin_name(l:full_url)

  " Register lazy triggers (on/for) before anything else: they must exist
  " even while the plugin is still being installed, and for skipped
  " declarations (already installed) which never reach the install path.
  call plugin_manager#lazy#register(
        \ empty(get(a:options, 'dir', '')) ? l:plugin_name : a:options.dir,
        \ a:options)

  " Check if already exists
  if plugin_manager#cmd#add#exists(l:plugin_name, a:options)
    return 'skipped'
  endif
  
  " Install
  try
    let l:result = plugin_manager#api#add(a:url, a:options)
    return l:result ? 'installed' : 'error'
  catch
    let l:op_id = plugin_manager#ui#start_operation(l:plugin_name, 'Installing')
    call plugin_manager#ui#complete_operation(l:op_id, 'fail', 'Installation failed')
    return 'error'
  endtry
endfunction