" autoload/plugin_manager/cmd/declare.vim - Simplified declarative configuration
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4.0

" State tracking
let s:plugin_block_active = 0
let s:plugin_declarations = []

" Begin a plugin declaration block
function! plugin_manager#cmd#declare#begin() abort
  let s:plugin_block_active = 1
  let s:plugin_declarations = []
endfunction

" Add a plugin declaration
function! plugin_manager#cmd#declare#plugin(url, ...) abort
  if !s:plugin_block_active
    echohl WarningMsg
    echomsg "Plugin called outside PluginBegin/PluginEnd block"
    echohl None
    return
  endif

  let l:options = a:0 > 0 ? a:1 : {}
  call add(s:plugin_declarations, {'url': a:url, 'options': l:options})
endfunction

" End declaration block and process
function! plugin_manager#cmd#declare#end() abort
  if !s:plugin_block_active
    echohl WarningMsg
    echomsg "PluginEnd called without matching PluginBegin"
    echohl None
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
    if !plugin_manager#core#ensure_vim_directory()
      call plugin_manager#core#throw('declare', 'NOT_VIM_DIR', 'Not in Vim configuration directory')
    endif
    
    if empty(s:plugin_declarations)
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
    
    " Summary
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
    
    call plugin_manager#ui#update_sidebar([''] + l:summary, 1)
  catch
    call plugin_manager#core#handle_error(v:exception, "declare")
  endtry
endfunction

function! s:process_plugin(url, options) abort
  " Convert to full URL
  let l:full_url = plugin_manager#core#convert_to_full_url(a:url)
  if empty(l:full_url)
    let l:plugin_name = fnamemodify(a:url, ':t')
    let l:op_id = plugin_manager#ui#start_operation(l:plugin_name, 'Processing')
    call plugin_manager#ui#complete_operation(l:op_id, 0, 'Invalid URL format')
    return 'error'
  endif
  
  " Extract plugin name
  let l:plugin_name = plugin_manager#core#extract_plugin_name(l:full_url)
  
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
    call plugin_manager#ui#complete_operation(l:op_id, 0, 'Installation failed')
    return 'error'
  endtry
endfunction