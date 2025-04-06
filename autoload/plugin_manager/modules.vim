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

" Improved status function with non-blocking operation
function! plugin_manager#modules#status()
    if !plugin_manager#utils#ensure_vim_directory()
      return
    endif
    
    " Display initial UI immediately - don't block
    let l:header = 'Submodule Status:'
    let l:lines = [l:header, repeat('-', len(l:header)), '', 'Initializing...']
    call plugin_manager#ui#open_sidebar(l:lines)
    
    " Schedule the loading of gitmodules to happen asynchronously
    function! s:load_modules_async(timer)
      " Use the gitmodules cache
      let l:modules = plugin_manager#utils#parse_gitmodules()
      
      if empty(l:modules)
        call plugin_manager#ui#open_sidebar([l:header, repeat('-', len(l:header)), '', 'No submodules found (.gitmodules not found)'])
        return
      endif
      
      " Update UI with table header
      let l:lines = [l:header, repeat('-', len(l:header)), '']
      call add(l:lines, 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 8).'Last Updated'.repeat(' ', 18).'Status')
      call add(l:lines, repeat('-', 120))
      call plugin_manager#ui#update_sidebar(l:lines, 0)
      
      " Start fetching updates asynchronously
      let l:callbacks = {
            \ 'name': 'Fetching repository updates',
            \ 'on_exit': function('s:fetch_completed', [l:modules, l:header])
            \ }
      
      call plugin_manager#jobs#start('git submodule foreach --recursive "git fetch -q origin 2>/dev/null || true"', l:callbacks)
    endfunction
    
    " Callback after fetch completes
    function! s:fetch_completed(modules, header, status, output)
      call plugin_manager#ui#update_sidebar(['Modules found: ' . len(a:modules) . ', processing status...'], 1)
      
      " Sort modules by name for consistent display
      let l:module_names = sort(keys(a:modules))
      
      " Use timer to avoid UI freeze
      let s:processed_modules = []
      let s:pending_modules = l:module_names
      let s:modules_data = a:modules
      let s:status_lines = []
      let s:header = a:header
      
      " Start processing modules in small batches
      call timer_start(10, function('s:process_module_batch'))
    endfunction
    
    " Process modules in batches to avoid UI freeze
    function! s:process_module_batch(timer)
      " Take up to 3 modules at a time to process
      let l:batch = []
      let l:count = 0
      while l:count < 3 && !empty(s:pending_modules)
        let l:module_name = remove(s:pending_modules, 0)
        call add(l:batch, l:module_name)
        let l:count += 1
      endwhile
      
      " Process this batch
      for l:name in l:batch
        let l:module = s:modules_data[l:name]
        if has_key(l:module, 'is_valid') && l:module.is_valid
          let l:status_line = s:format_module_status(l:module)
          if !empty(l:status_line)
            call add(s:status_lines, l:status_line)
          endif
        endif
      endfor
      
      " Update UI with progress
      let l:progress = (len(s:modules_data) - len(s:pending_modules)) * 100 / len(s:modules_data)
      call plugin_manager#ui#show_progress_bar(l:progress, 'Processing module status: ' . len(s:pending_modules) . ' remaining')
      
      " If more modules to process, schedule another batch
      if !empty(s:pending_modules)
        call timer_start(10, function('s:process_module_batch'))
      else
        " All done, show final result
        let l:final_lines = [s:header, repeat('-', len(s:header)), '']
        call add(l:final_lines, 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 8).'Last Updated'.repeat(' ', 18).'Status')
        call add(l:final_lines, repeat('-', 120))
        
        " Sort status lines for consistent display
        call sort(s:status_lines)
        call extend(l:final_lines, s:status_lines)
        
        call plugin_manager#ui#open_sidebar(l:final_lines)
        
        " Clear job progress section when done
        call timer_start(1000, {-> plugin_manager#ui#clear_job_progress()})
      endif
    endfunction
    
    " Format module status line
    function! s:format_module_status(module)
      let l:short_name = a:module.short_name
      
      " Initialize status to 'OK' by default
      let l:status = 'OK'
      
      " Initialize other information as N/A in case checks fail
      let l:commit = 'N/A'
      let l:branch = 'N/A'
      let l:last_updated = 'N/A'
      
      " Check if module exists
      if !isdirectory(a:module.path)
        let l:status = 'MISSING'
      else
        " Continue with all checks for existing modules
        
        " Get current commit
        let l:commit = system('cd "' . a:module.path . '" && git rev-parse --short HEAD 2>/dev/null || echo "N/A"')
        let l:commit = substitute(l:commit, '\n', '', 'g')
        
        " Get current branch
        let l:branch = system('cd "' . a:module.path . '" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A"')
        let l:branch = substitute(l:branch, '\n', '', 'g')
        
        " Get last commit date
        let l:last_updated = system('cd "' . a:module.path . '" && git log -1 --format=%cd --date=relative 2>/dev/null || echo "N/A"')
        let l:last_updated = substitute(l:last_updated, '\n', '', 'g')
        
        " Use the utility function to check for updates
        let l:update_status = plugin_manager#utils#check_module_updates(a:module.path)
        
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
      
      return l:name_col . l:commit_col . l:branch_col . l:date_col . l:status
    endfunction
    
    " Start the asynchronous process
    call timer_start(10, function('s:load_modules_async'))
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
    
    " Run summary command asynchronously if supported
    if plugin_manager#jobs#is_async_supported()
      let l:callbacks = {
            \ 'name': 'Generating module summary',
            \ 'on_stdout': function('s:handle_summary_output', [l:header])
            \ }
      call plugin_manager#jobs#start('git submodule summary', l:callbacks)
    else
      let l:output = system('git submodule summary')
      let l:lines = [l:header, repeat('-', len(l:header)), '']
      call extend(l:lines, split(l:output, "\n"))
      call plugin_manager#ui#open_sidebar(l:lines)
    endif
endfunction

function! s:handle_summary_output(header, output)
  let l:lines = [a:header, repeat('-', len(a:header)), '']
  call extend(l:lines, split(a:output, "\n"))
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

" Generate helptags asynchronously
function! s:generate_helptag_async(pluginPath)
  let l:docPath = a:pluginPath . '/doc'
  if !isdirectory(l:docPath)
    call plugin_manager#ui#update_sidebar(['No documentation directory found.'], 1)
    return
  endif
  
  " Callback for helptags generation
  function! s:helptags_callback(status, output) closure
    if a:status == 0
      call plugin_manager#ui#update_sidebar(['Helptags generated successfully.'], 1)
    else
      call plugin_manager#ui#update_sidebar(['Error generating helptags: ' . a:output], 1)
    endif
  endfunction
  
  " Use job system for helptags generation
  let l:cmd = 'vim -c "helptags ' . l:docPath . '" -c q'
  let l:callbacks = {
        \ 'name': 'Generating helptags',
        \ 'on_exit': function('s:helptags_callback')
        \ }
  
  call plugin_manager#jobs#start(l:cmd, l:callbacks)
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

" Update plugins with truly non-blocking operation
function! plugin_manager#modules#update(...)
  " Display initial UI immediately
  let l:title = 'Updating Plugins:'
  let l:header = [l:title, repeat('-', len(l:title)), '']
  
  " Check if a specific module was specified
  let l:specific_module = a:0 > 0 ? a:1 : 'all'
  
  " Initialize UI right away 
  let l:initial_message = l:header
  if l:specific_module == 'all'
    call add(l:initial_message, 'Initializing plugin update...')
  else
    call add(l:initial_message, 'Initializing update for plugin: ' . l:specific_module)
  endif
  call plugin_manager#ui#open_sidebar(l:initial_message)
  
  " Schedule directory check and continuation
  function! s:start_update_process(timer)
    " Prevent multiple concurrent update calls if not async
    if exists('s:update_in_progress') && s:update_in_progress && !plugin_manager#jobs#is_async_supported()
      call plugin_manager#ui#update_sidebar(['Update already in progress. Please wait...'], 1)
      return
    endif
    let s:update_in_progress = 1
    
    if !plugin_manager#utils#ensure_vim_directory()
      let s:update_in_progress = 0
      return
    endif
    
    " Continue with async checks of gitmodules
    call s:check_gitmodules()
  endfunction
  
  " Function to check gitmodules asynchronously 
  function! s:check_gitmodules()
    " Schedule reading of .gitmodules
    function! s:on_gitmodules_read(modules)
      if empty(a:modules)
        call plugin_manager#ui#update_sidebar(['No plugins to update (.gitmodules not found)'], 1)
        let s:update_in_progress = 0
        return
      endif
      
      " Store modules globally for update process
      let s:update_modules = a:modules
      
      " Continue with specific or full update
      if l:specific_module == 'all'
        call s:prepare_full_update()
      else
        call s:prepare_single_update(l:specific_module)
      endif
    endfunction
    
    " Read gitmodules asynchronously
    call plugin_manager#utils#parse_gitmodules_async(function('s:on_gitmodules_read'))
  endfunction
  
  " Prepare for updating all plugins
  function! s:prepare_full_update()
    call plugin_manager#ui#update_sidebar(['Checking plugins for updates...'], 1)
    
    " Create command sequence
    let l:commands = []
    
    " 1. First prepare by removing helptags
    call add(l:commands, {
          \ 'cmd': 'git submodule foreach --recursive "rm -f doc/tags doc/*/tags */tags 2>/dev/null || true"',
          \ 'name': 'Preparing modules'
          \ })
    
    " Schedule checking for local changes
    call timer_start(10, function('s:check_local_changes'))
  endfunction
  
  " Check for local changes in batches
  function! s:check_local_changes(timer)
    let l:any_changes = 0
    
    " Process modules in smaller batches to avoid freezing
    let s:batch_size = 5
    let s:modules_to_check = keys(s:update_modules)
    let s:checked_modules = 0
    let s:modules_count = len(s:modules_to_check)
    
    " Start checking in batches
    call timer_start(10, function('s:check_changes_batch'))
  endfunction
  
  " Check changes in a batch of modules
  function! s:check_changes_batch(timer)
    let l:any_changes = 0
    let l:batch = []
    
    " Take a batch of modules
    while len(l:batch) < s:batch_size && !empty(s:modules_to_check)
      call add(l:batch, remove(s:modules_to_check, 0))
    endwhile
    
    " Check each module in this batch
    for l:name in l:batch
      let l:module = s:update_modules[l:name]
      if l:module.is_valid && isdirectory(l:module.path)
        let l:changes = system('cd "' . l:module.path . '" && git status -s 2>/dev/null')
        if !empty(l:changes)
          let l:any_changes = 1
        endif
      endif
      
      let s:checked_modules += 1
    endfor
    
    " Update progress
    let l:progress = s:checked_modules * 100 / s:modules_count
    call plugin_manager#ui#show_progress_bar(l:progress, 'Checking for local changes: ' . s:checked_modules . '/' . s:modules_count)
    
    " Store if we found changes
    if l:any_changes
      let s:has_local_changes = 1
    endif
    
    " Continue with more batches or move to next step
    if !empty(s:modules_to_check)
      call timer_start(10, function('s:check_changes_batch'))
    else
      " All modules checked, continue process
      call timer_start(10, function('s:continue_update_process'))
    endif
  endfunction
  
  " Continue update process after checking changes
  function! s:continue_update_process(timer)
    " Create command sequence
    let l:commands = []
    
    " 1. First prepare by removing helptags (if not already done)
    call add(l:commands, {
          \ 'cmd': 'git submodule foreach --recursive "rm -f doc/tags doc/*/tags */tags 2>/dev/null || true"',
          \ 'name': 'Preparing modules'
          \ })
    
    " 2. Stash any local changes if needed
    if exists('s:has_local_changes') && s:has_local_changes
      call plugin_manager#ui#update_sidebar(['Stashing local changes in submodules...'], 1)
      call add(l:commands, {
            \ 'cmd': 'git submodule foreach --recursive "git stash -q || true"',
            \ 'name': 'Stashing local changes'
            \ })
    else
      call plugin_manager#ui#update_sidebar(['No local changes to stash...'], 1)
    endif
    
    " 3. Fetch updates without applying them yet
    call add(l:commands, {
          \ 'cmd': 'git submodule foreach --recursive "git fetch origin"',
          \ 'name': 'Fetching updates'
          \ })
    
    " Add callback for when fetch completes
    function! s:on_fetch_complete(results)
      call plugin_manager#ui#update_sidebar(['Update information fetched, checking modules...'], 1)
      
      " Process modules in batches to determine which need updates
      let s:modules_with_updates = []
      let s:modules_on_diff_branch = []
      let s:modules_to_process = keys(s:update_modules)
      let s:processed_count = 0
      
      call timer_start(10, function('s:check_updates_batch'))
    endfunction
    
    " Run the fetch commands and continue process
    call plugin_manager#jobs#run_sequence(l:commands, function('s:on_fetch_complete'))
  endfunction
  
  " Check for updates in batches
  function! s:check_updates_batch(timer)
    let l:batch = []
    let l:batch_size = 3 " Process a few modules at a time
    
    " Take a batch of modules
    while len(l:batch) < l:batch_size && !empty(s:modules_to_process)
      call add(l:batch, remove(s:modules_to_process, 0))
    endwhile
    
    " Check each module in this batch
    for l:name in l:batch
      let l:module = s:update_modules[l:name]
      if l:module.is_valid && isdirectory(l:module.path)
        " Check for updates
        let l:update_status = plugin_manager#utils#check_module_updates(l:module.path)
        
        " Record module status
        let l:module.update_status = l:update_status
        
        " If module is on a different branch and not in detached HEAD, add to special list
        if l:update_status.different_branch && l:update_status.branch != "detached"
          call add(s:modules_on_diff_branch, {'module': l:module, 'status': l:update_status})
        " If module has updates, add to update list
        elseif l:update_status.has_updates
          call add(s:modules_with_updates, l:module)
        endif
      endif
      
      let s:processed_count += 1
    endfor
    
    " Update progress
    let l:progress = s:processed_count * 100 / len(s:update_modules)
    call plugin_manager#ui#show_progress_bar(l:progress, 'Checking for updates: ' . s:processed_count . '/' . len(s:update_modules))
    
    " Continue with more batches or finalize
    if !empty(s:modules_to_process)
      call timer_start(10, function('s:check_updates_batch'))
    else
      " All modules checked, finalize update process
      call timer_start(10, function('s:finalize_update_process'))
    endif
  endfunction
  
  " Finalize update process
  function! s:finalize_update_process(timer)
    " Report on modules with custom branches
    if !empty(s:modules_on_diff_branch)
      let l:branch_lines = ['', 'The following plugins are on custom branches:']
      for l:item in s:modules_on_diff_branch
        call add(l:branch_lines, '- ' . l:item.module.short_name . 
              \ ' (local: ' . l:item.status.branch . 
              \ ', target: ' . l:item.status.remote_branch . ')')
      endfor
      call add(l:branch_lines, 'These plugins will not be updated automatically to preserve your branch choice.')
      call plugin_manager#ui#update_sidebar(l:branch_lines, 1)
    endif
    
    " Check if updates needed
    if empty(s:modules_with_updates)
      call plugin_manager#ui#update_sidebar(['All plugins are up-to-date.'], 1)
      let s:update_in_progress = 0
      return
    endif
    
    call plugin_manager#ui#update_sidebar(['Found ' . len(s:modules_with_updates) . ' plugins with updates available. Updating...'], 1)
    
    " Create final update commands
    let l:update_commands = []
    
    " Update command
    call add(l:update_commands, {
          \ 'cmd': 'git submodule sync && git submodule update --remote --merge --force',
          \ 'name': 'Updating plugins'
          \ })
    
    " Commit changes if needed
    call add(l:update_commands, {
          \ 'cmd': 'git diff --quiet || git commit -am "Update Modules"',
          \ 'name': 'Committing changes'
          \ })
    
    " Final callback to handle completion
    function! s:handle_update_completed(results)
      let l:modules_updated = 0
      let l:update_lines = ['', 'Update completed:']
      
      for l:result in a:results
        if l:result.status == 0
          let l:modules_updated += 1
          call add(l:update_lines, '✓ ' . l:result.name)
        else
          call add(l:update_lines, '✗ ' . l:result.name . ' (error)')
        endif
      endfor
      
      if l:modules_updated > 0
        call add(l:update_lines, '')
        call add(l:update_lines, len(s:modules_with_updates) . ' plugins updated successfully.')
        
        " Generate helptags for updated plugins asynchronously
        call add(l:update_lines, '')
        call add(l:update_lines, 'Generating helptags for updated plugins...')
        call plugin_manager#ui#update_sidebar(l:update_lines, 1)
        
        " Force refresh the cache after updates
        call plugin_manager#utils#refresh_modules_cache()
        
        " Generate helptags for updated modules
        call s:generate_helptags_for_modules(s:modules_with_updates)
      else
        call add(l:update_lines, '')
        call add(l:update_lines, 'No plugins were updated.')
        call plugin_manager#ui#update_sidebar(l:update_lines, 1)
      endif
      
      " Reset update in progress flag
      let s:update_in_progress = 0
      
      " Clear job progress section when done
      call timer_start(3000, {-> plugin_manager#ui#clear_job_progress()})
    endfunction
    
    " Run the update commands
    call plugin_manager#jobs#run_sequence(l:update_commands, function('s:handle_update_completed'))
  endfunction
  
  " Prepare for updating a single module
  function! s:prepare_single_update(module_name)
    " Find the module
    let l:module_info = {}
    
    " Check if the module exists in our cache
    for [l:name, l:module] in items(s:update_modules)
      " Try to match on short_name or path containing the module name
      if has_key(l:module, 'short_name') && l:module.short_name =~? a:module_name
            \ || has_key(l:module, 'path') && l:module.path =~? a:module_name
        let l:module_info = {'name': l:name, 'module': l:module}
        break
      endif
    endfor
    
    if empty(l:module_info)
      call plugin_manager#ui#update_sidebar(['Error: Module "' . a:module_name . '" not found.'], 1)
      let s:update_in_progress = 0
      return
    endif
    
    let l:module = l:module_info.module
    let l:module_path = l:module.path
    let l:module_name = l:module.short_name
    
    " Check if directory exists
    if !isdirectory(l:module_path)
      call plugin_manager#ui#update_sidebar(['Error: Module directory "' . l:module_path . '" not found.', 
            \ 'Try running "PluginManager restore" to reinstall missing modules.'], 1)
      let s:update_in_progress = 0
      return
    endif
    
    call plugin_manager#ui#update_sidebar(['Checking status of plugin: ' . l:module_name . '...'], 1)
    
    " Create command sequence for a single module
    let l:commands = []
    
    " 1. Prepare by removing helptags
    call add(l:commands, {
          \ 'cmd': 'cd "' . l:module_path . '" && rm -f doc/tags doc/*/tags */tags 2>/dev/null || true',
          \ 'name': 'Preparing ' . l:module_name
          \ })
    
    " 2. Check if there are any local changes
    let l:changes = system('cd "' . l:module_path . '" && git status -s 2>/dev/null')
    if !empty(l:changes)
      call add(l:commands, {
            \ 'cmd': 'cd "' . l:module_path . '" && git stash -q || true',
            \ 'name': 'Stashing local changes for ' . l:module_name
            \ })
    endif
    
    " 3. Fetch updates without applying
    call add(l:commands, {
          \ 'cmd': 'cd "' . l:module_path . '" && git fetch origin',
          \ 'name': 'Fetching updates for ' . l:module_name
          \ })
    
    " After fetch completes, check status
    function! s:check_single_module_status(results)
      " Check if module needs update
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
        let s:update_in_progress = 0
        return
      endif
      
      call plugin_manager#ui#update_sidebar(['Updates available for plugin "' . l:module_name . '". Updating...'], 1)
      
      " Create update commands
      let l:update_commands = []
      
      " Update this module
      call add(l:update_commands, {
            \ 'cmd': 'git submodule sync -- "' . l:module_path . '" && git submodule update --remote --merge --force -- "' . l:module_path . '"',
            \ 'name': 'Updating ' . l:module_name
            \ })
      
      " Commit changes if needed
      call add(l:update_commands, {
            \ 'cmd': 'git diff --quiet || git commit -am "Update Module: ' . l:module_name . '"',
            \ 'name': 'Committing changes for ' . l:module_name
            \ })
      
      " Final callback for single module update
      function! s:handle_single_update_completed(results)
        let l:success = 0
        let l:update_lines = ['', 'Update results:']
        
        for l:result in a:results
          if l:result.status == 0
            call add(l:update_lines, '✓ ' . l:result.name . ' succeeded')
            if l:result.name =~ '^Updating'
              let l:success = 1
            endif
          else
            call add(l:update_lines, '✗ ' . l:result.name . ' failed')
          endif
        endfor
        
        if l:success
          call add(l:update_lines, '')
          call add(l:update_lines, 'Plugin "' . l:module_name . '" updated successfully.')
          call add(l:update_lines, '')
          call add(l:update_lines, 'Generating helptags...')
          call plugin_manager#ui#update_sidebar(l:update_lines, 1)
          
          " Force refresh the cache after updates
          call plugin_manager#utils#refresh_modules_cache()
          
          " Generate helptags
          call s:generate_helptag_async(l:module_path)
        else
          call add(l:update_lines, '')
          call add(l:update_lines, 'Plugin update failed. See errors above.')
          call plugin_manager#ui#update_sidebar(l:update_lines, 1)
        endif
        
        " Reset update in progress flag
        let s:update_in_progress = 0
        
        " Clear job progress section when done
        call timer_start(3000, {-> plugin_manager#ui#clear_job_progress()})
      endfunction
      
      " Run update commands
      call plugin_manager#jobs#run_sequence(l:update_commands, function('s:handle_single_update_completed'))
    endfunction
    
    " Run the initial commands and continue
    call plugin_manager#jobs#run_sequence(l:commands, function('s:check_single_module_status'))
  endfunction
  
  " Generate helptags asynchronously
  function! s:generate_helptag_async(pluginPath)
    let l:docPath = a:pluginPath . '/doc'
    if !isdirectory(l:docPath)
      call plugin_manager#ui#update_sidebar(['No documentation directory found.'], 1)
      return
    endif
    
    " Callback for helptags generation
    function! s:helptags_callback(status, output) closure
      if a:status == 0
        call plugin_manager#ui#update_sidebar(['Helptags generated successfully.'], 1)
      else
        call plugin_manager#ui#update_sidebar(['Error generating helptags: ' . a:output], 1)
      endif
    endfunction
    
    " Use job system for helptags generation
    let l:cmd = 'vim -c "helptags ' . l:docPath . '" -c q'
    let l:callbacks = {
          \ 'name': 'Generating helptags',
          \ 'on_exit': function('s:helptags_callback')
          \ }
    
    call plugin_manager#jobs#start(l:cmd, l:callbacks)
  endfunction
  
  " Generate helptags for multiple modules
  function! s:generate_helptags_for_modules(modules)
    let s:modules_for_helptags = copy(a:modules)
    let s:helptags_generated = 0
    let s:helptags_total = len(s:modules_for_helptags)
    let s:helptags_processed = 0
    
    " Process helptags in batches
    call timer_start(100, function('s:process_helptags_batch'))
  endfunction
  
  " Process a batch of helptags
  function! s:process_helptags_batch(timer)
    let l:batch_size = 3
    let l:count = 0
    let l:processed_this_batch = 0
    
    while l:count < l:batch_size && !empty(s:modules_for_helptags)
      let l:module = remove(s:modules_for_helptags, 0)
      let l:plugin_path = l:module.path
      let l:docPath = l:plugin_path . '/doc'
      
      if isdirectory(l:docPath)
        execute 'helptags ' . l:docPath
        let s:helptags_generated += 1
        let l:processed_this_batch += 1
      endif
      
      let s:helptags_processed += 1
      let l:count += 1
    endwhile
    
    " Update progress
    let l:progress = s:helptags_processed * 100 / s:helptags_total
    call plugin_manager#ui#show_progress_bar(l:progress, 'Generating helptags: ' . s:helptags_processed . '/' . s:helptags_total)
    
    " Continue with more or finalize
    if !empty(s:modules_for_helptags)
      call timer_start(100, function('s:process_helptags_batch'))
    else
      " Report results
      let l:helptags_result = []
      if s:helptags_generated > 0
        call add(l:helptags_result, 'Generated helptags for ' . s:helptags_generated . ' plugins.')
        call add(l:helptags_result, 'Helptags generation completed.')
      else
        call add(l:helptags_result, 'No documentation directories found in updated plugins.')
      endif
      
      call plugin_manager#ui#update_sidebar(l:helptags_result, 1)
      
      " Clear progress
      call timer_start(1000, {-> plugin_manager#ui#clear_job_progress()})
    endif
  endfunction
  
  " Start the process with a slight delay to allow UI to render
  call timer_start(10, function('s:start_update_process'))
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
  
  " Create command sequence
  let l:commands = []
  
  " 1. Create the destination directory
  call mkdir(a:installDir, 'p')
  
  " 2. Copy the files, excluding .git directory
  if executable('rsync')
    call add(l:commands, {
          \ 'cmd': 'rsync -a --exclude=".git" ' . shellescape(a:localPath . '/') . ' ' . shellescape(a:installDir . '/'),
          \ 'name': 'Copying plugin files'
          \ })
  elseif has('win32') || has('win64')
    " Windows: try robocopy or xcopy
    if executable('robocopy')
      call add(l:commands, {
            \ 'cmd': 'robocopy ' . shellescape(a:localPath) . ' ' . shellescape(a:installDir) . ' /E /XD .git',
            \ 'name': 'Copying plugin files'
            \ })
    else
      call add(l:commands, {
            \ 'cmd': 'xcopy ' . shellescape(a:localPath) . '\* ' . shellescape(a:installDir) . ' /E /I /Y /EXCLUDE:.git',
            \ 'name': 'Copying plugin files'
            \ })
    endif
  else
    " Unix: use cp with find to exclude .git
    call add(l:commands, {
          \ 'cmd': 'cd ' . shellescape(a:localPath) . ' && find . -type d -name ".git" -prune -o -type f -print | xargs -I{} cp --parents {} ' . shellescape(a:installDir),
          \ 'name': 'Copying plugin files'
          \ })
  endif
  
  " 3. Execute custom command if provided
  if !empty(a:options.exec)
    call add(l:commands, {
          \ 'cmd': 'cd "' . a:installDir . '" && ' . a:options.exec,
          \ 'name': 'Executing custom command'
          \ })
  endif
  
  " Final callback
  function! s:handle_local_add_completed(results) closure
    let l:success = 1
    let l:result_lines = ['Local plugin installation results:']
    
    for l:result in a:results
      if l:result.status != 0
        let l:success = 0
        call add(l:result_lines, '✗ ' . l:result.name . ' failed')
      else
        call add(l:result_lines, '✓ ' . l:result.name . ' completed')
      endif
    endfor
    
    if l:success
      call add(l:result_lines, 'Local plugin installed successfully. Generating helptags...')
    else
      call add(l:result_lines, 'Local plugin installation had errors.')
    endif
    
    call plugin_manager#ui#update_sidebar(l:result_lines, 1)
    
    " Generate helptags asynchronously if successful
    if l:success
      call timer_start(500, {-> s:generate_helptag_async(a:installDir)})
    endif
    
    " Clear job progress section when done
    call timer_start(3000, {-> plugin_manager#ui#clear_job_progress()})
  endfunction
  
  " Run the commands in sequence
  call plugin_manager#jobs#run_sequence(l:commands, function('s:handle_local_add_completed'))
endfunction

" Add a new plugin asynchronously
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
  endif
  
  " Create command sequence
  let l:commands = []
  
  " 1. Add the submodule
  call add(l:commands, {
        \ 'cmd': 'git submodule add "' . a:moduleUrl . '" "' . l:relativeInstallDir . '"',
        \ 'name': 'Adding plugin ' . fnamemodify(l:relativeInstallDir, ':t')
        \ })
  
  " 2. Process branch and tag options if provided
  if !empty(a:options.branch)
    call add(l:commands, {
          \ 'cmd': 'cd "' . l:relativeInstallDir . '" && git checkout ' . a:options.branch,
          \ 'name': 'Checking out branch ' . a:options.branch
          \ })
  elseif !empty(a:options.tag)
    call add(l:commands, {
          \ 'cmd': 'cd "' . l:relativeInstallDir . '" && git checkout ' . a:options.tag,
          \ 'name': 'Checking out tag ' . a:options.tag
          \ })
  endif
  
  " 3. Execute custom command if provided
  if !empty(a:options.exec)
    call add(l:commands, {
          \ 'cmd': 'cd "' . l:relativeInstallDir . '" && ' . a:options.exec,
          \ 'name': 'Executing custom command'
          \ })
  endif
  
  " 4. Commit changes
  " Create a more informative commit message
  let l:commit_msg = "Added " . a:moduleUrl . " module"
  if !empty(a:options.branch)
    let l:commit_msg .= " (branch: " . a:options.branch . ")"
  elseif !empty(a:options.tag)
    let l:commit_msg .= " (tag: " . a:options.tag . ")"
  endif
  
  call add(l:commands, {
        \ 'cmd': 'git commit -m "' . l:commit_msg . '"',
        \ 'name': 'Committing changes'
        \ })
  
  " Final callback to handle completion
  function! s:handle_add_completed(results) closure
    let l:all_succeeded = 1
    let l:result_lines = ['Plugin installation completed:']
    
    for l:result in a:results
      if l:result.status != 0
        let l:all_succeeded = 0
        call add(l:result_lines, '✗ ' . l:result.name . ' failed')
      else
        call add(l:result_lines, '✓ ' . l:result.name . ' succeeded')
      endif
    endfor
    
    if l:all_succeeded
      call add(l:result_lines, '')
      call add(l:result_lines, 'Plugin installed successfully. Generating helptags...')
      call plugin_manager#ui#update_sidebar(l:result_lines, 1)
      
      " Generate helptags asynchronously if doc directory exists
      call timer_start(500, {-> s:generate_helptag_async(a:installDir)})
    else
      call add(l:result_lines, '')
      call add(l:result_lines, 'Plugin installation had errors. See details above.')
      call plugin_manager#ui#update_sidebar(l:result_lines, 1)
    endif
    
    " Force refresh the cache
    call plugin_manager#utils#refresh_modules_cache()
    
    " Clear job progress section when done
    call timer_start(3000, {-> plugin_manager#ui#clear_job_progress()})
  endfunction
  
  " Run the commands in sequence
  call plugin_manager#jobs#run_sequence(l:commands, function('s:handle_add_completed'))
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
  
" Remove an existing plugin asynchronously
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
  
  " If we found the module info, report it
  if !empty(l:module_info)
    call plugin_manager#ui#update_sidebar([
          \ 'Found module information:',
          \ '- Name: ' . l:module_info.name,
          \ '- URL: ' . l:module_info.url
          \ ], 1)
  endif
  
  " Create command sequence
  let l:commands = []
  
  " 1. Deinitialize the submodule
  call add(l:commands, {
        \ 'cmd': 'git submodule deinit -f "' . a:removedPluginPath . '" 2>&1',
        \ 'name': 'Deinitializing ' . a:moduleName,
        \ 'on_stdout': function('s:log_output')
        \ })
  
  " 2. Remove the repository
  call add(l:commands, {
        \ 'cmd': 'git rm -f "' . a:removedPluginPath . '" 2>&1',
        \ 'name': 'Removing repository ' . a:moduleName,
        \ 'on_stdout': function('s:log_output')
        \ })
  
  " 3. Clean .git/modules directory if it exists
  if isdirectory('.git/modules/' . a:removedPluginPath)
    call add(l:commands, {
          \ 'cmd': 'rm -rf ".git/modules/' . a:removedPluginPath . '" 2>&1',
          \ 'name': 'Cleaning git modules',
          \ 'on_stdout': function('s:log_output')
          \ })
  endif
  
  " 4. Commit changes
  let l:commit_msg = "Removed " . a:moduleName . " module"
  if !empty(l:module_info) && has_key(l:module_info, 'url')
    let l:commit_msg .= " (" . l:module_info.url . ")"
  endif
  
  call add(l:commands, {
        \ 'cmd': 'git add -A && git commit -m "' . l:commit_msg . '" || git commit --allow-empty -m "' . l:commit_msg . '" 2>&1',
        \ 'name': 'Committing changes',
        \ 'on_stdout': function('s:log_output')
        \ })
  
  " Log output for job callbacks
  function! s:log_output(output) 
    if !empty(a:output)
      call plugin_manager#ui#update_sidebar(['Output: ' . a:output], 1)
    endif
  endfunction
  
  " Final callback to handle completion
  function! s:handle_remove_completed(results) closure
    let l:any_errors = 0
    let l:result_lines = ['Plugin removal completed:']
    
    for l:result in a:results
      let l:name = get(l:result, 'name', 'Operation')
      if l:result.status != 0
        let l:any_errors = 1
        call add(l:result_lines, '✗ ' . l:name . ' (errors occurred)')
      else
        call add(l:result_lines, '✓ ' . l:name . ' completed successfully')
      endif
    endfor
    
    if l:any_errors
      call add(l:result_lines, '')
      call add(l:result_lines, 'Plugin removal completed with some errors.')
      call add(l:result_lines, 'The plugin may still have been removed successfully.')
    else
      call add(l:result_lines, '')
      call add(l:result_lines, 'Plugin removal completed successfully.')
    endif
    
    call plugin_manager#ui#update_sidebar(l:result_lines, 1)
    
    " Force refresh the cache after removal
    call plugin_manager#utils#refresh_modules_cache()
    
    " Clear job progress section when done
    call timer_start(3000, {-> plugin_manager#ui#clear_job_progress()})
  endfunction
  
  " Run the commands in sequence
  call plugin_manager#jobs#run_sequence(l:commands, function('s:handle_remove_completed'))
endfunction
  
" Backup configuration to remote repositories
function! plugin_manager#modules#backup()
  if !plugin_manager#utils#ensure_vim_directory()
    return
  endif
  
  let l:header = ['Backup Configuration:', '--------------------', '', 'Checking git status...']
  call plugin_manager#ui#open_sidebar(l:header)
  
  " Create command sequence
  let l:commands = []
  
  " 1. Check if vimrc or init.vim exists in the vim directory
  let l:vimrc_basename = fnamemodify(g:plugin_manager_vimrc_path, ':t')
  let l:local_vimrc = g:plugin_manager_vim_dir . '/' . l:vimrc_basename
  
  " If vimrc doesn't exist in the vim directory or isn't a symlink, copy it
  if !filereadable(l:local_vimrc) || (!has('win32') && !has('win64') && getftype(l:local_vimrc) != 'link')
    if filereadable(g:plugin_manager_vimrc_path)
      call plugin_manager#ui#update_sidebar(['Copying ' . l:vimrc_basename . ' file to vim directory for backup...'], 1)
      
      call add(l:commands, {
            \ 'cmd': 'cp "' . g:plugin_manager_vimrc_path . '" "' . l:local_vimrc . '"',
            \ 'name': 'Copying vimrc file'
            \ })
            
      call add(l:commands, {
            \ 'cmd': 'git add "' . l:local_vimrc . '"',
            \ 'name': 'Adding vimrc to git'
            \ })
    else
      call plugin_manager#ui#update_sidebar(['Warning: ' . l:vimrc_basename . ' file not found at ' . g:plugin_manager_vimrc_path], 1)
    endif
  endif
  
  " 2. Commit local changes
  call add(l:commands, {
        \ 'cmd': 'git diff --quiet || git commit -am "Automatic backup"',
        \ 'name': 'Committing local changes'
        \ })
  
  " 3. Check if any remotes exist
  let l:remotesExist = system('git remote')
  if empty(l:remotesExist)
    call plugin_manager#ui#update_sidebar([
          \ 'No remote repositories configured.',
          \ 'Use PluginManagerRemote to add a remote repository.'
          \ ], 1)
    return
  endif
  
  " 4. Push changes to all configured remotes
  call add(l:commands, {
        \ 'cmd': 'git push --all',
        \ 'name': 'Pushing to remote repositories'
        \ })
  
  " Final callback function
  function! s:handle_backup_completed(results) closure
    let l:success = 1
    let l:result_lines = ['Backup results:']
    
    for l:result in a:results
      if l:result.status != 0
        let l:success = 0
        call add(l:result_lines, '✗ ' . l:result.name . ' failed')
      else
        call add(l:result_lines, '✓ ' . l:result.name . ' succeeded')
      endif
    endfor
    
    if l:success
      call add(l:result_lines, '')
      call add(l:result_lines, 'Backup completed successfully.')
    else
      call add(l:result_lines, '')
      call add(l:result_lines, 'Backup completed with errors. See details above.')
    endif
    
    call plugin_manager#ui#update_sidebar(l:result_lines, 1)
    
    " Clear job progress section when done
    call timer_start(3000, {-> plugin_manager#ui#clear_job_progress()})
  endfunction
  
  " Run the commands in sequence
  call plugin_manager#jobs#run_sequence(l:commands, function('s:handle_backup_completed'))
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
    
    " Create command sequence
    let l:commands = []
    
    " 1. Initialize submodules
    call add(l:commands, {
          \ 'cmd': 'git submodule init',
          \ 'name': 'Initializing submodules'
          \ })
    
    " 2. Fetch and update all submodules
    call add(l:commands, {
          \ 'cmd': 'git submodule update --init --recursive',
          \ 'name': 'Updating submodules'
          \ })
    
    " 3. Make sure all submodules are at the correct commit
    call add(l:commands, {
          \ 'cmd': 'git submodule sync',
          \ 'name': 'Syncing submodules'
          \ })
          
    call add(l:commands, {
          \ 'cmd': 'git submodule update --init --recursive --force',
          \ 'name': 'Forcing submodule update'
          \ })
    
    " Final callback function
    function! s:handle_restore_completed(results) closure
      let l:success = 1
      let l:result_lines = ['Restore results:']
      
      for l:result in a:results
        if l:result.status != 0
          let l:success = 0
          call add(l:result_lines, '✗ ' . l:result.name . ' failed')
        else
          call add(l:result_lines, '✓ ' . l:result.name . ' succeeded')
        endif
      endfor
      
      if l:success
        call add(l:result_lines, '')
        call add(l:result_lines, 'All plugins have been restored successfully.')
        call add(l:result_lines, '')
        call add(l:result_lines, 'Generating helptags:')
        call plugin_manager#ui#update_sidebar(l:result_lines, 1)
        
        " Generate helptags for all plugins
        call plugin_manager#modules#generate_helptags(0)
      else
        call add(l:result_lines, '')
        call add(l:result_lines, 'Restore completed with errors. See details above.')
        call plugin_manager#ui#update_sidebar(l:result_lines, 1)
      endif
      
      " Clear job progress section when done
      call timer_start(3000, {-> plugin_manager#ui#clear_job_progress()})
    endfunction
    
    " Run the commands in sequence
    call plugin_manager#jobs#run_sequence(l:commands, function('s:handle_restore_completed'))
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