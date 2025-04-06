" UI functions for vim-plugin-manager

" Buffer name
let s:buffer_name = 'PluginManager'  

" Job status section
let s:job_progress_lines = {}
let s:job_progress_section_active = 0
let s:sidebar_update_timer = -1

" Open the sidebar window with optimized logic
function! plugin_manager#ui#open_sidebar(lines)
    " Check if sidebar buffer already exists
    let l:buffer_exists = bufexists(s:buffer_name)
    let l:win_id = bufwinid(s:buffer_name)
    
    if l:win_id != -1
      " Sidebar window is already open, focus it
      call win_gotoid(l:win_id)
    else
      " Create a new window on the right
      execute 'silent! rightbelow ' . g:plugin_manager_sidebar_width . 'vnew ' . s:buffer_name
      " Set the filetype to trigger ftplugin and syntax files
      set filetype=pluginmanager
    endif
    
    " Update buffer content more efficiently
    call plugin_manager#ui#update_sidebar(a:lines, 0)
endfunction
  
" Schedule sidebar update to avoid UI blocking
function! s:do_update_sidebar(lines, append)
  " Find the sidebar buffer window
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1
    " If the window doesn't exist, create it
    call plugin_manager#ui#open_sidebar(a:lines)
    return
  endif
  
  " Focus the sidebar window
  call win_gotoid(l:win_id)
  
  " Only change modifiable state once
  setlocal modifiable
  
  " Update content based on append flag
  if a:append && !empty(a:lines)
    " More efficient append - don't write empty lines
    if line('$') > 0 && getline('$') != ''
      call append(line('$'), '')  " Add separator line
    endif
    call append(line('$'), a:lines)
  else
    " Replace existing content more efficiently
    silent! %delete _
    if !empty(a:lines)
      call setline(1, a:lines)
    endif
  endif
  
  " Set back to non-modifiable and move cursor to top
  setlocal nomodifiable
  call cursor(1, 1)
endfunction

" Update the sidebar content with better performance using scheduled update
function! plugin_manager#ui#update_sidebar(lines, append)
  if s:sidebar_update_timer != -1
    call timer_stop(s:sidebar_update_timer)
  endif
  
  " Schedule an immediate update (1ms timer to ensure async behavior)
  let s:sidebar_update_timer = timer_start(1, {-> s:do_update_sidebar(a:lines, a:append)})
endfunction

" Schedule job progress update to avoid UI blocking
function! s:do_update_job_progress(job_id, status_line)
  " Store/update this job's status
  let s:job_progress_lines[a:job_id] = a:status_line
  
  " Check if the sidebar exists
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1
    " Not an error, just don't do anything if sidebar isn't open
    return
  endif
  
  " Focus the sidebar window
  call win_gotoid(l:win_id)
  setlocal modifiable
  
  " Find or create the job progress section
  let l:progress_section_start = -1
  let l:progress_section_end = -1
  
  " Look for existing section markers
  let l:line_count = line('$')
  for i in range(1, l:line_count)
    if getline(i) =~ '^Job Progress:$'
      let l:progress_section_start = i
    elseif l:progress_section_start > 0 && getline(i) =~ '^-\+$'
      if i == l:progress_section_start + 1
        " This is the line right after the header
        let l:progress_section_end = i
        break
      endif
    endif
  endfor
  
  " If no section exists yet, create it at the bottom
  if l:progress_section_start < 0
    call cursor(line('$'), 1)
    " Add some space if needed
    if getline('.') != ''
      call append(line('$'), ['', ''])
    endif
    call append(line('$'), ['Job Progress:', repeat('-', 12), ''])
    let l:progress_section_start = line('$') - 2
    let l:progress_section_end = line('$') - 1
    let s:job_progress_section_active = 1
  endif
  
  " Now find the end of the job progress section
  let l:content_end = l:progress_section_end + 1
  while l:content_end <= line('$') && getline(l:content_end) !~ '^[A-Z]'
    let l:content_end += 1
  endwhile
  let l:content_end -= 1
  
  " Delete existing progress lines
  if l:progress_section_end + 1 <= l:content_end
    execute (l:progress_section_end + 1) . ',' . l:content_end . 'delete _'
  endif
  
  " Add updated progress lines
  let l:progress_lines = []
  for [l:id, l:status] in items(s:job_progress_lines)
    call add(l:progress_lines, l:status)
  endfor
  
  " If no active jobs, add a placeholder
  if empty(l:progress_lines)
    if s:job_progress_section_active
      call add(l:progress_lines, 'No active jobs.')
    else
      " Remove the section entirely
      execute (l:progress_section_start) . ',' . (l:progress_section_end + 1) . 'delete _'
    endif
  else
    let s:job_progress_section_active = 1
  endif
  
  " Insert the progress lines
  if !empty(l:progress_lines) && s:job_progress_section_active
    call append(l:progress_section_end, l:progress_lines)
  endif
  
  " Restore modifiable state
  setlocal nomodifiable
