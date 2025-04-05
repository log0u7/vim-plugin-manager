" Module management functions for vim-plugin-manager

" Variable to prevent multiple concurrent updates
let s:update_in_progress = 0

" Improved list function with fixed column formatting
  function! plugin_manager#modules#list()
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
    
    " Use the gitmodules cache
    let l:modules = plugin_manager#utils#parse_gitmodules()
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

        if len(path) > 40
          let l:path = path[0:39]
        endif 

        " Format the output with properly aligned columns
        " Ensure fixed width columns with proper spacing
        let l:name_col = l:short_name . repeat(' ', max([0, 24 - len(l:short_name)]))
        let l:path_col = l:path . repeat(' ', max([0, 42 - len(l:path)]))
        
        let l:status = has_key(l:module, 'exists') && l:module.exists ? '' : ' [MISSING]'
        
        call add(l:lines, l:name_col . l:path_col . l:module.url . l:status)
      endif
    endfor
    
    call plugin_manager#ui#open_sidebar(l:lines)
endfunction

" Improved status function with fixed column formatting
function! plugin_manager#modules#status()
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
    
    " Use the gitmodules cache
    let l:modules = plugin_manager#utils#parse_gitmodules()
    let l:header = 'Submodule Status:'

    if empty(l:modules)
      let l:lines = [l:header, repeat('-', len(l:header)), '', 'No submodules found (.gitmodules not found)']
      call plugin_manager#ui#open_sidebar(l:lines)
      return
    endif
    
    let l:lines = [l:header, repeat('-', len(l:header)), '']
    call add(l:lines, 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 8).'Last Updated'.repeat(' ', 18).'Status')
    call add(l:lines, repeat('-', 120))
    
    " Sort modules by name
    let l:module_names = sort(keys(l:modules))
    
    for l:name in l:module_names
      let l:module = l:modules[l:name]
      if has_key(l:module, 'is_valid') && l:module.is_valid
        let l:short_name = l:module.short_name
        
        " Get current commit
        let l:commit = system('cd "' . l:module.path . '" && git rev-parse --short HEAD 2>/dev/null || echo "N/A"')
        let l:commit = substitute(l:commit, '\n', '', 'g')
        
        " Get current branch
        let l:branch = system('cd "' . l:module.path . '" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A"')
        let l:branch = substitute(l:branch, '\n', '', 'g')
        
        " Get last commit date
        let l:last_updated = system('cd "' . l:module.path . '" && git log -1 --format=%cd --date=relative 2>/dev/null || echo "N/A"')
        let l:last_updated = substitute(l:last_updated, '\n', '', 'g')
        
        " Check if there are uncommitted changes
        let l:changes = system('cd "' . l:module.path . '" && git status -s 2>/dev/null')
        let l:has_changes = !empty(l:changes)
        
        " Check if behind/ahead of remote
        let l:behind_ahead = system('cd "' . l:module.path . '" && git rev-list --count --left-right @{upstream}...HEAD 2>/dev/null || echo "?"')
        let l:behind_ahead = substitute(l:behind_ahead, '\n', '', 'g')
        let l:behind_ahead_parts = split(l:behind_ahead, '\t')
        let l:behind = len(l:behind_ahead_parts) >= 1 ? l:behind_ahead_parts[0] : '?'
        let l:ahead = len(l:behind_ahead_parts) >= 2 ? l:behind_ahead_parts[1] : '?'
        
        " Determine status
        let l:status = 'OK'
        if !isdirectory(l:module.path)
          let l:status = 'MISSING'
        elseif l:has_changes
          let l:status = 'LOCAL CHANGES'
        elseif l:behind != '0' && l:behind != '?'
          let l:status = 'BEHIND (' . l:behind . ')'
        elseif l:ahead != '0' && l:ahead != '?'
          let l:status = 'AHEAD (' . l:ahead . ')'
        endif

        if len(l:short_name) > 20
          let l:short_name = l:short_name[0:19]
        endif

        " Format the output with properly aligned columns
        " Ensure fixed width with proper spacing between columns 
        let l:name_col = l:short_name . repeat(' ', max([0, 22 - len(l:short_name)]))
        let l:commit_col = l:commit . repeat(' ', max([0, 20 - len(l:commit)]))
        let l:branch_col = l:branch . repeat(' ', max([0, 14 - len(l:branch)]))
        let l:date_col = l:last_updated . repeat(' ', max([0, 30 - len(l:last_updated)]))
        
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
    
    let l:header = 'Submodule Summary'

    " Check if .gitmodules exists
    if !filereadable('.gitmodules')
      let l:lines = [l:header, repeat('-', len(l:header)), '', 'No submodules found (.gitmodules not found)']
      call plugin_manager#ui#open_sidebar(l:lines)
      return
    endif
    
    let l:output = system('git submodule summary')
    let l:lines = [l:header, repeat('-', len(l:header)), '']
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
      let l:header = 'Generating Helptags:'
      let l:line = [l:header, repeat('-', len(l:header)), '', 'Generating helptags:']
      call plugin_manager#ui#open_sidebar(l:line)
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
  
