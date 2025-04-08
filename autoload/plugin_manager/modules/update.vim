" autoload/plugin_manager/modules/update.vim - Functions for updating plugins

" Variable to prevent multiple concurrent updates
let s:update_in_progress = 0

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
  finally 
    " Reset any in-progress flags
    let s:update_in_progress = 0
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