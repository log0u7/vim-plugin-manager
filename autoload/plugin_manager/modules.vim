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

" Improved status function with fixed column formatting and truly asynchronous behavior
function! plugin_manager#modules#status()
  if !plugin_manager#utils#ensure_vim_directory()
    return
  endif
  
  " Initial header display
  let l:header = 'Submodule Status:'
  let l:lines = [l:header, repeat('-', len(l:header)), '', 'Preparing submodule status...']
  call plugin_manager#ui#open_sidebar(l:lines)
  
  " Use the gitmodules cache (this is fast and non-blocking)
  let l:modules = plugin_manager#utils#parse_gitmodules()
  
  if empty(l:modules)
    call plugin_manager#ui#update_sidebar([l:header, repeat('-', len(l:header)), '', 'No submodules found (.gitmodules not found)'], 0)
    return
  endif
  
  " Define header and table format - this happens immediately
  let l:header_lines = [l:header, repeat('-', len(l:header)), '']
  call add(l:header_lines, 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 8).'Last Updated'.repeat(' ', 18).'Status')
  call add(l:header_lines, repeat('-', 120))
  call add(l:header_lines, 'Fetching updates from remote repositories...')
  
  " Update sidebar with the header immediately
  call plugin_manager#ui#update_sidebar(l:header_lines, 0)
  
  " Process fetch in background
  if plugin_manager#jobs#is_async_supported()
    " Fetch updates asynchronously first
    let l:callbacks = {
          \ 'name': 'Fetching repository updates',
          \ 'on_exit': function('s:process_status_after_fetch', [l:modules, l:header])
          \ }
    
    call plugin_manager#jobs#start('git submodule foreach --recursive "git fetch -q origin 2>/dev/null || true"', l:callbacks)
  else
    " No async support, do it all synchronously but still in chunks
    call timer_start(10, function('s:process_status_sync', [l:modules, l:header]))
  endif
endfunction

" Process module statuses after fetch completes
function! s:process_status_after_fetch(modules, header, status, output) 
  call plugin_manager#ui#update_sidebar([a:header, repeat('-', len(a:header)), '', 
        \ 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 8).'Last Updated'.repeat(' ', 18).'Status',
        \ repeat('-', 120),
        \ 'Processing status information...'], 0)
  
  " Process modules in background to avoid blocking UI
  call timer_start(1, function('s:process_status_async', [a:modules, a:header]))
endfunction

" Process module statuses synchronously in chunks
function! s:process_status_sync(modules, header, timer)
  call plugin_manager#ui#update_sidebar([a:header, repeat('-', len(a:header)), '', 
        \ 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 8).'Last Updated'.repeat(' ', 18).'Status',
        \ repeat('-', 120),
        \ 'Processing status information...'], 0)
        
  " Sort modules by name
  let l:module_names = sort(keys(a:modules))
  let l:lines = []

  " Process all modules
  for l:name in l:module_names
    let l:module = a:modules[l:name]
    if has_key(l:module, 'is_valid') && l:module.is_valid
      call add(l:lines, s:format_module_status_line(l:module))
    endif
  endfor
  
  " Final update
  let l:final_lines = [a:header, repeat('-', len(a:header)), '', 
        \ 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 8).'Last Updated'.repeat(' ', 18).'Status',
        \ repeat('-', 120)]
  call extend(l:final_lines, l:lines)
  call plugin_manager#ui#update_sidebar(l:final_lines, 0)
endfunction