" Update plugins
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
    let l:title = 'Updating Plugins:'
    if empty(l:modules)
      let l:lines = [l:title, repeat('-', len(l:title)), '', 'No plugins to update (.gitmodules not found)']
      call plugin_manager#ui#open_sidebar(l:lines)
      let s:update_in_progress = 0
      return
    endif
    
    " Initialize once before executing commands
    let l:header = [l:title, repeat('-', len(l:title)), '']
    
    " Check if a specific module was specified
    let l:specific_module = a:0 > 0 ? a:1 : 'all'
    
    if l:specific_module == 'all'
      let l:initial_message = l:header + ['Updating all plugins...']
      call plugin_manager#ui#open_sidebar(l:initial_message)
      
      " Stash local changes in submodules first
      call plugin_manager#ui#update_sidebar(['Stashing local changes in submodules...'], 1)
      call system('git submodule foreach --recursive "git stash -q || true"')
  
      " Execute update commands
      call system('git submodule sync')
      let l:updateResult = system('git submodule update --remote --merge --force')
      
      " Check if commit is needed
      let l:gitStatus = system('git status -s')
      if !empty(l:gitStatus)
        call system('git commit -am "Update Modules"')
      endif
    else
      " Update a specific module - use find_module function
      let l:module_info = plugin_manager#utils#find_module(l:specific_module)
      
      if empty(l:module_info)
        call plugin_manager#ui#open_sidebar(l:header + ['Error: Module "' . l:specific_module . '" not found.'])
        let s:update_in_progress = 0
        return
      endif
      
      let l:module = l:module_info.module
      let l:module_path = l:module.path
      let l:module_name = l:module.short_name
      
      let l:initial_message = l:header + ['Updating plugin: ' . l:module_name . ' (' . l:module_path . ')...']
      call plugin_manager#ui#open_sidebar(l:initial_message)
      
      " Check if directory exists
      if !isdirectory(l:module_path)
        call plugin_manager#ui#update_sidebar(['Error: Module directory "' . l:module_path . '" not found.', 
              \ 'Try running "PluginManager restore" to reinstall missing modules.'], 1)
        let s:update_in_progress = 0
        return
      endif
      
      " Stash local changes in the specific submodule
      call plugin_manager#ui#update_sidebar(['Stashing local changes in module...'], 1)
      call system('cd "' . l:module_path . '" && git stash -q || true')
      
      " Update only this module
      call system('git submodule sync -- "' . l:module_path . '"')
      let l:updateResult = system('git submodule update --remote --merge --force -- "' . l:module_path . '"')
      
      " Check if commit is needed
      let l:gitStatus = system('git status -s')
      if !empty(l:gitStatus)
        call system('git commit -am "Update Module: ' . l:module_name . '"')
      endif
    endif
    
    " Update with results
    let l:update_lines = []
    if !empty(l:updateResult)
      let l:update_lines += ['', 'Update details:', '']
      let l:update_lines += split(l:updateResult, "\n")
    endif
    
    " Show what was updated
    let l:update_lines += ['', 'Checking for updates...']
    let l:updated_modules = []
    
    " Use git log to determine what was updated
    if l:specific_module == 'all'
      " Check all modules
      for [l:name, l:module] in items(l:modules)
        if l:module.is_valid && isdirectory(l:module.path)
          let l:log = system('cd "' . l:module.path . '" && git log -1 --format="%h %s" 2>/dev/null')
          if !empty(l:log)
            call add(l:updated_modules, l:module.short_name . ': ' . substitute(l:log, '\n', '', 'g'))
          endif
        endif
      endfor
    else
      " Check only the specific module
      if isdirectory(l:module_path)
        let l:log = system('cd "' . l:module_path . '" && git log -1 --format="%h %s" 2>/dev/null')
        if !empty(l:log)
          call add(l:updated_modules, l:module_name . ': ' . substitute(l:log, '\n', '', 'g'))
        endif
      endif
    endif
    
    if !empty(l:updated_modules)
      let l:update_lines += ['Latest commits:']
      let l:update_lines += l:updated_modules
    endif
    
    " Add update success message
    if l:specific_module == 'all'
      let l:update_lines += ['', 'All plugins updated successfully.']
    else
      let l:update_lines += ['', 'Plugin "' . l:module_name . '" updated successfully.']
    endif
    
    " Update sidebar with results
    call plugin_manager#ui#update_sidebar(l:update_lines, 1)
    
    " Generate helptags
    if l:specific_module == 'all'
      " Call with flag to indicate NOT to create a header - use our existing sidebar
      call plugin_manager#modules#generate_helptags(0)
    else
      " Generate helptags only for the specific module
      call plugin_manager#modules#generate_helptags(0, l:specific_module)
    endif
    
    " Force refresh the cache after updates
    call plugin_manager#utils#refresh_modules_cache()
    
    " Reset update in progress flag
    let s:update_in_progress = 0
