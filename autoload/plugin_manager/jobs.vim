" jobs.vim - Asynchronous job handling for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4

" Variables for job handling
if !exists('s:job_list')
    let s:job_list = []
endif
      
if !exists('s:is_win')
    let s:is_win = has('win32') || has('win64')
endif
      
" Check if async jobs are supported
function! plugin_manager#jobs#is_async_supported()
    " Check for Neovim
    if has('nvim')
        return exists('*jobstart') && exists('*jobwait')
    endif    

    " Check for Vim
    return v:version >= 800 && exists('*job_start')
endfunction

" Start an async job with appropriate callback handling
function! plugin_manager#jobs#start(cmd, callbacks)
" If async not supported, fall back to sync
if !plugin_manager#jobs#is_async_supported()
    call plugin_manager#ui#update_sidebar(['Async jobs not supported in this Vim version, falling back to synchronous operation...'], 1)
    let l:output = system(a:cmd)
    let l:status = v:shell_error
    
    if has_key(a:callbacks, 'on_stdout')
    call a:callbacks.on_stdout(l:output)
    endif
    
    if has_key(a:callbacks, 'on_exit')
    call a:callbacks.on_exit(l:status, l:output)
    endif
    
    return -1
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
        \ }

" Display that we're starting the job
if has_key(a:callbacks, 'name')
    let l:job_info.name = a:callbacks.name
    call plugin_manager#jobs#display_progress(l:job_info.id, 'Starting: ' . l:job_info.name)
else
    call plugin_manager#jobs#display_progress(l:job_info.id, 'Starting job: ' . a:cmd)
endif

" Branch for Vim or Neovim implementation
if has('nvim')
    " Neovim job implementation
    function! s:on_stdout_nvim(id, data, event) dict
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
    endfunction
    
    function! s:on_stderr_nvim(id, data, event) dict
    " Collect stderr data
    if !empty(a:data)
        let self.stderr += a:data
        
        " If we have a stderr callback, pass the data
        if has_key(self.callbacks, 'on_stderr')
        call self.callbacks.on_stderr(join(a:data, "\n"))
        endif
    endif
    endfunction
    
    function! s:on_exit_nvim(id, status, event) dict
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
    
    " Clean up job list
    call plugin_manager#jobs#clean_jobs()
    endfunction
    
    " Set job options for Neovim
    let l:job_options = {
        \ 'stdout_buffered': 1,
        \ 'stderr_buffered': 1,
        \ 'on_stdout': function('s:on_stdout_nvim', [], l:job_info),
        \ 'on_stderr': function('s:on_stderr_nvim', [], l:job_info),
        \ 'on_exit': function('s:on_exit_nvim', [], l:job_info),
        \ }
    
    " Start the job
    let l:job = jobstart(a:cmd, l:job_options)
    let l:job_info.job = l:job
    let l:job_info.type = 'nvim'
    
    " Add job to list
    call add(s:job_list, l:job_info)
    
    return l:job_info.id
else
    " Vim job implementation
    function! s:on_stdout_vim(channel, msg) dict
    " Collect stdout data
    call add(self.stdout, a:msg)
    
    " If we have a stdout callback, pass the data
    if has_key(self.callbacks, 'on_stdout')
        call self.callbacks.on_stdout(a:msg)
    endif
    
    " Update progress display
    call plugin_manager#jobs#display_progress(self.id, 'Running: ' . get(self, 'name', 'job'))
    endfunction
    
    function! s:on_stderr_vim(channel, msg) dict
    " Collect stderr data
    call add(self.stderr, a:msg)
    
    " If we have a stderr callback, pass the data
    if has_key(self.callbacks, 'on_stderr')
        call self.callbacks.on_stderr(a:msg)
    endif
    endfunction
    
    function! s:on_exit_vim(channel, status) dict
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
    
    " Clean up job list
    call plugin_manager#jobs#clean_jobs()
    endfunction
    
    " Set job options for Vim
    let l:job_options = {
        \ 'out_cb': function('s:on_stdout_vim', [], l:job_info),
        \ 'err_cb': function('s:on_stderr_vim', [], l:job_info),
        \ 'exit_cb': function('s:on_exit_vim', [], l:job_info),
        \ 'in_io': 'null',
        \ }
    
    " Start the job
    let l:job = job_start(a:cmd, l:job_options)
    let l:job_info.job = l:job
    let l:job_info.type = 'vim'
    
    " Add job to list
    call add(s:job_list, l:job_info)
    
    return l:job_info.id
endif
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
    
    " Format status line
    if l:job.status == 'running'
    let l:status_line = l:spinner_char . ' ' . l:name . ' (' . l:elapsed_str . '): ' . a:message
    else
    let l:status_line = '✓ ' . l:name . ' (' . l:elapsed_str . '): ' . a:message
    endif
    
    " Update the UI
    call plugin_manager#ui#update_job_progress(a:job_id, l:status_line)
endif
endfunction

" Run a sequence of commands asynchronously, chaining them together
function! plugin_manager#jobs#run_sequence(commands, final_callback)
let l:sequence = copy(a:commands)
let l:results = []

function! s:run_next(results, commands, final_callback, status, output) closure
    " Add result of previous command
    call add(a:results, {'status': a:status, 'output': a:output})
    
    " If no more commands, we're done
    if empty(a:commands)
    call a:final_callback(a:results)
    return
    endif
    
    " Get next command and run it
    let l:cmd = remove(a:commands, 0)
    let l:name = get(l:cmd, 'name', 'Command ' . len(a:results) + 1)
    
    " Create callbacks for this command
    let l:callbacks = {
        \ 'name': l:name,
        \ 'on_stdout': get(l:cmd, 'on_stdout', function('s:default_stdout')),
        \ 'on_stderr': get(l:cmd, 'on_stderr', function('s:default_stderr')),
        \ 'on_exit': function('s:run_next', [a:results, a:commands, a:final_callback]),
        \ }
    
    " Start the job
    call plugin_manager#jobs#start(l:cmd.cmd, l:callbacks)
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
    call plugin_manager#jobs#start(l:cmd.cmd, l:callbacks)
else
    call a:final_callback([])
endif
endfunction