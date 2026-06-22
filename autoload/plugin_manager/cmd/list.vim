" autoload/plugin_manager/cmd/list.vim - Simplified list command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.5.0

" List all installed plugins
function! plugin_manager#cmd#list#all() abort
  try
    if !plugin_manager#core#ensure_vim_directory()
      return
    endif
    
    let l:modules = plugin_manager#git#parse_modules()
    
    if empty(l:modules)
      let l:lines = [
            \ 'Installed plugins:',
            \ plugin_manager#ui#get_symbol('separator'),
            \ '',
            \ plugin_manager#ui#info('No plugins installed')
            \ ]
      call plugin_manager#ui#open_sidebar(l:lines)
      return
    endif
    
    let l:lines = ['Installed plugins:', plugin_manager#ui#get_symbol('separator'), '']
    let l:module_names = sort(keys(l:modules))
    
    for l:name in l:module_names
      let l:module = l:modules[l:name]
      if has_key(l:module, 'is_valid') && l:module.is_valid
        let l:short_name = l:module.short_name
        let l:status = has_key(l:module, 'exists') && l:module.exists ? 'Installed' : 'Missing'
        let l:symbol = has_key(l:module, 'exists') && l:module.exists ? 
              \ plugin_manager#ui#get_symbol('tick') : plugin_manager#ui#get_symbol('cross')
        
        let l:formatted = plugin_manager#ui#format_plugin_line(l:symbol, l:short_name, l:status)
        call add(l:lines, l:formatted)
      endif
    endfor
    
    call plugin_manager#ui#open_sidebar(l:lines)
  catch
    call plugin_manager#core#handle_error(v:exception, "list")
  endtry
endfunction

" Show summary of submodule changes
function! plugin_manager#cmd#list#summary() abort
  try
    if !plugin_manager#core#ensure_vim_directory()
      return
    endif
    
    if !filereadable('.gitmodules')
      let l:lines = [
            \ 'Plugin summary:',
            \ plugin_manager#ui#get_symbol('separator'),
            \ '',
            \ plugin_manager#ui#info('No plugins found')
            \ ]
      call plugin_manager#ui#open_sidebar(l:lines)
      return
    endif
    
    let l:result = plugin_manager#git#execute('git submodule summary', '', 0, 0)
    let l:output = l:result.output
    
    let l:lines = ['Plugin summary:', plugin_manager#ui#get_symbol('separator'), '']
    
    if empty(l:output)
      call add(l:lines, plugin_manager#ui#info('No changes detected'))
    else
      call extend(l:lines, split(l:output, "\n"))
    endif
    
    call plugin_manager#ui#open_sidebar(l:lines)
  catch
    call plugin_manager#core#handle_error(v:exception, "summary")
  endtry
endfunction