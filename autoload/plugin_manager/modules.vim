" " autoload/plugin_manager/modules.vim - Module management functions for vim-plugin-manager

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
  try
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
    
    " Use the gitmodules cache
    let l:modules = plugin_manager#utils#parse_gitmodules()
    let l:title = 'Updating Plugins:'
    
    if empty(l:modules)
      throw 'PM_ERROR:update:No plugins to update (.gitmodules not found)'
    endif
    
    " Initialize header once
    let l:header = [l:title, repeat('-', len(l:title)), '']
    
    " Check if a specific module was specified
    let l:specific_module = a:0 > 0 ? a:1 : 'all'
    
    " List to track modules that have been updated
    let l:updated_modules = []
    
    if l:specific_module == 'all'
      call s:update_all_plugins(l:header, l:modules, l:updated_modules)
    else
      call s:update_specific_plugin(l:header, l:modules, l:specific_module, l:updated_modules)
    endif
    
    " Process update results and generate helptags
    call s:process_update_results(l:updated_modules)
    
    " Force refresh the cache after updates
    call plugin_manager#utils#refresh_modules_cache()
  catch
    let l:error = plugin_manager#utils#is_pm_error(v:exception) 
          \ ? plugin_manager#utils#format_error(v:exception)
          \ : 'Unexpected error during update: ' . v:exception
    
    call plugin_manager#ui#open_sidebar([l:title, repeat('-', len(l:title)), '', l:error])
  endtry
endfunction

" Helper function for updating all plugins
function! s:update_all_plugins(header, modules, updated_modules)
  let l:initial_message = a:header + ['Checking for updates on all plugins...']
  call plugin_manager#ui#open_sidebar(l:initial_message)
  
  " Handle helptags files differently to avoid merge conflicts
  call plugin_manager#ui#update_sidebar(['Preparing modules for update...'], 1)
  call system('git submodule foreach --recursive "rm -f doc/tags doc/*/tags */tags 2>/dev/null || true"')
  
  " Stash local changes if needed
  call s:stash_local_changes(a:modules)
  
  " Fetch updates from remote repositories
  call plugin_manager#ui#update_sidebar(['Fetching updates from remote repositories...'], 1)
  call system('git submodule foreach --recursive "git fetch origin"')
  
  " Check which modules have updates available
  let l:modules_with_updates = []
  let l:modules_on_diff_branch = []
  
  call s:analyze_modules_status(a:modules, l:modules_with_updates, l:modules_on_diff_branch)
  
  " Report on modules with custom branches
  if !empty(l:modules_on_diff_branch)
    call s:report_custom_branches(l:modules_on_diff_branch)
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
    let a:updated_modules += l:modules_with_updates
  endif
endfunction

" Helper function for updating a specific plugin
function! s:update_specific_plugin(header, modules, module_name, updated_modules)
  " Find the module
  let l:module_info = plugin_manager#utils#find_module(a:module_name)
  
  if empty(l:module_info)
    throw 'PM_ERROR:update:Module "' . a:module_name . '" not found'
  endif
  
  let l:module = l:module_info.module
  let l:module_path = l:module.path
  let l:module_name = l:module.short_name
  
  let l:initial_message = a:header + ['Checking for updates on plugin: ' . l:module_name . ' (' . l:module_path . ')...']
  call plugin_manager#ui#open_sidebar(l:initial_message)
  
  " Check if directory exists
  if !isdirectory(l:module_path)
    throw 'PM_ERROR:update:Module directory "' . l:module_path . '" not found. Try running "PluginManager restore"'
  endif
  
  " Handle helptags files and local changes
  call plugin_manager#ui#update_sidebar(['Preparing module for update...'], 1)
  call system('cd "' . l:module_path . '" && rm -f doc/tags doc/*/tags */tags 2>/dev/null || true')
  
  " Check if there are any remaining local changes
  call s:stash_module_changes(l:module_path)
  
  " Fetch updates from remote repository
  call plugin_manager#ui#update_sidebar(['Fetching updates from remote repository...'], 1)
  call system('cd "' . l:module_path . '" && git fetch origin')
  
  " Use the utility function to check for updates
  let l:update_status = plugin_manager#utils#check_module_updates(l:module_path)
  
  " Check if we're on a custom branch
  if l:update_status.different_branch && l:update_status.branch != "detached"
    call s:report_custom_branch_for_module(l:module_name, l:update_status, l:module_path)
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
    call add(a:updated_modules, l:module)
  endif
