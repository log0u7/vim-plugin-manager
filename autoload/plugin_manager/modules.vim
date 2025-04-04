" Module management functions for vim-plugin-manager

" Variable to prevent multiple concurrent updates
let s:update_in_progress = 0

" List all installed plugins
function! plugin_manager#modules#list()
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
    
    " Use the gitmodules cache
    let l:modules = plugin_manager#utils#parse_gitmodules()
    
    if empty(l:modules)
      let l:lines = ['Installed Plugins:', '----------------', '', 'No plugins installed (.gitmodules not found)']
      call plugin_manager#ui#open_sidebar(l:lines)
      return
    endif
    
    let l:lines = ['Installed Plugins:', '----------------', '', 'Name'.repeat(' ', 20).'Path'.repeat(' ', 30).'URL']
    let l:lines += [repeat('-', 100)]
    
    " Sort modules by name
    let l:module_names = sort(keys(l:modules))
    
    for l:name in l:module_names
      let l:module = l:modules[l:name]
      if has_key(l:module, 'is_valid') && l:module.is_valid
        let l:short_name = l:module.short_name
        let l:path = l:module.path
        let l:url = l:module.url
        
        " Format the output with aligned columns
        let l:name_col = l:short_name . repeat(' ', max([0, 20 - len(l:short_name)]))
        let l:path_col = l:path . repeat(' ', max([0, 30 - len(l:path)]))
        
        let l:status = has_key(l:module, 'exists') && l:module.exists ? '' : ' [MISSING]'
        
        call add(l:lines, l:name_col . l:path_col . l:url . l:status)
      endif
    endfor
    
    call plugin_manager#ui#open_sidebar(l:lines)
endfunction
  
" Show the status of submodules with detailed information
function! plugin_manager#modules#status()
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
    
    " Use the gitmodules cache
    let l:modules = plugin_manager#utils#parse_gitmodules()
    
    if empty(l:modules)
      let l:lines = ['Submodule Status:', '----------------', '', 'No submodules found (.gitmodules not found)']
      call plugin_manager#ui#open_sidebar(l:lines)
      return
    endif
    
    let l:lines = ['Submodule Status:', '----------------', '']
    call add(l:lines, 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 12).'Branch'.repeat(' ', 10).'Last Updated'.repeat(' ', 12).'Status')
    call add(l:lines, repeat('-', 100))
    
    " Sort modules by name
    let l:module_names = sort(keys(l:modules))
    
    for l:name in l:module_names
      let l:module = l:modules[l:name]
      if has_key(l:module, 'is_valid') && l:module.is_valid
        let l:path = l:module.path
        
        " Get current commit
        let l:commit = system('cd "' . l:path . '" && git rev-parse --short HEAD 2>/dev/null || echo "N/A"')
        let l:commit = substitute(l:commit, '\n', '', 'g')
        
        " Get current branch
        let l:branch = system('cd "' . l:path . '" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A"')
        let l:branch = substitute(l:branch, '\n', '', 'g')
        
        " Get last commit date
        let l:last_updated = system('cd "' . l:path . '" && git log -1 --format=%cd --date=relative 2>/dev/null || echo "N/A"')
        let l:last_updated = substitute(l:last_updated, '\n', '', 'g')
        
        " Check if there are uncommitted changes
        let l:changes = system('cd "' . l:path . '" && git status -s 2>/dev/null')
        let l:has_changes = !empty(l:changes)
        
        " Check if behind/ahead of remote
        let l:behind_ahead = system('cd "' . l:path . '" && git rev-list --count --left-right @{upstream}...HEAD 2>/dev/null || echo "?"')
        let l:behind_ahead = substitute(l:behind_ahead, '\n', '', 'g')
        let l:behind_ahead_parts = split(l:behind_ahead, '\t')
        let l:behind = len(l:behind_ahead_parts) >= 1 ? l:behind_ahead_parts[0] : '?'
        let l:ahead = len(l:behind_ahead_parts) >= 2 ? l:behind_ahead_parts[1] : '?'
        
        " Determine status
        let l:status = 'OK'
        if !isdirectory(l:path)
          let l:status = 'MISSING'
        elseif l:has_changes
          let l:status = 'LOCAL CHANGES'
        elseif l:behind != '0' && l:behind != '?'
          let l:status = 'BEHIND (' . l:behind . ')'
        elseif l:ahead != '0' && l:ahead != '?'
          let l:status = 'AHEAD (' . l:ahead . ')'
        endif
        
        " Format the output with aligned columns
        let l:name_col = l:module.short_name . repeat(' ', max([0, 20 - len(l:module.short_name)]))
        let l:commit_col = l:commit . repeat(' ', max([0, 15 - len(l:commit)]))
        let l:branch_col = l:branch . repeat(' ', max([0, 15 - len(l:branch)]))
        let l:date_col = l:last_updated . repeat(' ', max([0, 20 - len(l:last_updated)]))
        
        call add(l:lines, l:name_col . l:commit_col . l:branch_col . l:date_col . l:status)
      endif
    endfor
    
    call plugin_manager#ui#open_sidebar(l:lines)
