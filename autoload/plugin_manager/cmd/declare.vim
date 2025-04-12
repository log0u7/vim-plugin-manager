" autoload/plugin_manager/cmd/declare.vim - Declarative plugin configuration for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3.5

" Variables to track plugin block
let s:plugin_block_start = 0
let s:plugin_block_active = 0
let s:plugin_declarations = []
let s:plugin_context = {}

" Begin a plugin declaration block
function! plugin_manager#cmd#declare#begin() abort
  let s:plugin_block_start = line('.')
  let s:plugin_block_active = 1
  let s:plugin_declarations = []
  
  " If called from a sourced file, capture context for later processing
  if expand('<sfile>') !=# expand('<stack>')
    let s:plugin_context = {'file': expand('%:p'), 'line': line('.')}
  endif
endfunction

" Add a plugin declaration to the current block
function! plugin_manager#cmd#declare#plugin(url, options) abort
  if !s:plugin_block_active
    echohl WarningMsg
    echomsg "Plugin called outside of PluginBegin/PluginEnd block"
    echohl None
    return
  endif
  
  " Add to declarations list
  call add(s:plugin_declarations, {'url': a:url, 'options': a:options})
endfunction

" End a plugin declaration block and process all declarations
function! plugin_manager#cmd#declare#end() abort
  if !s:plugin_block_active
    echohl WarningMsg
    echomsg "PluginEnd called without matching PluginBegin"
    echohl None
    return
  endif
  
  " Process all plugin declarations
  call s:process_plugin_declarations()
  
  " Reset state
  let s:plugin_block_active = 0
  let s:plugin_declarations = []
endfunction

" Process all plugin declarations collected during a block
function! s:process_plugin_declarations() abort
  try
    " Make sure we're in the vim directory
    if !plugin_manager#core#ensure_vim_directory()
      throw 'PM_ERROR:declare:Not in Vim configuration directory'
    endif
    
    " Prepare header for UI
    let l:header = ['Processing Plugin Declarations:', '---------------------------', '']
    call plugin_manager#ui#open_sidebar(l:header)
    
    " Skip if no plugins to process
    if empty(s:plugin_declarations)
      call plugin_manager#ui#update_sidebar(['No plugin declarations found.'], 1)
      return
    endif
    
    call plugin_manager#ui#update_sidebar(['Found ' . len(s:plugin_declarations) . ' plugins to process...'], 1)
    
    " Process each plugin
    for l:plugin in s:plugin_declarations
      let l:url = l:plugin.url
      let l:options = l:plugin.options
      
      call plugin_manager#ui#update_sidebar(['Processing: ' . l:url], 1)
      
      " Convert URL to full format
      let l:full_url = plugin_manager#core#convert_to_full_url(l:url)
      if empty(l:full_url)
        call plugin_manager#ui#update_sidebar(['Error: Invalid plugin URL format: ' . l:url], 1)
        continue
      endif
      
      " Check if plugin already exists
      let l:plugin_name = plugin_manager#core#extract_plugin_name(l:full_url)
      
      if plugin_manager#cmd#add#exists(l:plugin_name, l:options)
        call plugin_manager#ui#update_sidebar(['Plugin already installed: ' . l:plugin_name], 1)
        continue
      endif
      
      " Install the plugin
      try
        call plugin_manager#api#add(l:url, l:options)
      catch
        call plugin_manager#ui#update_sidebar(['Error installing ' . l:url . ': ' . 
              \ plugin_manager#core#format_error(v:exception)], 1)
      endtry
    endfor
    
    call plugin_manager#ui#update_sidebar(['Plugin declarations processing completed.'], 1)
  catch
    call plugin_manager#core#handle_error(v:exception, "plugin_declarations")
  endtry
endfunction