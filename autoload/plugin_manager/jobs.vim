" autoload/plugin_manager/jobs.vim - Asynchronous job management for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4

" Internal state variables
let s:job_list = {}          " List of running jobs with their handlers
let s:has_job_support = 0    " Whether async jobs are supported
let s:job_id_counter = 1     " Counter for generating unique job IDs
let s:spinner_frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
let s:fallback_frames = ['-', '\\', '|', '/']
let s:spinner_idx = 0
let s:use_unicode = 1        " Whether to use Unicode characters
let s:update_timer_id = -1   " Timer ID for UI updates

" Initialize the job system and check capabilities
function! plugin_manager#jobs#init() abort
  " Check if Vim/Neovim supports async jobs
  if !exists('s:has_job_support')
    if has('nvim')
      " Neovim job support (jobstart function)
      let s:has_job_support = exists('*jobstart')
    else
      " Vim job support (job_start function and patch level)
      let s:has_job_support = exists('*job_start') && (v:version > 800 || (v:version == 800 && has('patch12')))
    endif
  endif

  " Check terminal capabilities for Unicode
  if !exists('s:use_unicode')
    let s:use_unicode = &encoding =~? 'utf-\?8'
  endif

  " Verify real terminal support 
  if s:use_unicode
    try
      call matchstr("✓", "✓")
    catch
      " If we get an error, disable Unicode
      let s:use_unicode = 0
    endtry
  endif

  return s:has_job_support
endfunction

" Get appropriate spinner frames based on terminal capabilities
function! plugin_manager#jobs#get_spinner_frames() abort
  return s:use_unicode ? s:spinner_frames : s:fallback_frames
endfunction

" Get appropriate check mark based on terminal capabilities
function! plugin_manager#jobs#get_success_mark() abort
  return s:use_unicode ? '✓' : '+'
endfunction

" Get appropriate failure mark based on terminal capabilities
function! plugin_manager#jobs#get_failure_mark() abort
  return s:use_unicode ? '✗' : 'x'
endfunction

" Function to start an asynchronous job with proper abstraction
function! plugin_manager#jobs#start(cmd, options) abort
  if !plugin_manager#jobs#init()
    " If async jobs aren't supported, fall back to synchronous execution
    return plugin_manager#jobs#start_sync(a:cmd, a:options)
  endif

  " Generate unique job ID
  let l:job_id = 's:job_' . s:job_id_counter
  let s:job_id_counter += 1

  " Extract handlers from options
  let l:stdout_handler = get(a:options, 'on_stdout', function('s:default_stdout_handler'))
  let l:stderr_handler = get(a:options, 'on_stderr', function('s:default_stderr_handler'))
  let l:exit_handler = get(a:options, 'on_exit', function('s:default_exit_handler'))
  let l:title = get(a:options, 'title', 'Running job')
  let l:job_data = get(a:options, 'job_data', {})

  " Create job data structure with state
  let l:job_data = extend(l:job_data, {
        \ 'id': l:job_id,
        \ 'status': 'running',
        \ 'output': [],
        \ 'title': l:title,
        \ 'stdout': [],
        \ 'stderr': [],
        \ 'exit_code': -1,
        \ 'start_time': localtime(),
        \ 'cmd': a:cmd,
        \ })

  " Start job according to Vim/Neovim API
  if has('nvim')
    " Neovim job start
    let l:job_opts = {
          \ 'on_stdout': function('s:nvim_on_stdout', [l:stdout_handler, l:job_id]),
          \ 'on_stderr': function('s:nvim_on_stderr', [l:stderr_handler, l:job_id]),
          \ 'on_exit': function('s:nvim_on_exit', [l:exit_handler, l:job_id]),
          \ 'stdout_buffered': 1,
          \ 'stderr_buffered': 1,
          \ }
    
    if type(a:cmd) == v:t_list
      let l:job = jobstart(a:cmd, l:job_opts)
    else
      let l:job = jobstart(a:cmd, l:job_opts)
    endif
    
    if l:job <= 0
      " Job creation failed
      let l:job_data.status = 'failed'
      let l:job_data.exit_code = -1
      let l:job_data.stderr = ['Failed to start job: ' . a:cmd]
      call l:exit_handler(l:job_data)
      return 0
    endif
  else
    " Vim job start
    let l:job_opts = {
          \ 'out_cb': function('s:vim_on_stdout', [l:stdout_handler, l:job_id]),
          \ 'err_cb': function('s:vim_on_stderr', [l:stderr_handler, l:job_id]),
          \ 'exit_cb': function('s:vim_on_exit', [l:exit_handler, l:job_id]),
          \ 'mode': 'raw',
          \ }
    
    if type(a:cmd) == v:t_list
      let l:job = job_start(a:cmd, l:job_opts)
    else
      let l:job = job_start([&shell, &shellcmdflag, a:cmd], l:job_opts)
    endif
    
    if job_status(l:job) ==# 'fail'
      " Job creation failed
      let l:job_data.status = 'failed'
      let l:job_data.exit_code = -1
      let l:job_data.stderr = ['Failed to start job: ' . a:cmd]
      call l:exit_handler(l:job_data)
      return 0
    endif
  endif

  " Store job information
  let l:job_data.job = l:job
  let s:job_list[l:job_id] = l:job_data

  " Start UI update timer if not already running
  call s:ensure_update_timer()

  " Start or update spinner
  call plugin_manager#ui#update_job_status(l:job_data)

  return l:job_id
