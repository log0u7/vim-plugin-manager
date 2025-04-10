" autoload/plugin_manager/cmd/helptags.vim - Helptags command for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3.4

" Generate helptags for all or a specific plugin
    function! plugin_manager#cmd#helptags#execute(...) abort
        try
          " Parse arguments
          let l:create_header = a:0 > 0 ? a:1 : 1
          let l:specific_module = a:0 > 1 ? a:2 : ''
          
          if !plugin_manager#core#ensure_vim_directory()
            return
          endif
          
          " Initialize output only if creating a new header
          if l:create_header
            let l:header = 'Generating Helptags:'
            let l:line = [l:header, repeat('-', len(l:header)), '', 'Generating helptags:']
            call plugin_manager#ui#open_sidebar(l:line)
          else
            " If we're not creating a new header, just add a separator line
            call plugin_manager#ui#update_sidebar(['', 'Generating helptags:'], 1)
          endif
          
          " Check if plugins directory exists
          let l:plugins_dir = plugin_manager#core#get_config('plugins_dir', '')
          
          " Ensure plugins_dir ends with a slash
          if l:plugins_dir !~ '[\/]$'
            let l:plugins_dir .= '/'
          endif
          
          let l:tags_generated = 0
          let l:generated_plugins = []
          
          if !plugin_manager#core#dir_exists(l:plugins_dir)
            call plugin_manager#ui#update_sidebar(['Plugin directory not found: ' . l:plugins_dir], 1)
            return
          endif
          
          if !empty(l:specific_module)
            " Find the specific plugin path
            call plugin_manager#ui#update_sidebar(['Looking for plugin: ' . l:specific_module], 1)
            
            let l:module_info = plugin_manager#git#find_module(l:specific_module)
            if empty(l:module_info)
              call plugin_manager#ui#update_sidebar(['Plugin not found: ' . l:specific_module], 1)
              return
            endif
            
            let l:module_path = l:module_info.module.path
            call plugin_manager#ui#update_sidebar(['Found plugin at: ' . l:module_path], 1)
            
            if s:generate_helptag(l:module_path)
              let l:tags_generated = 1
              call add(l:generated_plugins, "Generated helptags for " . l:module_info.module.short_name)
            endif
          else
            " Generate helptags for all plugins in start and opt directories
            call plugin_manager#ui#update_sidebar(['Searching for plugins...'], 1)
            
            " Get plugin directories
            let l:start_dir = plugin_manager#core#get_plugin_dir('start')
            let l:opt_dir = plugin_manager#core#get_plugin_dir('opt')
            
            " Scan all subdirectories in start and opt folders
            let l:all_plugin_dirs = []
            
            " Add directories from start folder
            if plugin_manager#core#dir_exists(l:start_dir)
              let l:start_plugins = glob(l:start_dir . '/*', 0, 1)
              call extend(l:all_plugin_dirs, l:start_plugins)
            endif
            
            " Add directories from opt folder
            if plugin_manager#core#dir_exists(l:opt_dir)
              let l:opt_plugins = glob(l:opt_dir . '/*', 0, 1)
              call extend(l:all_plugin_dirs, l:opt_plugins)
            endif
            
            call plugin_manager#ui#update_sidebar(['Found ' . len(l:all_plugin_dirs) . ' plugin directories.'], 1)
            
            " Process each plugin directory
            for l:plugin_dir in l:all_plugin_dirs
              if plugin_manager#core#dir_exists(l:plugin_dir)
                let l:plugin_name = fnamemodify(l:plugin_dir, ':t')
                
                if s:generate_helptag(l:plugin_dir)
                  let l:tags_generated = 1
                  call add(l:generated_plugins, "Generated helptags for " . l:plugin_name)
                endif
              endif
            endfor
          endif
          
          " Report results
          let l:result_message = []
          if l:tags_generated
            call extend(l:result_message, l:generated_plugins)
            call add(l:result_message, "Helptags generated successfully.")
          else
            call add(l:result_message, "No documentation directories found.")
          endif
          
          call plugin_manager#ui#update_sidebar(l:result_message, 1)
        catch
          call plugin_manager#core#handle_error(v:exception, "helptags")
        endtry
      endfunction
      
      " Generate helptags for a specific plugin directory
      function! s:generate_helptag(plugin_path) abort
        let l:doc_path = a:plugin_path . '/doc'
        if plugin_manager#core#dir_exists(l:doc_path)
          try
            execute 'helptags ' . fnameescape(l:doc_path)
            return 1
          catch
            call plugin_manager#ui#update_sidebar(['Error generating helptags for: ' . l:doc_path . ' - ' . v:exception], 1)
            return 0
          endtry
        endif
        return 0
      endfunction