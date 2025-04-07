" jobs.vim - Asynchronous job handling for vim-plugin-manager
" Version: 1.4

" Initialize job tracking variables
if !exists('s:job_list')
  let s:job_list = []
endif

if !exists('s:is_win')
  let s:is_win = has('win32') || has('win64')
endif

" Global lock to prevent nested job operations
let s:jobs_operations_lock = 0

" Check if async jobs are supported
function! plugin_manager#jobs#is_async_supported()
  " Check for Neovim with job support
  if has('nvim-0.2') || (has('nvim') && exists('*jobwait'))
    return 1
  endif
  
  " Check for Vim with job support
  if has('patch-8.0.0039') && exists('*job_start')
    return 1 
  endif
  
  return 0
endfunction

" Log job-related errors to both UI and message history
function! s:log_job_error(message)
  echohl ErrorMsg
  echomsg 'Job Error: ' . a:message
  echohl None
  
  try
    call plugin_manager#ui#update_sidebar(['Job Error: ' . a:message], 1)
  catch
    " Silently fail if UI update isn't possible
  endtry
endfunction

" Release jobs operations lock safely
function! s:release_jobs_operations_lock()
  let s:jobs_operations_lock = 0
endfunction

" Start an async job with appropriate callbacks
function! plugin_manager#jobs#start(cmd, callbacks)
  " Prevent nested job operations
  if s:jobs_operations_lock
    call s:log_job_error('Job operations already in progress')
    return -2
  endif
  
  " Set lock with timeout to prevent deadlocks
  let s:jobs_operations_lock = 1
  let l:timer_id = timer_start(10000, {-> s:release_jobs_operations_lock()})
  
  try
    " Fall back to sync operation if async not supported
    if !plugin_manager#jobs#is_async_supported()
      call plugin_manager#ui#update_sidebar(['Async not supported, using synchronous operation...'], 1)
      
      try
        let l:cmd = type(a:cmd) == v:t_list ? join(a:cmd, ' ') : a:cmd
        let l:output = system(l:cmd)
        let l:status = v:shell_error
        
        if has_key(a:callbacks, 'on_stdout')
          call a:callbacks.on_stdout(l:output)
        endif
        
        if has_key(a:callbacks, 'on_exit')
          call a:callbacks.on_exit(l:status, l:output)
        endif
        
        call timer_stop(l:timer_id)
        let s:jobs_operations_lock = 0
        return 0
      catch
        call s:log_job_error('Error in synchronous execution: ' . v:exception)
        throw v:exception
      endtry
    endif
    
    " Create job tracking structure
    let l:job_info = {
          \ 'cmd': a:cmd,
          \ 'callbacks': a:callbacks,
          \ 'start_time': reltime(),
          \ 'stdout': [],
          \ 'stderr': [],
          \ 'id': len(s:job_list) + 1,
          \ 'status': 'running',
          \ 'lock_released': 0,
          \ }
    
    " Display job start progress
    if has_key(a:callbacks, 'name')
      let l:job_info.name = a:callbacks.name
      call plugin_manager#ui#update_job_progress(l:job_info.id, 'Starting: ' . l:job_info.name)
    else
      let l:job_name = type(a:cmd) == v:t_list ? join(a:cmd) : a:cmd
      let l:job_name = strlen(l:job_name) > 40 ? strpart(l:job_name, 0, 37) . '...' : l:job_name
      call plugin_manager#ui#update_job_progress(l:job_info.id, 'Starting job: ' . l:job_name)
    endif
    
    " Branch for Vim or Neovim implementation
    if has('nvim')
      " Neovim implementation
      function! s:on_stdout_nvim(id, data, event) dict
        try
          if !empty(a:data)
            let self.stdout += a:data
            
            if has_key(self.callbacks, 'on_stdout')
              call self.callbacks.on_stdout(join(a:data, "\n"))
            endif
            
            call plugin_manager#ui#update_job_progress(self.id, 'Running: ' . get(self, 'name', 'job'))
          endif
        catch
          call s:log_job_error('Error in stdout handler: ' . v:exception)
        endtry
      endfunction
      
      function! s:on_stderr_nvim(id, data, event) dict
        try
          if !empty(a:data)
            let self.stderr += a:data
            
            if has_key(self.callbacks, 'on_stderr')
              call self.callbacks.on_stderr(join(a:data, "\n"))
            endif
          endif
        catch
          call s:log_job_error('Error in stderr handler: ' . v:exception)
        endtry
      endfunction
      
      function! s:on_exit_nvim(id, status, event) dict
        try
          let self.lock_released = 1
          let self.status = 'completed'
          let self.exit_status = a:status
          let l:stdout = join(self.stdout, "\n")
          
          if a:status == 0
            call plugin_manager#ui#update_job_progress(self.id, 'Completed: ' . get(self, 'name', 'job'))
          else
            call plugin_manager#ui#update_job_progress(self.id, 'Failed: ' . get(self, 'name', 'job') . ' (status ' . a:status . ')')
          endif
          
          if has_key(self.callbacks, 'on_exit')
            call self.callbacks.on_exit(a:status, l:stdout)
          endif
          
          if has_key(self.callbacks, 'on_chain') && a:status == 0
            call self.callbacks.on_chain()
          endif
        catch
          call s:log_job_error('Error in exit handler: ' . v:exception)
        finally
          if !self.lock_released && s:jobs_operations_lock
            let s:jobs_operations_lock = 0
          endif
          
          call plugin_manager#jobs#clean_jobs()
        endtry
      endfunction
      
      let l:job_options = {
            \ 'stdout_buffered': 1,
            \ 'stderr_buffered': 1,
            \ 'on_stdout': function('s:on_stdout_nvim', [], l:job_info),
            \ 'on_stderr': function('s:on_stderr_nvim', [], l:job_info),
            \ 'on_exit': function('s:on_exit_nvim', [], l:job_info),
            \ }
      
      let l:cmd = type(a:cmd) == v:t_list ? a:cmd : split(a:cmd, '\s\+')
      let l:job = jobstart(l:cmd, l:job_options)
      
      if l:job <= 0
        call s:log_job_error('Failed to start Neovim job, code: ' . l:job)
        throw 'Failed to start Neovim job'
      endif
      
      let l:job_info.job = l:job
      let l:job_info.type = 'nvim'
    else
      " Vim implementation
      function! s:on_stdout_vim(channel, msg) dict
        try
          call add(self.stdout, a:msg)
          
          if has_key(self.callbacks, 'on_stdout')
            call self.callbacks.on_stdout(a:msg)
          endif
          
          call plugin_manager#ui#update_job_progress(self.id, 'Running: ' . get(self, 'name', 'job'))
        catch
          call s:log_job_error('Error in stdout handler: ' . v:exception)
        endtry
      endfunction
      
      function! s:on_stderr_vim(channel, msg) dict
        try
          call add(self.stderr, a:msg)
          
          if has_key(self.callbacks, 'on_stderr')
            call self.callbacks.on_stderr(a:msg)
          endif
        catch
          call s:log_job_error('Error in stderr handler: ' . v:exception)
        endtry
      endfunction
      
      function! s:on_exit_vim(channel, status) dict
        try
          let self.lock_released = 1
          let self.status = 'completed'
          let self.exit_status = a:status
          let l:stdout = join(self.stdout, "\n")
          
          if a:status == 0
            call plugin_manager#ui#update_job_progress(self.id, 'Completed: ' . get(self, 'name', 'job'))
          else
            call plugin_manager#ui#update_job_progress(self.id, 'Failed: ' . get(self, 'name', 'job') . ' (status ' . a:status . ')')
          endif
          
          if has_key(self.callbacks, 'on_exit')
            call self.callbacks.on_exit(a:status, l:stdout)
          endif
          
          if has_key(self.callbacks, 'on_chain') && a:status == 0
            call self.callbacks.on_chain()
          endif
        catch
          call s:log_job_error('Error in exit handler: ' . v:exception)
        finally
          if !self.lock_released && s:jobs_operations_lock
            let s:jobs_operations_lock = 0
          endif
          
          call plugin_manager#jobs#clean_jobs()
        endtry
      endfunction
      
      let l:job_options = {
            \ 'out_cb': function('s:on_stdout_vim', [], l:job_info),
            \ 'err_cb': function('s:on_stderr_vim', [], l:job_info),
            \ 'exit_cb': function('s:on_exit_vim', [], l:job_info),
            \ 'in_io': 'null',
            \ }
      
      let l:job = job_start(a:cmd, l:job_options)
      
      if job_status(l:job) ==# 'fail'
        call s:log_job_error('Failed to start Vim job')
        throw 'Failed to start Vim job'
      endif
      
      let l:job_info.job = l:job
      let l:job_info.type = 'vim'
    endif
    
    call add(s:job_list, l:job_info)
    call timer_stop(l:timer_id)
    let l:job_info.started_async = 1
    
    return l:job_info.id
  catch
    call s:log_job_error('Error starting job: ' . v:exception)
    return -1
  finally
    if !exists('l:job_info') || !has_key(l:job_info, 'started_async') || !l:job_info.started_async
      call timer_stop(l:timer_id)
      let s:jobs_operations_lock = 0
    endif
  endtry
