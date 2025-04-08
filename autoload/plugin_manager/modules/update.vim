" autoload/plugin_manager/modules/update.vim - Functions for updating plugins

" Update plugins
function! plugin_manager#modules#update#plugins(...)
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
      
      " Check if a specific module was specified
      let l:specific_module = a:0 > 0 ? a:1 : 'all'
      
      " List to track modules that have been updated
      let l:updated_modules = []
      
      if l:specific_module == 'all'
        let l:updated_modules = s:update_all_plugins(l:title, l:modules)
      else
        call s:update_specific_plugin(l:title, l:modules, l:specific_module, l:updated_modules)
      endif
      
      " Process update results and generate helptags
      call s:process_update_results(l:updated_modules)
      
      " Force refresh the cache after updates
      call plugin_manager#utils#refresh_modules_cache()
    catch
      let l:error = plugin_manager#utils#is_pm_error(v:exception) 
            \ ? plugin_manager#utils#format_error(v:exception)
            \ : 'Unexpected error during update: ' . v:exception
      
      call plugin_manager#ui#display_error('update', l:error)
    endtry
endfunction
  
" Helper function for updating all plugins
function! s:update_all_plugins(title, modules) abort
    let l:header = [a:title, repeat('-', len(a:title)), '']
    call plugin_manager#ui#open_sidebar(l:header)
    
    " Create a variable to track updated modules
    let l:updated_modules = []
    
    " Start a task for the overall update process
    let l:job_id = plugin_manager#ui#start_task('Plugin update process', len(a:modules))
    let l:current_progress = 0
    
    " Handle helptags files differently to avoid merge conflicts
    call plugin_manager#ui#start_spinner('Preparing modules for update')
    call system('git submodule foreach --recursive "rm -f doc/tags doc/*/tags */tags 2>/dev/null || true"')
    call plugin_manager#ui#stop_spinner(1, plugin_manager#ui#success('Modules prepared for update'))
    call plugin_manager#ui#update_task(l:job_id, l:current_progress, 'Modules prepared')
    
    " Stash local changes if needed
    call plugin_manager#ui#start_spinner('Checking for local changes')
    call s:stash_local_changes(a:modules)
    call plugin_manager#ui#stop_spinner(1, plugin_manager#ui#success('Local changes handled'))
    let l:current_progress += 1
    call plugin_manager#ui#update_task(l:job_id, l:current_progress, 'Local changes handled')
    
    " Fetch updates from remote repositories
    call plugin_manager#ui#start_spinner('Fetching updates from remote repositories')
    call system('git submodule foreach --recursive "git fetch origin"')
    call plugin_manager#ui#stop_spinner(1, plugin_manager#ui#success('Updates fetched successfully'))
    let l:current_progress += 1
    call plugin_manager#ui#update_task(l:job_id, l:current_progress, 'Updates fetched')
    
    " Check which modules have updates available
    call plugin_manager#ui#start_spinner('Analyzing repository status')
    let l:modules_with_updates = []
    let l:modules_on_diff_branch = []
    
    call s:analyze_modules_status(a:modules, l:modules_with_updates, l:modules_on_diff_branch)
    call plugin_manager#ui#stop_spinner(1, plugin_manager#ui#success('Repository analysis complete'))
    let l:current_progress += 1
    call plugin_manager#ui#update_task(l:job_id, l:current_progress, 'Analysis complete')
    
    " Report on modules with custom branches
    if !empty(l:modules_on_diff_branch)
      call s:report_custom_branches(l:modules_on_diff_branch)
    endif
    
    if empty(l:modules_with_updates)
      call plugin_manager#ui#update_sidebar([plugin_manager#ui#info('All plugins are up-to-date.')], 1)
      call plugin_manager#ui#complete_task(l:job_id, 1, 'All plugins are already up-to-date!')
    else
      call plugin_manager#ui#update_sidebar([plugin_manager#ui#info('Found ' . len(l:modules_with_updates) . ' plugins with updates available.')], 1)
      
      " Execute update commands with progress visualization
      call plugin_manager#ui#start_spinner('Synchronizing submodules')
      call system('git submodule sync')
      call plugin_manager#ui#stop_spinner(1, plugin_manager#ui#success('Submodules synchronized'))
      let l:current_progress += 1
      call plugin_manager#ui#update_task(l:job_id, l:current_progress, 'Submodules synced')
      
      " Start the actual update with a new spinner
      call plugin_manager#ui#start_spinner('Updating ' . len(l:modules_with_updates) . ' plugins')
      let l:updateResult = system('git submodule update --remote --merge --force')
      call plugin_manager#ui#stop_spinner(1, plugin_manager#ui#success('Plugin updates completed'))
      let l:current_progress += 1
      call plugin_manager#ui#update_task(l:job_id, l:current_progress, 'Plugins updated')
      
      " Check if commit is needed
      call plugin_manager#ui#start_spinner('Committing changes')
      let l:gitStatus = system('git status -s')
      if !empty(l:gitStatus)
        let l:commitResult = system('git commit -am "Update Modules"')
        call plugin_manager#ui#stop_spinner(1, plugin_manager#ui#success('Changes committed successfully'))
      else
        call plugin_manager#ui#stop_spinner(1, plugin_manager#ui#info('No changes to commit'))
      endif
      let l:current_progress += 1
      call plugin_manager#ui#update_task(l:job_id, l:current_progress, 'Changes committed')
      
      " Save the updated modules to our local variable
      let l:updated_modules = l:modules_with_updates
      
      " Complete the overall task
      call plugin_manager#ui#complete_task(l:job_id, 1, 'Update process completed successfully!')
    endif
    
    " Return the updated modules
    return l:updated_modules