" Process module statuses asynchronously in chunks
function! s:process_status_async(modules, header, timer)
  " Sort modules by name
  let l:module_names = sort(keys(a:modules))
  let l:total_modules = len(l:module_names)
  let l:chunk_size = min([10, l:total_modules]) " Process up to 10 modules at a time
  
  " Store state across timer calls
  if !exists('s:status_state')
    let s:status_state = {
          \ 'processed': 0,
          \ 'lines': [],
          \ 'header': a:header
          \ }
  endif

  " Process a chunk of modules
  let l:chunk_end = min([s:status_state.processed + l:chunk_size, l:total_modules])
  let l:current_chunk = l:module_names[s:status_state.processed : l:chunk_end - 1]
  
  " Process current chunk
  for l:name in l:current_chunk
    let l:module = a:modules[l:name]
    if has_key(l:module, 'is_valid') && l:module.is_valid
      call add(s:status_state.lines, s:format_module_status_line(l:module))
    endif
  endfor
  
  " Update process tracking
  let s:status_state.processed = l:chunk_end
  
  " Show progress
  let l:progress = (s:status_state.processed * 100) / l:total_modules
  let l:header_lines = [a:header, repeat('-', len(a:header)), '', 
        \ 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 8).'Last Updated'.repeat(' ', 18).'Status',
        \ repeat('-', 120),
        \ 'Processing... ' . l:progress . '% complete']
  call plugin_manager#ui#update_sidebar(l:header_lines, 0)

  if s:status_state.processed < l:total_modules
    " Schedule next chunk processing
    call timer_start(1, function('s:process_status_async', [a:modules, a:header]))
  else
    " Final update
    let l:final_lines = [a:header, repeat('-', len(a:header)), '', 
          \ 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 8).'Last Updated'.repeat(' ', 18).'Status',
          \ repeat('-', 120)]
    call extend(l:final_lines, s:status_state.lines)
    call plugin_manager#ui#update_sidebar(l:final_lines, 0)
    
    " Clean up state
    unlet s:status_state
  endif
endfunction

" Format a single module status line
function! s:format_module_status_line(module)
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