endfunction

" Fallback to synchronous execution when async isn't available
function! plugin_manager#jobs#start_sync(cmd, options) abort
  let l:title = get(a:options, 'title', 'Running job')
  let l:exit_handler = get(a:options, 'on_exit', function('s:default_exit_handler'))
  let l:job_data = get(a:options, 'job_data', {})

  " Create job data structure
  let l:job_id = 's:job_' . s:job_id_counter
  let s:job_id_counter += 1
  
  let l:job_data = extend(l:job_data, {
        \ 'id': l:job_id,
        \ 'status': 'running',
        \ 'title': l:title,
        \ 'stdout': [],
        \ 'stderr': [],
        \ 'exit_code': -1,
        \ 'start_time': localtime(),
        \ 'cmd': a:cmd,
        \ 'sync': 1,
        \ })

  " Display initial status
  call plugin_manager#ui#update_sidebar(['Executing: ' . l:title . ' (sync)'], 1)

  " Execute command synchronously
  let l:output = system(a:cmd)
  let l:exit_code = v:shell_error

  " Update job data
  let l:job_data.status = l:exit_code == 0 ? 'done' : 'failed'
  let l:job_data.exit_code = l:exit_code
  let l:job_data.stdout = split(l:output, "\n")
  
  " Call exit handler
  call l:exit_handler(l:job_data)
  
  return l:job_id
endfunction

" Get job info by ID
function! plugin_manager#jobs#get_info(job_id) abort
  return get(s:job_list, a:job_id, {})
endfunction

" Stop a running job
function! plugin_manager#jobs#stop(job_id) abort
  if !has_key(s:job_list, a:job_id)
    return 0
  endif
  
  let l:job_data = s:job_list[a:job_id]
  
  if l:job_data.status !=# 'running'
    return 0
  endif
  
  " Stop according to Vim/Neovim API
  if has('nvim')
    call jobstop(l:job_data.job)
  else
    call job_stop(l:job_data.job)
  endif
  
  let l:job_data.status = 'stopped'
  call plugin_manager#ui#update_job_status(l:job_data)
  
  return 1
endfunction

" Check if any jobs are running
function! plugin_manager#jobs#any_running() abort
  for [l:job_id, l:job_data] in items(s:job_list)
    if l:job_data.status ==# 'running'
      return 1
    endif
  endfor
  return 0
endfunction

" Default stdout handler
function! s:default_stdout_handler(job_data, output) abort
  let l:job_data = a:job_data
  call extend(l:job_data.stdout, a:output)
  call plugin_manager#ui#update_job_status(l:job_data)
endfunction

" Default stderr handler
function! s:default_stderr_handler(job_data, output) abort
  let l:job_data = a:job_data
  call extend(l:job_data.stderr, a:output)
  call plugin_manager#ui#update_job_status(l:job_data)