endfunction
  
" Show a summary of submodule changes
function! plugin_manager#modules#summary()
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
    
    " Check if .gitmodules exists
    if !filereadable('.gitmodules')
      let l:lines = ['Submodule Summary:', '----------------', '', 'No submodules found (.gitmodules not found)']
      call plugin_manager#ui#open_sidebar(l:lines)
      return
    endif
    
    let l:output = system('git submodule summary')
    let l:lines = ['Submodule Summary:', '----------------', '']
    call extend(l:lines, split(l:output, "\n"))
    
    call plugin_manager#ui#open_sidebar(l:lines)
endfunction
  
" Generate helptags for a specific plugin
function! s:generate_helptag(pluginPath)
    let l:docPath = a:pluginPath . '/doc'
    if isdirectory(l:docPath)
      execute 'helptags ' . l:docPath
      return 1
    endif
    return 0
endfunction
  
" Generate helptags for all installed plugins
function! plugin_manager#modules#generate_helptags(...)
    " Fix: Properly handle optional arguments
    let l:create_header = a:0 > 0 ? a:1 : 1
    let l:specific_module = a:0 > 1 ? a:2 : ''
    
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
      
    " Initialize output only if creating a new header
    if l:create_header
      let l:header = ['Generating Helptags:', '------------------', '', 'Generating helptags:']
      call plugin_manager#ui#open_sidebar(l:header)
    else
      " If we're not creating a new header, just add a separator line
      call plugin_manager#ui#update_sidebar(['', 'Generating helptags:'], 1)
    endif
  
    " Fix: Check if plugins directory exists
    let l:pluginsDir = g:plugin_manager_plugins_dir . '/'
    let l:tagsGenerated = 0
    let l:generated_plugins = []
    
    if isdirectory(l:pluginsDir)
      if !empty(l:specific_module)
        " Find the specific plugin path
        let l:plugin_pattern = l:pluginsDir . '*/*' . l:specific_module . '*'
        for l:plugin in glob(l:plugin_pattern, 0, 1)
          if s:generate_helptag(l:plugin)
            let l:tagsGenerated = 1
            call add(l:generated_plugins, "Generated helptags for " . fnamemodify(l:plugin, ':t'))
          endif
        endfor
      else
        " Generate helptags for all plugins
        for l:plugin in glob(l:pluginsDir . '*/*', 0, 1)
          if s:generate_helptag(l:plugin)
            let l:tagsGenerated = 1
            call add(l:generated_plugins, "Generated helptags for " . fnamemodify(l:plugin, ':t'))
          endif
        endfor
      endif
    endif
  
    let l:result_message = []
    if l:tagsGenerated
      call extend(l:result_message, l:generated_plugins)
      call add(l:result_message, "Helptags generated successfully.")
    else
      call add(l:result_message, "No documentation directories found.")
    endif
    
    call plugin_manager#ui#update_sidebar(l:result_message, 1)
endfunction
  
