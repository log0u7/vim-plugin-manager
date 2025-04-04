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
    
    " Fetch updates to ensure we have up-to-date status information
    call plugin_manager#ui#update_sidebar(['Fetching updates from remote repositories...'], 1)
    call system('git submodule foreach --recursive "git fetch -q origin 2>/dev/null || true"')
    call plugin_manager#ui#update_sidebar(['Status information:'], 1)
    
    " Sort modules by name
    let l:module_names = sort(keys(l:modules))
    
    for l:name in l:module_names
      let l:module = l:modules[l:name]
      if has_key(l:module, 'is_valid') && l:module.is_valid
        let l:short_name = l:module.short_name
        
        " Initialize status to 'OK' by default
        let l:status = 'OK'
        
        " Initialize other information as N/A in case checks fail
        let l:commit = 'N/A'
        let l:branch = 'N/A'
        let l:last_updated = 'N/A'
        
        " Check if module exists
        if !isdirectory(l:module.path)
          let l:status = 'MISSING'
        else
          " Continue with all checks for existing modules
          
          " Get current commit
          let l:commit = system('cd "' . l:module.path . '" && git rev-parse --short HEAD 2>/dev/null || echo "N/A"')
          let l:commit = substitute(l:commit, '\n', '', 'g')
          
          " Get current branch
          let l:branch = system('cd "' . l:module.path . '" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A"')
          let l:branch = substitute(l:branch, '\n', '', 'g')
          
          " Get last commit date
          let l:last_updated = system('cd "' . l:module.path . '" && git log -1 --format=%cd --date=relative 2>/dev/null || echo "N/A"')
          let l:last_updated = substitute(l:last_updated, '\n', '', 'g')
          
          " Use the new utility function to check for updates
          let l:update_status = plugin_manager#utils#check_module_updates(l:module.path)
          
          " Get local changes status from the utility function
          let l:has_changes = l:update_status.has_changes
          
          " Determine status combining local changes and remote status
          if l:update_status.different_branch
            let l:status = 'CUSTOM BRANCH (local: ' . l:update_status.branch . ', target: ' . l:update_status.remote_branch . ')'
            if l:has_changes
              let l:status .= ' + LOCAL CHANGES'
            endif
          elseif l:update_status.behind > 0 && l:update_status.ahead > 0
            " DIVERGED state has highest priority after different branch
            let l:status = 'DIVERGED (BEHIND ' . l:update_status.behind . ', AHEAD ' . l:update_status.ahead . ')'
            if l:has_changes
              let l:status .= ' + LOCAL CHANGES'
            endif
          elseif l:update_status.behind > 0
            let l:status = 'BEHIND (' . l:update_status.behind . ')'
            if l:has_changes
              let l:status .= ' + LOCAL CHANGES'
            endif
          elseif l:update_status.ahead > 0
            let l:status = 'AHEAD (' . l:update_status.ahead . ')'
            if l:has_changes
              let l:status .= ' + LOCAL CHANGES'
            endif
          elseif l:has_changes
            let l:status = 'LOCAL CHANGES'
          endif
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
  
  " List to track modules that have been updated
  let l:updated_modules = []
  
  if l:specific_module == 'all'
    let l:initial_message = l:header + ['Checking for updates on all plugins...']
    call plugin_manager#ui#open_sidebar(l:initial_message)
    
    " Handle helptags files differently to avoid merge conflicts
    call plugin_manager#ui#update_sidebar(['Preparing modules for update...'], 1)
    
    " First, remove any helptags files to avoid conflicts
    call system('git submodule foreach --recursive "rm -f doc/tags doc/*/tags */tags 2>/dev/null || true"')
    
    " Stash any other local changes if needed
    let l:any_changes = 0
    
    " Check if any module has local changes (after removing helptags)
    for [l:name, l:module] in items(l:modules)
      if l:module.is_valid && isdirectory(l:module.path)
        let l:changes = system('cd "' . l:module.path . '" && git status -s 2>/dev/null')
        if !empty(l:changes)
          let l:any_changes = 1
          break
        endif
      endif
    endfor
    
    " Only stash if we found actual changes
    if l:any_changes
      call plugin_manager#ui#update_sidebar(['Stashing local changes in submodules...'], 1)
      call system('git submodule foreach --recursive "git stash -q || true"')
    else
      call plugin_manager#ui#update_sidebar(['No local changes to stash...'], 1)
    endif

    " Fetch updates from remote repositories without applying them yet
    call plugin_manager#ui#update_sidebar(['Fetching updates from remote repositories...'], 1)
    call system('git submodule foreach --recursive "git fetch origin"')
    
    " Check which modules have updates available
    let l:modules_with_updates = []
    let l:modules_on_diff_branch = []
    
    for [l:name, l:module] in items(l:modules)
      if l:module.is_valid && isdirectory(l:module.path)
        " Use the utility function to check for updates
        let l:update_status = plugin_manager#utils#check_module_updates(l:module.path)
        
        " If module is on a different branch and not in detached HEAD, add to special list
        if l:update_status.different_branch && l:update_status.branch != "detached"
          call add(l:modules_on_diff_branch, {'module': l:module, 'status': l:update_status})
        " If module has updates, add to update list
        elseif l:update_status.has_updates
          call add(l:modules_with_updates, l:module)
        endif
      endif
    endfor
    
    " Report on modules with custom branches
    if !empty(l:modules_on_diff_branch)
      let l:branch_lines = ['', 'The following plugins are on custom branches:']
      for l:item in l:modules_on_diff_branch
        call add(l:branch_lines, '- ' . l:item.module.short_name . 
              \ ' (local: ' . l:item.status.branch . 
              \ ', target: ' . l:item.status.remote_branch . ')')
      endfor
      call add(l:branch_lines, 'These plugins will not be updated automatically to preserve your branch choice.')
      call plugin_manager#ui#update_sidebar(l:branch_lines, 1)
    endif
    
    if empty(l:modules_with_updates)
      call plugin_manager#ui#update_sidebar(['All plugins are up-to-date.'], 1)
    else
      call plugin_manager#ui#update_sidebar(['Found ' . len(l:modules_with_updates) . ' plugins with updates available. Updating...'], 1)
      
      " Execute update commands
      call system('git submodule sync')
      let l:updateResult = system('git submodule update --remote --merge --force')
      
      " Check if commit is needed
      let l:gitStatus = system('git status -s')
      if !empty(l:gitStatus)
        call system('git commit -am "Update Modules"')
      endif
      
      " Record which modules were updated
      let l:updated_modules = l:modules_with_updates
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
    
    let l:initial_message = l:header + ['Checking for updates on plugin: ' . l:module_name . ' (' . l:module_path . ')...']
    call plugin_manager#ui#open_sidebar(l:initial_message)
    
    " Check if directory exists
    if !isdirectory(l:module_path)
      call plugin_manager#ui#update_sidebar(['Error: Module directory "' . l:module_path . '" not found.', 
            \ 'Try running "PluginManager restore" to reinstall missing modules.'], 1)
      let s:update_in_progress = 0
      return
    endif
    
    " Handle helptags files and local changes
    call plugin_manager#ui#update_sidebar(['Preparing module for update...'], 1)
    
    " First, remove any helptags files to avoid conflicts
    call system('cd "' . l:module_path . '" && rm -f doc/tags doc/*/tags */tags 2>/dev/null || true')
    
    " Check if there are any remaining local changes
    let l:changes = system('cd "' . l:module_path . '" && git status -s 2>/dev/null')
    if !empty(l:changes)
      call plugin_manager#ui#update_sidebar(['Stashing local changes...'], 1)
      call system('cd "' . l:module_path . '" && git stash -q || true')
    else
      call plugin_manager#ui#update_sidebar(['No local changes to stash...'], 1)
    endif
    
    " Fetch updates from remote repository without applying them yet
    call plugin_manager#ui#update_sidebar(['Fetching updates from remote repository...'], 1)
    call system('cd "' . l:module_path . '" && git fetch origin')
    
    " Use the utility function to check for updates
    let l:update_status = plugin_manager#utils#check_module_updates(l:module_path)
    
    " Check if we're on a custom branch and user wants to maintain it
    if l:update_status.different_branch && l:update_status.branch != "detached"
      call plugin_manager#ui#update_sidebar([
            \ 'Plugin "' . l:module_name . '" is on a custom branch:', 
            \ '- Local branch: ' . l:update_status.branch,
            \ '- Target branch: ' . l:update_status.remote_branch,
            \ 'To preserve your branch choice, the plugin will not be updated automatically.',
            \ 'To update anyway, run: git submodule update --remote --force -- "' . l:module_path . '"'
            \ ], 1)
      let s:update_in_progress = 0
      return
    endif
    
    " If module has no updates, it's up to date
    if !l:update_status.has_updates
      call plugin_manager#ui#update_sidebar(['Plugin "' . l:module_name . '" is already up-to-date.'], 1)
    else
      call plugin_manager#ui#update_sidebar(['Updates available for plugin "' . l:module_name . '". Updating...'], 1)
      
      " Update only this module
      call system('git submodule sync -- "' . l:module_path . '"')
      let l:updateResult = system('git submodule update --remote --merge --force -- "' . l:module_path . '"')
      
      " Check if commit is needed
      let l:gitStatus = system('git status -s')
      if !empty(l:gitStatus)
        call system('git commit -am "Update Module: ' . l:module_name . '"')
      endif
      
      " Add to list of updated modules
      call add(l:updated_modules, l:module)
    endif
  endif
  
  " Update with results
  let l:update_lines = []
  if !empty(l:updated_modules)
    " Show what was updated
    let l:update_lines += ['', 'Updated plugins:']
    for l:module in l:updated_modules
      let l:log = system('cd "' . l:module.path . '" && git log -1 --format="%h %s" 2>/dev/null')
      if !empty(l:log)
        call add(l:update_lines, l:module.short_name . ': ' . substitute(l:log, '\n', '', 'g'))
      else
        call add(l:update_lines, l:module.short_name)
      endif
    endfor
    
    " Add update success message
    let l:update_lines += ['', 'Update completed successfully.']
    
    " Update sidebar with results
    call plugin_manager#ui#update_sidebar(l:update_lines, 1)
    
    " Generate helptags only for updated modules
    call plugin_manager#ui#update_sidebar(['', 'Generating helptags for updated plugins:'], 1)
    let l:helptags_generated = 0
    let l:generated_plugins = []
    
    for l:module in l:updated_modules
      let l:plugin_path = l:module.path
      let l:docPath = l:plugin_path . '/doc'
      if isdirectory(l:docPath)
        execute 'helptags ' . l:docPath
        let l:helptags_generated = 1
        call add(l:generated_plugins, "Generated helptags for " . l:module.short_name)
      endif
    endfor
    
    let l:helptags_result = []
    if l:helptags_generated
      call extend(l:helptags_result, l:generated_plugins)
      call add(l:helptags_result, "Helptags generation completed.")
    else
      call add(l:helptags_result, "No documentation directories found in updated plugins.")
    endif
    
    call plugin_manager#ui#update_sidebar(l:helptags_result, 1)
  else
    " No updates performed
    call plugin_manager#ui#update_sidebar(['', 'No plugins were updated.'], 1)
  endif
  
  " Force refresh the cache after updates
  call plugin_manager#utils#refresh_modules_cache()
  
  " Reset update in progress flag
  let s:update_in_progress = 0