endfunction

" Helper function to stash local changes in all modules
function! s:stash_local_changes(modules)
  let l:any_changes = 0
  
  " Check if any module has local changes
  for [l:name, l:module] in items(a:modules)
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
endfunction

" Helper function to stash changes in a single module
function! s:stash_module_changes(module_path)
  let l:changes = system('cd "' . a:module_path . '" && git status -s 2>/dev/null')
  if !empty(l:changes)
    call plugin_manager#ui#update_sidebar(['Stashing local changes...'], 1)
    call system('cd "' . a:module_path . '" && git stash -q || true')
  else
    call plugin_manager#ui#update_sidebar(['No local changes to stash...'], 1)
  endif
endfunction

" Helper function to analyze update status of all modules
function! s:analyze_modules_status(modules, modules_with_updates, modules_on_diff_branch)
  for [l:name, l:module] in items(a:modules)
    if l:module.is_valid && isdirectory(l:module.path)
      " Use the utility function to check for updates
      let l:update_status = plugin_manager#utils#check_module_updates(l:module.path)
      
      " If module is on a different branch, add to special list
      if l:update_status.different_branch && l:update_status.branch != "detached"
        call add(a:modules_on_diff_branch, {'module': l:module, 'status': l:update_status})
      " If module has updates, add to update list
      elseif l:update_status.has_updates
        call add(a:modules_with_updates, l:module)
      endif
    endif
  endfor
endfunction

" Helper function to report on custom branches
function! s:report_custom_branches(modules_on_diff_branch)
  let l:branch_lines = ['', 'The following plugins are on custom branches:']
  for l:item in a:modules_on_diff_branch
    call add(l:branch_lines, '- ' . l:item.module.short_name . 
          \ ' (local: ' . l:item.status.branch . 
          \ ', target: ' . l:item.status.remote_branch . ')')
  endfor
  call add(l:branch_lines, 'These plugins will not be updated automatically to preserve your branch choice.')
  call plugin_manager#ui#update_sidebar(l:branch_lines, 1)
endfunction

" Helper function to report on a custom branch for a specific module
function! s:report_custom_branch_for_module(module_name, update_status, module_path)
  call plugin_manager#ui#update_sidebar([
        \ 'Plugin "' . a:module_name . '" is on a custom branch:', 
        \ '- Local branch: ' . a:update_status.branch,
        \ '- Target branch: ' . a:update_status.remote_branch,
        \ 'To preserve your branch choice, the plugin will not be updated automatically.',
        \ 'To update anyway, run: git submodule update --remote --force -- "' . a:module_path . '"'
        \ ], 1)
endfunction

