" autoload/plugin_manager/jobs.vim - Asynchronous jobs for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4

" Variables for job handling
  let s:job_list = get(s:, 'job_list', [])
  let s:is_win = has('win32') || has('win64')
  let s:jobs_operations_lock = 0
  
  " Check if async jobs are supported
  function! plugin_manager#jobs#is_async_supported()
    " Check for Neovim
    if has('nvim-0.2') || (has('nvim') && exists('*jobwait') && !s:is_win)
      return 1
    endif
    
    " Check for Vim
    if has('patch-8.0.0039') && exists('*job_start')
      return 1 
    endif
    
    " Not supported
    return 0
  endfunction
  
  " Log job-related errors to both the UI and Vim's message history
  function! s:log_job_error(message)
    " Log to Vim's message history
    echohl ErrorMsg
    echomsg 'Job Error: ' . a:message
    echohl None
    
    " Try to log to UI if possible
    try
      call plugin_manager#ui#update_sidebar(['Job Error: ' . a:message], 1)
    catch
      " Silently fail if UI update isn't possible
    endtry
  endfunction
  
  " Release jobs operations lock safely
  function! s:release_jobs_operations_lock()
    try
      let s:jobs_operations_lock = 0
    catch
      " Silently handle errors during lock release
    endtry
  endfunction
  
  " Start an async job with appropriate callback handling and error protection
  function! plugin_manager#jobs#start(cmd, callbacks)
    " Prevent job operations from being nested/recursive
    if s:jobs_operations_lock
      call s:log_job_error('Job operations already in progress, please wait')
      return -2
    endif
    
    " Set lock with timeout to prevent deadlocks
    let s:jobs_operations_lock = 1
    let l:timer_id = timer_start(10000, {-> s:release_jobs_operations_lock()})
    
    try
      " If async not supported, fall back to sync with error handling
      if !plugin_manager#jobs#is_async_supported()
        call plugin_manager#ui#update_sidebar(['Async jobs not supported in this Vim version, falling back to synchronous operation...'], 1)
        
        try
          " Handle command as a list or string
          let l:cmd = type(a:cmd) == v:t_list ? join(a:cmd, ' ') : a:cmd
          
          " Execute command synchronously
          let l:output = system(l:cmd)
          let l:status = v:shell_error
          
          if has_key(a:callbacks, 'on_stdout')
            call a:callbacks.on_stdout(l:output)
          endif
          
          if has_key(a:callbacks, 'on_exit')
            call a:callbacks.on_exit(l:status, l:output)
          endif
          
          " Release lock immediately for synchronous execution
          call timer_stop(l:timer_id)
          let s:jobs_operations_lock = 0
          return 0
        catch
          call s:log_job_error('Error in synchronous execution: ' . v:exception)
          throw v:exception
        endtry
      endif
      
      " Create a structure to keep track of this job
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
      
      " Display that we're starting the job
      if has_key(a:callbacks, 'name')
        let l:job_info.name = a:callbacks.name
        call plugin_manager#jobs#display_progress(l:job_info.id, 'Starting: ' . l:job_info.name)
      else
        let l:job_name = type(a:cmd) == v:t_list ? join(a:cmd) : a:cmd
        let l:job_name = strlen(l:job_name) > 40 ? strpart(l:job_name, 0, 37) . '...' : l:job_name
        call plugin_manager#jobs#display_progress(l:job_info.id, 'Starting job: ' . l:job_name)
      endif
      
      " Branch for Vim or Neovim implementation
      if has('nvim')
        " Neovim job implementation
        function! s:on_stdout_nvim(id, data, event) dict
          try
            " Collect stdout data
            if !empty(a:data)
              let self.stdout += a:data
              
              " If we have a stdout callback, pass the data
              if has_key(self.callbacks, 'on_stdout')
                call self.callbacks.on_stdout(join(a:data, "\n"))
              endif
              
              " Update progress display
              call plugin_manager#jobs#display_progress(self.id, 'Running: ' . get(self, 'name', 'job'))
            endif
          catch
            call s:log_job_error('Error in stdout handler: ' . v:exception)
          endtry
        endfunction
        
        function! s:on_stderr_nvim(id, data, event) dict
          try
            " Collect stderr data
            if !empty(a:data)
              let self.stderr += a:data
              
              " If we have a stderr callback, pass the data
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
            " Mark lock as released to prevent double release
            let self.lock_released = 1
            
            " Set job status
            let self.status = 'completed'
            let self.exit_status = a:status
            
            " Format output 
            let l:stdout = join(self.stdout, "\n")
            
            " Update progress display
            if a:status == 0
              call plugin_manager#jobs#display_progress(self.id, 'Completed: ' . get(self, 'name', 'job'))
            else
              call plugin_manager#jobs#display_progress(self.id, 'Failed: ' . get(self, 'name', 'job') . ' (status ' . a:status . ')')
            endif
            
            " Call the exit callback if provided
            if has_key(self.callbacks, 'on_exit')
              call self.callbacks.on_exit(a:status, l:stdout)
            endif
            
            " If there's a chain callback, call the next job
            if has_key(self.callbacks, 'on_chain') && a:status == 0
              call self.callbacks.on_chain()
            endif
          catch
            call s:log_job_error('Error in exit handler: ' . v:exception)
          finally
            " Release the lock if this is the job that set it
            if !self.lock_released && s:jobs_operations_lock
              let s:jobs_operations_lock = 0
            endif
            
            " Clean up job list
            call plugin_manager#jobs#clean_jobs()
          endtry
        endfunction
        
        " Set job options for Neovim
        let l:job_options = {
              \ 'stdout_buffered': 1,
              \ 'stderr_buffered': 1,
              \ 'on_stdout': function('s:on_stdout_nvim', [], l:job_info),
              \ 'on_stderr': function('s:on_stderr_nvim', [], l:job_info),
              \ 'on_exit': function('s:on_exit_nvim', [], l:job_info),
              \ }
        
        " Handle command as a list or string
        let l:cmd = type(a:cmd) == v:t_list ? a:cmd : split(a:cmd, '\s\+')
        
        " Start the job
        let l:job = jobstart(l:cmd, l:job_options)
        
        " Check if job started successfully
        if l:job <= 0
          call s:log_job_error('Failed to start Neovim job, error code: ' . l:job)
          throw 'Failed to start Neovim job'
        endif
        
        let l:job_info.job = l:job
        let l:job_info.type = 'nvim'
      else
        " Vim job implementation
        function! s:on_stdout_vim(channel, msg) dict
          try
            " Collect stdout data
            call add(self.stdout, a:msg)
            
            " If we have a stdout callback, pass the data
            if has_key(self.callbacks, 'on_stdout')
              call self.callbacks.on_stdout(a:msg)
            endif
            
            " Update progress display
            call plugin_manager#jobs#display_progress(self.id, 'Running: ' . get(self, 'name', 'job'))
          catch
            call s:log_job_error('Error in stdout handler: ' . v:exception)
          endtry
        endfunction
        
        function! s:on_stderr_vim(channel, msg) dict
          try
            " Collect stderr data
            call add(self.stderr, a:msg)
            
            " If we have a stderr callback, pass the data
            if has_key(self.callbacks, 'on_stderr')
              call self.callbacks.on_stderr(a:msg)
            endif
          catch
            call s:log_job_error('Error in stderr handler: ' . v:exception)
          endtry
        endfunction
        
        function! s:on_exit_vim(channel, status) dict
          try
            " Mark lock as released to prevent double release
            let self.lock_released = 1
            
            " Set job status
            let self.status = 'completed'
            let self.exit_status = a:status
            
            " Format output
            let l:stdout = join(self.stdout, "\n")
            
            " Update progress display
            if a:status == 0
              call plugin_manager#jobs#display_progress(self.id, 'Completed: ' . get(self, 'name', 'job'))
            else
              call plugin_manager#jobs#display_progress(self.id, 'Failed: ' . get(self, 'name', 'job') . ' (status ' . a:status . ')')
            endif
            
            " Call the exit callback if provided
            if has_key(self.callbacks, 'on_exit')
              call self.callbacks.on_exit(a:status, l:stdout)
            endif
            
            " If there's a chain callback, call the next job
            if has_key(self.callbacks, 'on_chain') && a:status == 0
              call self.callbacks.on_chain()
            endif
          catch
            call s:log_job_error('Error in exit handler: ' . v:exception)
          finally
            " Release the lock if this is the job that set it
            if !self.lock_released && s:jobs_operations_lock
              let s:jobs_operations_lock = 0
            endif
            
            " Clean up job list
            call plugin_manager#jobs#clean_jobs()
          endtry
        endfunction
        
        " Set job options for Vim
        let l:job_options = {
              \ 'out_cb': function('s:on_stdout_vim', [], l:job_info),
              \ 'err_cb': function('s:on_stderr_vim', [], l:job_info),
              \ 'exit_cb': function('s:on_exit_vim', [], l:job_info),
              \ 'in_io': 'null',
              \ }
        
        " Handle shell command as string (Vim's job_start can handle shell commands directly)
        let l:cmd = a:cmd
        
        " Start the job
        let l:job = job_start(l:cmd, l:job_options)
        
        " Check if job started successfully
        if job_status(l:job) ==# 'fail'
          call s:log_job_error('Failed to start Vim job')
          throw 'Failed to start Vim job'
        endif
        
        let l:job_info.job = l:job
        let l:job_info.type = 'vim'
      endif
      
      " Add job to list
      call add(s:job_list, l:job_info)
      
      " Cancel the lock release timer - callbacks will handle it
      call timer_stop(l:timer_id)
      let l:job_info.started_async = 1
      
      return l:job_info.id
    catch
      call s:log_job_error('Error starting job: ' . v:exception)
      return -1
    finally
      " Only release the lock if we're not starting an async job,
      " for async jobs, the exit callback will release the lock
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
    " Filter out completed jobs that are older than 60 seconds
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
    " Find the job by ID
    let l:job = {}
    for j in s:job_list
      if j.id == a:job_id
        let l:job = j
        break
      endif
    endfor
    
    " Handle progress display
    if !empty(l:job)
      let l:name = get(l:job, 'name', 'Job ' . a:job_id)
      let l:elapsed = reltimefloat(reltime(l:job.start_time))
      let l:elapsed_str = printf("%.1fs", l:elapsed)
      
      " Create progress indicator
      let l:spinner = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
      let l:spinner_idx = float2nr(l:elapsed * 10) % len(l:spinner)
      let l:spinner_char = l:spinner[l:spinner_idx]
      
      " Fall back to simpler characters if terminal might not support Unicode
      if !has('gui_running') && !has('nvim') && &encoding !~? 'utf'
        let l:spinner = ['-', '\', '|', '/']
        let l:spinner_idx = float2nr(l:elapsed * 4) % len(l:spinner)
        let l:spinner_char = l:spinner[l:spinner_idx]
      endif
      
      " Format status line
      if l:job.status == 'running'
        let l:status_line = l:spinner_char . ' ' . l:name . ' (' . l:elapsed_str . '): ' . a:message
      else
        " Use check mark or 'OK' based on terminal capabilities
        let l:check = has('gui_running') || has('nvim') || &encoding =~? 'utf' ? '✓' : 'OK'
        let l:status_line = l:check . ' ' . l:name . ' (' . l:elapsed_str . '): ' . a:message
      endif
      
      " Update the UI
      call plugin_manager#ui#update_job_progress(a:job_id, l:status_line)
    endif
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
    
    " Clean up job list
    call plugin_manager#jobs#clean_jobs()
    
    " Reset locks
    let s:jobs_operations_lock = 0
    
    " Clear job progress display
    call plugin_manager#ui#clear_job_progress()
    
    " Report any errors
    if !empty(l:stop_errors)
      for l:err in l:stop_errors
        call s:log_job_error(l:err)
      endfor
    endif
    
    return len(l:stop_errors) == 0
  endfunction
  
  " Run a sequence of commands asynchronously, chaining them together
  function! plugin_manager#jobs#run_sequence(commands, final_callback)
    " Prevent job operations from being nested
    if s:jobs_operations_lock
      call s:log_job_error('Job sequence already in progress, please wait')
      return -1
    endif
    
    " Set lock with timeout to prevent deadlocks
    let s:jobs_operations_lock = 1
    let l:timer_id = timer_start(10000, {-> s:release_jobs_operations_lock()})
    
    try
      let l:sequence = copy(a:commands)
      let l:results = []
      
      function! s:run_next(results, commands, final_callback, status, output) closure
        try
          " Add result of previous command
          call add(a:results, {'status': a:status, 'output': a:output, 'name': get(l:cmd, 'name', 'Command ' . len(a:results))})
          
          " If no more commands, we're done
          if empty(a:commands)
            call a:final_callback(a:results)
            return
          endif
          
          " Get next command and run it
          let l:cmd = remove(a:commands, 0)
          let l:name = get(l:cmd, 'name', 'Command ' . (len(a:results) + 1))
          
          " Create callbacks for this command
          let l:callbacks = {
                \ 'name': l:name,
                \ 'on_stdout': get(l:cmd, 'on_stdout', function('s:default_stdout')),
                \ 'on_stderr': get(l:cmd, 'on_stderr', function('s:default_stderr')),
                \ 'on_exit': function('s:run_next', [a:results, a:commands, a:final_callback]),
                \ }
          
          " Start the job
          call plugin_manager#jobs#start(l:cmd.cmd, l:callbacks)
        catch
          call s:log_job_error('Error in job sequence: ' . v:exception)
          
          " Call final callback with error state to ensure chain isn't broken
          call add(a:results, {'status': 1, 'output': 'Error: ' . v:exception, 'name': 'Error in job sequence'})
          call a:final_callback(a:results)
          
          " Make sure lock is released
          if s:jobs_operations_lock
            let s:jobs_operations_lock = 0
          endif
        endtry
      endfunction
      
      " Default callbacks
      function! s:default_stdout(msg)
        " Do nothing by default
      endfunction
      
      function! s:default_stderr(msg)
        " Do nothing by default
      endfunction
      
      " Start the first command
      if !empty(l:sequence)
        let l:cmd = remove(l:sequence, 0)
        let l:name = get(l:cmd, 'name', 'Command 1')
        
        " Create callbacks for this command
        let l:callbacks = {
              \ 'name': l:name,
              \ 'on_stdout': get(l:cmd, 'on_stdout', function('s:default_stdout')),
              \ 'on_stderr': get(l:cmd, 'on_stderr', function('s:default_stderr')),
              \ 'on_exit': function('s:run_next', [l:results, l:sequence, a:final_callback]),
              \ }
        
        " Start the job
        let l:job_id = plugin_manager#jobs#start(l:cmd.cmd, l:callbacks)
        
        " Check if job started successfully
        if l:job_id < 0
          throw "Failed to start job: " . l:cmd.cmd
        endif
        
        " The lock is now owned by the job chain
        call timer_stop(l:timer_id)
        return l:job_id
      else
        " No commands to run
        call a:final_callback([])
        let s:jobs_operations_lock = 0
        call timer_stop(l:timer_id)
        return 0
      endif
    catch
      call s:log_job_error('Error starting job sequence: ' . v:exception)
      
      " Try to call the callback with error information
      try
        call a:final_callback([{'status': 1, 'output': 'Error: ' . v:exception, 'name': 'Error starting sequence'}])
      catch
        " Silently fail if callback can't be called
      endtry
      
      return -1
    finally
      " Release the lock if we didn't start an async job chain successfully
      if !exists('l:job_id') || l:job_id < 0
        call timer_stop(l:timer_id)
        let s:jobs_operations_lock = 0
      endif
    endtry
  endfunction