endfunction

" Modification de la fonction update_job_progress pour éviter les doublons
function! plugin_manager#ui#update_job_progress(job_id, status_line)
  " Obtenir le nom du job à partir de la ligne de statut
  let l:job_name = matchstr(a:status_line, '^[^:]\+: \zs[^(]\+')
  let l:job_name = trim(l:job_name)

  " Vérifier s'il existe déjà un job avec le même nom
  let l:existing_job_id = -1
  for [l:id, l:status] in items(s:job_progress_lines)
    let l:existing_name = matchstr(l:status, '^[^:]\+: \zs[^(]\+')
    let l:existing_name = trim(l:existing_name)
    if l:existing_name == l:job_name && l:id != a:job_id
      let l:existing_job_id = l:id
      break
    endif
  endfor

  " Si un job avec le même nom existe déjà, supprimez-le
  if l:existing_job_id != -1
    unlet s:job_progress_lines[l:existing_job_id]
  endif

  " Store/update this job's status
  let s:job_progress_lines[a:job_id] = a:status_line
  
  " Schedule job progress update (1ms timer to ensure async behavior)
  call timer_start(1, {-> s:do_update_job_progress(a:job_id, a:status_line)})
endfunction

" Modification de la fonction status pour tenir compte des appels multiples
function! plugin_manager#modules#status()
  " Protection contre les appels multiples
  if exists('s:status_in_progress') && s:status_in_progress
    call plugin_manager#ui#update_sidebar(['Status operation already in progress...'], 1)
    return
  endif
  let s:status_in_progress = 1
  
  if !plugin_manager#utils#ensure_vim_directory()
    let s:status_in_progress = 0
    return
  endif
  
  " Nettoyer la section Job Progress avant de commencer
  call plugin_manager#ui#clear_job_progress()
  
  " Initial header display
  let l:header = 'Submodule Status:'
  let l:lines = [l:header, repeat('-', len(l:header)), '', 'Preparing submodule status...']
  call plugin_manager#ui#open_sidebar(l:lines)
  
  " Use the gitmodules cache (this is fast and non-blocking)
  let l:modules = plugin_manager#utils#parse_gitmodules()
  
  if empty(l:modules)
    call plugin_manager#ui#update_sidebar([l:header, repeat('-', len(l:header)), '', 'No submodules found (.gitmodules not found)'], 0)
    let s:status_in_progress = 0
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

" Modifier la fonction process_status_after_fetch pour réinitialiser le flag
function! s:process_status_after_fetch(modules, header, status, output) 
  call plugin_manager#ui#update_sidebar([a:header, repeat('-', len(a:header)), '', 
        \ 'Plugin'.repeat(' ', 16).'Commit'.repeat(' ', 14).'Branch'.repeat(' ', 8).'Last Updated'.repeat(' ', 18).'Status',
        \ repeat('-', 120),
        \ 'Processing status information...'], 0)
  
  " Process modules in background to avoid blocking UI
  call timer_start(1, function('s:process_status_async', [a:modules, a:header]))
