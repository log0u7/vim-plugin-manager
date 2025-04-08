" autoload/plugin_manager/async.vim - Asynchronous operation support for vim-plugin-manager
" This file provides a compatibility layer for asynchronous operations in Vim 8+ and Neovim.
" Inspired by prabirshrestha/async.vim but simplified for our specific needs.

" Internal state
let s:has_async = 0
let s:is_win = has('win32') || has('win64')
let s:nvim = has('nvim')
let s:vim8 = !s:nvim && has('job') && has('channel') && has('lambda')
let s:job_map = {}  " Maps job IDs to job data
let s:job_id_counter = 1
let s:callback_counter = 0  " Counter for unique callback function names

" Check if async is supported
function! plugin_manager#async#has_async() abort
  if s:has_async
    return 1
  endif
  
  if s:nvim || s:vim8
    let s:has_async = 1
    return 1
  endif
  
  return 0
endfunction

" Get job status constants
function! plugin_manager#async#job_status() abort
  if s:nvim
    return {
      \ 'run': 'run',
      \ 'exit': 'exit',
      \ }
  elseif s:vim8
    return {
      \ 'run': 'run',
      \ 'exit': 'dead',
      \ }
  endif
endfunction

" Start a job asynchronously
" Options:
"   cmd: string or list - Command to execute
"   cwd: string - Working directory for command
"   on_stdout: funcref - Callback for stdout data
"   on_stderr: funcref - Callback for stderr data
"   on_exit: funcref - Callback when job exits
"   env: dict - Environment variables (Neovim only)
"   detach: bool - Whether to detach the process (Neovim only)
function! plugin_manager#async#job_start(cmd, opts) abort
  if !plugin_manager#async#has_async()
    throw 'PM_ERROR:async:Async operations not supported in this Vim version'
  endif
  
  let l:job_info = {}
  let l:job_id = 0
  let l:opts = copy(a:opts)
  
  " Ensure we have all necessary callback fields
  let l:opts.on_stdout = get(l:opts, 'on_stdout', function('s:noop_callback'))
  let l:opts.on_stderr = get(l:opts, 'on_stderr', function('s:noop_callback'))
  let l:opts.on_exit = get(l:opts, 'on_exit', function('s:noop_callback'))
  
  " Store original callbacks for later use
  let l:job_info.on_stdout = l:opts.on_stdout
  let l:job_info.on_stderr = l:opts.on_stderr
  let l:job_info.on_exit = l:opts.on_exit
  
  if s:nvim
    " Neovim specific setup
    let l:wrapped_opts = {}
    
    function! s:on_stdout_nvim(job_id, data, event) closure
      call l:job_info.on_stdout(a:job_id, a:data, a:event)
    endfunction

    function! s:on_stderr_nvim(job_id, data, event) closure
      call l:job_info.on_stderr(a:job_id, a:data, a:event)
    endfunction
    
    function! s:on_exit_nvim(job_id, data, event) closure
      call l:job_info.on_exit(a:job_id, a:data, a:event)
      if has_key(s:job_map, a:job_id)
        unlet s:job_map[a:job_id]
      endif
    endfunction
    
    let l:wrapped_opts.on_stdout = function('s:on_stdout_nvim')
    let l:wrapped_opts.on_stderr = function('s:on_stderr_nvim')
    let l:wrapped_opts.on_exit = function('s:on_exit_nvim')
    
    " Handle CWD option
    if has_key(l:opts, 'cwd')
      let l:wrapped_opts.cwd = l:opts.cwd
    endif
    
    " Handle ENV option
    if has_key(l:opts, 'env')
      let l:wrapped_opts.env = l:opts.env
    endif
    
    " Handle detach option
    if has_key(l:opts, 'detach')
      let l:wrapped_opts.detach = l:opts.detach
    endif
    
    " Prepare command
    let l:cmd = a:cmd
    if type(a:cmd) == type('')
      let l:cmd = split(&shell) + split(&shellcmdflag) + [a:cmd]
    endif
    
    let l:job = jobstart(l:cmd, l:wrapped_opts)
    let l:job_id = l:job
    
  elseif s:vim8
    " Vim 8 specific setup
    let l:wrapped_opts = {}
    
    function! s:on_stdout_vim8(channel, data) closure
      call l:job_info.on_stdout(s:channel_to_job_id(a:channel), [a:data], 'stdout')
    endfunction
    
    function! s:on_stderr_vim8(channel, data) closure
      call l:job_info.on_stderr(s:channel_to_job_id(a:channel), [a:data], 'stderr')
    endfunction
    
    function! s:on_exit_vim8(channel, data) closure
      let l:job_id = s:channel_to_job_id(a:channel)
      call l:job_info.on_exit(l:job_id, a:data, 'exit')
      if has_key(s:job_map, l:job_id)
        unlet s:job_map[l:job_id]
      endif
    endfunction
    
    " Vim 8 channels are very different from Neovim callbacks
    let l:wrapped_opts = {
          \ 'out_cb': function('s:on_stdout_vim8'),
          \ 'err_cb': function('s:on_stderr_vim8'),
          \ 'exit_cb': function('s:on_exit_vim8'),
          \ 'out_mode': 'nl',
          \ 'err_mode': 'nl',
          \ 'mode': 'nl',
          \ }
    
    " Handle CWD option
    if has_key(l:opts, 'cwd')
      let l:old_cwd = getcwd()
      try
        execute 'lcd' fnameescape(l:opts.cwd)
        let l:job = job_start(a:cmd, l:wrapped_opts)
      finally
        execute 'lcd' fnameescape(l:old_cwd)
      endtry
    else
      let l:job = job_start(a:cmd, l:wrapped_opts)
    endif
    
    let l:job_id = s:vim8_job_id(l:job)
    let l:job_info.job = l:job
  endif
  
  if l:job_id > 0
    let l:job_info.id = l:job_id
    let l:job_info.cmd = a:cmd
    let s:job_map[l:job_id] = l:job_info
    return l:job_id
  endif
  
  return 0
