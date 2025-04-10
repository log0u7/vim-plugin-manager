" autoload/plugin_manager/cmd/add.vim - Add command for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: refacto2 v1.3.3 d4f8fda

" Main function to add a plugin
    function! plugin_manager#cmd#add#execute(...) abort
        try
          if a:0 < 1
            throw 'PM_ERROR:add:Missing plugin argument'
          endif
          
          let l:plugin_input = a:1
          let l:module_url = plugin_manager#core#convert_to_full_url(l:plugin_input)
          
          " Check if URL is valid or if it's a local path
          if empty(l:module_url)
            throw 'PM_ERROR:add:Invalid plugin format: ' . l:plugin_input . '. Use format "user/repo", complete URL, or local path.'
          endif
          
          " Process options (second parameter)
          let l:options = {}
          if a:0 >= 2
            let l:options = plugin_manager#core#process_plugin_options(a:000[1:])
          endif
          
          " Check if it's a local path
          let l:is_local = l:module_url =~# '^local:'
          
          " For remote plugins, check if repository exists
          if !l:is_local && !plugin_manager#git#repository_exists(l:module_url)
            if l:plugin_input =~# '^[a-zA-Z0-9_.-]\+/[a-zA-Z0-9_.-]\+$'
              let l:host = plugin_manager#core#get_config('default_git_host', 'github.com')
              throw 'PM_ERROR:add:Repository not found: ' . l:module_url . '. This plugin was not found on ' . l:host . '.'
            else
              throw 'PM_ERROR:add:Repository not found: ' . l:module_url
            endif
          endif
          
          " Install the plugin
          if l:is_local
            let l:local_path = substitute(l:module_url, '^local:', '', '')
            return s:install_local_plugin(l:local_path, l:options)
          else
            return s:install_remote_plugin(l:module_url, l:options)
          endif
        catch
          call plugin_manager#core#handle_error(v:exception, "add")
          return 0
        endtry
      endfunction
      
      " Function to check if a plugin exists
      function! plugin_manager#cmd#add#exists(plugin_name, options) abort
        let l:plugin_name = a:plugin_name
        let l:custom_name = get(a:options, 'dir', '')
        let l:plugin_dir_name = empty(l:custom_name) ? l:plugin_name : l:custom_name
        
        " Determine install type (start/opt)
        let l:plugin_type = get(a:options, 'load', 'start')
        let l:plugin_dir = plugin_manager#core#get_plugin_dir(l:plugin_type) . '/' . l:plugin_dir_name
        
        return isdirectory(l:plugin_dir)
      endfunction
      
      " Helper function to install a remote plugin
      function! s:install_remote_plugin(url, options) abort
        let l:plugin_name = plugin_manager#core#extract_plugin_name(a:url)
        let l:custom_name = get(a:options, 'dir', '')
        let l:plugin_dir_name = empty(l:custom_name) ? l:plugin_name : l:custom_name
        
        " Determine install type (start/opt)
        let l:plugin_type = get(a:options, 'load', 'start')
        let l:plugin_dir = plugin_manager#core#get_plugin_dir(l:plugin_type) . '/' . l:plugin_dir_name
        
        let l:header = ['Add Plugin:', '----------', '', 'Installing ' . a:url . ' in ' . l:plugin_dir . '...']
        call plugin_manager#ui#open_sidebar(l:header)
        
        " Add the plugin as a git submodule
        if plugin_manager#git#add_submodule(a:url, l:plugin_dir, a:options)
          " Generate helptags if there's a doc directory
          let l:doc_path = l:plugin_dir . '/doc'
          if isdirectory(l:doc_path)
            call plugin_manager#ui#update_sidebar(['Generating helptags...'], 1)
            execute 'helptags ' . fnameescape(l:doc_path)
            call plugin_manager#ui#update_sidebar(['Helptags generated successfully.'], 1)
          endif
          
          call plugin_manager#ui#update_sidebar(['Plugin installed successfully.'], 1)
          return 1
        endif
        
        return 0
      endfunction
      
      " Helper function to install a local plugin
      function! s:install_local_plugin(path, options) abort
        let l:plugin_name = fnamemodify(a:path, ':t')
        let l:custom_name = get(a:options, 'dir', '')
        let l:plugin_dir_name = empty(l:custom_name) ? l:plugin_name : l:custom_name
        
        " Determine install type (start/opt)
        let l:plugin_type = get(a:options, 'load', 'start')
        let l:plugin_dir = plugin_manager#core#get_plugin_dir(l:plugin_type) . '/' . l:plugin_dir_name
        
        let l:header = ['Add Local Plugin:', '----------------', '', 'Installing from ' . a:path . ' to ' . l:plugin_dir . '...']
        call plugin_manager#ui#open_sidebar(l:header)
        
        " Check if local path exists
        if !isdirectory(a:path)
          throw 'PM_ERROR:add:Local directory "' . a:path . '" not found'
        endif
        
        " Check if destination directory exists
        if isdirectory(l:plugin_dir)
          throw 'PM_ERROR:add:Destination directory "' . l:plugin_dir . '" already exists'
        endif
        
        " Create parent directory if needed
        let l:parent_dir = fnamemodify(l:plugin_dir, ':h')
        if !isdirectory(l:parent_dir)
          call mkdir(l:parent_dir, 'p')
        endif
        
        " Create destination directory
        call mkdir(l:plugin_dir, 'p')
        
        " Copy files from local directory
        call s:copy_local_files(a:path, l:plugin_dir)
        
        " Execute custom command if provided
        if !empty(get(a:options, 'exec', ''))
          call plugin_manager#ui#update_sidebar(['Executing command: ' . a:options.exec . '...'], 1)
          let l:result = plugin_manager#git#execute(a:options.exec, l:plugin_dir, 1, 0)
          
          if !l:result.success
            call plugin_manager#ui#update_sidebar(['Warning: Command execution failed:', l:result.output], 1)
          else
            call plugin_manager#ui#update_sidebar(['Command executed successfully.'], 1)
          endif
        endif
        
        " Generate helptags if there's a doc directory
        let l:doc_path = l:plugin_dir . '/doc'
        if isdirectory(l:doc_path)
          call plugin_manager#ui#update_sidebar(['Generating helptags...'], 1)
          execute 'helptags ' . fnameescape(l:doc_path)
          call plugin_manager#ui#update_sidebar(['Helptags generated successfully.'], 1)
        endif
        
        call plugin_manager#ui#update_sidebar(['Local plugin installed successfully.'], 1)
        return 1
      endfunction
      
      " Helper function to copy local files
      function! s:copy_local_files(src_path, dest_path) abort
        call plugin_manager#ui#update_sidebar(['Copying files...'], 1)
        
        let l:copy_success = 0
        
        " Try rsync first (most reliable with .git exclusion)
        if executable('rsync')
          call plugin_manager#ui#update_sidebar(['Using rsync...'], 1)
          let l:rsync_command = 'rsync -a --exclude=".git" ' . shellescape(a:src_path . '/') . ' ' . shellescape(a:dest_path . '/')
          let l:result = plugin_manager#git#execute(l:rsync_command, '', 0, 0)
          let l:copy_success = l:result.success
          
          if l:copy_success
            return
          endif
        endif
        
        " Platform-specific fallbacks
        if has('win32') || has('win64')
          let l:copy_success = s:copy_files_windows(a:src_path, a:dest_path)
        else
          let l:copy_success = s:copy_files_unix(a:src_path, a:dest_path)
        endif
        
        if !l:copy_success
          throw 'PM_ERROR:add:Failed to copy files to destination'
        endif
      endfunction
      
      " Helper function for Windows copy operations
      function! s:copy_files_windows(src_path, dest_path) abort
        let l:copy_success = 0
        
        if executable('robocopy')
          call plugin_manager#ui#update_sidebar(['Using robocopy...'], 1)
          let l:result = plugin_manager#git#execute('robocopy ' . shellescape(a:src_path) . ' ' . 
                \ shellescape(a:dest_path) . ' /E /XD .git', '', 0, 0)
          " Note: robocopy returns non-zero for successful operations with info codes
          let l:copy_success = v:shell_error < 8
        endif
        
        if !l:copy_success && executable('xcopy')
          call plugin_manager#ui#update_sidebar(['Using xcopy...'], 1)
          let l:result = plugin_manager#git#execute('xcopy ' . shellescape(a:src_path) . '\* ' . 
                \ shellescape(a:dest_path) . ' /E /I /Y /EXCLUDE:.git', '', 0, 0)
          let l:copy_success = l:result.success
        endif
        
        return l:copy_success
      endfunction
      
      " Helper function for Unix copy operations
      function! s:copy_files_unix(src_path, dest_path) abort
        let l:copy_success = 0
        
        call plugin_manager#ui#update_sidebar(['Using cp/find...'], 1)
        let l:copy_cmd = 'cd ' . shellescape(a:src_path) . ' && find . -type d -name ".git" -prune -o -type f -print | ' .
              \ 'xargs -I{} cp --parents {} ' . shellescape(a:dest_path)
        let l:result = plugin_manager#git#execute(l:copy_cmd, '', 0, 0)
        let l:copy_success = l:result.success
        
        if !l:copy_success
          call plugin_manager#ui#update_sidebar(['Trying simple copy...'], 1)
          let l:result = plugin_manager#git#execute('cp -R ' . shellescape(a:src_path) . '/* ' . 
                \ shellescape(a:dest_path), '', 0, 0)
          let l:copy_success = l:result.success
          
          " Remove .git if it was copied
          if l:copy_success && isdirectory(a:dest_path . '/.git')
            let l:rm_result = plugin_manager#git#execute('rm -rf ' . shellescape(a:dest_path . '/.git'), '', 0, 0)
          endif
        endif
        
        return l:copy_success
      endfunction