endfunction

" Modifier la fonction process_status_async pour réinitialiser le flag quand terminé
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
    let s:status_in_progress = 0
    
    " Clear job progress section when done
    call timer_start(3000, {-> plugin_manager#ui#clear_job_progress()})
  endif
endfunction

" Clear the job progress section
function! plugin_manager#ui#clear_job_progress()
  " Schedule clear job progress (1ms timer to ensure async behavior)
  call timer_start(1, {-> s:do_clear_job_progress()})
endfunction

" Display a progress bar in the sidebar
function! plugin_manager#ui#show_progress_bar(percent, msg)
  " Calculate progress bar width (50% of sidebar width)
  let l:bar_width = g:plugin_manager_sidebar_width / 2
  
  " Calculate filled portion
  let l:filled_width = float2nr(l:bar_width * (a:percent / 100.0))
  
  " Create progress bar string
  let l:progress_bar = '[' . repeat('=', l:filled_width) . repeat(' ', l:bar_width - l:filled_width) . ']'
  
  " Format percentage display
  let l:percent_str = printf("%3d%%", float2nr(a:percent))
  
  " Create complete progress line
  let l:progress_line = l:progress_bar . ' ' . l:percent_str . ' ' . a:msg
  
  " Update the sidebar with the progress
  call plugin_manager#ui#update_sidebar([l:progress_line], 1)
endfunction
  
" Display usage instructions
function! plugin_manager#ui#usage()
  let l:lines = [
        \ "PluginManager Commands:",
        \ "---------------------",
        \ "add <plugin_url> [options]    - Add a new plugin with options",
        \ "                                Options: {'dir':'name', 'load':'start|opt', 'branch':'branch',",
        \ "                                          'tag':'tag', 'exec':'cmd'}",
        \ "remove [plugin_name] [-f]     - Remove a plugin",
        \ "backup                        - Backup configuration",
        \ "reload [plugin]               - Reload configuration",        
        \ "list                          - List installed plugins",
        \ "status                        - Show status of submodules",
        \ "update [plugin_name|all]      - Update all plugins or a specific one",
        \ "helptags [plugin_name]        - Generate plugins helptags, optionally for a specific plugin",
        \ "summary                       - Show summary of changes",
        \ "restore                       - Reinstall all modules",
        \ "",
        \ "Sidebar Keyboard Shortcuts:",
        \ "-------------------------",
        \ "q - Close the sidebar",
        \ "l - List installed plugins",
        \ "u - Update all plugins",
        \ "h - Generate helptags for all plugins",
        \ "s - Show status of submodules",
        \ "S - Show summary of changes",        
        \ "b - Backup configuration",
        \ "r - Restore all plugins",
        \ "R - Reload configuration",
        \ "? - Show this help",
        \ "",
        \ "Configuration:",
        \ "-------------",
        \ "g:plugin_manager_vim_dir = \"" . g:plugin_manager_vim_dir . "\"",
        \ "g:plugin_manager_plugins_dir = \"" . g:plugin_manager_plugins_dir . "\"",
        \ "g:plugin_manager_vimrc_path = \"" . expand(g:plugin_manager_vimrc_path) . "\""
        \ ]
  
  call plugin_manager#ui#open_sidebar(l:lines)
endfunction
  
" Function to toggle the Plugin Manager sidebar
function! plugin_manager#ui#toggle_sidebar()
   let l:win_id = bufwinid(s:buffer_name)
   if l:win_id != -1
     " Sidebar is visible, close it
     execute 'bd ' . bufnr(s:buffer_name)
   else
     " Open sidebar with usage info
     call plugin_manager#ui#usage()
   endif
endfunction