endfunction
  
" Handle 'add' command
function! plugin_manager#modules#add(...)
  if a:0 < 1
    let l:lines = ["Add Plugin Usage:", "---------------", "", 
          \ "Usage: PluginManager add <plugin> [options]", "",
          \ "Options format: {'dir':'custom_dir', 'load':'start|opt', 'branch':'branch_name',",
          \ "                 'tag':'tag_name', 'exec':'command_to_exec'}", 
          \ "",
          \ "Example: PluginManager add tpope/vim-fugitive {'dir':'fugitive', 'load':'start', 'branch':'main'}", "",
          \ "Local plugin: PluginManager add ~/path/to/local/plugin", "",
          \ "For backward compatibility:", 
          \ "PluginManager add <plugin> [modulename] [opt]"]
    call plugin_manager#ui#open_sidebar(l:lines)
    return 1
  endif
  
  let l:pluginInput = a:1
  let l:moduleUrl = plugin_manager#utils#convert_to_full_url(l:pluginInput)
  
  " Check if URL is valid or if it's a local path
  if empty(l:moduleUrl)
    let l:lines = ["Invalid Plugin Format:", "--------------------", "", l:pluginInput . " is not a valid plugin name, URL, or local path.", "Use format 'user/repo', complete URL, or local path."]
    call plugin_manager#ui#open_sidebar(l:lines)
    return 1
  endif
  
  " Check if it's a local path
  let l:isLocalPath = l:moduleUrl =~ '^local:'
  
  " For remote plugins, check if repository exists
  if !l:isLocalPath && !plugin_manager#utils#repository_exists(l:moduleUrl)
    let l:lines = ["Repository Not Found:", "--------------------", "", "Repository not found: " . l:moduleUrl]
    
    " If it was a short name, suggest using a full URL
    if l:pluginInput =~ g:pm_shortNameRegexp
      call add(l:lines, "This plugin was not found on " . g:plugin_manager_default_git_host . ".")
      call add(l:lines, "Try using a full URL to the repository if it's hosted elsewhere.")
    endif
    
    call plugin_manager#ui#open_sidebar(l:lines)
    return 1
  endif
  
  " Extract the actual path for local plugins
  if l:isLocalPath
    let l:localPath = substitute(l:moduleUrl, '^local:', '', '')
  endif
  
  " Get module name - for local paths, use the directory name
  if l:isLocalPath
    let l:moduleName = fnamemodify(l:localPath, ':t')
  else
    let l:moduleName = fnamemodify(l:moduleUrl, ':t:r')  " Remove .git from the end if present
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
  if a:0 >= 2
    " Check if the second argument is a dictionary (new format) or string (old format)
    if type(a:2) == v:t_dict
      " New format with options dictionary
      let l:provided_options = a:2
      
      " Update options with provided values
      for [l:key, l:val] in items(l:provided_options)
        if has_key(l:options, l:key)
          let l:options[l:key] = l:val
        endif
      endfor
    else
      " Old format with separate arguments
      " Custom name was provided as second argument
      let l:options.dir = a:2
      
      " Optional loading was provided as third argument
      if a:0 >= 3 && a:3 != ""
        let l:options.load = 'opt'
      endif
    endif
  endif
  
  " Determine install directory
  let l:installDir = ""
  
  " Set custom directory name if provided, otherwise use plugin name
  let l:dirName = !empty(l:options.dir) ? l:options.dir : l:moduleName
  
  " Set load dir based on options
  let l:loadDir = l:options.load == 'opt' ? g:plugin_manager_opt_dir : g:plugin_manager_start_dir
  
  " Construct full installation path
  let l:installDir = g:plugin_manager_plugins_dir . "/" . l:loadDir . "/" . l:dirName
  
  " Call the appropriate installation function based on whether it's a local path
  if l:isLocalPath
    call s:add_local_module(l:localPath, l:installDir, l:options)
  else
    call s:add_module(l:moduleUrl, l:installDir, l:options)
  endif
  
  return 0
