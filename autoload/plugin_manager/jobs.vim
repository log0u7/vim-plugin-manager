" autoload/plugin_manager/jobs.vim - Asynchronous jobs handling for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4

" Global job state variables
let s:jobs = {}
let s:job_id_counter = 0
let s:locks = {}
let s:spinner_chars = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
let s:spinner_idx = 0
let s:spinner_timer = 0
let s:status_line = ''

" Feature detection for async support
let s:has_async = 0
let s:async_type = ''

" Detect what type of async support is available
function! s:detect_async_support()
  if has('nvim')
    let s:has_async = 1
    let s:async_type = 'nvim'
    return 1
  elseif has('job') && has('channel') && has('timers')
    let s:has_async = 1
    let s:async_type = 'vim'
    return 1
  else
    let s:has_async = 0
    let s:async_type = 'none'
    return 0
  endif
endfunction

call s:detect_async_support()

" Start a spinner timer
function! s:start_spinner()
  if s:spinner_timer == 0 && s:has_async 
    let s:spinner_timer = timer_start(100, function('s:update_spinner'), {'repeat': -1})
  endif
endfunction

" Update spinner animation frame
function! s:update_spinner(timer)
  let s:spinner_idx = (s:spinner_idx + 1) % len(s:spinner_chars)
  
  " Only update if there are active jobs
  if !empty(s:jobs)
    call s:refresh_job_status()
  else
    call s:stop_spinner()
  endif
endfunction

" Stop the spinner
function! s:stop_spinner()
  if s:spinner_timer != 0
    call timer_stop(s:spinner_timer)
    let s:spinner_timer = 0
  endif
endfunction

" Refresh the UI with current job status
function! s:refresh_job_status()
  let l:active_count = len(s:jobs)
  
  if l:active_count > 0
    " Get current spinner character
    let l:spinner = s:spinner_chars[s:spinner_idx]
    
    " Create status message
    let l:message = l:spinner . ' ' . l:active_count . ' job(s) running...'
    
    " Add specific job info
    for [l:id, l:job] in items(s:jobs)
      let l:message .= "\n  - " . l:job.description
      if has_key(l:job, 'progress') && l:job.progress > 0
        let l:message .= ' (' . l:job.progress . '%)'
      endif
    endfor
    
    " Update the status in the UI
    if l:message != s:status_line
      let s:status_line = l:message
      call plugin_manager#ui#update_job_status(l:message)
    endif
  else
    call plugin_manager#ui#clear_job_status()
    let s:status_line = ''
  endif
endfunction

" Check if a job with the given name exists and is running
function! plugin_manager#jobs#is_running(job_name)
  for [l:id, l:job] in items(s:jobs)
    if l:job.name ==# a:job_name
      return 1
    endif
  endfor
  return 0
endfunction

" Acquire a lock for a job
function! plugin_manager#jobs#acquire_lock(lock_name)
  if has_key(s:locks, a:lock_name) && s:locks[a:lock_name]
    return 0
  endif
  
  let s:locks[a:lock_name] = 1
  return 1
endfunction

" Release a lock
function! plugin_manager#jobs#release_lock(lock_name)
  let s:locks[a:lock_name] = 0
endfunction

" Common function to handle job completion
function! s:job_complete(job_id, status, output)
  if has_key(s:jobs, a:job_id)
    let l:job = s:jobs[a:job_id]
    
    " Release lock if one was used
    if has_key(l:job, 'lock') && !empty(l:job.lock)
      call plugin_manager#jobs#release_lock(l:job.lock)
    endif
    
    " Call completion callback with output and status
    if has_key(l:job, 'on_complete') && type(l:job.on_complete) == v:t_func
      call l:job.on_complete(a:status, a:output)
    endif
    
    " Remove job from active jobs
    call remove(s:jobs, a:job_id)
    
    " Stop spinner if no more jobs
    if empty(s:jobs)
      call s:stop_spinner()
    endif
    
    " Update UI
    call s:refresh_job_status()
  endif
endfunction

" Handle job output for Vim jobs
function! s:vim_job_out(channel, msg)
  let l:job = ch_getjob(a:channel)
  let l:job_id = string(l:job)
  
  if has_key(s:jobs, l:job_id)
    call add(s:jobs[l:job_id].output, a:msg)
  endif
endfunction

" Handle job errors for Vim jobs
function! s:vim_job_err(channel, msg)
  let l:job = ch_getjob(a:channel)
  let l:job_id = string(l:job)
  
  if has_key(s:jobs, l:job_id)
    call add(s:jobs[l:job_id].errors, a:msg)
  endif
endfunction

" Handle job exit for Vim jobs
function! s:vim_job_exit(job, status)
  let l:job_id = string(a:job)
  
  if has_key(s:jobs, l:job_id)
    " Combine output and errors
    let l:output = s:jobs[l:job_id].output + s:jobs[l:job_id].errors
    
    " Call common completion handler
    call s:job_complete(l:job_id, a:status, l:output)
  endif
endfunction