" Helper function to process update results and generate helptags
function! s:process_update_results(updated_modules)
  if empty(a:updated_modules)
    call plugin_manager#ui#update_sidebar(['', 'No plugins were updated.'], 1)
    return
  endif
  
  " Show what was updated
  let l:update_lines = ['', 'Updated plugins:']
  for l:module in a:updated_modules
    let l:log = system('cd "' . l:module.path . '" && git log -1 --format="%h %s" 2>/dev/null')
    if !empty(l:log)
      call add(l:update_lines, l:module.short_name . ': ' . substitute(l:log, '\n', '', 'g'))
    else
      call add(l:update_lines, l:module.short_name)
    endif
  endfor
  
  " Add update success message
  let l:update_lines += ['', 'Update completed successfully.']
  call plugin_manager#ui#update_sidebar(l:update_lines, 1)
  
  " Generate helptags only for updated modules
  call plugin_manager#ui#update_sidebar(['', 'Generating helptags for updated plugins:'], 1)
  let l:helptags_generated = 0
  let l:generated_plugins = []
  
  for l:module in a:updated_modules
    let l:plugin_path = l:module.path
    let l:docPath = l:plugin_path . '/doc'
    if isdirectory(l:docPath)
      execute 'helptags ' . l:docPath
      let l:helptags_generated = 1
      call add(l:generated_plugins, "Generated helptags for " . l:module.short_name)
    endif
  endfor
  
  let l:helptags_result = l:helptags_generated 
        \ ? l:generated_plugins + ["Helptags generation completed."]
        \ : ["No documentation directories found in updated plugins."]
  
  call plugin_manager#ui#update_sidebar(l:helptags_result, 1)
endfunction
  
" Handle 'add' command
function! plugin_manager#modules#add(...)
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
  
  if s:generate_helptag(a:installDir)
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
  
" Handle 'remove' command
function! plugin_manager#modules#remove(...)
  try
    if a:0 < 1
      throw 'PM_ERROR:remove:Missing plugin name argument'
    endif
    
    let l:moduleName = a:1
    let l:force_flag = a:0 >= 2 && a:2 == "-f"
    
    " Find the module
    let [l:found, l:module_name, l:module_path] = s:find_module_for_removal(l:moduleName)
    
    if !l:found
      throw 'PM_ERROR:remove:Module "' . l:moduleName . '" not found'
    endif
    
    " Force flag provided or prompt for confirmation
    if l:force_flag || s:confirm_removal(l:module_name, l:module_path)
      call s:remove_module(l:module_name, l:module_path)
    endif
    
    return 0
  catch
    let l:error = plugin_manager#utils#is_pm_error(v:exception) 
          \ ? plugin_manager#utils#format_error(v:exception)
          \ : 'Unexpected error during plugin removal: ' . v:exception
    
    let l:lines = ["Remove Plugin Error:", repeat('-', 20), "", l:error]
    
    if v:exception =~ 'not found'
      " Add available modules list to help the user
      let l:modules = plugin_manager#utils#parse_gitmodules()
      if !empty(l:modules)
        let l:lines += ["", "Available modules:"]
        for [l:name, l:module] in items(l:modules)
          if l:module.is_valid
            call add(l:lines, "- " . l:module.short_name . " (" . l:module.path . ")")
          endif
        endfor
      endif
    endif
    
    call plugin_manager#ui#open_sidebar(l:lines)
    return 1
  endtry
endfunction

" Helper function to find a module for removal
function! s:find_module_for_removal(module_name)
  " Use the module finder from the cache system
  let l:module_info = plugin_manager#utils#find_module(a:module_name)
  
  if !empty(l:module_info)
    let l:module = l:module_info.module
    return [1, l:module.short_name, l:module.path]
  endif
  
  " Module not found in cache, fallback to filesystem search
  let l:find_cmd = 'find ' . g:plugin_manager_plugins_dir . ' -type d -name "*' . a:module_name . '*" | head -n1'
  let l:removedPluginPath = substitute(system(l:find_cmd), '\n$', '', '')
  
  if !empty(l:removedPluginPath) && isdirectory(l:removedPluginPath)
    let l:module_name = fnamemodify(l:removedPluginPath, ':t')
    return [1, l:module_name, l:removedPluginPath]
  endif
  
  return [0, '', '']
endfunction

" Helper function to confirm module removal
function! s:confirm_removal(module_name, module_path)
  let l:response = input("Are you sure you want to remove " . a:module_name . " (" . a:module_path . ")? [y/N] ")
  return l:response =~? '^y\(es\)\?$'
endfunction
  