" Update plugins using async jobs
function! plugin_manager#modules#update(...)
  " Prevent multiple concurrent update calls
  if exists('s:update_in_progress') && s:update_in_progress
    return
  endif
  let s:update_in_progress = 1

  if !plugin_manager#utils#ensure_vim_directory()
    let s:update_in_progress = 0
    return
  endif
  
  " Use the gitmodules cache
  let l:modules = plugin_manager#utils#parse_gitmodules()
  
  if empty(l:modules)
    let l:lines = ['Updating Plugins:', '----------------', '', 'No plugins to update (.gitmodules not found)']
    call plugin_manager#ui#open_sidebar(l:lines)
    let s:update_in_progress = 0
    return
  endif
  
  " Check if a specific module was specified
  let l:specific_module = a:0 > 0 ? a:1 : 'all'
  
  if l:specific_module == 'all'
    let l:title = 'Updating All Plugins'
    
    " Create command chain for all plugins
    let l:cmd = 'git submodule foreach --recursive "git stash -q || true" && '
    let l:cmd .= 'git submodule sync && '
    let l:cmd .= 'git submodule update --remote --merge --force && '
    let l:cmd .= 'git status -s | wc -l | xargs -I {} /bin/sh -c "if [ {} -gt 0 ]; then git commit -am \"Update Modules\"; fi"'
    
    " Execute command asynchronously
    call plugin_manager#jobs#execute(l:title, l:cmd, function('s:update_complete_callback'), 'all')
  else
    " Update a specific module - use find_module function
    let l:module_info = plugin_manager#utils#find_module(l:specific_module)
    
    if empty(l:module_info)
      let l:header = ['Updating Plugins:', '----------------', '']
      call plugin_manager#ui#open_sidebar(l:header + ['Error: Module "' . l:specific_module . '" not found.'])
      let s:update_in_progress = 0
      return
    endif
    
    let l:module = l:module_info.module
    let l:module_path = l:module.path
    let l:module_name = l:module.short_name
    
    let l:title = 'Updating Plugin: ' . l:module_name
    
    " Check if directory exists
    if !isdirectory(l:module_path)
      let l:header = ['Updating Plugins:', '----------------', '']
      call plugin_manager#ui#open_sidebar(l:header + ['Error: Module directory "' . l:module_path . '" not found.', 
            \ 'Try running "PluginManager restore" to reinstall missing modules.'])
      let s:update_in_progress = 0
      return
    endif
    
    " Create command chain for specific plugin
    let l:cmd = 'cd "' . l:module_path . '" && git stash -q || true && cd "' . g:plugin_manager_vim_dir . '" && '
    let l:cmd .= 'git submodule sync -- "' . l:module_path . '" && '
    let l:cmd .= 'git submodule update --remote --merge --force -- "' . l:module_path . '" && '
    let l:cmd .= 'git status -s | wc -l | xargs -I {} /bin/sh -c "if [ {} -gt 0 ]; then git commit -am \"Update Module: ' . l:module_name . '\"; fi"'
    
    " Execute command asynchronously
    call plugin_manager#jobs#execute(l:title, l:cmd, function('s:update_complete_callback'), l:specific_module)
  endif
endfunction

" Callback function when update completes
function! s:update_complete_callback(job_id, status, output, module_name)
  " Update with results
  let l:update_lines = []
  
  " Show what was updated
  let l:update_lines += ['Checking for updates...']
  let l:updated_modules = []
  
  " Check what was updated
  if a:module_name == 'all'
    " Use the gitmodules cache
    let l:modules = plugin_manager#utils#parse_gitmodules()
    
    " Check all modules
    for [l:name, l:module] in items(l:modules)
      if l:module.is_valid && isdirectory(l:module.path)
        " Use async job for this check
        let l:cmd = 'cd "' . l:module.path . '" && git log -1 --format="%h %s" 2>/dev/null'
        let l:log_output = system(l:cmd) " This could be async too, but we need results now
        if !empty(l:log_output)
          call add(l:updated_modules, l:module.short_name . ': ' . substitute(l:log_output, '\n', '', 'g'))
        endif
      endif
    endfor
  else
    " Get module_info again for safety
    let l:module_info = plugin_manager#utils#find_module(a:module_name)
    if !empty(l:module_info)
      let l:module = l:module_info.module
      let l:module_path = l:module.path
      let l:module_name = l:module.short_name
      
      if isdirectory(l:module_path)
        let l:cmd = 'cd "' . l:module_path . '" && git log -1 --format="%h %s" 2>/dev/null'
        let l:log_output = system(l:cmd) " This could be async too, but we need results now
        if !empty(l:log_output)
          call add(l:updated_modules, l:module_name . ': ' . substitute(l:log_output, '\n', '', 'g'))
        endif
      endif
    endif
  endif
  
  if !empty(l:updated_modules)
    let l:update_lines += ['Latest commits:']
    let l:update_lines += l:updated_modules
  endif
  
  " Add update success message
  if a:status == 0
    if a:module_name == 'all'
      let l:update_lines += ['', 'All plugins updated successfully.']
    else
      let l:update_lines += ['', 'Plugin "' . a:module_name . '" updated successfully.']
    endif
  else
    let l:update_lines += ['', 'Update completed with errors. Check output above.']
  endif
  
  " Update sidebar with results
  call plugin_manager#ui#update_sidebar(l:update_lines, 1)
  
  " Generate helptags
  if a:module_name == 'all'
    " Call with flag to indicate NOT to create a header - use our existing sidebar
    call plugin_manager#modules#generate_helptags(0)
  else
    " Generate helptags only for the specific module
    call plugin_manager#modules#generate_helptags(0, a:module_name)
  endif
  
  " Force refresh the cache after updates
  call plugin_manager#utils#refresh_modules_cache()
  
  " Reset update in progress flag
  let s:update_in_progress = 0