endfunction

" Helper function for updating a specific plugin
function! s:update_specific_plugin(title, modules, module_name, updated_modules)
  " Find the module
  let l:module_info = plugin_manager#utils#find_module(a:module_name)
  
  if empty(l:module_info)
    throw 'PM_ERROR:update:Module "' . a:module_name . '" not found'
  endif
  
  let l:module = l:module_info.module
  let l:module_path = l:module.path
  let l:module_name = l:module.short_name
  
  let l:header = [a:title, repeat('-', len(a:title)), '']
  call plugin_manager#ui#open_sidebar(l:header)
  
  " Start update process with a spinner
  call plugin_manager#ui#start_spinner('Preparing to update plugin: ' . l:module_name)
  
  " Check if directory exists
  if !isdirectory(l:module_path)
    call plugin_manager#ui#stop_spinner(0, plugin_manager#ui#error('Module directory not found'))
    throw 'PM_ERROR:update:Module directory "' . l:module_path . '" not found. Try running "PluginManager restore"'
  endif
  
  " Handle helptags files and local changes
  call system('cd "' . l:module_path . '" && rm -f doc/tags doc/*/tags */tags 2>/dev/null || true')
  call plugin_manager#ui#stop_spinner(1, plugin_manager#ui#success('Plugin prepared for update'))
  
  " Check if there are any remaining local changes
  call plugin_manager#ui#start_spinner('Checking for local changes')
  call s:stash_module_changes(l:module_path)
  call plugin_manager#ui#stop_spinner(1, plugin_manager#ui#success('Local changes handled'))
  
  " Fetch updates from remote repository
  call plugin_manager#ui#start_spinner('Fetching updates from remote repository')
  call system('cd "' . l:module_path . '" && git fetch origin')
  call plugin_manager#ui#stop_spinner(1, plugin_manager#ui#success('Updates fetched successfully'))
  
  " Use the utility function to check for updates
  call plugin_manager#ui#start_spinner('Analyzing repository status')
  let l:update_status = plugin_manager#utils#check_module_updates(l:module_path)
  call plugin_manager#ui#stop_spinner(1, plugin_manager#ui#success('Repository analysis complete'))
  
  " Check if we're on a custom branch
  if l:update_status.different_branch && l:update_status.branch != "detached"
    call s:report_custom_branch_for_module(l:module_name, l:update_status, l:module_path)
    return
  endif
  
  " If module has no updates, it's up to date
  if !l:update_status.has_updates
    call plugin_manager#ui#update_sidebar([plugin_manager#ui#info('Plugin "' . l:module_name . '" is already up-to-date.')], 1)
  else
    call plugin_manager#ui#update_sidebar([plugin_manager#ui#info('Updates available for plugin "' . l:module_name . '".')], 1)
    
    " Update only this module
    call plugin_manager#ui#start_spinner('Updating plugin: ' . l:module_name)
    call system('git submodule sync -- "' . l:module_path . '"')
    let l:updateResult = system('git submodule update --remote --merge --force -- "' . l:module_path . '"')
    call plugin_manager#ui#stop_spinner(1, plugin_manager#ui#success('Plugin updated successfully'))
    
    " Check if commit is needed
    call plugin_manager#ui#start_spinner('Committing changes')
    let l:gitStatus = system('git status -s')
    if !empty(l:gitStatus)
      let l:commitResult = system('git commit -am "Update Module: ' . l:module_name . '"')
      call plugin_manager#ui#stop_spinner(1, plugin_manager#ui#success('Changes committed successfully'))
    else
      call plugin_manager#ui#stop_spinner(1, plugin_manager#ui#info('No changes to commit'))
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
    call plugin_manager#ui#update_sidebar([plugin_manager#ui#info('Stashing local changes in submodules...')], 1)
    call system('git submodule foreach --recursive "git stash -q || true"')
  else
    call plugin_manager#ui#update_sidebar([plugin_manager#ui#info('No local changes to stash.')], 1)
  endif
