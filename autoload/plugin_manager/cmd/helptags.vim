" autoload/plugin_manager/cmd/helptags.vim - Simplified helptags command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 2.0.0

" Generate helptags for all or a specific plugin
" Args: [create_header=1], [specific_module=''], [silent=0]
" When silent is 1, no UI lines are generated (no start_operation/complete_operation).
" This is used internally after update/add where the parent operation already shows progress.
function! plugin_manager#cmd#helptags#execute(...) abort
  try
    let l:create_header = a:0 > 0 ? a:1 : 1
    let l:specific_module = a:0 > 1 ? a:2 : ''
    let l:silent = a:0 > 2 ? a:3 : 0
    
    if !plugin_manager#core#ensure_vim_directory()
      return
    endif
    
    " Initialize output only when not silent
    if !l:silent && l:create_header
      call plugin_manager#ui#open_header('Generating helptags:')
    endif
    
    let l:plugins_dir = plugin_manager#core#get_config('plugins_dir', '')
    
    if !l:silent && !plugin_manager#core#dir_exists(l:plugins_dir)
      call plugin_manager#ui#update_sidebar([plugin_manager#ui#error('Plugin directory not found')], 1)
      return
    endif
    
    if !empty(l:specific_module)
      call s:generate_for_specific_plugin(l:specific_module, l:silent)
    else
      call s:generate_for_all_plugins(l:silent)
    endif
    
  catch
    call plugin_manager#core#handle_error(v:exception, "helptags")
  endtry
endfunction

" ------------------------------------------------------------------------------
" SPECIFIC PLUGIN
" ------------------------------------------------------------------------------

function! s:generate_for_specific_plugin(module_name, ...) abort
  let l:silent = a:0 > 0 ? a:1 : 0
  let l:module_info = plugin_manager#git#find_module(a:module_name)
  if empty(l:module_info)
    if !l:silent
      call plugin_manager#ui#update_sidebar([plugin_manager#ui#error('Plugin not found: ' . a:module_name)], 1)
    endif
    return
  endif
  
  call s:generate_for_plugin(l:module_info.module.short_name, l:module_info.module.path, l:silent)
endfunction

" ------------------------------------------------------------------------------
" ALL PLUGINS
" ------------------------------------------------------------------------------

function! s:generate_for_all_plugins(...) abort
  let l:silent = a:0 > 0 ? a:1 : 0
  let l:start_dir = plugin_manager#core#get_plugin_dir('start')
  let l:opt_dir = plugin_manager#core#get_plugin_dir('opt')
  
  let l:all_plugin_dirs = []
  
  " Add from start folder
  if plugin_manager#core#dir_exists(l:start_dir)
    call extend(l:all_plugin_dirs, glob(l:start_dir . '/*', 0, 1))
  endif
  
  " Add from opt folder
  if plugin_manager#core#dir_exists(l:opt_dir)
    call extend(l:all_plugin_dirs, glob(l:opt_dir . '/*', 0, 1))
  endif
  
  if empty(l:all_plugin_dirs)
    if !l:silent
      call plugin_manager#ui#update_sidebar([plugin_manager#ui#info('No plugins found')], 1)
    endif
    return
  endif
  
  let l:generated_count = 0
  
  " Process each plugin
  for l:plugin_dir in l:all_plugin_dirs
    if plugin_manager#core#dir_exists(l:plugin_dir)
      let l:plugin_name = fnamemodify(l:plugin_dir, ':t')
      
      if s:generate_for_plugin(l:plugin_name, l:plugin_dir, l:silent)
        let l:generated_count += 1
      endif
    endif
  endfor
  
  " Summary only when not silent
  if !l:silent
    if l:generated_count > 0
      call plugin_manager#ui#footer([plugin_manager#ui#success('Generated helptags for ' . l:generated_count . ' plugins')])
    else
      call plugin_manager#ui#footer([plugin_manager#ui#info('No documentation directories found')])
    endif
  endif
endfunction

" ------------------------------------------------------------------------------
" CORE GENERATION LOGIC
" ------------------------------------------------------------------------------

function! s:generate_for_plugin(plugin_name, plugin_path, ...) abort
  let l:silent = a:0 > 0 ? a:1 : 0
  
  if l:silent
    " Silent mode: no UI lines, just run helptags internally
    return s:generate_helptag(a:plugin_path)
  endif
  
  let l:op_id = plugin_manager#ui#start_operation(a:plugin_name, 'Generating helptags')
  
  if s:generate_helptag(a:plugin_path)
    call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Helptags generated')
    return 1
  else
    call plugin_manager#ui#complete_operation(l:op_id, 'skip', 'No doc directory')
    return 0
  endif
endfunction

" ------------------------------------------------------------------------------
" HELPER
" ------------------------------------------------------------------------------

function! s:generate_helptag(plugin_path) abort
  let l:doc_path = a:plugin_path . '/doc'
  if plugin_manager#core#dir_exists(l:doc_path)
    try
      execute 'helptags ' . fnameescape(l:doc_path)
      return 1
    catch
      return 0
    endtry
  endif
  return 0
endfunction