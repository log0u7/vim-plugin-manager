" autoload/plugin_manager/modules/remove.vim - Functions for removing plugins

" Handle 'remove' command
function! plugin_manager#modules#remove#plugin(...)
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