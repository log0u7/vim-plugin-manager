" Asynchronous job functions for vim-plugin-manager
" This implementation uses Vim's job API to run commands asynchronously

" Store job-related metadata
let s:job_data = {
  \ 'active_jobs': {},
  \ 'job_count': 0,
  \ 'last_job_id': 0,
  \ 'job_output': {},
  \ 'job_status': {}
\}

" Execute command asynchronously with output directed to sidebar
function! plugin_manager#jobs#execute(title, cmd, callback, ...)
    " Generate a unique job ID
    let s:job_data.last_job_id += 1
    let l:job_id = s:job_data.last_job_id
    
    " Ensure we're in the Vim directory
    if !plugin_manager#utils#ensure_vim_directory()
      return -1
    endif
    
    " Create initial header
    let l:header = [a:title, repeat('-', len(a:title)), '']
    let l:initial_message = l:header + ['Executing operation asynchronously, please wait...']
    
    " Create or update sidebar window with initial message
    call plugin_manager#ui#open_sidebar(l:initial_message)
    
    " Initialize job output storage
    let s:job_data.job_output[l:job_id] = []
    let s:job_data.job_status[l:job_id] = {
      \ 'title': a:title,
      \ 'header': l:header,
      \ 'cmd': a:cmd,
      \ 'callback': a:callback,
      \ 'args': a:000,
      \ 'start_time': localtime()
    \}
    
    " Check if Vim supports job feature
    if !has('job')
      call s:fallback_sync_execution(l:job_id, a:cmd)
      return l:job_id
    endif
    
    " Configure job options
    let l:job_opts = {
      \ 'out_cb': function('s:job_output_callback', [l:job_id]),
      \ 'err_cb': function('s:job_error_callback', [l:job_id]),
      \ 'exit_cb': function('s:job_exit_callback', [l:job_id])
    \}
    
    " Start the job
    let l:job = job_start([&shell, &shellcmdflag, a:cmd], l:job_opts)
    
    " Check if job started successfully
    if job_status(l:job) == "fail"
      call plugin_manager#ui#update_sidebar(['Failed to start job. Using synchronous fallback.'], 1)
      call s:fallback_sync_execution(l:job_id, a:cmd)
    else
      let s:job_data.active_jobs[l:job_id] = l:job
      let s:job_data.job_count += 1
      call plugin_manager#ui#update_sidebar(['Job started with ID: ' . l:job_id], 1)
    endif
    
    return l:job_id
endfunction

" Fallback to synchronous execution if jobs aren't supported
function! s:fallback_sync_execution(job_id, cmd)
    let l:job_status = s:job_data.job_status[a:job_id]
    call plugin_manager#ui#update_sidebar(['Using synchronous execution (jobs not supported)...'], 1)
    
    " Execute command and collect output
    let l:output = system(a:cmd)
    let l:exit_status = v:shell_error
    let l:output_lines = split(l:output, "\n")
    
    " Store output
    let s:job_data.job_output[a:job_id] = l:output_lines
    
    " Call exit callback manually
    call s:job_exit_callback(a:job_id, 0, l:exit_status)
endfunction

" Handle job output
function! s:job_output_callback(job_id, channel, msg) abort
    " Append output to job data
    let l:lines = split(a:msg, "\n")
    call extend(s:job_data.job_output[a:job_id], l:lines)
    
    " Update the sidebar with new output (limit to last few lines)
    let l:display_lines = s:job_data.job_status[a:job_id].header + 
          \ ['Job progress:'] + s:get_last_n_lines(s:job_data.job_output[a:job_id], 10)
    call plugin_manager#ui#update_sidebar(l:display_lines, 0)
endfunction

" Handle job errors
function! s:job_error_callback(job_id, channel, msg) abort
    " Append errors to job data - mark them for display
    let l:lines = split(a:msg, "\n")
    for l:line in l:lines
        call add(s:job_data.job_output[a:job_id], 'ERROR: ' . l:line)
    endfor
    
    " Update the sidebar with error information
    let l:display_lines = s:job_data.job_status[a:job_id].header + 
          \ ['Job encountered errors:'] + s:get_last_n_lines(s:job_data.job_output[a:job_id], 10)
    call plugin_manager#ui#update_sidebar(l:display_lines, 0)
endfunction

" Handle job completion
function! s:job_exit_callback(job_id, job, status) abort
    " Record job completion
    if has_key(s:job_data.active_jobs, a:job_id)
      let s:job_data.job_count -= 1
      unlet s:job_data.active_jobs[a:job_id]
    endif
    
    let l:job_status = s:job_data.job_status[a:job_id]
    
    " Format job result
    let l:all_output = s:job_data.job_output[a:job_id]
    let l:final_output = l:job_status.header
    
    if a:status == 0
        call add(l:final_output, 'Operation completed successfully.')
    else
        call add(l:final_output, 'Operation failed with exit code: ' . a:status)
    endif
    
    call add(l:final_output, '')
    call extend(l:final_output, l:all_output)
    call add(l:final_output, '')
    call add(l:final_output, 'Press q to close this window...')
    
    " Update sidebar with final content
    call plugin_manager#ui#update_sidebar(l:final_output, 0)
    
    " Execute callback if provided
    if !empty(l:job_status.callback)
        try
            " Pass all job information to the callback
            call call(l:job_status.callback, [a:job_id, a:status, l:all_output] + l:job_status.args)
        catch
            call plugin_manager#ui#update_sidebar(['Error in callback: ' . v:exception], 1)
        endtry
    endif
    
    " Clean up job data after a delay (keep for reference)
    call timer_start(60000, function('s:cleanup_job_data', [a:job_id]))
endfunction

" Get the last N lines from an array
function! s:get_last_n_lines(lines, n)
    let l:count = len(a:lines)
    if l:count <= a:n
        return a:lines
    else
        return a:lines[l:count - a:n : l:count - 1]
    endif
endfunction

" Clean up job data after some time
function! s:cleanup_job_data(job_id, timer)
    if has_key(s:job_data.job_output, a:job_id)
        unlet s:job_data.job_output[a:job_id]
    endif
    if has_key(s:job_data.job_status, a:job_id)
        unlet s:job_data.job_status[a:job_id]
    endif
endfunction

" Check if jobs are running
function! plugin_manager#jobs#running()
    return s:job_data.job_count > 0
endfunction

" Cancel all running jobs
function! plugin_manager#jobs#cancel_all()
    for [l:job_id, l:job] in items(s:job_data.active_jobs)
        call job_stop(l:job, 'kill')
    endfor
    let s:job_data.active_jobs = {}
    let s:job_data.job_count = 0
    
    call plugin_manager#ui#update_sidebar(['All jobs cancelled.'], 1)
endfunction