" Remove an existing plugin
function! s:remove_module(moduleName, removedPluginPath)
  try
    if !plugin_manager#utils#ensure_vim_directory()
      throw 'PM_ERROR:remove:Not in Vim configuration directory'
    endif
    
    let l:header = ['Remove Plugin:', '-------------', '', 'Removing ' . a:moduleName . ' from ' . a:removedPluginPath . '...']
    call plugin_manager#ui#open_sidebar(l:header)
    
    " Back up module information before removing it
    let l:module_info = s:get_module_info(a:removedPluginPath)
    
    " Execute deinit command
    call plugin_manager#ui#update_sidebar(['Deinitializing submodule...'], 1)
    let l:result = system('git submodule deinit -f "' . a:removedPluginPath . '" 2>&1')
    let l:deinit_success = v:shell_error == 0
    
    if !l:deinit_success
      call plugin_manager#ui#update_sidebar(['Warning during deinitializing submodule (continuing anyway):', l:result], 1)
    else
      call plugin_manager#ui#update_sidebar(['Deinitialized submodule successfully.'], 1)
    endif
    
    " Remove repository
    call plugin_manager#ui#update_sidebar(['Removing repository...'], 1)
    let l:result = system('git rm -f "' . a:removedPluginPath . '" 2>&1')
    
    if v:shell_error != 0
      call plugin_manager#ui#update_sidebar(['Error removing repository, trying alternative method...'], 1)
      let l:result = system('rm -rf "' . a:removedPluginPath . '" 2>&1')
      
      if v:shell_error != 0
        throw 'PM_ERROR:remove:Failed to remove directory: ' . l:result
      endif
      
      call plugin_manager#ui#update_sidebar(['Directory removed manually. You may need to edit .gitmodules manually.'], 1)
    else
      call plugin_manager#ui#update_sidebar(['Repository removed successfully.'], 1)
    endif
    
    " Clean .git modules directory
    call s:clean_git_modules(a:removedPluginPath)
    
    " Commit changes
    call s:commit_removal(a:moduleName, l:module_info)
    
    " Force refresh the cache after removal
    call plugin_manager#utils#refresh_modules_cache()
    
    call plugin_manager#ui#update_sidebar(['Plugin removal completed.'], 1)
  catch
    let l:error = plugin_manager#utils#is_pm_error(v:exception) 
          \ ? plugin_manager#utils#format_error(v:exception)
          \ : 'Error during plugin removal: ' . v:exception
    
    call plugin_manager#ui#update_sidebar(['Error: ' . l:error], 1)
  endtry
endfunction

" Helper to get module info
function! s:get_module_info(module_path)
  let l:modules = plugin_manager#utils#parse_gitmodules()
  let l:module_info = {}
  
  for [l:name, l:module] in items(l:modules)
    if has_key(l:module, 'path') && l:module.path ==# a:module_path
      let l:module_info = l:module
      call plugin_manager#ui#update_sidebar([
            \ 'Found module information:',
            \ '- Name: ' . l:module_info.name,
            \ '- URL: ' . l:module_info.url
            \ ], 1)
      break
    endif
  endfor
  
  return l:module_info
endfunction

" Helper to clean .git/modules directory
function! s:clean_git_modules(module_path)
  call plugin_manager#ui#update_sidebar(['Cleaning .git modules...'], 1)
  
  if isdirectory('.git/modules/' . a:module_path)
    let l:result = system('rm -rf ".git/modules/' . a:module_path . '" 2>&1')
    if v:shell_error != 0
      call plugin_manager#ui#update_sidebar(['Warning cleaning git modules (continuing anyway):', l:result], 1)
    else
      call plugin_manager#ui#update_sidebar(['Git modules cleaned successfully.'], 1)
    endif
  else
    call plugin_manager#ui#update_sidebar(['No module directory to clean in .git/modules.'], 1)
  endif
endfunction