endfunction
  
" Handle 'add' command
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
    
    " Check if repository exists
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
  
" Add a new plugin
function! s:add_module(moduleUrl, installDir)
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
    
    let l:header = ['Add Plugin:', '----------', '', 'Installing ' . a:moduleUrl . ' in ' . a:installDir . '...']
    call plugin_manager#ui#open_sidebar(l:header)
    
    " Check if module directory exists and create if needed
    let l:parentDir = fnamemodify(a:installDir, ':h')
    if !isdirectory(l:parentDir)
      call mkdir(l:parentDir, 'p')
    endif
  
    " Ensure the path is relative to vim directory
    let l:relativeInstallDir = substitute(a:installDir, '^' . g:plugin_manager_vim_dir . '/', '', '')
    
    " Fix: Check if submodule already exists
    let l:gitmoduleCheck = system('grep -c "' . l:relativeInstallDir . '" .gitmodules 2>/dev/null')
    if shellescape(l:gitmoduleCheck) != 0
      call plugin_manager#ui#update_sidebar(['Error: Plugin already installed at this location :'. l:relativeInstallDir], 1)
      return
    end
    
    " Execute git submodule add command
    let l:result = system('git submodule add "' . a:moduleUrl . '" "' . l:relativeInstallDir . '"')
    if v:shell_error != 0
      let l:error_lines = ['Error installing plugin:']
      call extend(l:error_lines, split(l:result, "\n"))
      call plugin_manager#ui#update_sidebar(l:error_lines, 1)
      return
    endif
    
    call plugin_manager#ui#update_sidebar(['Committing changes...'], 1)
    
    let l:result = system('git commit -m "Added ' . a:moduleUrl . ' module"')
    let l:result_lines = []
    if v:shell_error != 0
      let l:result_lines += ['Error committing changes:']
      let l:result_lines += split(l:result, "\n")
    else
      let l:result_lines += ['Plugin installed successfully.', 'Generating helptags...']
      if s:generate_helptag(a:installDir)
        let l:result_lines += ['Helptags generated successfully.']
      else
        let l:result_lines += ['No documentation directory found.']
      endif
    endif
    
    call plugin_manager#ui#update_sidebar(l:result_lines, 1)
endfunction
  