endfunction
  
" Handle 'add' command with async job support
function! plugin_manager#modules#add(...)
  if a:0 < 1
    let l:lines = ["Add Plugin Usage:", "---------------", "", "Usage: PluginManager add <plugin> [modulename] [opt]"]
    call plugin_manager#ui#open_sidebar(l:lines)
    return 1
  endif
  
  let l:pluginInput = a:1
  let l:moduleUrl = plugin_manager#utils#convert_to_full_url(l:pluginInput)
  
  " Check if URL is valid
  if empty(l:moduleUrl)
    let l:lines = ["Invalid Plugin Format:", "--------------------", "", l:pluginInput . " is not a valid plugin name or URL.", "Use format 'user/repo' or complete URL."]
    call plugin_manager#ui#open_sidebar(l:lines)
    return 1
  endif
  
  " Check if repository exists - this check needs to be synchronous for UX
  if !plugin_manager#utils#repository_exists(l:moduleUrl)
    let l:lines = ["Repository Not Found:", "--------------------", "", "Repository not found: " . l:moduleUrl]
    
    " If it was a short name, suggest using a full URL
    if l:pluginInput =~ g:pm_shortNameRegexp
      call add(l:lines, "This plugin was not found on " . g:plugin_manager_default_git_host . ".")
      call add(l:lines, "Try using a full URL to the repository if it's hosted elsewhere.")
    endif
    
    call plugin_manager#ui#open_sidebar(l:lines)
    return 1
  endif
  
  " If we got here, the repository exists
  let l:moduleName = fnamemodify(l:moduleUrl, ':t:r')  " Remove .git from the end if present
  
  " Check if a custom module name was provided
  let l:installDir = ""
  
  " Fix: Better parameter handling
  let l:customName = a:0 >= 2 ? a:2 : ""
  let l:isOptional = a:0 >= 3 && a:3 != ""
  
  if l:isOptional
    " Install in opt directory
    if !empty(l:customName)
      let l:installDir = g:plugin_manager_plugins_dir . "/" . g:plugin_manager_opt_dir . "/" . l:customName
    else
      let l:installDir = g:plugin_manager_plugins_dir . "/" . g:plugin_manager_opt_dir . "/" . l:moduleName
    endif
  else
    " Install in start directory
    if !empty(l:customName)
      let l:installDir = g:plugin_manager_plugins_dir . "/" . g:plugin_manager_start_dir . "/" . l:customName
    else
      let l:installDir = g:plugin_manager_plugins_dir . "/" . g:plugin_manager_start_dir . "/" . l:moduleName
    endif
  endif
  
  call s:add_module(l:moduleUrl, l:installDir)
  return 0
endfunction

