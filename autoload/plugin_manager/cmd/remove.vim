" autoload/plugin_manager/cmd/remove.vim - Remove command for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: refacto2 v1.3.3 d4f8fda

" Execute the remove command
function! plugin_manager#cmd#remove#execute(module_name, force_flag) abort
    try
      if !plugin_manager#core#ensure_vim_directory()
        throw 'PM_ERROR:remove:Not in Vim configuration directory'
      endif
      
      if empty(a:module_name)
        throw 'PM_ERROR:remove:Missing plugin name argument'
      endif
      
      " Find the module
      let l:module_info = plugin_manager#git#find_module(a:module_name)
      
      if empty(l:module_info)
        " Try to find it in the file system as a fallback
        let l:dir_found = s:find_module_directory(a:module_name)
        
        if empty(l:dir_found)
          throw 'PM_ERROR:remove:Module "' . a:module_name . '" not found'
        endif
        
        let l:module_path = l:dir_found.path
        let l:module_name = l:dir_found.name
      else
        let l:module_path = l:module_info.module.path
        let l:module_name = l:module_info.module.short_name
      endif
      
      " Force flag provided or prompt for confirmation
      let l:force_flag = a:force_flag ==# '-f'
      if l:force_flag || s:confirm_removal(l:module_name, l:module_path)
        call s:remove_module(l:module_name, l:module_path)
      endif
      
      return 1
    catch
      call plugin_manager#core#handle_error(v:exception, "remove")
      return 0
    endtry
  endfunction
  
  " Try to find a module directory without using .gitmodules
  function! s:find_module_directory(name) abort
    let l:start_dir = plugin_manager#core#get_plugin_dir('start')
    let l:opt_dir = plugin_manager#core#get_plugin_dir('opt')
    
    " Try to find in start directory
    if plugin_manager#core#dir_exists(l:start_dir)
      let l:potential_path = l:start_dir . '/' . a:name
      if plugin_manager#core#dir_exists(l:potential_path)
        return {'path': l:potential_path, 'name': a:name}
      endif
      
      " Try with more fuzzy matching
      let l:find_cmd = 'find ' . shellescape(l:start_dir) . ' -type d -name "*' . a:name . '*" -maxdepth 1 | head -n1'
      let l:result = plugin_manager#git#execute(l:find_cmd, '', 0, 0)
      if l:result.success && !empty(l:result.output)
        let l:found_path = substitute(l:result.output, '\n$', '', '')
        if plugin_manager#core#dir_exists(l:found_path)
          return {'path': l:found_path, 'name': fnamemodify(l:found_path, ':t')}
        endif
      endif
    endif
    
    " Try to find in opt directory
    if plugin_manager#core#dir_exists(l:opt_dir)
      let l:potential_path = l:opt_dir . '/' . a:name
      if plugin_manager#core#dir_exists(l:potential_path)
        return {'path': l:potential_path, 'name': a:name}
      endif
      
      " Try with more fuzzy matching
      let l:find_cmd = 'find ' . shellescape(l:opt_dir) . ' -type d -name "*' . a:name . '*" -maxdepth 1 | head -n1'
      let l:result = plugin_manager#git#execute(l:find_cmd, '', 0, 0)
      if l:result.success && !empty(l:result.output)
        let l:found_path = substitute(l:result.output, '\n$', '', '')
        if plugin_manager#core#dir_exists(l:found_path)
          return {'path': l:found_path, 'name': fnamemodify(l:found_path, ':t')}
        endif
      endif
    endif
    
    " Not found
    return {}
  endfunction
  
  " Confirm module removal with user
  function! s:confirm_removal(module_name, module_path) abort
    let l:response = input("Are you sure you want to remove " . a:module_name . " (" . a:module_path . ")? [y/N] ")
    return l:response =~? '^y\(es\)\?$'
  endfunction
  
  " Remove a module
  function! s:remove_module(module_name, module_path) abort
    let l:header = ['Remove Plugin:', '-------------', '', 'Removing ' . a:module_name . ' from ' . a:module_path . '...']
    call plugin_manager#ui#open_sidebar(l:header)
    
    " Back up module information before removing it
    let l:module_info = s:get_module_info(a:module_path)
    
    " Step 1: Deinitialize the submodule
    call plugin_manager#ui#update_sidebar(['Deinitializing submodule...'], 1)
    let l:result = plugin_manager#git#execute('git submodule deinit -f ' . shellescape(a:module_path), '', 0, 0)
    let l:deinit_success = l:result.success
    
    if !l:deinit_success
      call plugin_manager#ui#update_sidebar(['Warning during deinitializing submodule (continuing anyway):', l:result.output], 1)
    else
      call plugin_manager#ui#update_sidebar(['Deinitialized submodule successfully.'], 1)
    endif
    
    " Step 2: Remove from git
    call plugin_manager#ui#update_sidebar(['Removing repository...'], 1)
    let l:result = plugin_manager#git#execute('git rm -f ' . shellescape(a:module_path), '', 0, 0)
    
    if !l:result.success
      call plugin_manager#ui#update_sidebar(['Error removing repository from git, trying alternative method...'], 1)
      call plugin_manager#core#remove_path(a:module_path)
      call plugin_manager#ui#update_sidebar(['Directory removed manually. You may need to edit .gitmodules manually.'], 1)
    else
      call plugin_manager#ui#update_sidebar(['Repository removed successfully from git.'], 1)
    endif
    
    " Step 3: Clean .git/modules directory
    call s:clean_git_modules(a:module_path)
    
    " Step 4: Commit changes
    call s:commit_removal(a:module_name, l:module_info)
    
    " Force refresh the cache after removal
    call plugin_manager#git#refresh_modules_cache()
    
    call plugin_manager#ui#update_sidebar(['Plugin removal completed.'], 1)
  endfunction
  
  " Helper to get module info
  function! s:get_module_info(module_path) abort
    let l:modules = plugin_manager#git#parse_modules()
    let l:module_info = {}
    
    for [l:name, l:module] in items(l:modules)
      if has_key(l:module, 'path') && l:module.path ==# a:module_path
        let l:module_info = l:module
        call plugin_manager#ui#update_sidebar([
              \ 'Found module information:',
              \ '- Name: ' . l:name,
              \ '- URL: ' . l:module.url
              \ ], 1)
        break
      endif
    endfor
    
    return l:module_info
  endfunction
  
  " Helper to clean .git/modules directory
  function! s:clean_git_modules(module_path) abort
    call plugin_manager#ui#update_sidebar(['Cleaning .git modules...'], 1)
    
    if plugin_manager#core#dir_exists('.git/modules/' . a:module_path)
      call plugin_manager#core#remove_path('.git/modules/' . a:module_path)
      call plugin_manager#ui#update_sidebar(['Git modules cleaned successfully.'], 1)
    else
      call plugin_manager#ui#update_sidebar(['No module directory to clean in .git/modules.'], 1)
    endif
  endfunction
  
  " Helper to commit removal
  function! s:commit_removal(module_name, module_info) abort
    call plugin_manager#ui#update_sidebar(['Committing changes...'], 1)
    
    " Create a commit message with module info if available
    let l:commit_msg = "Removed " . a:module_name . " module"
    if !empty(a:module_info) && has_key(a:module_info, 'url')
      let l:commit_msg .= " (" . a:module_info.url . ")"
    endif
    
    let l:result = plugin_manager#git#execute('git add -A && git commit -m ' . shellescape(l:commit_msg) . 
          \ ' || git commit --allow-empty -m ' . shellescape(l:commit_msg), '', 0, 0)
    
    if !l:result.success
      call plugin_manager#ui#update_sidebar(['Warning during commit (plugin still removed):', l:result.output], 1)
    else
      call plugin_manager#ui#update_sidebar(['Changes committed successfully.'], 1)
    endif
  endfunction