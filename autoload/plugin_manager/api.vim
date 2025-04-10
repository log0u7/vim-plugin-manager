" autoload/plugin_manager/api.vim - Unified API for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4-dev

" ------------------------------------------------------------------------------
" PLUGIN DECLARATION TRACKING
" ------------------------------------------------------------------------------

" Variables to track plugin block
let s:plugin_block_start = 0
let s:plugin_block_active = 0
let s:plugin_declarations = []

" ------------------------------------------------------------------------------
" MAIN COMMAND DISPATCHER
" ------------------------------------------------------------------------------

" Main function to handle all plugin manager commands
function! plugin_manager#api#dispatch(...) abort
  try
    if !plugin_manager#core#ensure_vim_directory()
      return
    endif
    
    if a:0 < 1
      call plugin_manager#ui#usage()
      return
    endif
    
    let l:command = a:1
    
    " Route command to appropriate module
    if l:command ==# 'add' && a:0 >= 2
      call call('plugin_manager#cmd#add#execute', a:000[1:])
    elseif l:command ==# 'remove' && a:0 >= 2
      call plugin_manager#cmd#remove#execute(a:2, get(a:, 3, ''))
    elseif l:command ==# 'list'
      call plugin_manager#cmd#list#all()
    elseif l:command ==# 'status'
      call plugin_manager#cmd#status#execute()
    elseif l:command ==# 'update'
      " Pass the optional module name if provided
      if a:0 >= 2
        call plugin_manager#cmd#update#execute(a:2)
      else
        call plugin_manager#cmd#update#execute('all')
      endif
    elseif l:command ==# 'summary'
      call plugin_manager#cmd#list#summary()
    elseif l:command ==# 'backup'
      call plugin_manager#cmd#backup#execute()
    elseif l:command ==# 'restore'
      call plugin_manager#cmd#restore#execute()
    elseif l:command ==# 'helptags'
      " Pass the optional module name if provided
      if a:0 >= 2
        call plugin_manager#cmd#helptags#execute(1, a:2)
      else
        call plugin_manager#cmd#helptags#execute()
      endif
    elseif l:command ==# 'reload'
      " Pass the optional module name if provided
      if a:0 >= 2
        call plugin_manager#cmd#reload#execute(a:2)
      else
        call plugin_manager#cmd#reload#execute()
      endif
    else
      call plugin_manager#ui#usage()
    endif
  catch
    " Handle errors properly
    call plugin_manager#core#handle_error(v:exception, "command:" . l:command)
  endtry
endfunction

" ------------------------------------------------------------------------------
" DECLARATIVE PLUGIN CONFIGURATION
" ------------------------------------------------------------------------------

" Begin a plugin declaration block
function! plugin_manager#api#begin() abort
  let s:plugin_block_start = line('.')
  let s:plugin_block_active = 1
  let s:plugin_declarations = []
  
  " If called from a sourced file, capture context for later processing
  if expand('<sfile>') !=# expand('<stack>')
    let s:plugin_context = {'file': expand('%:p'), 'line': line('.')}
  endif
endfunction

" Add a plugin declaration to the current block
function! plugin_manager#api#plugin(...) abort
  if !s:plugin_block_active
    echohl WarningMsg
    echomsg "Plugin called outside of PluginBegin/PluginEnd block"
    echohl None
    return
  endif
  
  " Must have at least the plugin name
  if a:0 < 1
    return
  endif
  
  let l:plugin_url = a:1
  
  " Check if options were provided
  let l:options = {}
  if a:0 >= 2
    if type(a:2) == v:t_dict
      let l:options = a:2
    else
      " Old format compatibility - second arg is dir
      let l:options.dir = a:2
      
      " Check for third arg - load type
      if a:0 >= 3 && a:3 ==# 'opt'
        let l:options.load = 'opt'
      endif
    endif
  endif
  
  " Add to declarations list
  call add(s:plugin_declarations, {'url': l:plugin_url, 'options': l:options})
endfunction

" End a plugin declaration block and process all declarations
function! plugin_manager#api#end() abort
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
      throw 'PM_ERROR:api:Not in Vim configuration directory'
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
      
      " Check if it's a local path
      let l:is_local = l:full_url =~# '^local:'
      
      " For remote plugins, check if repository exists
      if !l:is_local && !plugin_manager#git#repository_exists(l:full_url)
        call plugin_manager#ui#update_sidebar(['Error: Repository not found: ' . l:full_url], 1)
        continue
      endif
      
      " Install the plugin
      try
        if l:is_local
          " Handle local plugin
          let l:local_path = substitute(l:full_url, '^local:', '', '')
          call s:install_local_plugin(l:local_path, l:options)
        else
          " Handle remote plugin
          call s:install_remote_plugin(l:full_url, l:options)
        endif
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

" Helper function to install a remote plugin
function! s:install_remote_plugin(url, options) abort
  " Check if plugin already exists (to avoid reinstalling)
  let l:plugin_name = plugin_manager#core#extract_plugin_name(a:url)
  let l:custom_name = get(a:options, 'dir', '')
  let l:plugin_dir_name = empty(l:custom_name) ? l:plugin_name : l:custom_name
  
  " Determine install type (start/opt)
  let l:plugin_type = get(a:options, 'load', 'start')
  let l:plugin_dir = plugin_manager#core#get_plugin_dir(l:plugin_type) . '/' . l:plugin_dir_name
  
  " Only install if not already present
  if !isdirectory(l:plugin_dir)
    call plugin_manager#cmd#add#execute(a:url, a:options)
  else
    call plugin_manager#ui#update_sidebar(['Plugin already installed: ' . l:plugin_dir_name], 1)
  endif
endfunction

" Helper function to install a local plugin
function! s:install_local_plugin(path, options) abort
  " Extract name from path
  let l:plugin_name = fnamemodify(a:path, ':t')
  let l:custom_name = get(a:options, 'dir', '')
  let l:plugin_dir_name = empty(l:custom_name) ? l:plugin_name : l:custom_name
  
  " Determine install type (start/opt)
  let l:plugin_type = get(a:options, 'load', 'start')
  let l:plugin_dir = plugin_manager#core#get_plugin_dir(l:plugin_type) . '/' . l:plugin_dir_name
  
  " Only install if not already present
  if !isdirectory(l:plugin_dir)
    call plugin_manager#cmd#add#execute(a:path, a:options)
  else
    call plugin_manager#ui#update_sidebar(['Plugin already installed: ' . l:plugin_dir_name], 1)
  endif
endfunction

" ------------------------------------------------------------------------------
" REMOTE REPOSITORY MANAGEMENT
" ------------------------------------------------------------------------------

" Add a remote backup repository
function! plugin_manager#api#add_remote(url) abort
  return plugin_manager#cmd#remote#add(a:url)
endfunction