" Handle 'remove' command
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
        call s:remove_module(l:module_name, l:module_path)
      else
        let l:response = input("Are you sure you want to remove " . l:module_name . " (" . l:module_path . ")? [y/N] ")
        if l:response =~? '^y\(es\)\?$'
          call s:remove_module(l:module_name, l:module_path)
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
          call s:remove_module(l:filesystem_name, l:removedPluginPath)
        else
          let l:response = input("Are you sure you want to remove " . l:filesystem_name . " (" . l:removedPluginPath . ")? [y/N] ")
          if l:response =~? '^y\(es\)\?$'
            call s:remove_module(l:filesystem_name, l:removedPluginPath)
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
  
" Remove an existing plugin
function! s:remove_module(moduleName, removedPluginPath)
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
    
    let l:header = ['Remove Plugin:', '-------------', '', 'Removing ' . a:moduleName . ' from ' . a:removedPluginPath . '...']
    call plugin_manager#ui#open_sidebar(l:header)
    
    " Back up module information before removing it
    let l:modules = plugin_manager#utils#parse_gitmodules()
    let l:module_info = {}
    
    " Find module information by path
    for [l:name, l:module] in items(l:modules)
      if has_key(l:module, 'path') && l:module.path ==# a:removedPluginPath
        let l:module_info = l:module
        break
      endif
    endfor
    
    " If we found the module info, save it for later reporting
    if !empty(l:module_info)
      call plugin_manager#ui#update_sidebar([
            \ 'Found module information:',
            \ '- Name: ' . l:module_info.name,
            \ '- URL: ' . l:module_info.url
            \ ], 1)
    endif
    
    " Execute deinit command with better error handling
    let l:result = system('git submodule deinit -f "' . a:removedPluginPath . '" 2>&1')
    let l:deinit_success = v:shell_error == 0
    
    if !l:deinit_success
      let l:error_lines = ['Warning during deinitializing submodule (continuing anyway):']
      call extend(l:error_lines, split(l:result, "\n"))
      call plugin_manager#ui#update_sidebar(l:error_lines, 1)
    else
      call plugin_manager#ui#update_sidebar(['Deinitialized submodule successfully.'], 1)
    endif
    
    call plugin_manager#ui#update_sidebar(['Removing repository...'], 1)
    
    " Try to remove repository even if deinit failed
    let l:result = system('git rm -f "' . a:removedPluginPath . '" 2>&1')
    if v:shell_error != 0
      let l:error_lines = ['Error removing repository:']
      call extend(l:error_lines, split(l:result, "\n"))
      call plugin_manager#ui#update_sidebar(l:error_lines, 1)
      
      " Try alternative removal method
      call plugin_manager#ui#update_sidebar(['Trying alternative removal method...'], 1)
      let l:result = system('rm -rf "' . a:removedPluginPath . '" 2>&1')
      if v:shell_error != 0
        call plugin_manager#ui#update_sidebar(['Alternative removal also failed.'], 1)
        return
      else
        call plugin_manager#ui#update_sidebar(['Directory removed manually. You may need to edit .gitmodules manually.'], 1)
      endif
    else
      call plugin_manager#ui#update_sidebar(['Repository removed successfully.'], 1)
    endif
    
    call plugin_manager#ui#update_sidebar(['Cleaning .git modules...'], 1)
    
    " Clean .git/modules directory
    if isdirectory('.git/modules/' . a:removedPluginPath)
      let l:result = system('rm -rf ".git/modules/' . a:removedPluginPath . '" 2>&1')
      if v:shell_error != 0
        let l:error_lines = ['Warning cleaning git modules (continuing anyway):']
        call extend(l:error_lines, split(l:result, "\n"))
        call plugin_manager#ui#update_sidebar(l:error_lines, 1)
      else
        call plugin_manager#ui#update_sidebar(['Git modules cleaned successfully.'], 1)
      endif
    else
      call plugin_manager#ui#update_sidebar(['No module directory to clean in .git/modules.'], 1)
    endif
    
    call plugin_manager#ui#update_sidebar(['Committing changes...'], 1)
    
    " Commit changes - create a forced commit even if nothing staged
    let l:commit_msg = "Removed " . a:moduleName . " module"
    if !empty(l:module_info)
      let l:commit_msg .= " (" . l:module_info.url . ")"
    endif
    
    let l:result = system('git add -A && git commit -m "' . l:commit_msg . '" || git commit --allow-empty -m "' . l:commit_msg . '" 2>&1')
    if v:shell_error != 0
      let l:error_lines = ['Warning during commit (plugin still removed):']
      call extend(l:error_lines, split(l:result, "\n"))
      call plugin_manager#ui#update_sidebar(l:error_lines, 1)
    else
      call plugin_manager#ui#update_sidebar(['Changes committed successfully.'], 1)
    endif
    
    " Force refresh the cache after removal
    call plugin_manager#utils#refresh_modules_cache()
    
    call plugin_manager#ui#update_sidebar(['Plugin removal completed.'], 1)
