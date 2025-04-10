" autoload/plugin_manager/async.vim - Asynchronous operations for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3.4

" ------------------------------------------------------------------------------
" PLATFORM DETECTION AND INITIALIZATION
" ------------------------------------------------------------------------------

" Detect Vim vs Neovim for appropriate async implementation
let s:is_nvim = has('nvim')
let s:has_async = s:is_nvim || (has('job') && has('channel'))

" Job tracking
let s:jobs = {}
let s:job_id_counter = 0
let s:exited_with_callback = {}

" Check if async is supported
function! plugin_manager#async#supported() abort
    return s:has_async
endfunction

" ------------------------------------------------------------------------------
" UNIFIED JOB INTERFACE
" ------------------------------------------------------------------------------

" Start a job asynchronously, with unified interface for Vim/Neovim
function! plugin_manager#async#start_job(cmd, opts) abort
    " If async is not supported, execute synchronously
    if !s:has_async
        let l:output = system(a:cmd)
        let l:status = v:shell_error
        
        if has_key(a:opts, 'callback')
            call a:opts.callback({
                \ 'id': -1,
                \ 'status': l:status,
                \ 'output': l:output
                \ })
        endif
        
        return -1
    endif
    
    " Generate a unique job ID
    let s:job_id_counter += 1
    let l:job_id = s:job_id_counter
    
    " Initialize job state
    let s:jobs[l:job_id] = {
        \ 'id': l:job_id,
        \ 'cmd': a:cmd,
        \ 'opts': a:opts,
        \ 'output': '',
        \ 'errors': '',
        \ 'status': -1,
        \ 'started': localtime(),
        \ 'finished': 0,
        \ 'job': v:null
        \ }
    
    " Change directory if specified
    let l:cmd = a:cmd
    if has_key(a:opts, 'dir') && !empty(a:opts.dir)
        let l:cmd = 'cd ' . shellescape(a:opts.dir) . ' && ' . l:cmd
    endif
    
    " Report job start to UI if needed
    if has_key(a:opts, 'ui_message') && !empty(a:opts.ui_message) && exists('*plugin_manager#ui#update_sidebar')
        call plugin_manager#ui#update_sidebar(['Starting: ' . a:opts.ui_message], 1)
    endif
    
    " Start the job with appropriate platform-specific method
    if s:is_nvim
        " Neovim implementation
        let l:job_opts = {
                \ 'on_stdout': function('s:nvim_callback'),
                \ 'on_stderr': function('s:nvim_callback'),
                \ 'on_exit': function('s:nvim_exit'),
                \ 'stdout_buffered': 1,
                \ 'stderr_buffered': 1,
                \ }
        
        let l:job = jobstart(['sh', '-c', l:cmd], l:job_opts)
        
        if l:job > 0
            let s:jobs[l:job_id].job = l:job
            let s:jobs[l:job_id].nvim_job_id = l:job
        else
            " Job failed to start
            let s:jobs[l:job_id].status = 127
            let s:jobs[l:job_id].finished = localtime()
            call s:process_job_completion(l:job_id)
            return -1
        endif
    else
        " Vim implementation
        let l:job_opts = {
                \ 'out_cb': function('s:vim_out_cb', [l:job_id]),
                \ 'err_cb': function('s:vim_err_cb', [l:job_id]),
                \ 'exit_cb': function('s:vim_exit_cb', [l:job_id]),
                \ 'mode': 'raw',
                \ }
        
        let l:job = job_start(['sh', '-c', l:cmd], l:job_opts)
        
        if job_status(l:job) !=# 'fail'
            let s:jobs[l:job_id].job = l:job
        else
            " Job failed to start
            let s:jobs[l:job_id].status = 127
            let s:jobs[l:job_id].finished = localtime()
            call s:process_job_completion(l:job_id)
            return -1
        endif
    endif
    
    return l:job_id
endfunction