" Helper to commit removal
function! s:commit_removal(module_name, module_info)
  call plugin_manager#ui#update_sidebar(['Committing changes...'], 1)
  
  " Create a commit message with module info if available
  let l:commit_msg = "Removed " . a:module_name . " module"
  if !empty(a:module_info) && has_key(a:module_info, 'url')
    let l:commit_msg .= " (" . a:module_info.url . ")"
  endif
  
  let l:result = system('git add -A && git commit -m "' . l:commit_msg . '" || git commit --allow-empty -m "' . l:commit_msg . '" 2>&1')
  if v:shell_error != 0
    call plugin_manager#ui#update_sidebar(['Warning during commit (plugin still removed):', l:result], 1)
  else
    call plugin_manager#ui#update_sidebar(['Changes committed successfully.'], 1)
  endif
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
  
" Reload a specific plugin or all Vim configuration
function! plugin_manager#modules#reload(...)
  try
    if !plugin_manager#utils#ensure_vim_directory()
      throw 'PM_ERROR:reload:Not in Vim configuration directory'
    endif
    
    let l:header = ['Reload:', '-------', '']
    
    " Check if a specific module was specified
    let l:specific_module = a:0 > 0 ? a:1 : ''
    
    if !empty(l:specific_module)
      call s:reload_specific_plugin(l:header, l:specific_module)
    else
      call s:reload_all_configuration(l:header)
    endif
  catch
    let l:error = plugin_manager#utils#is_pm_error(v:exception) 
          \ ? plugin_manager#utils#format_error(v:exception)
          \ : 'Unexpected error during reload: ' . v:exception
    
    call plugin_manager#ui#open_sidebar(['Reload Error:', repeat('-', 13), '', l:error])
  endtry
endfunction

" Helper function to reload a specific plugin
function! s:reload_specific_plugin(header, module_name)
  call plugin_manager#ui#open_sidebar(a:header + ['Reloading plugin: ' . a:module_name . '...'])
  
  " Find the module path
  let l:module_path = s:find_plugin_path(a:module_name)
  if empty(l:module_path)
    throw 'PM_ERROR:reload:Module "' . a:module_name . '" not found'
  endif
  
  " Remove plugin from runtimepath
  call s:remove_from_runtimepath(l:module_path)
  
  " Unload plugin scripts
  call s:unload_plugin_scripts(l:module_path)
  
  " Add back to runtimepath
  call s:add_to_runtimepath(l:module_path)
  
  " Reload plugin runtime files
  call s:reload_plugin_runtime_files(l:module_path)
  
  call plugin_manager#ui#update_sidebar(['Plugin "' . a:module_name . '" reloaded successfully.', 
        \ 'Note: Some plugins may require restarting Vim for a complete reload.'], 1)
endfunction

" Helper function to reload all Vim configuration
function! s:reload_all_configuration(header)
  call plugin_manager#ui#open_sidebar(a:header + ['Reloading entire Vim configuration...'])
  
  " Unload all plugins
  call plugin_manager#ui#update_sidebar(['Unloading plugins...'], 1)
  
  " Reload runtime files
  call s:reload_all_runtime_files()
  
  " Source vimrc file
  call s:source_vimrc()
  
  call plugin_manager#ui#update_sidebar(['Vim configuration reloaded successfully.', 
        \ 'Note: Some plugins may require restarting Vim for a complete reload.'], 1)
endfunction

" Helper function to find plugin path
function! s:find_plugin_path(module_name)
  let l:grep_cmd = 'grep -A1 "path = .*' . a:module_name . '" .gitmodules | grep "path =" | cut -d "=" -f2 | tr -d " "'
  let l:module_path = system(l:grep_cmd)
  let l:module_path = substitute(l:module_path, '\n$', '', '')
  
  return l:module_path
endfunction

" Helper function to remove plugin from runtimepath
function! s:remove_from_runtimepath(module_path)
  execute 'set rtp-=' . a:module_path
endfunction