endfunction
  
" Backup configuration to remote repositories
function! plugin_manager#modules#backup()
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
    
    let l:header = ['Backup Configuration:', '--------------------', '', 'Checking git status...']
    call plugin_manager#ui#open_sidebar(l:header)
    
    " Fix: Check if there are changes to commit
    let l:gitStatus = system('git status -s')
    let l:status_lines = []
    if !empty(l:gitStatus)
      let l:status_lines += ['Committing local changes...']
      let l:commitResult = system('git commit -am "Automatic backup"')
      let l:status_lines += split(l:commitResult, "\n")
    else
      let l:status_lines += ['No local changes to commit.']
    endif
    
    call plugin_manager#ui#update_sidebar(l:status_lines, 1)
    
    " Push changes to all configured remotes
    call plugin_manager#ui#update_sidebar(['Pushing changes to remote repositories...'], 1)
    
    " Fix: Check if any remotes exist
    let l:remotesExist = system('git remote')
    if empty(l:remotesExist)
      call plugin_manager#ui#update_sidebar([
            \ 'No remote repositories configured.',
            \ 'Use PluginManagerRemote to add a remote repository.'
            \ ], 1)
      return
    endif
    
    let l:pushResult = system('git push --all')
    if v:shell_error != 0
      let l:error_lines = ['Error pushing to remote:']
      call extend(l:error_lines, split(l:pushResult, "\n"))
      call plugin_manager#ui#update_sidebar(l:error_lines, 1)
    else
      call plugin_manager#ui#update_sidebar(['Backup completed successfully.'], 1)
    endif
endfunction
  
" Restore all plugins from .gitmodules
function! plugin_manager#modules#restore()
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
    
    let l:header = ['Restore Plugins:', '---------------', '', 'Checking for .gitmodules file...']
    call plugin_manager#ui#open_sidebar(l:header)
    
    " First, check if .gitmodules exists
    if !filereadable('.gitmodules')
      call plugin_manager#ui#update_sidebar(['Error: .gitmodules file not found!'], 1)
      return
    endif
    
    " Initialize submodules if they haven't been yet
    call plugin_manager#ui#update_sidebar(['Initializing submodules...'], 1)
    let l:result = system('git submodule init')
    if v:shell_error != 0
      let l:error_lines = ['Error initializing submodules:']
      call extend(l:error_lines, split(l:result, "\n"))
      call plugin_manager#ui#update_sidebar(l:error_lines, 1)
      return
    endif
    
    " Fetch and update all submodules
    call plugin_manager#ui#update_sidebar(['Fetching and updating all submodules...'], 1)
    let l:result = system('git submodule update --init --recursive')
    if v:shell_error != 0
      let l:error_lines = ['Error updating submodules:']
      call extend(l:error_lines, split(l:result, "\n"))
      call plugin_manager#ui#update_sidebar(l:error_lines, 1)
      return
    endif
    
    " Make sure all submodules are at the correct commit
    call plugin_manager#ui#update_sidebar(['Ensuring all submodules are at the correct commit...'], 1)
    call system('git submodule sync')
    let l:result = system('git submodule update --init --recursive --force')
    if v:shell_error != 0
      let l:error_lines = ['Error during final submodule update:']
      call extend(l:error_lines, split(l:result, "\n"))
      call plugin_manager#ui#update_sidebar(l:error_lines, 1)
      return
    endif
    
    call plugin_manager#ui#update_sidebar(['All plugins have been restored successfully.', '', 'Generating helptags:'], 1)
    
    " Generate helptags for all plugins
    call plugin_manager#modules#generate_helptags(0)
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
      if filereadable(expand(g:plugin_manager_vimrc_path))
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