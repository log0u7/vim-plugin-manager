" autoload/plugin_manager/async.vim - Asynchronous operations for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 2.0.0

" ------------------------------------------------------------------------------
" PLATFORM DETECTION AND INITIALIZATION
" ------------------------------------------------------------------------------

" Async support requires Vim compiled with +job and +channel.
" Neovim is not supported (see plugin/plugin_manager.vim guard).
let s:has_async = has('job') && has('channel')

" Job tracking
let s:jobs = {}
let s:job_id_counter = 0
let s:exited_with_callback = {}

" Concurrency control
let s:active_count = 0
let s:job_queue = []

" Check if async is supported
function! plugin_manager#async#supported() abort
    return s:has_async
endfunction

" Build the argv list to pass to job_start().
" The project targets Linux only, so sh -c is always correct.
" Exposed as a public function so tests can verify the shape without
" depending on actually starting a job.
function! plugin_manager#async#shell_argv(cmd) abort
    return ['sh', '-c', a:cmd]
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
            " Match the async callback dict shape (errors, cmd) so callers
            " work identically regardless of whether +job is available.
            call a:opts.callback({
                \ 'id':     -1,
                \ 'status': l:status,
                \ 'output': l:output,
                \ 'errors': '',
                \ 'cmd':    a:cmd
                \ })
        endif
        
        return -1
    endif
    
    " Generate a unique job ID
    let s:job_id_counter += 1
    let l:job_id = s:job_id_counter
    
    " Initialize job state.
    " Promote opts.callback to the top-level 'callback' key so that
    " s:process_job_completion can find it without having to dig into opts.
    " Callers that pass the callback via opts (start_job) and callers that
    " register it later via on_complete() both land in the same place.
    let s:jobs[l:job_id] = {
        \ 'id': l:job_id,
        \ 'cmd': a:cmd,
        \ 'opts': a:opts,
        \ 'output': '',
        \ 'errors': '',
        \ 'status': -1,
        \ 'started': 0,
        \ 'finished': 0,
        \ 'queued': localtime(),
        \ 'job': v:null,
        \ 'timeout_timer': 0
        \ }
    if has_key(a:opts, 'callback')
        let s:jobs[l:job_id].callback = a:opts.callback
    endif
    
    " Respect the maximum concurrent jobs limit: queue if at capacity
    let l:max = get(g:, 'plugin_manager_max_concurrent_jobs', 4)
    if l:max > 0 && s:active_count >= l:max
        call add(s:job_queue, l:job_id)
        return l:job_id
    endif
    
    call s:spawn_job(l:job_id)
    return l:job_id
endfunction

