" autoload/plugin_manager/cmd/update.vim - Update command for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3.4

" Update plugins - main command handler
function! plugin_manager#cmd#update#execute(module_name) abort
    try
      if !plugin_manager#core#ensure_vim_directory()
        throw 'PM_ERROR:update:Not in Vim configuration directory'
      endif
      
      let l:header = ['Updating Plugins:', '-----------------', '']
      call plugin_manager#ui#open_sidebar(l:header)
      
      " Check if a specific module was specified or 'all'
      if a:module_name ==# 'all'
        call s:update_all_plugins()
      else
        call s:update_specific_plugin(a:module_name)
      endif
      
      " Generate helptags for updated modules
      call plugin_manager#cmd#helptags#execute(0)
      
      return 1
    catch
      call plugin_manager#core#handle_error(v:exception, "update")
      return 0
    endtry
  endfunction
  
  " Update a specific plugin
  function! s:update_specific_plugin(module_name) abort
    " Find the module
    let l:module_info = plugin_manager#git#find_module(a:module_name)
    if empty(l:module_info)
      throw 'PM_ERROR:update:Module "' . a:module_name . '" not found'
    endif
    
    let l:module = l:module_info.module
    let l:module_path = l:module.path
    let l:module_name = l:module.short_name
    
    call plugin_manager#ui#update_sidebar(['Updating plugin: ' . l:module_name . ' (' . l:module_path . ')...'], 1)
    
    " Check if directory exists
    if !plugin_manager#core#dir_exists(l:module_path)
      throw 'PM_ERROR:update:Module directory "' . l:module_path . '" not found. Try running "PluginManager restore"'
    endif
    
    " Stash local changes if any
    call s:stash_module_changes(l:module_path)
    
    " Check update status
    let l:update_status = plugin_manager#git#check_updates(l:module_path)
    
    " Handle custom branch scenario
    if l:update_status.different_branch && l:update_status.branch != 'detached'
      call s:report_custom_branch(l:module_name, l:update_status)
      return
    endif
    
    " Check if module has updates
    if !l:update_status.has_updates
      call plugin_manager#ui#update_sidebar(['Plugin "' . l:module_name . '" is already up-to-date.'], 1)
      return
    endif
    
    " Update the module
    call plugin_manager#ui#update_sidebar(['Updates available. Updating plugin...'], 1)
    if plugin_manager#git#update_submodule(l:module_path)
      " Record the update in our list
      call s:show_update_details(l:module)
    else
      call plugin_manager#ui#update_sidebar(['Error updating plugin.'], 1)
    endif
  endfunction
  
  " Update all plugins
  function! s:update_all_plugins() abort
    " Parse gitmodules
    let l:modules = plugin_manager#git#parse_modules()
    
    if empty(l:modules)
      throw 'PM_ERROR:update:No plugins to update (.gitmodules not found)'
    endif
    
    call plugin_manager#ui#update_sidebar(['Stashing any local changes in submodules...'], 1)
    call plugin_manager#git#execute('git submodule foreach --recursive "git stash -q || true"', '', 1, 0)
    
    call plugin_manager#ui#update_sidebar(['Fetching updates from remote repositories...'], 1)
    call plugin_manager#git#execute('git submodule foreach --recursive "git fetch origin"', '', 1, 0)
    
    " Find modules that need updates
    let l:modules_with_updates = []
    let l:modules_on_diff_branch = []
    
    call plugin_manager#ui#update_sidebar(['Checking plugins for available updates...'], 1)
    call s:analyze_modules_status(l:modules, l:modules_with_updates, l:modules_on_diff_branch)
    
    " Report on modules with custom branches
    if !empty(l:modules_on_diff_branch)
      call s:report_custom_branches(l:modules_on_diff_branch)
    endif
    
    " Update modules if needed
    if empty(l:modules_with_updates)
      call plugin_manager#ui#update_sidebar(['All plugins are up-to-date.'], 1)
    else
      call plugin_manager#ui#update_sidebar(['Found ' . len(l:modules_with_updates) . ' plugins with updates. Updating...'], 1)
      
      " Execute update command
      call plugin_manager#git#execute('git submodule sync', '', 1, 0)
      call plugin_manager#git#execute('git submodule update --remote --merge --force', '', 1, 1)
      
      " Check if commit is needed
      let l:status = plugin_manager#git#execute('git status -s', '', 0, 0)
      if !empty(l:status.output)
        call plugin_manager#git#execute('git commit -am "Update Modules"', '', 1, 0)
      endif
      
      " Show what was updated
      call s:show_update_summary(l:modules_with_updates)
    endif
  endfunction
  
  " Helper function to stash changes in a single module
  function! s:stash_module_changes(module_path) abort
    call plugin_manager#ui#update_sidebar(['Checking for local changes...'], 1)
    
    let l:status = plugin_manager#git#execute('git status -s', a:module_path, 0, 0)
    if !empty(l:status.output)
      call plugin_manager#ui#update_sidebar(['Stashing local changes...'], 1)
      call plugin_manager#git#execute('git stash -q || true', a:module_path, 0, 0)
    else
      call plugin_manager#ui#update_sidebar(['No local changes to stash.'], 1)
    endif
  endfunction
  
  " Helper function to analyze update status of all modules
  function! s:analyze_modules_status(modules, modules_with_updates, modules_on_diff_branch) abort
    for [l:name, l:module] in items(a:modules)
      if l:module.is_valid && plugin_manager#core#dir_exists(l:module.path)
        " Check update status
        let l:update_status = plugin_manager#git#check_updates(l:module.path)
        
        " If module is on a different branch, add to special list
        if l:update_status.different_branch && l:update_status.branch != 'detached'
          call add(a:modules_on_diff_branch, {'module': l:module, 'status': l:update_status})
        " If module has updates, add to update list
        elseif l:update_status.has_updates
          call add(a:modules_with_updates, l:module)
        endif
      endif
    endfor
  endfunction
  
  " Helper function to report on custom branches
  function! s:report_custom_branches(modules_on_diff_branch) abort
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
  function! s:report_custom_branch(module_name, update_status) abort
    call plugin_manager#ui#update_sidebar([
          \ 'Plugin "' . a:module_name . '" is on a custom branch:', 
          \ '- Local branch: ' . a:update_status.branch,
          \ '- Target branch: ' . a:update_status.remote_branch,
          \ 'To preserve your branch choice, the plugin will not be updated automatically.',
          \ 'To update anyway, run: git submodule update --remote --force -- "[path]"'
          \ ], 1)
  endfunction
  
  " Helper function to show update details for a single module
  function! s:show_update_details(module) abort
    let l:log = plugin_manager#git#execute('git log -1 --format="%h %s"', a:module.path, 0, 0)
    if l:log.success && !empty(l:log.output)
      let l:commit_info = substitute(l:log.output, '\n', '', 'g')
      call plugin_manager#ui#update_sidebar(['Updated ' . a:module.short_name . ' to: ' . l:commit_info], 1)
    else
      call plugin_manager#ui#update_sidebar(['Updated ' . a:module.short_name . ' successfully.'], 1)
    endif
  endfunction
  
  " Helper function to show update summary for multiple modules
  function! s:show_update_summary(updated_modules) abort
    let l:update_lines = ['', 'Updated plugins:']
    
    for l:module in a:updated_modules
      let l:log = plugin_manager#git#execute('git log -1 --format="%h %s"', l:module.path, 0, 0)
      if l:log.success && !empty(l:log.output)
        let l:commit_info = substitute(l:log.output, '\n', '', 'g')
        call add(l:update_lines, l:module.short_name . ': ' . l:commit_info)
      else
        call add(l:update_lines, l:module.short_name)
      endif
    endfor
    
    call add(l:update_lines, '', 'Update completed successfully.')
    call plugin_manager#ui#update_sidebar(l:update_lines, 1)
  endfunction