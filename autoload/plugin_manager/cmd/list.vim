" autoload/plugin_manager/cmd/list.vim - List plugins command for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4-dev

" List all installed plugins with formatted output
function! plugin_manager#cmd#list#all() abort
    try
      if !plugin_manager#core#ensure_vim_directory()
        return
      endif
      
      " Use git module to get plugin information
      let l:modules = plugin_manager#git#parse_modules()
      let l:header = 'Installed Plugins:' 
      
      if empty(l:modules)
        let l:lines = [l:header, repeat('-', len(l:header)), '', 'No plugins installed (.gitmodules not found)']
        call plugin_manager#ui#open_sidebar(l:lines)
        return
      endif
      
      let l:lines = [l:header, repeat('-', len(l:header)), '', 'Name'.repeat(' ', 20).'Path'.repeat(' ', 38).'URL']
      let l:lines += [repeat('-', 120)]
      
      " Sort modules by name
      let l:module_names = sort(keys(l:modules))
      
      for l:name in l:module_names
        let l:module = l:modules[l:name]
        if has_key(l:module, 'is_valid') && l:module.is_valid
          let l:short_name = l:module.short_name
          let l:path = l:module.path
          
          if len(l:short_name) > 22
            let l:short_name = l:short_name[0:21]
          endif
          
          if len(l:path) > 40
            let l:path = l:path[0:39]
          endif 
          
          " Format the output with properly aligned columns
          let l:name_col = l:short_name . repeat(' ', max([0, 24 - len(l:short_name)]))
          let l:path_col = l:path . repeat(' ', max([0, 42 - len(l:path)]))
          
          let l:status = has_key(l:module, 'exists') && l:module.exists ? '' : ' [MISSING]'
          
          call add(l:lines, l:name_col . l:path_col . l:module.url . l:status)
        endif
      endfor
      
      call plugin_manager#ui#open_sidebar(l:lines)
    catch
      call plugin_manager#core#handle_error(v:exception, "list")
    endtry
  endfunction
  
  " Show a summary of submodule changes
  function! plugin_manager#cmd#list#summary() abort
    try
      if !plugin_manager#core#ensure_vim_directory()
        return
      endif
      
      let l:header = 'Submodule Summary'
      
      " Check if .gitmodules exists
      if !filereadable('.gitmodules')
        let l:lines = [l:header, repeat('-', len(l:header)), '', 'No submodules found (.gitmodules not found)']
        call plugin_manager#ui#open_sidebar(l:lines)
        return
      endif
      
      " Use git module to get summary
      let l:result = plugin_manager#git#execute('git submodule summary', '', 0, 0)
      let l:output = l:result.output
      
      let l:lines = [l:header, repeat('-', len(l:header)), '']
      call extend(l:lines, split(l:output, "\n"))
      
      call plugin_manager#ui#open_sidebar(l:lines)
    catch
      call plugin_manager#core#handle_error(v:exception, "summary")
    endtry
  endfunction