" Helper function to add plugin to runtimepath
function! s:add_to_runtimepath(module_path)
  execute 'set rtp+=' . a:module_path
endfunction

" Helper function to unload plugin scripts
function! s:unload_plugin_scripts(module_path)
  let l:runtime_paths = split(globpath(a:module_path, '**/*.vim'), '\n')
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
endfunction

" Helper function to reload plugin runtime files
function! s:reload_plugin_runtime_files(module_path)
  let l:runtime_paths = split(globpath(a:module_path, '**/*.vim'), '\n')
  for l:rtp in l:runtime_paths
    if l:rtp =~ '/plugin/' || l:rtp =~ '/ftplugin/'
      execute 'runtime! ' . l:rtp
    endif
  endfor
endfunction

" Helper function to reload all runtime files
function! s:reload_all_runtime_files()
  execute 'runtime! plugin/**/*.vim'
  execute 'runtime! ftplugin/**/*.vim'
  execute 'runtime! syntax/**/*.vim'
  execute 'runtime! indent/**/*.vim'
endfunction

" Helper function to source vimrc file
function! s:source_vimrc()
  if filereadable(expand(g:plugin_manager_vimrc_path))
    call plugin_manager#ui#update_sidebar(['Sourcing ' . g:plugin_manager_vimrc_path . '...'], 1)
    execute 'source ' . g:plugin_manager_vimrc_path
  else
    call plugin_manager#ui#update_sidebar(['Warning: Vimrc file not found at ' . g:plugin_manager_vimrc_path], 1)
  endif
endfunction

" Backup configuration to remote repositories
function! plugin_manager#modules#backup()
  try
    if !plugin_manager#utils#ensure_vim_directory()
      throw 'PM_ERROR:backup:Not in Vim configuration directory'
    endif
    
    let l:header = ['Backup Configuration:', '--------------------', '', 'Starting backup process...']
    call plugin_manager#ui#open_sidebar(l:header)
    
    " Copy vimrc file if needed
    call s:backup_vimrc_file()
    
    " Commit local changes if any
    call s:commit_local_changes()
    
    " Push to remote repositories
    call s:push_to_remotes()
    
  catch
    let l:error = plugin_manager#utils#is_pm_error(v:exception) 
          \ ? plugin_manager#utils#format_error(v:exception)
          \ : 'Unexpected error during backup: ' . v:exception
    
    call plugin_manager#ui#update_sidebar(['Error: ' . l:error], 1)
  endtry
endfunction

" Helper function to backup vimrc file
function! s:backup_vimrc_file()
  " Check if vimrc or init.vim exists in the vim directory
  let l:vimrc_basename = fnamemodify(g:plugin_manager_vimrc_path, ':t')
  let l:local_vimrc = g:plugin_manager_vim_dir . '/' . l:vimrc_basename
  
  " If vimrc doesn't exist in the vim directory or isn't a symlink, copy it
  if !filereadable(l:local_vimrc) || (!has('win32') && !has('win64') && getftype(l:local_vimrc) != 'link')
    if filereadable(g:plugin_manager_vimrc_path)
      call plugin_manager#ui#update_sidebar(['Copying ' . l:vimrc_basename . ' file to vim directory...'], 1)
      
      " Create a backup copy of the vimrc file
      let l:copy_cmd = 'cp "' . g:plugin_manager_vimrc_path . '" "' . l:local_vimrc . '"'
      let l:copy_result = system(l:copy_cmd)
      
      if v:shell_error != 0
        throw 'PM_ERROR:backup:Error copying vimrc file: ' . l:copy_result
      endif
      
      call plugin_manager#ui#update_sidebar([l:vimrc_basename . ' file copied successfully.'], 1)
      
      " Add the copied file to git
      let l:git_add = system('git add "' . l:local_vimrc . '"')
      if v:shell_error != 0
        call plugin_manager#ui#update_sidebar(['Warning: Could not add ' . l:vimrc_basename . ' to git: ' . l:git_add], 1)
      endif
    else
      call plugin_manager#ui#update_sidebar(['Warning: ' . l:vimrc_basename . ' file not found at ' . g:plugin_manager_vimrc_path], 1)
    endif
  endif