endfunction

" Helper function to stash changes in a single module
function! s:stash_module_changes(module_path)
  let l:changes = system('cd "' . a:module_path . '" && git status -s 2>/dev/null')
  if !empty(l:changes)
    call plugin_manager#ui#update_sidebar([plugin_manager#ui#info('Stashing local changes...')], 1)
    call system('cd "' . a:module_path . '" && git stash -q || true')
  else
    call plugin_manager#ui#update_sidebar([plugin_manager#ui#info('No local changes to stash.')], 1)
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
  let l:branch_lines = ['', plugin_manager#ui#warning('The following plugins are on custom branches:')]
  for l:item in a:modules_on_diff_branch
    call add(l:branch_lines, '- ' . l:item.module.short_name . 
          \ ' (local: ' . l:item.status.branch . 
          \ ', target: ' . l:item.status.remote_branch . ')')
  endfor
  call add(l:branch_lines, plugin_manager#ui#info('These plugins will not be updated automatically to preserve your branch choice.'))
  call plugin_manager#ui#update_sidebar(l:branch_lines, 1)
endfunction

" Helper function to report on a custom branch for a specific module
function! s:report_custom_branch_for_module(module_name, update_status, module_path)
  call plugin_manager#ui#update_sidebar([
        \ plugin_manager#ui#warning('Plugin "' . a:module_name . '" is on a custom branch:'), 
        \ '- Local branch: ' . a:update_status.branch,
        \ '- Target branch: ' . a:update_status.remote_branch,
        \ plugin_manager#ui#info('To preserve your branch choice, the plugin will not be updated automatically.'),
        \ plugin_manager#ui#info('To update anyway, run: git submodule update --remote --force -- "' . a:module_path . '"')
        \ ], 1)
endfunction

" Helper function to process update results and generate helptags
function! s:process_update_results(updated_modules)
  if empty(a:updated_modules)
    call plugin_manager#ui#update_sidebar(['', plugin_manager#ui#info('No plugins were updated.')], 1)
    return
  endif
  
  " Start a task for helptags generation
  let l:task_id = plugin_manager#ui#start_task('Updating helptags', len(a:updated_modules))
  
  " Show what was updated
  let l:update_lines = ['', plugin_manager#ui#success('Updated plugins:')]
  let l:module_count = 0
  
  for l:module in a:updated_modules
    let l:module_count += 1
    call plugin_manager#ui#update_task(l:task_id, l:module_count, 'Processing ' . l:module.short_name)
    
    let l:log = system('cd "' . l:module.path . '" && git log -1 --format="%h %s" 2>/dev/null')
    if !empty(l:log)
      call add(l:update_lines, l:module.short_name . ': ' . substitute(l:log, '\n', '', 'g'))
    else
      call add(l:update_lines, l:module.short_name)
    endif
  endfor
  
  " Add update success message
  let l:update_lines += ['', plugin_manager#ui#success('Update completed successfully.')]
  call plugin_manager#ui#update_sidebar(l:update_lines, 1)
  
  " Generate helptags only for updated modules
  call plugin_manager#ui#update_sidebar(['', plugin_manager#ui#info('Generating helptags for updated plugins:')], 1)
  let l:helptags_generated = 0
  let l:generated_plugins = []
  let l:module_count = 0
  
  for l:module in a:updated_modules
    let l:module_count += 1
    call plugin_manager#ui#update_task(l:task_id, l:module_count, 'Generating helptags for ' . l:module.short_name)
    
    let l:plugin_path = l:module.path
    let l:docPath = l:plugin_path . '/doc'
    if isdirectory(l:docPath)
      execute 'helptags ' . l:docPath
      let l:helptags_generated = 1
      call add(l:generated_plugins, "Generated helptags for " . l:module.short_name)
    endif
  endfor
  
  let l:helptags_result = l:helptags_generated 
        \ ? l:generated_plugins + [plugin_manager#ui#success("Helptags generation completed.")]
        \ : [plugin_manager#ui#info("No documentation directories found in updated plugins.")]
  
  call plugin_manager#ui#update_sidebar(l:helptags_result, 1)
  call plugin_manager#ui#complete_task(l:task_id, 1, "Update process completed successfully!")
endfunction