endfunction

" Stop a job
function! plugin_manager#async#job_stop(job_id) abort
  if !plugin_manager#async#has_async()
    return
  endif
  
  if !has_key(s:job_map, a:job_id)
    return
  endif
  
  if s:nvim
    call jobstop(a:job_id)
  elseif s:vim8
    call job_stop(s:job_map[a:job_id].job)
  endif
endfunction

" Get job status
function! plugin_manager#async#job_status_get(job_id) abort
  if !plugin_manager#async#has_async()
    return 'exit'
  endif
  
  if !has_key(s:job_map, a:job_id)
    return 'exit'
  endif
  
  let l:status = plugin_manager#async#job_status()
  
  if s:nvim
    let l:job_status = jobwait([a:job_id], 0)[0]
    if l:job_status == -1
      return l:status.run
    else
      return l:status.exit
    endif
  elseif s:vim8
    let l:job_status = job_status(s:job_map[a:job_id].job)
    return l:job_status
  endif
  
  return 'exit'
endfunction

" Send data to a job
function! plugin_manager#async#job_send(job_id, data) abort
  if !plugin_manager#async#has_async()
    return
  endif
  
  if !has_key(s:job_map, a:job_id)
    return
  endif
  
  if s:nvim
    call jobsend(a:job_id, a:data)
  elseif s:vim8
    let l:job = s:job_map[a:job_id].job
    let l:channel = job_getchannel(l:job)
    call ch_sendraw(l:channel, a:data)
  endif
endfunction

" Wait for a job to complete
function! plugin_manager#async#job_wait(job_id, timeout) abort
  if !plugin_manager#async#has_async()
    return
  endif
  
  if !has_key(s:job_map, a:job_id)
    return
  endif
  
  if s:nvim
    call jobwait([a:job_id], a:timeout)
  elseif s:vim8
    let l:timeout = a:timeout / 1000.0  " Convert to seconds for Vim8
    call job_wait([s:job_map[a:job_id].job], float2nr(l:timeout * 1000))
  endif
endfunction

" Create a wrapper around system() that uses async when available
" This provides a drop-in replacement for many existing synchronous operations
function! plugin_manager#async#system(cmd, callback) abort
  if !plugin_manager#async#has_async()
    " Fallback to synchronous call if async is not available
    let l:output = system(a:cmd)
    let l:status = v:shell_error
    call a:callback(l:output, l:status)
    return 0
  endif
  
  " Increment the counter to create unique function names
  let s:callback_counter += 1
  let l:counter = s:callback_counter
  
  " Collect stdout and stderr
  let l:output = []
  let l:error_output = []
  
  " Use unique function names with the counter
  function! s:on_stdout_{l:counter}(job_id, data, event) closure
    if len(a:data) > 0
      call extend(l:output, a:data)
    endif
  endfunction
  
  function! s:on_stderr_{l:counter}(job_id, data, event) closure
    if len(a:data) > 0
      call extend(l:error_output, a:data)
    endif
  endfunction
  
  function! s:on_exit_{l:counter}(job_id, status, event) closure
    " Combine stdout and stderr
    " Remove empty string at the end if present
    if !empty(l:output) && l:output[-1] == ''
      call remove(l:output, -1)
    endif
    
    let l:combined_output = join(l:output, "\n")
    
    " Pass the result to the callback
    call a:callback(l:combined_output, a:status)
  endfunction
  
  " Start the async job
  let l:job_id = plugin_manager#async#job_start(a:cmd, {
        \ 'on_stdout': function('s:on_stdout_' . l:counter),
        \ 'on_stderr': function('s:on_stderr_' . l:counter),
        \ 'on_exit': function('s:on_exit_' . l:counter),
        \ })
  
  return l:job_id
endfunction

" Helper functions
function! s:noop_callback(job_id, data, event) abort
  " Do nothing - default callback
endfunction

" For Vim 8, convert channel to job ID
function! s:channel_to_job_id(channel) abort
  if has_key(s:job_map, a:channel)
    return a:channel
  endif
  
  " Find job id from channel
  for [l:job_id, l:job_info] in items(s:job_map)
    if has_key(l:job_info, 'job')
      let l:channel = job_getchannel(l:job_info.job)
      if ch_info(l:channel).id == ch_info(a:channel).id
        return l:job_id
      endif
    endif
  endfor
  
  return 0
endfunction

" Generate a unique job ID for Vim 8
function! s:vim8_job_id(job) abort
  let l:id = s:job_id_counter
  let s:job_id_counter += 1
  return l:id
endfunction

" Detect if we can use async operations
call plugin_manager#async#has_async()