" Stop a running job
function! plugin_manager#async#stop_job(job_id) abort
    if !has_key(s:jobs, a:job_id)
        return 0
    endif
    
    let l:job = s:jobs[a:job_id].job
    
    if s:is_nvim
        if jobstop(l:job)
            let s:jobs[a:job_id].status = -2  " Manually stopped
            let s:jobs[a:job_id].finished = localtime()
            call s:process_job_completion(a:job_id)
            return 1
        endif
    else
        if job_stop(l:job)
            let s:jobs[a:job_id].status = -2  " Manually stopped
            let s:jobs[a:job_id].finished = localtime()
            call s:process_job_completion(a:job_id)
            return 1
        endif
    endif
    
    return 0
endfunction

" Get job status
function! plugin_manager#async#job_status(job_id) abort
    if !has_key(s:jobs, a:job_id)
        return 'invalid'
    endif
    
    let l:job = s:jobs[a:job_id]
    
    if l:job.finished
        return 'finished'
    endif
    
    if s:is_nvim
        try
            let l:status = jobwait([l:job.nvim_job_id], 0)[0]
            return l:status == -1 ? 'running' : 'finished'
        catch
            return 'error'
        endtry
    else
        let l:status = job_status(l:job.job)
        return l:status ==# 'run' ? 'running' : 'finished'
    endif
endfunction

" Get job information
function! plugin_manager#async#job_info(job_id) abort
    if !has_key(s:jobs, a:job_id)
        return {}
    endif
    
    " Return a copy of job info to prevent modification
    return copy(s:jobs[a:job_id])
endfunction

" ------------------------------------------------------------------------------
" CALLBACKS AND HANDLERS
" ------------------------------------------------------------------------------

" Add a callback for when a job finishes
function! plugin_manager#async#on_complete(job_id, callback) abort
    if !has_key(s:jobs, a:job_id)
        return 0
    endif
    
    let s:jobs[a:job_id].callback = a:callback
    
    " If the job is already finished, call the callback immediately
    if s:jobs[a:job_id].finished
        call s:process_job_completion(a:job_id)
    endif
    
    return 1
endfunction

" Wait for a job to complete with timeout
function! plugin_manager#async#wait_job(job_id, timeout_ms) abort
    if !has_key(s:jobs, a:job_id)
        return -1
    endif
    
    let l:job = s:jobs[a:job_id]
    
    if l:job.finished
        return l:job.status
    endif
    
    let l:start_time = localtime()
    let l:end_time = l:start_time + (a:timeout_ms / 1000)
    
    while localtime() < l:end_time
        if s:is_nvim
            let l:status = jobwait([l:job.nvim_job_id], 10)[0]
            if l:status != -1
                return l:job.status
            endif
        else
            if job_status(l:job.job) !=# 'run'
                sleep 10m
                return l:job.status
            endif
        endif
        
        sleep 10m
    endwhile
    
    return -1
endfunction

" Clean up finished jobs older than a certain age
function! plugin_manager#async#cleanup(max_age_seconds) abort
    let l:now = localtime()
    let l:job_ids = keys(s:jobs)
    
    for l:id in l:job_ids
        let l:job = s:jobs[l:id]
        if l:job.finished && (l:now - l:job.finished) > a:max_age_seconds
            " Only remove jobs that have completed callbacks
            if has_key(s:exited_with_callback, l:id)
                unlet s:jobs[l:id]
                unlet s:exited_with_callback[l:id]
            endif
        endif
    endfor
endfunction

" ------------------------------------------------------------------------------
" HELPER FUNCTIONS FOR EXECUTING COMMON OPERATIONS
" ------------------------------------------------------------------------------

" Execute a git command asynchronously
function! plugin_manager#async#git(cmd, opts) abort
    " Default options
    let l:opts = {
        \ 'ui_message': get(a:opts, 'ui_message', ''),
        \ 'callback': get(a:opts, 'callback', v:null),
        \ 'dir': get(a:opts, 'dir', ''),
        \ }
    
    let l:job_id = plugin_manager#async#start_job(a:cmd, l:opts)
    
    if l:job_id > 0 && !empty(l:opts.callback)
        call plugin_manager#async#on_complete(l:job_id, l:opts.callback)
    endif
    
    return l:job_id
