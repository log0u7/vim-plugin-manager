" autoload/plugin_manager/modules/add.vim - Functions for adding plugins

" Handle 'add' command
function! plugin_manager#modules#add#plugin(...)
    try
      if a:0 < 1
        throw 'PM_ERROR:add:Missing plugin argument'
      endif
      
      let l:pluginInput = a:1
      let l:moduleUrl = plugin_manager#utils#convert_to_full_url(l:pluginInput)
      
      " Check if URL is valid or if it's a local path
      if empty(l:moduleUrl)
        throw 'PM_ERROR:add:Invalid plugin format: ' . l:pluginInput . '. Use format "user/repo", complete URL, or local path.'
      endif
      
      " Check if it's a local path
      let l:isLocalPath = l:moduleUrl =~ '^local:'
      
      " For remote plugins, check if repository exists
      if !l:isLocalPath && !plugin_manager#utils#repository_exists(l:moduleUrl)
        if l:pluginInput =~ g:pm_shortNameRegexp
          throw 'PM_ERROR:add:Repository not found: ' . l:moduleUrl . '. This plugin was not found on ' . g:plugin_manager_default_git_host . '.'
        else
          throw 'PM_ERROR:add:Repository not found: ' . l:moduleUrl
        endif
      endif
      
      " Process module options and determine installation path
      let [l:options, l:installDir, l:localPath] = s:process_add_options(l:moduleUrl, l:isLocalPath, a:000)
      
      " Call the appropriate installation function based on whether it's a local path
      if l:isLocalPath
        call s:add_local_module(l:localPath, l:installDir, l:options)
      else
        call s:add_module(l:moduleUrl, l:installDir, l:options)
      endif
      
      return 0
    catch
      let l:error = plugin_manager#utils#is_pm_error(v:exception) 
            \ ? plugin_manager#utils#format_error(v:exception)
            \ : 'Unexpected error during plugin installation: ' . v:exception
            
      let l:lines = ["Add Plugin Error:", repeat('-', 17), "", l:error]
      if !plugin_manager#utils#is_pm_error(v:exception)
        " For unexpected errors, add usage information
        let l:lines += ["", "Usage: PluginManager add <plugin> [options]", 
              \ "Options: {'dir':'custom_dir', 'load':'start|opt', 'branch':'branch_name', 'tag':'tag_name', 'exec':'command'}"]
      endif
      
      call plugin_manager#ui#open_sidebar(l:lines)
      return 1
    endtry
endfunction
  
" Helper function to process options and determine installation path
function! s:process_add_options(moduleUrl, isLocalPath, args)
    " Extract the actual path for local plugins
    let l:localPath = a:isLocalPath ? substitute(a:moduleUrl, '^local:', '', '') : ''
    
    " Get module name - for local paths, use the directory name
    if a:isLocalPath
      let l:moduleName = fnamemodify(l:localPath, ':t')
    else
      " Extract repo name from URL, preserving dots in the name
      let l:moduleName = matchstr(a:moduleUrl, '[^/]*$')  " Get everything after the last /
      let l:moduleName = substitute(l:moduleName, '\.git$', '', '')  " Remove .git extension if present
    endif
    
    " Initialize options with defaults
    let l:options = {
          \ 'dir': '',
          \ 'load': 'start',
          \ 'branch': '',
          \ 'tag': '',
          \ 'exec': ''
          \ }
    
    " Check if options were provided
    if len(a:args) >= 2
      " Check if the second argument is a dictionary (new format) or string (old format)
      if type(a:args[1]) == v:t_dict
        " New format with options dictionary
        let l:provided_options = a:args[1]
        
        " Update options with provided values
        for [l:key, l:val] in items(l:provided_options)
          if has_key(l:options, l:key)
            let l:options[l:key] = l:val
          endif
        endfor
      else
        " Old format with separate arguments
        " Custom name was provided as second argument
        let l:options.dir = a:args[1]
        
        " Optional loading was provided as third argument
        if len(a:args) >= 3 && a:args[2] != ""
          let l:options.load = 'opt'
        endif
      endif
    endif
    
    " Set custom directory name if provided, otherwise use plugin name
    let l:dirName = !empty(l:options.dir) ? l:options.dir : l:moduleName
    
    " Set load dir based on options
    let l:loadDir = l:options.load == 'opt' ? g:plugin_manager_opt_dir : g:plugin_manager_start_dir
    
    " Construct full installation path
    let l:installDir = g:plugin_manager_plugins_dir . "/" . l:loadDir . "/" . l:dirName
    
    return [l:options, l:installDir, l:localPath]
endfunction
  