endfunction

" Default exit handler
function! s:default_exit_handler(job_data) abort
  let l:job_data = a:job_data
  let l:job_data.status = l:job_data.exit_code == 0 ? 'done' : 'failed'
  
  " Update UI with completion status
  call plugin_manager#ui#update_job_status(l:job_data)
  
  " Check if all jobs are done and stop the update timer if so
  if !plugin_manager#jobs#any_running()
    call s:stop_update_timer()
  endif
endfunction

" Nvim stdout handler
function! s:nvim_on_stdout(handler, job_id, job, data, event) abort
  if !has_key(s:job_list, a:job_id)
    return
  endif
  
  let l:job_data = s:job_list[a:job_id]
  
  " Filter out empty lines that Neovim tends to include
  let l:filtered_data = filter(copy(a:data), 'v:val !=# ""')
  if !empty(l:filtered_data)
    call a:handler(l:job_data, l:filtered_data)
  endif
endfunction

" Nvim stderr handler
function! s:nvim_on_stderr(handler, job_id, job, data, event) abort
  if !has_key(s:job_list, a:job_id)
    return
  endif
  
  let l:job_data = s:job_list[a:job_id]
  
  " Filter out empty lines that Neovim tends to include
  let l:filtered_data = filter(copy(a:data), 'v:val !=# ""')
  if !empty(l:filtered_data)
    call a:handler(l:job_data, l:filtered_data)
  endif
endfunction

" Nvim exit handler
function! s:nvim_on_exit(handler, job_id, job, exit_code, event) abort
  if !has_key(s:job_list, a:job_id)
    return
  endif
  
  let l:job_data = s:job_list[a:job_id]
  let l:job_data.exit_code = a:exit_code
  let l:job_data.end_time = localtime()
  
  call a:handler(l:job_data)
endfunction

" Vim stdout handler
function! s:vim_on_stdout(handler, job_id, channel, msg) abort
  if !has_key(s:job_list, a:job_id)
    return
  endif
  
  let l:job_data = s:job_list[a:job_id]
  
  " Process message and split into lines
  let l:lines = split(a:msg, "\n")
  if !empty(l:lines)
    call a:handler(l:job_data, l:lines)
  endif
endfunction

" Vim stderr handler
function! s:vim_on_stderr(handler, job_id, channel, msg) abort
  if !has_key(s:job_list, a:job_id)
    return
  endif
  
  let l:job_data = s:job_list[a:job_id]
  
  " Process message and split into lines
  let l:lines = split(a:msg, "\n")
  if !empty(l:lines)
    call a:handler(l:job_data, l:lines)
  endif
endfunction

" Vim exit handler
function! s:vim_on_exit(handler, job_id, job, exit_code) abort
  if !has_key(s:job_list, a:job_id)
    return
  endif
  
  let l:job_data = s:job_list[a:job_id]
  let l:job_data.exit_code = a:exit_code
  let l:job_data.end_time = localtime()
  
  call a:handler(l:job_data)
endfunction

" Timer to update spinner and job status
function! s:update_timer_callback(timer_id) abort
  " Update spinner index
  let s:spinner_idx = (s:spinner_idx + 1) % len(s:use_unicode ? s:spinner_frames : s:fallback_frames)
  
  " Update UI for all running jobs
  for [l:job_id, l:job_data] in items(s:job_list)
    if l:job_data.status ==# 'running'
      call plugin_manager#ui#update_job_status(l:job_data)
    endif
  endfor
endfunction

" Start update timer if not already running
function! s:ensure_update_timer() abort
  if s:update_timer_id == -1
    " Start timer with 100ms interval for spinner updates
    if has('nvim')
      let s:update_timer_id = timer_start(100, function('s:update_timer_callback'), {'repeat': -1})
    else
      let s:update_timer_id = timer_start(100, function('s:update_timer_callback'), {'repeat': -1})
    endif
  endif
endfunction

" Stop update timer
function! s:stop_update_timer() abort
  if s:update_timer_id != -1
    call timer_stop(s:update_timer_id)
    let s:update_timer_id = -1
  endif
endfunction