" Add a new plugin with async job support
function! s:add_module(moduleUrl, installDir)
  if !plugin_manager#utils#ensure_vim_directory()
    return
  endif
  
  let l:title = 'Adding Plugin: ' . fnamemodify(a:moduleUrl, ':t:r')
  
  " Ensure the path is relative to vim directory
  let l:relativeInstallDir = substitute(a:installDir, '^' . g:plugin_manager_vim_dir . '/', '', '')
  
  " Check if module directory exists and create if needed
  let l:parentDir = fnamemodify(a:installDir, ':h')
  if !isdirectory(l:parentDir)
    call mkdir(l:parentDir, 'p')
  endif
  
  " Fix: Check if submodule already exists
  let l:gitmoduleCheck = system('grep -c "' . l:relativeInstallDir . '" .gitmodules 2>/dev/null')
  if shellescape(l:gitmoduleCheck) != 0
    call plugin_manager#ui#open_sidebar([l:title, repeat('-', len(l:title)), '', 'Error: Plugin already installed at this location :'. l:relativeInstallDir])
    return
  end
  
  " Create command chain for adding plugin
  let l:cmd = 'git submodule add "' . a:moduleUrl . '" "' . l:relativeInstallDir . '" && '
  let l:cmd .= 'git commit -m "Added ' . a:moduleUrl . ' module"'
  
  " Execute command asynchronously
  call plugin_manager#jobs#execute(l:title, l:cmd, function('s:add_module_complete_callback'), a:installDir)
endfunction

" Callback function when add module completes
function! s:add_module_complete_callback(job_id, status, output, installDir)
  let l:result_lines = []
  
  if a:status == 0
    let l:result_lines += ['Plugin installed successfully.', 'Generating helptags...']
    if s:generate_helptag(a:installDir)
      let l:result_lines += ['Helptags generated successfully.']
    else
      let l:result_lines += ['No documentation directory found.']
    endif
  else
    let l:result_lines += ['Error installing plugin:', '']
    let l:result_lines += a:output
  endif
  
  " Force refresh the cache after adding a module
  call plugin_manager#utils#refresh_modules_cache()
  
  call plugin_manager#ui#update_sidebar(l:result_lines, 1)
endfunction

" Remove module using async job
function! plugin_manager#modules#remove(...)
  if a:0 < 1
    let l:lines = ["Remove Plugin Usage:", "-----------------", "", "Usage: PluginManager remove <modulename> [-f]"]
    call plugin_manager#ui#open_sidebar(l:lines)
    return 1
  endif
  
  let l:moduleName = a:1
  let l:force_flag = a:0 >= 2 && a:2 == "-f"
  
  " Use the module finder from the cache system
  let l:module_info = plugin_manager#utils#find_module(l:moduleName)
  
  if !empty(l:module_info)
    let l:module = l:module_info.module
    let l:module_path = l:module.path
    let l:module_name = l:module.short_name
    
    " Force flag provided or prompt for confirmation
    if l:force_flag
      call s:remove_module(l:module_name, l:module_path, l:module.url)
    else
      let l:response = input("Are you sure you want to remove " . l:module_name . " (" . l:module_path . ")? [y/N] ")
      if l:response =~? '^y\(es\)\?$'
        call s:remove_module(l:module_name, l:module_path, l:module.url)
      endif
    endif
  else
    " Module not found in cache, fallback to filesystem search
    let l:removedPluginPath = ""
    
    " Try direct filesystem search
    let l:find_cmd = 'find ' . g:plugin_manager_plugins_dir . ' -type d -name "*' . l:moduleName . '*" | head -n1'
    let l:removedPluginPath = substitute(system(l:find_cmd), '\n$', '', '')
    
    if !empty(l:removedPluginPath) && isdirectory(l:removedPluginPath)
      let l:filesystem_name = fnamemodify(l:removedPluginPath, ':t')
      
      " Force flag provided or prompt for confirmation
      if l:force_flag
        call s:remove_module(l:filesystem_name, l:removedPluginPath, "")
      else
        let l:response = input("Are you sure you want to remove " . l:filesystem_name . " (" . l:removedPluginPath . ")? [y/N] ")
        if l:response =~? '^y\(es\)\?$'
          call s:remove_module(l:filesystem_name, l:removedPluginPath, "")
        endif
      endif
    else
      " Provide more informative error for debugging
      let l:lines = ["Module Not Found:", "----------------", "", 
            \ "Unable to find module '" . l:moduleName . "'", ""]
      
      " List available modules for reference
      let l:modules = plugin_manager#utils#parse_gitmodules()
      if !empty(l:modules)
        let l:lines += ["Available modules:"]
        for [l:name, l:module] in items(l:modules)
          if l:module.is_valid
            call add(l:lines, "- " . l:module.short_name . " (" . l:module.path . ")")
          endif
        endfor
      else
        let l:lines += ["No modules found in .gitmodules"]
        
        " Check filesystem if nothing in .gitmodules
        let l:fs_plugins = systemlist('find ' . g:plugin_manager_plugins_dir . ' -mindepth 2 -maxdepth 2 -type d | sort')
        if !empty(l:fs_plugins)
          let l:lines += ["", "Plugin directories found in filesystem:"]
          let l:lines += l:fs_plugins
        endif
      endif
      
      call plugin_manager#ui#open_sidebar(l:lines)
      return 1
    endif
  endif
  
  return 0