endfunction

" Helper function to commit local changes
function! s:commit_local_changes()
  " Check if there are changes to commit
  let l:gitStatus = system('git status -s')
  
  if !empty(l:gitStatus)
    call plugin_manager#ui#update_sidebar(['Committing local changes...'], 1)
    let l:commitResult = system('git commit -am "Automatic backup"')
    call plugin_manager#ui#update_sidebar(split(l:commitResult, "\n"), 1)
  else
    call plugin_manager#ui#update_sidebar(['No local changes to commit.'], 1)
  endif
endfunction

" Helper function to push to remote repositories
function! s:push_to_remotes()
  call plugin_manager#ui#update_sidebar(['Pushing changes to remote repositories...'], 1)
  
  " Check if any remotes exist
  let l:remotesExist = system('git remote')
  if empty(l:remotesExist)
    throw 'PM_ERROR:backup:No remote repositories configured. Use PluginManagerRemote to add a remote repository.'
  endif
  
  let l:pushResult = system('git push --all')
  if v:shell_error != 0
    throw 'PM_ERROR:backup:Error pushing to remote: ' . l:pushResult
  endif
  
  call plugin_manager#ui#update_sidebar(['Backup completed successfully.'], 1)
endfunction

" Restore all plugins from .gitmodules
function! plugin_manager#modules#restore()
  try
    if !plugin_manager#utils#ensure_vim_directory()
      throw 'PM_ERROR:restore:Not in Vim configuration directory'
    endif
    
    let l:header = ['Restore Plugins:', '---------------', '', 'Starting plugin restoration...']
    call plugin_manager#ui#open_sidebar(l:header)
    
    call s:check_gitmodules_exists()
    call s:initialize_submodules()
    call s:update_submodules()
    call s:finalize_submodules()
    
    call plugin_manager#ui#update_sidebar(['All plugins have been restored successfully.', '', 'Generating helptags:'], 1)
    call plugin_manager#modules#generate_helptags(0)
    
  catch
    let l:error = plugin_manager#utils#is_pm_error(v:exception) 
          \ ? plugin_manager#utils#format_error(v:exception)
          \ : 'Unexpected error during restore: ' . v:exception
    
    call plugin_manager#ui#update_sidebar(['Error: ' . l:error], 1)
  endtry
endfunction

" Helper function to check if .gitmodules exists
function! s:check_gitmodules_exists()
  if !filereadable('.gitmodules')
    throw 'PM_ERROR:restore:.gitmodules file not found'
  endif
  
  call plugin_manager#ui#update_sidebar(['Found .gitmodules file.'], 1)
endfunction

" Helper function to initialize submodules
function! s:initialize_submodules()
  call plugin_manager#ui#update_sidebar(['Initializing submodules...'], 1)
  
  let l:result = system('git submodule init')
  if v:shell_error != 0
    throw 'PM_ERROR:restore:Error initializing submodules: ' . l:result
  endif
endfunction

" Helper function to update submodules
function! s:update_submodules()
  call plugin_manager#ui#update_sidebar(['Fetching and updating all submodules...'], 1)
  
  let l:result = system('git submodule update --init --recursive')
  if v:shell_error != 0
    throw 'PM_ERROR:restore:Error updating submodules: ' . l:result
  endif
endfunction

" Helper function to finalize submodule restoration
function! s:finalize_submodules()
  call plugin_manager#ui#update_sidebar(['Ensuring all submodules are at the correct commit...'], 1)
  
  call system('git submodule sync')
  let l:result = system('git submodule update --init --recursive --force')
  if v:shell_error != 0
    throw 'PM_ERROR:restore:Error during final submodule update: ' . l:result
  endif
endfunction