" Get current spinner frame
function! plugin_manager#jobs#get_spinner_frame() abort
  let l:frames = s:use_unicode ? s:spinner_frames : s:fallback_frames
  return l:frames[s:spinner_idx]
endfunction

" Clean up job from the list (called after a job is done)
function! plugin_manager#jobs#cleanup(job_id) abort
  if has_key(s:job_list, a:job_id)
    call remove(s:job_list, a:job_id)
  endif
endfunction

" Run multiple jobs in sequence
function! plugin_manager#jobs#run_sequence(jobs, final_callback) abort
  if empty(a:jobs)
    call a:final_callback({'success': 1})
    return
  endif
  
  let l:job_seq = {
        \ 'jobs': copy(a:jobs),
        \ 'results': [],
        \ 'index': 0,
        \ 'final_callback': a:final_callback,
        \ }
  
  " Start first job
  call s:run_next_job_in_sequence(l:job_seq)
endfunction

" Show jobs status
function! plugin_manager#jobs#show_status() abort
  let l:header = ['Plugin Manager Jobs:', '-------------------', '']
  
  if !plugin_manager#jobs#any_running()
    call plugin_manager#ui#open_sidebar(l:header + ['No active jobs.'])
    return
  endif
  
  call plugin_manager#ui#open_sidebar(l:header)
  " The UI will be updated automatically via timer callbacks
endfunction

" Cancel a specific job
function! plugin_manager#jobs#cancel(job_id) abort
  if plugin_manager#jobs#stop(a:job_id)
    call plugin_manager#ui#open_sidebar(['Job Cancelled:', '-------------', '', 'Job ' . a:job_id . ' has been cancelled.'])
  else
    call plugin_manager#ui#open_sidebar(['Error:', '------', '', 'Failed to cancel job ' . a:job_id . ' or job not found.'])
  endif
endfunction

" Cancel all running jobs
function! plugin_manager#jobs#cancel_all() abort
  let l:header = ['Cancelling Jobs:', '---------------', '']
  call plugin_manager#ui#open_sidebar(l:header)
  
  let l:cancelled = 0
  
  " Go through all running jobs and stop them
  for [l:job_id, l:job_data] in items(s:job_list)
    if l:job_data.status ==# 'running'
      call plugin_manager#jobs#stop(l:job_id)
      let l:cancelled += 1
    endif
  endfor
  
  call plugin_manager#ui#update_sidebar(['Cancelled ' . l:cancelled . ' running job' . (l:cancelled != 1 ? 's' : '') . '.'], 1)
endfunction

" Helper function to run the next job in a sequence
function! s:run_next_job_in_sequence(seq) abort
  if a:seq.index >= len(a:seq.jobs)
    " All jobs done, call final callback
    call a:seq.final_callback({'success': 1, 'results': a:seq.results})
    return
  endif
  
  let l:job_info = a:seq.jobs[a:seq.index]
  
  " Create new options with a custom exit handler
  let l:options = copy(get(l:job_info, 'options', {}))
  let l:original_exit = get(l:options, 'on_exit', function('s:default_exit_handler'))
  let l:options.on_exit = function('s:sequence_job_exit', [l:original_exit, a:seq])
  
  " Start the job
  let l:job_id = plugin_manager#jobs#start(l:job_info.cmd, l:options)
  if !l:job_id
    " Job failed to start, stop sequence
    call a:seq.final_callback({'success': 0, 'message': 'Failed to start job', 'results': a:seq.results})
  endif
endfunction

" Exit handler for sequential jobs
function! s:sequence_job_exit(original_handler, seq, job_data) abort
  " Call original handler
  call a:original_handler(a:job_data)
  
  " Add result to sequence results
  call add(a:seq.results, a:job_data)
  
  " Move to next job or stop on error
  if a:job_data.exit_code == 0
    let a:seq.index += 1
    call s:run_next_job_in_sequence(a:seq)
  else
    " Failed job, stop sequence
    call a:seq.final_callback({
          \ 'success': 0, 
          \ 'message': 'Job failed with exit code ' . a:job_data.exit_code,
          \ 'results': a:seq.results,
          \ 'failed_job': a:job_data
          \ })
  endif
endfunction