" Update plugins asynchronously
function! plugin_manager#modules#update(...)
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
  
  " List to track modules that will be updated
  let l:modules_to_update = []
  
  " Initialize the UI for async updates
  let l:initial_message = l:header
  if l:specific_module == 'all'
    call add(l:initial_message, 'Starting asynchronous update of all plugins...')
  else 
    call add(l:initial_message, 'Starting asynchronous update of plugin: ' . l:specific_module)
  endif
  call plugin_manager#ui#open_sidebar(l:initial_message)
  
  " Create a function to handle the final results
  function! s:handle_update_completed(results) closure
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
      call add(l:update_lines, l:modules_updated . ' plugins updated successfully.')
      
      " Generate helptags for updated plugins asynchronously
      call add(l:update_lines, '')
      call add(l:update_lines, 'Generating helptags for updated plugins...')
      call plugin_manager#ui#update_sidebar(l:update_lines, 1)
      
      " Force refresh the cache after updates
      call plugin_manager#utils#refresh_modules_cache()
      
      " Call helptags generation
      call plugin_manager#modules#generate_helptags(0)
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
  
  " Process for updating all plugins
  if l:specific_module == 'all'
    " Handle all plugins
    call plugin_manager#ui#update_sidebar(['Preparing plugin updates...'], 1)
    
    " Create command sequence
    let l:commands = []
    
    " 1. First prepare by removing helptags
    call add(l:commands, {
          \ 'cmd': 'git submodule foreach --recursive "rm -f doc/tags doc/*/tags */tags 2>/dev/null || true"',
          \ 'name': 'Preparing modules'
          \ })
    
    " 2. Stash any local changes
    let l:any_changes = 0
    
    " Check if any module has local changes (done synchronously for simplicity)
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
      call add(l:commands, {
            \ 'cmd': 'git submodule foreach --recursive "git stash -q || true"',
            \ 'name': 'Stashing local changes'
            \ })
    endif
    
    " 3. Fetch updates without applying them
    call add(l:commands, {
          \ 'cmd': 'git submodule foreach --recursive "git fetch origin"',
          \ 'name': 'Fetching updates'
          \ })
    
    " 4. Determine which modules need updates (done synchronously for simplicity)
    let l:modules_with_updates = []
    let l:modules_on_diff_branch = []
    
    for [l:name, l:module] in items(l:modules)
      if l:module.is_valid && isdirectory(l:module.path)
        " Use the utility function to check for updates
        let l:update_status = plugin_manager#utils#check_module_updates(l:module.path)
        
        " Record module status
        let l:module.update_status = l:update_status
        
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
    
    " 5. Apply updates if any
    if empty(l:modules_with_updates)
      call plugin_manager#ui#update_sidebar(['All plugins are up-to-date.'], 1)
      let s:update_in_progress = 0
      return
    else
      call plugin_manager#ui#update_sidebar(['Found ' . len(l:modules_with_updates) . ' plugins with updates available. Updating...'], 1)
      
      " Add update command
      call add(l:commands, {
            \ 'cmd': 'git submodule sync && git submodule update --remote --merge --force',
            \ 'name': 'Updating plugins'
            \ })
      
      " 6. Commit changes if needed
      call add(l:commands, {
            \ 'cmd': 'git diff --quiet || git commit -am "Update Modules"',
            \ 'name': 'Committing changes'
            \ })
      
      " Store the updated modules info
      for l:module in l:modules_with_updates
        call add(l:modules_to_update, {'name': l:module.short_name, 'path': l:module.path})
      endfor
    endif
    
    " Run the commands in sequence
    call plugin_manager#jobs#run_sequence(l:commands, function('s:handle_update_completed'))
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
    
    " Check if directory exists
    if !isdirectory(l:module_path)
      call plugin_manager#ui#update_sidebar(['Error: Module directory "' . l:module_path . '" not found.', 
            \ 'Try running "PluginManager restore" to reinstall missing modules.'], 1)
      let s:update_in_progress = 0
      return
    endif
    
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
    
    " 4. Check if module needs update (done synchronously for simplicity)
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
    else
      call plugin_manager#ui#update_sidebar(['Updates available for plugin "' . l:module_name . '". Updating...'], 1)
      
      " 5. Update this module
      call add(l:commands, {
            \ 'cmd': 'git submodule sync -- "' . l:module_path . '" && git submodule update --remote --merge --force -- "' . l:module_path . '"',
            \ 'name': 'Updating ' . l:module_name
            \ })
      
      " 6. Commit changes if needed
      call add(l:commands, {
            \ 'cmd': 'git diff --quiet || git commit -am "Update Module: ' . l:module_name . '"',
            \ 'name': 'Committing changes for ' . l:module_name
            \ })
      
      " Add module to the update list
      call add(l:modules_to_update, {'name': l:module_name, 'path': l:module_path})
    endif
    
    " Run the commands in sequence
    call plugin_manager#jobs#run_sequence(l:commands, function('s:handle_update_completed'))
  endif
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
    
    " Create command sequence
    let l:commands = []
    
    " Check if remote origin exists
    let l:originExists = system('git remote | grep -c "^origin$" || echo 0')
    if l:originExists == "0"
      call add(l:commands, {
            \ 'cmd': 'git remote add origin ' . l:repoUrl,
            \ 'name': 'Adding origin remote'
            \ })
    else
      call add(l:commands, {
            \ 'cmd': 'git remote set-url origin --add --push ' . l:repoUrl,
            \ 'name': 'Adding push URL to origin remote'
            \ })
    endif
    
    " Final callback function
    function! s:handle_remote_add_completed(results) closure
      let l:success = 1
      let l:result_lines = []
      
      for l:result in a:results
        if l:result.status != 0
          let l:success = 0
          call add(l:result_lines, '✗ ' . l:result.name . ' failed')
        else
          call add(l:result_lines, '✓ ' . l:result.name . ' succeeded')
        endif
      endfor
      
      if l:success
        call add(l:result_lines, 'Repository added successfully.')
      else
        call add(l:result_lines, 'Error adding remote repository.')
      endif
      
      " Display configured repositories
      call add(l:result_lines, '')
      call add(l:result_lines, 'Configured repositories:')
      
      " Get configured remotes
      let l:remotes = system('git remote -v')
      call extend(l:result_lines, split(l:remotes, "\n"))
      
      call plugin_manager#ui#update_sidebar(l:result_lines, 1)
      
      " Clear job progress section when done
      call timer_start(3000, {-> plugin_manager#ui#clear_job_progress()})
    endfunction
    
    " Run the commands in sequence
    call plugin_manager#jobs#run_sequence(l:commands, function('s:handle_remote_add_completed'))
endfunction