endfunction

" Remove an existing plugin with async job support
function! s:remove_module(moduleName, removedPluginPath, moduleUrl)
  if !plugin_manager#utils#ensure_vim_directory()
    return
  endif
  
  let l:title = 'Removing Plugin: ' . a:moduleName
  
  " Create command chain for removing module
  let l:cmd = 'git submodule deinit -f "' . a:removedPluginPath . '" && '
  let l:cmd .= 'git rm -f "' . a:removedPluginPath . '" && '
  let l:cmd .= 'rm -rf ".git/modules/' . a:removedPluginPath . '" 2>/dev/null || true && '
  
  " Commit message with URL if available
  let l:commit_msg = "Removed " . a:moduleName . " module"
  if !empty(a:moduleUrl)
    let l:commit_msg .= " (" . a:moduleUrl . ")"
  endif
  let l:cmd .= 'git add -A && git commit -m "' . l:commit_msg . '" || git commit --allow-empty -m "' . l:commit_msg . '"'
  
  " Execute command asynchronously
  call plugin_manager#jobs#execute(l:title, l:cmd, function('s:remove_module_complete_callback'), a:moduleName)
endfunction

" Callback function when remove module completes
function! s:remove_module_complete_callback(job_id, status, output, moduleName)
  let l:result_lines = []
  
  if a:status == 0
    let l:result_lines += ['Plugin "' . a:moduleName . '" removed successfully.']
  else
    let l:result_lines += ['Warning: There were issues removing the plugin:']
    let l:result_lines += ['Manual cleanup may be required.', '']
    let l:result_lines += a:output
  endif
  
  " Force refresh the cache after removal
  call plugin_manager#utils#refresh_modules_cache()
  
  call plugin_manager#ui#update_sidebar(l:result_lines, 1)
endfunction

" Backup configuration to remote repositories using async jobs
function! plugin_manager#modules#backup()
  if !plugin_manager#utils#ensure_vim_directory()
    return
  endif
  
  let l:title = 'Backing Up Configuration'
  
  " Create command chain for backup
  let l:cmd = 'git status -s | wc -l | xargs -I {} /bin/sh -c "if [ {} -gt 0 ]; then git commit -am \"Automatic backup\"; fi" && '
  
  " Check if any remotes exist
  let l:remotesExist = system('git remote')
  if empty(l:remotesExist)
    call plugin_manager#ui#open_sidebar([l:title, repeat('-', len(l:title)), '', 
          \ 'No remote repositories configured.',
          \ 'Use PluginManagerRemote to add a remote repository.'])
    return
  endif
  
  " Add push command
  let l:cmd .= 'git push --all'
  
  " Execute command asynchronously
  call plugin_manager#jobs#execute(l:title, l:cmd, function('s:backup_complete_callback'))
endfunction

" Callback function when backup completes
function! s:backup_complete_callback(job_id, status, output)
  let l:result_lines = []
  
  if a:status == 0
    let l:result_lines += ['Backup completed successfully.']
  else
    let l:result_lines += ['Warning: There were issues with the backup:']
    let l:result_lines += a:output
  endif
  
  call plugin_manager#ui#update_sidebar(l:result_lines, 1)
endfunction

" Restore all plugins from .gitmodules using async jobs
function! plugin_manager#modules#restore()
  if !plugin_manager#utils#ensure_vim_directory()
    return
  endif
  
  let l:title = 'Restoring Plugins'
  
  " First, check if .gitmodules exists
  if !filereadable('.gitmodules')
    call plugin_manager#ui#open_sidebar([l:title, repeat('-', len(l:title)), '', 'Error: .gitmodules file not found!'])
    return
  endif
  
  " Create command chain for restore
  let l:cmd = 'git submodule init && '
  let l:cmd .= 'git submodule update --init --recursive && '
  let l:cmd .= 'git submodule sync && '
  let l:cmd .= 'git submodule update --init --recursive --force'
  
  " Execute command asynchronously
  call plugin_manager#jobs#execute(l:title, l:cmd, function('s:restore_complete_callback'))