endfunction

" Function to install local plugins
function! s:add_local_module(localPath, installDir, options)
  if !plugin_manager#utils#ensure_vim_directory()
    return
  endif
  
  let l:header = ['Add Local Plugin:', '----------------', '', 'Installing from ' . a:localPath . ' to ' . a:installDir . '...']
  call plugin_manager#ui#open_sidebar(l:header)
  
  " Check if local path exists
  if !isdirectory(a:localPath)
    call plugin_manager#ui#update_sidebar(['Error: Local directory "' . a:localPath . '" not found'], 1)
    return
  endif
  
  " Check if module directory exists and create if needed
  let l:parentDir = fnamemodify(a:installDir, ':h')
  if !isdirectory(l:parentDir)
    call mkdir(l:parentDir, 'p')
  endif
  
  " Ensure the installation directory doesn't already exist
  if isdirectory(a:installDir)
    call plugin_manager#ui#update_sidebar(['Error: Destination directory "' . a:installDir . '" already exists'], 1)
    return
  endif
  
  " Create the destination directory
  call mkdir(a:installDir, 'p')
  
  " Copy the files, excluding .git directory if it exists
  let l:copy_result = ''
  let l:copy_success = 0
  
  " Try using rsync first (most reliable with .git exclusion)
  if executable('rsync')
    call plugin_manager#ui#update_sidebar(['Copying files using rsync...'], 1)
    let l:rsync_command = 'rsync -a --exclude=".git" ' . shellescape(a:localPath . '/') . ' ' . shellescape(a:installDir . '/')
    let l:copy_result = system(l:rsync_command)
    let l:copy_success = v:shell_error == 0
  endif
  
  " If rsync failed or isn't available, try platform-specific methods
  if !l:copy_success
    if has('win32') || has('win64')
      " Windows: try robocopy or xcopy
      if executable('robocopy')
        call plugin_manager#ui#update_sidebar(['Copying files using robocopy...'], 1)
        let l:copy_result = system('robocopy ' . shellescape(a:localPath) . ' ' . shellescape(a:installDir) . ' /E /XD .git')
        " Note: robocopy returns non-zero for successful operations with info codes
        let l:copy_success = v:shell_error < 8  
      else
        call plugin_manager#ui#update_sidebar(['Copying files using xcopy...'], 1)
        let l:copy_result = system('xcopy ' . shellescape(a:localPath) . '\* ' . shellescape(a:installDir) . ' /E /I /Y /EXCLUDE:.git')
        let l:copy_success = v:shell_error == 0
      endif
    else
      " Unix: use cp with find to exclude .git
      call plugin_manager#ui#update_sidebar(['Copying files using cp/find...'], 1)
      let l:copy_cmd = 'cd ' . shellescape(a:localPath) . ' && find . -type d -name ".git" -prune -o -type f -print | xargs -I{} cp --parents {} ' . shellescape(a:installDir)
      let l:copy_result = system(l:copy_cmd)
      let l:copy_success = v:shell_error == 0
      
      " If that fails, try simple cp with manual .git removal after
      if !l:copy_success
        call plugin_manager#ui#update_sidebar(['Trying simple copy method...'], 1)
        let l:copy_result = system('cp -R ' . shellescape(a:localPath) . '/* ' . shellescape(a:installDir))
        let l:copy_success = v:shell_error == 0
        
        " If successful, remove .git if it was copied
        if l:copy_success && isdirectory(a:installDir . '/.git')
          let l:rm_result = system('rm -rf ' . shellescape(a:installDir . '/.git'))
        endif
      endif
    endif
  endif
  
  if !l:copy_success
    let l:error_lines = ['Error copying files:']
    call extend(l:error_lines, split(l:copy_result, "\n"))
    call plugin_manager#ui#update_sidebar(l:error_lines, 1)
    return
  endif
  
  call plugin_manager#ui#update_sidebar(['Files copied successfully.'], 1)
  
  " Execute custom command if provided
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
  
  " Generate helptags if doc directory exists
  call plugin_manager#ui#update_sidebar(['Local plugin installed successfully.', 'Generating helptags...'], 1)
  if s:generate_helptag(a:installDir)
    call plugin_manager#ui#update_sidebar(['Helptags generated successfully.'], 1)
  else
    call plugin_manager#ui#update_sidebar(['No documentation directory found.'], 1)
  endif