endfunction

" Check if any jobs are running
function! plugin_manager#jobs#is_running()
  for l:job in s:job_list
    if l:job.status == 'running'
      return 1
    endif
  endfor
  return 0
endfunction

" Clean up completed jobs
function! plugin_manager#jobs#clean_jobs()
  let l:now = reltime()
  let l:new_list = []
  
  for l:job in s:job_list
    if l:job.status == 'running' || reltimefloat(reltime(l:job.start_time, l:now)) < 60.0
      call add(l:new_list, l:job)
    endif
  endfor
  
  let s:job_list = l:new_list
endfunction

" Display job progress in the sidebar
function! plugin_manager#jobs#display_progress(job_id, message)
  let l:job = {}
  for j in s:job_list
    if j.id == a:job_id
      let l:job = j
      break
    endif
  endfor
  
  if !empty(l:job)
    let l:name = get(l:job, 'name', 'Job ' . a:job_id)
    let l:elapsed = reltimefloat(reltime(l:job.start_time))
    let l:elapsed_str = printf("%.1fs", l:elapsed)
    
    let l:spinner = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
    let l:spinner_idx = float2nr(l:elapsed * 10) % len(l:spinner)
    let l:spinner_char = l:spinner[l:spinner_idx]
    
    if !has('gui_running') && !has('nvim') && &encoding !~? 'utf'
      let l:spinner = ['-', '\', '|', '/']
      let l:spinner_idx = float2nr(l:elapsed * 4) % len(l:spinner)
      let l:spinner_char = l:spinner[l:spinner_idx]
    endif
    
    if l:job.status == 'running'
      let l:status_line = l:spinner_char . ' ' . l:name . ' (' . l:elapsed_str . '): ' . a:message
    else
      let l:check = has('gui_running') || has('nvim') || &encoding =~? 'utf' ? '✓' : 'OK'
      let l:status_line = l:check . ' ' . l:name . ' (' . l:elapsed_str . '): ' . a:message
    endif
    
    call plugin_manager#ui#update_job_progress(a:job_id, l:status_line)
  endif
endfunction

" Run a sequence of commands asynchronously
function! plugin_manager#jobs#run_sequence(commands, final_callback)
  if s:jobs_operations_lock
    call s:log_job_error('Job sequence already in progress')
    return -1
  endif
  
  let s:jobs_operations_lock = 1
  let l:timer_id = timer_start(10000, {-> s:release_jobs_operations_lock()})
  
  try
    let l:sequence = copy(a:commands)
    let l:results = []
    
    function! s:run_next(results, commands, final_callback, status, output) closure
      try
        call add(a:results, {'status': a:status, 'output': a:output, 'name': get(l:cmd, 'name', 'Command ' . len(a:results))})
        
        if empty(a:commands)
          call a:final_callback(a:results)
          return
        endif
        
        let l:cmd = remove(a:commands, 0)
        let l:name = get(l:cmd, 'name', 'Command ' . (len(a:results) + 1))
        
        let l:callbacks = {
              \ 'name': l:name,
              \ 'on_stdout': get(l:cmd, 'on_stdout', function('s:default_stdout')),
              \ 'on_stderr': get(l:cmd, 'on_stderr', function('s:default_stderr')),
              \ 'on_exit': function('s:run_next', [a:results, a:commands, a:final_callback]),
              \ }
        
        call plugin_manager#jobs#start(l:cmd.cmd, l:callbacks)
      catch
        call s:log_job_error('Error in job sequence: ' . v:exception)
        
        call add(a:results, {'status': 1, 'output': 'Error: ' . v:exception, 'name': 'Error in job sequence'})
        call a:final_callback(a:results)
        
        if s:jobs_operations_lock
          let s:jobs_operations_lock = 0
        endif
      endtry
    endfunction
    
    function! s:default_stdout(msg)
      " Empty by design
    endfunction
    
    function! s:default_stderr(msg)
      " Empty by design
    endfunction
    
    if !empty(l:sequence)
      let l:cmd = remove(l:sequence, 0)
      let l:name = get(l:cmd, 'name', 'Command 1')
      
      let l:callbacks = {
            \ 'name': l:name,
            \ 'on_stdout': get(l:cmd, 'on_stdout', function('s:default_stdout')),
            \ 'on_stderr': get(l:cmd, 'on_stderr', function('s:default_stderr')),
            \ 'on_exit': function('s:run_next', [l:results, l:sequence, a:final_callback]),
            \ }
      
      let l:job_id = plugin_manager#jobs#start(l:cmd.cmd, l:callbacks)
      
      if l:job_id < 0
        throw "Failed to start job: " . l:cmd.cmd
      endif
      
      call timer_stop(l:timer_id)
      return l:job_id
    else
      call a:final_callback([])
      let s:jobs_operations_lock = 0
      call timer_stop(l:timer_id)
      return 0
    endif
  catch
    call s:log_job_error('Error starting job sequence: ' . v:exception)
    
    try
      call a:final_callback([{'status': 1, 'output': 'Error: ' . v:exception, 'name': 'Error starting sequence'}])
    catch
      " Silent fail if callback fails
    endtry
    
    return -1
  finally
    if !exists('l:job_id') || l:job_id < 0
      call timer_stop(l:timer_id)
      let s:jobs_operations_lock = 0
    endif
  endtry
endfunction

" Stop all running jobs 
function! plugin_manager#jobs#stop_all()
  let l:stop_errors = []
  
  for l:job in s:job_list
    if l:job.status == 'running'
      try
        if l:job.type == 'nvim'
          call jobstop(l:job.job)
        else
          call job_stop(l:job.job)
        endif
        let l:job.status = 'stopped'
      catch
        call add(l:stop_errors, 'Failed to stop job ' . get(l:job, 'name', l:job.id) . ': ' . v:exception)
      endtry
    endif
  endfor
  
  call plugin_manager#jobs#clean_jobs()
  let s:jobs_operations_lock = 0
  call plugin_manager#ui#clear_job_progress()
  
  if !empty(l:stop_errors)
    for l:err in l:stop_errors
      call s:log_job_error(l:err)
    endfor
  endif
  
  return len(l:stop_errors) == 0
endfunction