endfunction

" Callback function when restore completes
function! s:restore_complete_callback(job_id, status, output)
  let l:result_lines = []
  
  if a:status == 0
    let l:result_lines += ['All plugins have been restored successfully.', '', 'Generating helptags:']
    call plugin_manager#ui#update_sidebar(l:result_lines, 1)
    
    " Generate helptags for all plugins
    call plugin_manager#modules#generate_helptags(0)
  else
    let l:result_lines += ['Warning: There were issues restoring plugins:']
    let l:result_lines += a:output
    call plugin_manager#ui#update_sidebar(l:result_lines, 1)
  endif
  
  " Force refresh the cache after restore
  call plugin_manager#utils#refresh_modules_cache()
endfunction

" Function to add a backup remote repository using async jobs
function! plugin_manager#modules#add_remote_backup(...)
  if !plugin_manager#utils#ensure_vim_directory()
    return
  endif
  
  if a:0 < 1
    let l:lines = ["Remote Backup Usage:", "-------------------", "", "Usage: PluginManagerRemote <repository_url>"]
    call plugin_manager#ui#open_sidebar(l:lines)
    return
  endif
  
  let l:repoUrl = a:1
  if l:repoUrl !~ g:pm_urlRegexp
    let l:lines = ["Invalid URL:", "-----------", "", l:repoUrl . " is not a valid url"]
    call plugin_manager#ui#open_sidebar(l:lines)
    return
  endif
  
  let l:title = 'Adding Remote Repository'
  
  " Check if remote origin exists
  let l:originExists = system('git remote | grep -c "^origin$" || echo 0')
  
  " Create command chain based on whether origin exists
  if l:originExists == "0"
    let l:cmd = 'git remote add origin ' . l:repoUrl
  else
    let l:cmd = 'git remote set-url origin --add --push ' . l:repoUrl
  endif
  
  " Execute command asynchronously
  call plugin_manager#jobs#execute(l:title, l:cmd, function('s:add_remote_complete_callback'), l:repoUrl)
endfunction

" Callback function when add remote completes
function! s:add_remote_complete_callback(job_id, status, output, repoUrl)
  let l:result_lines = []
  
  if a:status == 0
    let l:result_lines += ['Repository "' . a:repoUrl . '" added successfully.', '', 'Configured repositories:']
    
    " Display configured repositories
    let l:remotes = system('git remote -v')
    let l:result_lines += split(l:remotes, "\n")
  else
    let l:result_lines += ['Warning: There were issues adding the remote repository:']
    let l:result_lines += a:output
  endif
  
  call plugin_manager#ui#update_sidebar(l:result_lines, 1)
endfunction
  