endfunction

" Add a new plugin
function! s:add_module(moduleUrl, installDir, options)
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
  
  " Process branch and tag options if provided
  if !empty(a:options.branch)
    call plugin_manager#ui#update_sidebar(['Checking out branch: ' . a:options.branch . '...'], 1)
    let l:branch_result = system('cd "' . l:relativeInstallDir . '" && git checkout ' . a:options.branch)
    if v:shell_error != 0
      call plugin_manager#ui#update_sidebar(['Warning: Failed to checkout branch: ' . a:options.branch, 
            \ l:branch_result], 1)
    endif
  elseif !empty(a:options.tag)
    call plugin_manager#ui#update_sidebar(['Checking out tag: ' . a:options.tag . '...'], 1)
    let l:tag_result = system('cd "' . l:relativeInstallDir . '" && git checkout ' . a:options.tag)
    if v:shell_error != 0
      call plugin_manager#ui#update_sidebar(['Warning: Failed to checkout tag: ' . a:options.tag, 
            \ l:tag_result], 1)
    endif
  endif
  
  " Execute custom command if provided
  if !empty(a:options.exec)
    call plugin_manager#ui#update_sidebar(['Executing command: ' . a:options.exec . '...'], 1)
    let l:exec_result = system('cd "' . l:relativeInstallDir . '" && ' . a:options.exec)
    if v:shell_error != 0
      call plugin_manager#ui#update_sidebar(['Warning: Command execution failed:', 
            \ l:exec_result], 1)
    else
      call plugin_manager#ui#update_sidebar(['Command executed successfully.'], 1)
    endif
  endif
  
  call plugin_manager#ui#update_sidebar(['Committing changes...'], 1)
  
  " Create a more informative commit message
  let l:commit_msg = "Added " . a:moduleUrl . " module"
  if !empty(a:options.branch)
    let l:commit_msg .= " (branch: " . a:options.branch . ")"
  elseif !empty(a:options.tag)
    let l:commit_msg .= " (tag: " . a:options.tag . ")"
  endif
  
  let l:result = system('git commit -m "' . l:commit_msg . '"')
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
  
  " Check if vimrc or init.vim exists in the vim directory
  let l:vimrc_basename = fnamemodify(g:plugin_manager_vimrc_path, ':t')
  let l:local_vimrc = g:plugin_manager_vim_dir . '/' . l:vimrc_basename
  
  " If vimrc doesn't exist in the vim directory or isn't a symlink, copy it
  if !filereadable(l:local_vimrc) || (!has('win32') && !has('win64') && getftype(l:local_vimrc) != 'link')
    if filereadable(g:plugin_manager_vimrc_path)
      call plugin_manager#ui#update_sidebar(['Copying ' . l:vimrc_basename . ' file to vim directory for backup...'], 1)
      
      " Create a backup copy of the vimrc file
      let l:copy_cmd = 'cp "' . g:plugin_manager_vimrc_path . '" "' . l:local_vimrc . '"'
      let l:copy_result = system(l:copy_cmd)
      
      if v:shell_error != 0
        call plugin_manager#ui#update_sidebar(['Error copying vimrc file: ' . l:copy_result], 1)
      else
        call plugin_manager#ui#update_sidebar([l:vimrc_basename . ' file copied successfully.'], 1)
        
        " Add the copied file to git
        let l:git_add = system('git add "' . l:local_vimrc . '"')
        if v:shell_error != 0
          call plugin_manager#ui#update_sidebar(['Warning: Could not add ' . l:vimrc_basename . ' to git: ' . l:git_add], 1)
        endif
      endif
    else
      call plugin_manager#ui#update_sidebar(['Warning: ' . l:vimrc_basename . ' file not found at ' . g:plugin_manager_vimrc_path], 1)
    endif
  endif
  
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