" Add a new plugin from remote repository
function! s:add_module(moduleUrl, installDir, options)
    try
      if !plugin_manager#utils#ensure_vim_directory()
        throw 'PM_ERROR:add:Not in Vim configuration directory'
      endif
      
      let l:header = ['Add Plugin:', '----------', '', 'Installing ' . a:moduleUrl . ' in ' . a:installDir . '...']
      call plugin_manager#ui#open_sidebar(l:header)
      
      " Check and create parent directory if needed
      call s:prepare_parent_directory(a:installDir)
  
      " Ensure the path is relative to vim directory
      let l:relativeInstallDir = substitute(a:installDir, '^' . g:plugin_manager_vim_dir . '/', '', '')
      
      " Check if submodule already exists
      call s:check_submodule_exists(l:relativeInstallDir)
      
      " Execute git submodule add command
      call plugin_manager#ui#update_sidebar(['Adding Git submodule...'], 1)
      let l:result = system('git submodule add "' . a:moduleUrl . '" "' . l:relativeInstallDir . '"')
      if v:shell_error != 0
        throw 'PM_ERROR:add:Error installing plugin: ' . l:result
      endif
      
      " Process branch and tag options if provided
      call s:process_version_options(l:relativeInstallDir, a:options)
      
      " Execute custom command if provided
      call s:execute_post_command(l:relativeInstallDir, a:options)
      
      " Commit changes
      call s:commit_installation(a:moduleUrl, a:options)
      
      " Generate helptags
      call s:generate_plugin_helptags(a:installDir)
      
    catch
      let l:error = plugin_manager#utils#is_pm_error(v:exception) 
            \ ? plugin_manager#utils#format_error(v:exception)
            \ : 'Error adding remote plugin: ' . v:exception
      
      call plugin_manager#ui#update_sidebar(['Error: ' . l:error], 1)
    endtry
endfunction
  
" Add a plugin from local directory
function! s:add_local_module(localPath, installDir, options)
    try
      if !plugin_manager#utils#ensure_vim_directory()
        throw 'PM_ERROR:add:Not in Vim configuration directory'
      endif
      
      let l:header = ['Add Local Plugin:', '----------------', '', 'Installing from ' . a:localPath . ' to ' . a:installDir . '...']
      call plugin_manager#ui#open_sidebar(l:header)
      
      " Check if local path exists
      if !isdirectory(a:localPath)
        throw 'PM_ERROR:add:Local directory "' . a:localPath . '" not found'
      endif
      
      " Check and create parent directory if needed
      call s:prepare_parent_directory(a:installDir)
      
      " Ensure the installation directory doesn't already exist
      if isdirectory(a:installDir)
        throw 'PM_ERROR:add:Destination directory "' . a:installDir . '" already exists'
      endif
      
      " Create the destination directory
      call mkdir(a:installDir, 'p')
      
      " Copy the files, excluding .git directory if it exists
      call s:copy_local_files(a:localPath, a:installDir)
      
      " Execute custom command if provided
      call s:execute_post_command(a:installDir, a:options)
      
      " Generate helptags
      call s:generate_plugin_helptags(a:installDir)
      
    catch
      let l:error = plugin_manager#utils#is_pm_error(v:exception) 
            \ ? plugin_manager#utils#format_error(v:exception)
            \ : 'Error adding local plugin: ' . v:exception
      
      call plugin_manager#ui#update_sidebar(['Error: ' . l:error], 1)
    endtry
endfunction
  
" Helper function to check and create parent directory
function! s:prepare_parent_directory(installDir)
    let l:parentDir = fnamemodify(a:installDir, ':h')
    if !isdirectory(l:parentDir)
      call mkdir(l:parentDir, 'p')
    endif
endfunction
  
" Helper function to check if submodule exists
function! s:check_submodule_exists(relativeInstallDir)
    let l:gitmoduleCheck = system('grep -c "' . a:relativeInstallDir . '" .gitmodules 2>/dev/null')
    if shellescape(l:gitmoduleCheck) != 0
      throw 'PM_ERROR:add:Plugin already installed at this location: ' . a:relativeInstallDir
    endif
endfunction
  
" Helper function to process branch and tag options
function! s:process_version_options(installDir, options)
    if !empty(a:options.branch)
      call plugin_manager#ui#update_sidebar(['Checking out branch: ' . a:options.branch . '...'], 1)
      let l:branch_result = system('cd "' . a:installDir . '" && git checkout ' . a:options.branch)
      if v:shell_error != 0
        call plugin_manager#ui#update_sidebar(['Warning: Failed to checkout branch: ' . a:options.branch, 
              \ l:branch_result], 1)
      endif
    elseif !empty(a:options.tag)
      call plugin_manager#ui#update_sidebar(['Checking out tag: ' . a:options.tag . '...'], 1)
      let l:tag_result = system('cd "' . a:installDir . '" && git checkout ' . a:options.tag)
      if v:shell_error != 0
        call plugin_manager#ui#update_sidebar(['Warning: Failed to checkout tag: ' . a:options.tag, 
              \ l:tag_result], 1)
      endif
    endif
endfunction
  