" Actually spawn a previously-registered job
function! s:spawn_job(job_id) abort
    if !has_key(s:jobs, a:job_id)
        return
    endif
    
    let l:job = s:jobs[a:job_id]
    let l:opts = l:job.opts
    let l:job.started = localtime()
    
    let s:active_count += 1
    
    " Start the job using Vim's job/channel API
    let l:job_opts = {
            \ 'out_cb': function('s:vim_out_cb', [a:job_id]),
            \ 'err_cb': function('s:vim_err_cb', [a:job_id]),
            \ 'exit_cb': function('s:vim_exit_cb', [a:job_id]),
            \ 'mode': 'raw',
            \ }
    
    let l:vim_job = job_start(plugin_manager#async#shell_argv(l:job.cmd), l:job_opts)
    
    if job_status(l:vim_job) !=# 'fail'
        let s:jobs[a:job_id].job = l:vim_job
    else
        " Job failed to start
        let s:jobs[a:job_id].status = 127
        let s:jobs[a:job_id].finished = localtime()
        call s:process_job_completion(a:job_id)
        return
    endif
    
    " Arm a timeout watcher if configured and timers are available
    let l:timeout = get(g:, 'plugin_manager_job_timeout', 60)
    if l:timeout > 0 && exists('*timer_start')
        let s:jobs[a:job_id].timeout_timer = timer_start(l:timeout * 1000,
                    \ function('s:on_job_timeout', [a:job_id]))
    endif
endfunction

" Start the next queued job if capacity allows
function! s:try_start_next() abort
    let l:max = get(g:, 'plugin_manager_max_concurrent_jobs', 4)
    while !empty(s:job_queue) && (l:max <= 0 || s:active_count < l:max)
        let l:next_id = remove(s:job_queue, 0)
        " Skip jobs that were stopped/cleaned while queued
        if has_key(s:jobs, l:next_id) && !s:jobs[l:next_id].finished
            call s:spawn_job(l:next_id)
        endif
    endwhile
endfunction

" Handle a job exceeding its timeout
function! s:on_job_timeout(job_id, timer) abort
    if !has_key(s:jobs, a:job_id) || s:jobs[a:job_id].finished
        return
    endif
    " Best-effort stop; completion bookkeeping happens in stop_job/exit cb
    try
        call plugin_manager#async#stop_job(a:job_id)
    catch
        " Ignore stop failures
    endtry
endfunction

" Stop a running job
function! plugin_manager#async#stop_job(job_id) abort
    if !has_key(s:jobs, a:job_id)
        call plugin_manager#core#throw('async', 'INVALID_JOB_ID', 'Invalid job ID: ' . a:job_id)
    endif

    let l:job_handle = s:jobs[a:job_id].job

    " A queued job has job = v:null (never spawned); mark it finished without
    " calling job_stop, which would error on v:null.
    if l:job_handle is v:null
        let s:jobs[a:job_id].status   = -2
        let s:jobs[a:job_id].finished = localtime()
        call s:process_job_completion(a:job_id)
        return 1
    endif

    if job_stop(l:job_handle)
        let s:jobs[a:job_id].status   = -2  " Manually stopped
        let s:jobs[a:job_id].finished = localtime()
        call s:process_job_completion(a:job_id)
        return 1
    endif

    return 0
endfunction

" ------------------------------------------------------------------------------
" CALLBACKS AND HANDLERS
" ------------------------------------------------------------------------------

" Add a callback for when a job finishes
function! plugin_manager#async#on_complete(job_id, callback) abort
    if !has_key(s:jobs, a:job_id)
        " Standardized error handling
        call plugin_manager#core#throw('async', 'INVALID_JOB_ID', 'Invalid job ID: ' . a:job_id)
    endif
    
    let s:jobs[a:job_id].callback = a:callback
    
    " If the job is already finished, call the callback immediately
    if s:jobs[a:job_id].finished
        call s:process_job_completion(a:job_id)
    endif
    
    return 1
endfunction

" Clean up finished jobs older than a certain age.
" Previously only jobs that had fired a callback were removed, leaking
" finished callback-less jobs indefinitely.  All finished jobs are now
" removed once they exceed max_age_seconds.
function! plugin_manager#async#cleanup(max_age_seconds) abort
    let l:now = localtime()
    let l:job_ids = keys(s:jobs)

    for l:id in l:job_ids
        let l:job = s:jobs[l:id]
        if l:job.finished && (l:now - l:job.finished) > a:max_age_seconds
            unlet s:jobs[l:id]
            if has_key(s:exited_with_callback, l:id)
                unlet s:exited_with_callback[l:id]
            endif
        endif
    endfor
endfunction

" ------------------------------------------------------------------------------
" HELPER FUNCTIONS FOR EXECUTING COMMON OPERATIONS
" ------------------------------------------------------------------------------

" Execute a git command asynchronously.
" opts: dict with optional 'callback' key (Funcref called on completion).
function! plugin_manager#async#git(cmd, opts) abort
    let l:job_id = plugin_manager#async#start_job(a:cmd, a:opts)
    return l:job_id
endfunction

" ------------------------------------------------------------------------------
" JOB CALLBACK IMPLEMENTATIONS
" ------------------------------------------------------------------------------

" Vim job/channel callbacks
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

" Process job completion and call callback if provided
function! s:process_job_completion(job_id) abort
    if !has_key(s:jobs, a:job_id)
        return
    endif
    
    let l:job = s:jobs[a:job_id]
    
    " Guard against double-processing (failed start + exit callback)
    if get(l:job, 'completed', 0)
        return
    endif
    let l:job.completed = 1
    
    " Release concurrency slot and cancel any pending timeout watcher
    if get(l:job, 'timeout_timer', 0) && exists('*timer_stop')
        call timer_stop(l:job.timeout_timer)
        let l:job.timeout_timer = 0
    endif
    if s:active_count > 0
        let s:active_count -= 1
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
    
    " A slot freed up: start the next queued job if any
    call s:try_start_next()

    " Clean up finished jobs older than 60 seconds
    call plugin_manager#async#cleanup(60)
endfunction