endfunction

" ------------------------------------------------------------------------------
" PLATFORM-SPECIFIC CALLBACK IMPLEMENTATIONS
" ------------------------------------------------------------------------------

" Neovim callbacks
function! s:nvim_callback(job_id, data, event) dict abort
    " Find our internal job ID from Neovim job ID
    let l:our_job_id = s:find_job_by_nvim_id(a:job_id)
    if l:our_job_id == 0
        return
    endif
    
    if a:event ==# 'stdout'
        let s:jobs[l:our_job_id].output .= join(a:data, "\n")
    elseif a:event ==# 'stderr'
        let s:jobs[l:our_job_id].errors .= join(a:data, "\n")
    endif
endfunction

function! s:nvim_exit(job_id, status, event) dict abort
    " Find our internal job ID from Neovim job ID
    let l:our_job_id = s:find_job_by_nvim_id(a:job_id)
    if l:our_job_id == 0
        return
    endif
    
    let s:jobs[l:our_job_id].status = a:status
    let s:jobs[l:our_job_id].finished = localtime()
    
    call s:process_job_completion(l:our_job_id)
endfunction

" Vim callbacks - FIXED with correct signatures
function! s:vim_out_cb(job_id, channel, msg) abort
    if !has_key(s:jobs, a:job_id)
        return
    endif
    
    let s:jobs[a:job_id].output .= a:msg
endfunction

function! s:vim_err_cb(job_id, channel, msg) abort
    if !has_key(s:jobs, a:job_id)
        return
    endif
    
    let s:jobs[a:job_id].errors .= a:msg
endfunction

function! s:vim_exit_cb(job_id, job, status) abort
    if !has_key(s:jobs, a:job_id)
        return
    endif
    
    let s:jobs[a:job_id].status = a:status
    let s:jobs[a:job_id].finished = localtime()
    
    call s:process_job_completion(a:job_id)
endfunction

" ------------------------------------------------------------------------------
" INTERNAL UTILITY FUNCTIONS
" ------------------------------------------------------------------------------

" Find our internal job ID from Neovim job ID
function! s:find_job_by_nvim_id(nvim_job_id) abort
    for [l:id, l:job] in items(s:jobs)
        if get(l:job, 'nvim_job_id', 0) == a:nvim_job_id
            return l:id
        endif
    endfor
    
    return 0
endfunction

" Process job completion and call callback if provided
function! s:process_job_completion(job_id) abort
    if !has_key(s:jobs, a:job_id)
        return
    endif
    
    let l:job = s:jobs[a:job_id]
    
    " Report job completion to UI if needed
    if has_key(l:job.opts, 'ui_message') && !empty(l:job.opts.ui_message) && exists('*plugin_manager#ui#update_sidebar')
        let l:success = l:job.status == 0
        let l:status_msg = l:success ? 'Completed' : 'Failed with status ' . l:job.status
        call plugin_manager#ui#update_sidebar([l:status_msg . ': ' . l:job.opts.ui_message], 1)
    
        " Show output if requested
        if get(l:job.opts, 'ui_show_output', 0) && !empty(l:job.output)
            call plugin_manager#ui#update_sidebar(split(l:job.output, "\n"), 1)
        endif
    
        " Show errors if there are any
        if !empty(l:job.errors)
            call plugin_manager#ui#update_sidebar(['Errors:'], 1)
            call plugin_manager#ui#update_sidebar(split(l:job.errors, "\n"), 1)
        endif
    endif
    
    " Call the callback if provided
    if has_key(l:job, 'callback') && !empty(l:job.callback)
        try
            call l:job.callback({
                \ 'id': a:job_id,
                \ 'status': l:job.status,
                \ 'output': l:job.output,
                \ 'errors': l:job.errors,
                \ 'cmd': l:job.cmd
                \ })
        
            " Mark that callback was called
            let s:exited_with_callback[a:job_id] = 1
        catch
            " Handle callback errors
            echohl ErrorMsg
            echomsg "Error in async callback: " . v:exception
            echohl None
        endtry
    endif
endfunction