" Helper function to execute post-installation command
function! s:execute_post_command(installDir, options)
    if !empty(a:options.exec)
      call plugin_manager#ui#update_sidebar(['Executing command: ' . a:options.exec . '...'], 1)
      let l:exec_result = system('cd "' . a:installDir . '" && ' . a:options.exec)
      if v:shell_error != 0
        call plugin_manager#ui#update_sidebar(['Warning: Command execution failed:', 
              \ l:exec_result], 1)
      else
        call plugin_manager#ui#update_sidebar(['Command executed successfully.'], 1)
      endif
    endif
endfunction
  
" Helper function to commit installation
function! s:commit_installation(moduleUrl, options)
    call plugin_manager#ui#update_sidebar(['Committing changes...'], 1)
    
    " Create a more informative commit message
    let l:commit_msg = "Added " . a:moduleUrl . " module"
    if !empty(a:options.branch)
      let l:commit_msg .= " (branch: " . a:options.branch . ")"
    elseif !empty(a:options.tag)
      let l:commit_msg .= " (tag: " . a:options.tag . ")"
    endif
    
    let l:result = system('git commit -m "' . l:commit_msg . '"')
    if v:shell_error != 0
      call plugin_manager#ui#update_sidebar(['Error committing changes:', l:result], 1)
    else
      call plugin_manager#ui#update_sidebar(['Plugin installed successfully.'], 1)
    endif
endfunction
  
" Helper function to generate helptags
function! s:generate_plugin_helptags(installDir)
    call plugin_manager#ui#update_sidebar(['Generating helptags...'], 1)
    
    let l:docPath = a:installDir . '/doc'
    if isdirectory(l:docPath)
      execute 'helptags ' . l:docPath
      call plugin_manager#ui#update_sidebar(['Helptags generated successfully.'], 1)
    else
      call plugin_manager#ui#update_sidebar(['No documentation directory found.'], 1)
    endif
endfunction
  
" Helper function to copy local files
function! s:copy_local_files(srcPath, destPath)
    let l:copy_result = ''
    let l:copy_success = 0
    
    call plugin_manager#ui#update_sidebar(['Copying files...'], 1)
    
    " Try rsync first (most reliable with .git exclusion)
    if executable('rsync')
      call plugin_manager#ui#update_sidebar(['Using rsync...'], 1)
      let l:rsync_command = 'rsync -a --exclude=".git" ' . shellescape(a:srcPath . '/') . ' ' . shellescape(a:destPath . '/')
      let l:copy_result = system(l:rsync_command)
      let l:copy_success = v:shell_error == 0
      
      if l:copy_success
        return
      endif
    endif
    
    " Platform-specific fallbacks
    if has('win32') || has('win64')
      call s:copy_files_windows(a:srcPath, a:destPath, l:copy_success)
    else
      call s:copy_files_unix(a:srcPath, a:destPath, l:copy_success)
    endif
    
    if !l:copy_success
      throw 'PM_ERROR:add:Failed to copy files to destination'
    endif
endfunction
  
" Helper function for Windows copy operations
function! s:copy_files_windows(srcPath, destPath, copy_success)
    let l:copy_success = a:copy_success
    
    if executable('robocopy') && !l:copy_success
      call plugin_manager#ui#update_sidebar(['Using robocopy...'], 1)
      let l:copy_result = system('robocopy ' . shellescape(a:srcPath) . ' ' . shellescape(a:destPath) . ' /E /XD .git')
      " Note: robocopy returns non-zero for successful operations with info codes
      let l:copy_success = v:shell_error < 8
    endif
    
    if executable('xcopy') && !l:copy_success
      call plugin_manager#ui#update_sidebar(['Using xcopy...'], 1)
      let l:copy_result = system('xcopy ' . shellescape(a:srcPath) . '\* ' . shellescape(a:destPath) . ' /E /I /Y /EXCLUDE:.git')
      let l:copy_success = v:shell_error == 0
    endif
    
    return l:copy_success
endfunction
  
" Helper function for Unix copy operations
function! s:copy_files_unix(srcPath, destPath, copy_success)
    let l:copy_success = a:copy_success
    
    if !l:copy_success
      call plugin_manager#ui#update_sidebar(['Using cp/find...'], 1)
      let l:copy_cmd = 'cd ' . shellescape(a:srcPath) . ' && find . -type d -name ".git" -prune -o -type f -print | xargs -I{} cp --parents {} ' . shellescape(a:destPath)
      let l:copy_result = system(l:copy_cmd)
      let l:copy_success = v:shell_error == 0
    endif
    
    if !l:copy_success
      call plugin_manager#ui#update_sidebar(['Trying simple copy...'], 1)
      let l:copy_result = system('cp -R ' . shellescape(a:srcPath) . '/* ' . shellescape(a:destPath))
      let l:copy_success = v:shell_error == 0
      
      " Remove .git if it was copied
      if l:copy_success && isdirectory(a:destPath . '/.git')
        let l:rm_result = system('rm -rf ' . shellescape(a:destPath . '/.git'))
      endif
    endif
    
    return l:copy_success
endfunction