" Reload a specific plugin or all Vim configuration
function! plugin_manager#modules#reload(...)
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
    
    let l:header = ['Reload:', '-------', '']
    
    " Check if a specific module was specified
    let l:specific_module = a:0 > 0 ? a:1 : ''
    
    if !empty(l:specific_module)
      " Reload a specific module
      call plugin_manager#ui#open_sidebar(l:header + ['Reloading plugin: ' . l:specific_module . '...'])
      
      " Find the module path
      let l:grep_cmd = 'grep -A1 "path = .*' . l:specific_module . '" .gitmodules | grep "path =" | cut -d "=" -f2 | tr -d " "'
      let l:module_path = system(l:grep_cmd)
      let l:module_path = substitute(l:module_path, '\n$', '', '')
      
      if empty(l:module_path)
        call plugin_manager#ui#update_sidebar(['Error: Module "' . l:specific_module . '" not found.'], 1)
        return
      endif
      
      " A more effective approach to reload a plugin:
      " 1. Remove it from runtimepath
      execute 'set rtp-=' . l:module_path
      
      " 2. Clear any runtime files loaded from this plugin
      let l:runtime_paths = split(globpath(l:module_path, '**/*.vim'), '\n')
      for l:rtp in l:runtime_paths
        " Only try to clear files that are in autoload, plugin, or ftplugin directories
        if l:rtp =~ '/autoload/' || l:rtp =~ '/plugin/' || l:rtp =~ '/ftplugin/'
          " Get the script ID if loaded
          let l:sid = 0
          redir => l:scriptnames
          silent scriptnames
          redir END
          
          for l:line in split(l:scriptnames, '\n')
            if l:line =~ l:rtp
              let l:sid = str2nr(matchstr(l:line, '^\s*\zs\d\+\ze:'))
              break
            endif
          endfor
          
          " If script is loaded, try to unload it
          if l:sid > 0
            " Attempt to clear script variables (doesn't work for all plugins)
            execute 'runtime! ' . l:rtp
          endif
        endif
      endfor
      
      " 3. Add it back to runtimepath
      execute 'set rtp+=' . l:module_path
      
      " 4. Reload all runtime files from the plugin
      for l:rtp in l:runtime_paths
        if l:rtp =~ '/plugin/' || l:rtp =~ '/ftplugin/'
          execute 'runtime! ' . l:rtp
        endif
      endfor
      
      call plugin_manager#ui#update_sidebar(['Plugin "' . l:specific_module . '" reloaded successfully.', 'Note: Some plugins may require restarting Vim for a complete reload.'], 1)
    else
      " Reload all Vim configuration
      call plugin_manager#ui#open_sidebar(l:header + ['Reloading entire Vim configuration...'])
      
      " First unload all plugins
      call plugin_manager#ui#update_sidebar(['Unloading plugins...'], 1)
      
      " Then reload vimrc file
      if filereadable(g:plugin_manager_vimrc_path)
        call plugin_manager#ui#update_sidebar(['Sourcing ' . g:plugin_manager_vimrc_path . '...'], 1)
        
        " More effective reloading approach
        execute 'runtime! plugin/**/*.vim'
        execute 'runtime! ftplugin/**/*.vim'
        execute 'runtime! syntax/**/*.vim'
        execute 'runtime! indent/**/*.vim'
        
        " Finally source the vimrc
        execute 'source ' . g:plugin_manager_vimrc_path
        
        call plugin_manager#ui#update_sidebar(['Vim configuration reloaded successfully.', 'Note: Some plugins may require restarting Vim for a complete reload.'], 1)
      else
        call plugin_manager#ui#update_sidebar(['Warning: Vimrc file not found at ' . g:plugin_manager_vimrc_path], 1)
      endif
    endif
endfunction
  
" Function to add a backup remote repository
function! plugin_manager#modules#add_remote_backup(...)
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
    
    if a:0 < 1
      let l:lines = ["Remote Backup Usage:", "-------------------", "", "Usage: PluginManagerRemote <repository_url>"]
      call plugin_manager#ui#open_sidebar(l:lines)
      return
    endif
    
    let l:repoUrl = a:1
    if l:repoUrl !~ g:pm_urlRegexp
      let l:lines = ["Invalid URL:", "-----------", "", l:repoUrl . " is not a valid url"]
      call plugin_manager#ui#open_sidebar(l:lines)
      return
    endif
    
    let l:header = ['Add Remote Repository:', '---------------------', '', 'Adding backup repository: ' . l:repoUrl]
    call plugin_manager#ui#open_sidebar(l:header)
    
    " Check if remote origin exists
    let l:originExists = system('git remote | grep -c "^origin$" || echo 0')
    if l:originExists == "0"
      call plugin_manager#ui#update_sidebar(['Adding origin remote...'], 1)
      let l:result = system('git remote add origin ' . l:repoUrl)
    else
      call plugin_manager#ui#update_sidebar(['Adding push URL to origin remote...'], 1)
      let l:result = system('git remote set-url origin --add --push ' . l:repoUrl)
    endif
    
    let l:result_lines = []
    if v:shell_error != 0
      let l:result_lines += ['Error adding remote:']
      let l:result_lines += split(l:result, "\n")
    else
      let l:result_lines += ['Repository added successfully.']
    endif
    
    call plugin_manager#ui#update_sidebar(l:result_lines, 1)
    
    " Display configured repositories
    call plugin_manager#ui#update_sidebar(['', 'Configured repositories:'], 1)
    let l:remotes = system('git remote -v')
    call plugin_manager#ui#update_sidebar(split(l:remotes, "\n"), 1)
endfunction