" Handle all Neovim job callbacks
function! s:nvim_job_handler(job_id, data, event)
  let l:string_id = string(a:job_id)
  
  if !has_key(s:jobs, l:string_id)
    return
  endif
  
  if a:event == 'stdout'
    if !empty(a:data) && a:data[0] != ''
      call extend(s:jobs[l:string_id].output, a:data)
    endif
  elseif a:event == 'stderr'
    if !empty(a:data) && a:data[0] != ''
      call extend(s:jobs[l:string_id].errors, a:data)
    endif
  elseif a:event == 'exit'
    " Combine output and errors, and filter empty lines
    let l:output = filter(s:jobs[l:string_id].output + s:jobs[l:string_id].errors, 'v:val != ""')
    
    " Call common completion handler
    call s:job_complete(l:string_id, a:data, l:output)
  endif
endfunction

" Start a new job (asynchronously if supported)
function! plugin_manager#jobs#start(cmd, options)
  " Generate a unique job ID
  let s:job_id_counter += 1
  let l:job_id = s:job_id_counter
  
  " Prepare job data structure
  let l:job = {
        \ 'id': l:job_id,
        \ 'name': get(a:options, 'name', 'job-' . l:job_id),
        \ 'description': get(a:options, 'description', a:cmd),
        \ 'output': [],
        \ 'errors': [],
        \ 'lock': get(a:options, 'lock', ''),
        \ 'on_complete': get(a:options, 'on_complete', 0),
        \ 'progress': 0,
        \ 'cmd': a:cmd
        \ }
  
  " Try to acquire lock if specified
  if !empty(l:job.lock) && !plugin_manager#jobs#acquire_lock(l:job.lock)
    " Lock not available, call completion callback with error
    if type(l:job.on_complete) == v:t_func
      call l:job.on_complete(1, ['Error: Another job is currently using this resource'])
    endif
    return -1
  endif
  
  " Start spinner
  call s:start_spinner()
  
  " Start job based on available async support
  if s:has_async
    let l:string_job_id = ''
    
    if s:async_type == 'nvim'
      " Start job with Neovim's job API
      let l:job_obj = jobstart(a:cmd, {
            \ 'on_stdout': function('s:nvim_job_handler'),
            \ 'on_stderr': function('s:nvim_job_handler'),
            \ 'on_exit': function('s:nvim_job_handler')
            \ })
      
      let l:string_job_id = string(l:job_obj)
      let l:job.job_obj = l:job_obj
      
    elseif s:async_type == 'vim'
      " Start job with Vim's job API
      let l:job_obj = job_start(a:cmd, {
            \ 'out_cb': function('s:vim_job_out'),
            \ 'err_cb': function('s:vim_job_err'),
            \ 'exit_cb': function('s:vim_job_exit')
            \ })
      
      let l:string_job_id = string(l:job_obj)
      let l:job.job_obj = l:job_obj
    endif
    
    " Store job by its string ID
    let s:jobs[l:string_job_id] = l:job
    
    " Update UI
    call s:refresh_job_status()
    
    return l:string_job_id
  else
    " Fallback to synchronous execution
    let l:output = system(a:cmd)
    let l:status = v:shell_error
    
    " Split output into lines
    let l:output_lines = split(l:output, "\n")
    
    " Call the completion callback directly
    if type(l:job.on_complete) == v:t_func
      call l:job.on_complete(l:status, l:output_lines)
    endif
    
    " Release lock if one was acquired
    if !empty(l:job.lock)
      call plugin_manager#jobs#release_lock(l:job.lock)
    endif
    
    return -1
  endif
endfunction

" Stop a specific job
function! plugin_manager#jobs#stop(job_id)
  if !has_key(s:jobs, a:job_id)
    return 0
  endif
  
  let l:job = s:jobs[a:job_id]
  
  if s:async_type == 'nvim'
    call jobstop(l:job.job_obj)
  elseif s:async_type == 'vim'
    call job_stop(l:job.job_obj)
  endif
  
  " Mark job as cancelled in completion handler
  call s:job_complete(a:job_id, -1, ['Job cancelled by user'])
  
  return 1
endfunction

" Stop all running jobs
function! plugin_manager#jobs#stop_all()
  for l:job_id in keys(s:jobs)
    call plugin_manager#jobs#stop(l:job_id)
  endfor
  
  call s:stop_spinner()
  return len(keys(s:jobs))
endfunction

" List all running jobs
function! plugin_manager#jobs#list()
  let l:jobs_list = []
  
  for [l:id, l:job] in items(s:jobs)
    call add(l:jobs_list, {
          \ 'id': l:id,
          \ 'name': l:job.name,
          \ 'description': l:job.description,
          \ 'progress': get(l:job, 'progress', 0)
          \ })
  endfor
  
  return l:jobs_list
endfunction

" Update job progress
function! plugin_manager#jobs#update_progress(job_id, progress)
  if has_key(s:jobs, a:job_id)
    let s:jobs[a:job_id].progress = a:progress
    call s:refresh_job_status()
    return 1
  endif
  
  return 0
endfunction

" Check if async jobs are supported
function! plugin_manager#jobs#has_async()
  return s:has_async
endfunction

" Get the type of async support
function! plugin_manager#jobs#async_type()
  return s:async_type
endfunction