" autoload/plugin_manager/cmd/reload.vim - Simplified reload command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.6.0

" Reload a specific plugin or all Vim configuration
function! plugin_manager#cmd#reload#execute(...) abort
  try
    call plugin_manager#core#require_vim_directory('reload')
    
    call plugin_manager#ui#open_header('Reloading:')
    
    let l:specific_module = a:0 > 0 ? a:1 : ''
    
    if !empty(l:specific_module)
      call s:reload_specific_plugin(l:specific_module)
    else
      call s:reload_all_configuration()
    endif
  catch
    call plugin_manager#core#handle_error(v:exception, "reload")
  endtry
endfunction

" ------------------------------------------------------------------------------
" SPECIFIC PLUGIN RELOAD
" ------------------------------------------------------------------------------

function! s:reload_specific_plugin(module_name) abort
  let l:module_info = plugin_manager#git#find_module(a:module_name, 1)
  if empty(l:module_info)
    call plugin_manager#core#throw('reload', 'MODULE_NOT_FOUND', 'Module not found: ' . a:module_name)
  endif
  
  let l:module_path = l:module_info.module.path
  
  if !isdirectory(l:module_path)
    call plugin_manager#core#throw('reload', 'MODULE_NOT_FOUND', 'Module directory not found: ' . l:module_path)
  endif
  
  let l:op_id = plugin_manager#ui#start_operation(a:module_name, 'Reloading')
  
  call s:remove_from_runtimepath(l:module_path)
  call s:add_to_runtimepath(l:module_path)
  call s:reload_plugin_runtime_files(l:module_path)
  
  call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Reloaded')
  call plugin_manager#ui#footer([plugin_manager#ui#info('Some plugins may require restarting Vim')])
endfunction

" ------------------------------------------------------------------------------
" ALL CONFIGURATION RELOAD
" ------------------------------------------------------------------------------

function! s:reload_all_configuration() abort
  let l:op_id = plugin_manager#ui#start_operation('configuration', 'Reloading')

  call s:reload_all_runtime_files()
  call s:source_vimrc()

  call plugin_manager#ui#complete_operation(l:op_id, 'ok', 'Reloaded')
  call plugin_manager#ui#footer([plugin_manager#ui#info('Some plugins may require restarting Vim')])
endfunction

" ------------------------------------------------------------------------------
" HELPER FUNCTIONS
" ------------------------------------------------------------------------------

function! s:remove_from_runtimepath(module_path) abort
  execute 'set rtp-=' . fnameescape(a:module_path)
  
  let l:after_path = a:module_path . '/after'
  if isdirectory(l:after_path)
    execute 'set rtp-=' . fnameescape(l:after_path)
  endif
endfunction

function! s:add_to_runtimepath(module_path) abort
  execute 'set rtp+=' . fnameescape(a:module_path)
  
  let l:after_path = a:module_path . '/after'
  if isdirectory(l:after_path)
    execute 'set rtp+=' . fnameescape(l:after_path)
  endif
endfunction

function! s:reload_plugin_runtime_files(module_path) abort
  let l:runtime_paths = split(globpath(a:module_path, '**/*.vim'), '\n')
  
  for l:rtp in l:runtime_paths
    if l:rtp =~# '/plugin/' || l:rtp =~# '/ftplugin/'
      execute 'runtime! ' . fnameescape(l:rtp)
    endif
  endfor
endfunction

function! s:reload_all_runtime_files() abort
  execute 'runtime! plugin/**/*.vim'
  execute 'runtime! ftplugin/**/*.vim'
  execute 'runtime! syntax/**/*.vim'
  execute 'runtime! indent/**/*.vim'
endfunction

function! s:source_vimrc() abort
  let l:vimrc_path = expand(plugin_manager#core#get_config('vimrc_path', ''))
  
  if !empty(l:vimrc_path) && filereadable(l:vimrc_path)
    execute 'source ' . fnameescape(l:vimrc_path)
  endif
endfunction