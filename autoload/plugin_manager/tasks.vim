" autoload/plugin_manager/tasks.vim - Task management for vim-plugin-manager
" This file provides a task system to manage sequential and parallel operations.

" Task system internal state
let s:tasks = {}
let s:task_id_counter = 1
let s:task_queue = []
let s:active_tasks = {}
let s:is_queue_processing = 0

" Constants for task status
let s:STATUS_PENDING = 'pending'
let s:STATUS_RUNNING = 'running'
let s:STATUS_COMPLETED = 'completed'
let s:STATUS_FAILED = 'failed'
let s:STATUS_CANCELLED = 'cancelled'

" Constants for task type
let s:TYPE_SINGLE = 'single'
let s:TYPE_SEQUENCE = 'sequence'
let s:TYPE_PARALLEL = 'parallel'

" Maximum number of parallel tasks
let s:max_parallel_tasks = 4

" Check if async is supported
function! s:has_async() abort
  return plugin_manager#async#has_async()
endfunction

" Create a new task
" Parameters:
"   type: single|sequence|parallel - Type of task
"   options: dict with keys:
"     name: string - Task name for display
"     commands: list or function - Commands to execute or function returning commands
"     on_success: funcref - Called when task completes successfully
"     on_failure: funcref - Called when task fails
"     on_complete: funcref - Called when task completes (success or failure)
"     on_progress: funcref - Called for progress updates
"     cwd: string - Working directory for command
"     use_async: boolean - Whether to use async execution (default: true)
function! plugin_manager#tasks#create(type, options) abort
  " Generate unique task ID
  let l:task_id = s:task_id_counter
  let s:task_id_counter += 1
  
  " Initialize the task structure
  let l:task = {
        \ 'id': l:task_id,
        \ 'type': a:type,
        \ 'status': s:STATUS_PENDING,
        \ 'name': get(a:options, 'name', 'Task ' . l:task_id),
        \ 'commands': get(a:options, 'commands', []),
        \ 'current_index': 0,
        \ 'results': [],
        \ 'error': '',
        \ 'start_time': 0,
        \ 'end_time': 0,
        \ 'subtasks': [],
        \ 'parent_id': get(a:options, 'parent_id', 0),
        \ 'cwd': get(a:options, 'cwd', ''),
        \ 'ui_job_id': '',
        \ 'use_async': get(a:options, 'use_async', 1),
        \ }
  
  " Set callback functions
  let l:task.on_success = get(a:options, 'on_success', function('s:default_success_callback'))
  let l:task.on_failure = get(a:options, 'on_failure', function('s:default_failure_callback'))  
  let l:task.on_complete = get(a:options, 'on_complete', function('s:default_complete_callback'))
  let l:task.on_progress = get(a:options, 'on_progress', function('s:default_progress_callback'))
  
  " Store the task
  let s:tasks[l:task_id] = l:task
  
  " For sequence or parallel tasks, process commands into subtasks
  if a:type == s:TYPE_SEQUENCE || a:type == s:TYPE_PARALLEL
    let l:subtasks = []
    let l:commands = type(l:task.commands) == v:t_func 
          \ ? l:task.commands() 
          \ : l:task.commands
    
    for l:cmd in l:commands
      let l:subtask_options = {
            \ 'name': l:task.name . ' - Subtask ' . len(l:subtasks),
            \ 'commands': l:cmd,
            \ 'parent_id': l:task_id,
            \ 'cwd': l:task.cwd,
            \ 'use_async': l:task.use_async,
            \ }
      let l:subtask_id = plugin_manager#tasks#create(s:TYPE_SINGLE, l:subtask_options)
      call add(l:subtasks, l:subtask_id)
      call add(l:task.subtasks, l:subtask_id)
    endfor
  endif
  
  return l:task_id
endfunction

" Start a task
function! plugin_manager#tasks#start(task_id) abort
  if !has_key(s:tasks, a:task_id)
    throw 'PM_ERROR:tasks:Task ID not found: ' . a:task_id
  endif
  
  let l:task = s:tasks[a:task_id]
  
  " If task is already running or completed, do nothing
  if l:task.status == s:STATUS_RUNNING || l:task.status == s:STATUS_COMPLETED
    return a:task_id
  endif
  
  " Mark task as running
  let l:task.status = s:STATUS_RUNNING
  let l:task.start_time = localtime()
  
  " Create UI job if necessary
  if empty(l:task.ui_job_id)
    let l:task.ui_job_id = plugin_manager#ui#start_task(l:task.name, 
          \ l:task.type == s:TYPE_SINGLE ? 1 : len(l:task.subtasks))
  endif
  
  " Process based on task type
  if l:task.type == s:TYPE_SINGLE
    call s:process_single_task(l:task)
  elseif l:task.type == s:TYPE_SEQUENCE
    call s:process_sequence_task(l:task)
  elseif l:task.type == s:TYPE_PARALLEL
    call s:process_parallel_task(l:task)
  endif
  
  return a:task_id
endfunction

" Process a single task
function! s:process_single_task(task) abort
  let l:task = a:task
  let l:cmd = type(l:task.commands) == v:t_func 
        \ ? l:task.commands() 
        \ : l:task.commands
  
  " For non-async Vim, function command, or when async is disabled, execute synchronously
  if !s:has_async() || type(l:cmd) == v:t_func || !l:task.use_async
    call s:execute_sync_task(l:task)
    return
  endif
  
  " Update UI
  call l:task.on_progress(l:task.id, 0, 1, 'Starting task...')
  
  " Create success callback
  function! s:on_success(task_id, output, status) closure
    let l:task = s:tasks[a:task_id]
    let l:task.status = s:STATUS_COMPLETED
    let l:task.end_time = localtime()
    call add(l:task.results, {'output': a:output, 'status': a:status})
    
    " Update UI
    call l:task.on_progress(l:task.id, 1, 1, 'Task completed successfully')
    
    " Trigger callbacks
    call l:task.on_success(l:task.id, a:output, a:status)
    call l:task.on_complete(l:task.id, 1, a:output, a:status)
    
    " Remove from active tasks
    if has_key(s:active_tasks, l:task.id)
      unlet s:active_tasks[l:task.id]
    endif
    
    " If this is a subtask, update parent task
    if l:task.parent_id > 0
      call s:update_parent_task(l:task.parent_id)
    endif
    
    " Process next task in queue
    call s:process_task_queue()
  endfunction
  
  " Create failure callback
  function! s:on_failure(task_id, output, status) closure
    let l:task = s:tasks[a:task_id]
    let l:task.status = s:STATUS_FAILED
    let l:task.end_time = localtime()
    let l:task.error = a:output
    call add(l:task.results, {'output': a:output, 'status': a:status})
    
    " Update UI
    call l:task.on_progress(l:task.id, 1, 1, 'Task failed: ' . a:status)
    
    " Trigger callbacks
    call l:task.on_failure(l:task.id, a:output, a:status)
    call l:task.on_complete(l:task.id, 0, a:output, a:status)
    
    " Remove from active tasks
    if has_key(s:active_tasks, l:task.id)
      unlet s:active_tasks[l:task.id]
    endif
    
    " If this is a subtask, update parent task
    if l:task.parent_id > 0
      call s:update_parent_task(l:task.parent_id)
    endif
    
    " Process next task in queue
    call s:process_task_queue()
  endfunction
  
  " Process command options
  let l:cmd_options = {}
  if !empty(l:task.cwd)
    let l:cmd_options.cwd = l:task.cwd
  endif
  
  " Start the async job
  function! s:on_complete(output, status) closure
    if a:status == 0
      call s:on_success(l:task.id, a:output, a:status)
    else
      call s:on_failure(l:task.id, a:output, a:status)
    endif
  endfunction
  
  " Store the active task
  let s:active_tasks[l:task.id] = l:task
  
  " Update UI if job_id is provided
  if !empty(l:task.ui_job_id)
    call plugin_manager#ui#update_task(l:task.ui_job_id, 0, 'Running: ' . l:cmd)
  endif
  
  " Execute command asynchronously
  let l:job_id = plugin_manager#async#system(l:cmd, function('s:on_complete'))
  let l:task.job_id = l:job_id
endfunction

" Execute a task synchronously (fallback for non-async Vim)
function! s:execute_sync_task(task) abort
  let l:task = a:task
  let l:cmd = type(l:task.commands) == v:t_func 
        \ ? l:task.commands() 
        \ : l:task.commands
  
  " Update UI
  call l:task.on_progress(l:task.id, 0, 1, 'Starting task synchronously...')
  
  " For function commands, execute directly
  if type(l:cmd) == v:t_func
    try
      let l:output = l:cmd()
      let l:status = 0
    catch
      let l:output = v:exception
      let l:status = 1
    endtry
  else
    " Save current directory if cwd is set
    let l:old_cwd = getcwd()
    try
      if !empty(l:task.cwd)
        execute 'lcd ' . fnameescape(l:task.cwd)
      endif
      
      " Show command in UI
      if !empty(l:task.ui_job_id)
        call plugin_manager#ui#update_task(l:task.ui_job_id, 0, 'Running: ' . l:cmd)
      endif
      
      let l:output = system(l:cmd)
      let l:status = v:shell_error
    finally
      if !empty(l:task.cwd)
        execute 'lcd ' . fnameescape(l:old_cwd)
      endif
    endtry
  endif
  
  " Complete the task
  let l:task.status = l:status == 0 ? s:STATUS_COMPLETED : s:STATUS_FAILED
  let l:task.end_time = localtime()
  call add(l:task.results, {'output': l:output, 'status': l:status})
  
  " Update UI
  if l:status == 0
    call l:task.on_progress(l:task.id, 1, 1, 'Task completed successfully')
    call l:task.on_success(l:task.id, l:output, l:status)
  else
    let l:task.error = l:output
    call l:task.on_progress(l:task.id, 1, 1, 'Task failed: ' . l:status)
    call l:task.on_failure(l:task.id, l:output, l:status)
  endif
  
  call l:task.on_complete(l:task.id, l:status == 0, l:output, l:status)
  
  " Remove from active tasks
  if has_key(s:active_tasks, l:task.id)
    unlet s:active_tasks[l:task.id]
  endif
  
  " If this is a subtask itself, update its parent
  if l:task.parent_id > 0
    call s:update_parent_task(l:task.parent_id)
  endif
  
  " Process next task in queue
  call s:process_task_queue()
endfunction

" Process a sequence task
function! s:process_sequence_task(task) abort
  let l:task = a:task
  
  " If no subtasks, mark as completed
  if empty(l:task.subtasks)
    let l:task.status = s:STATUS_COMPLETED
    call l:task.on_success(l:task.id, [], 0)
    call l:task.on_complete(l:task.id, 1, [], 0)
    return
  endif
  
  " Start the first subtask
  let l:subtask_id = l:task.subtasks[l:task.current_index]
  call plugin_manager#tasks#start(l:subtask_id)
endfunction

" Process a parallel task
function! s:process_parallel_task(task) abort
  let l:task = a:task
  
  " If no subtasks, mark as completed
  if empty(l:task.subtasks)
    let l:task.status = s:STATUS_COMPLETED
    call l:task.on_success(l:task.id, [], 0)
    call l:task.on_complete(l:task.id, 1, [], 0)
    return
  endif
  
  " Start all subtasks in parallel
  for l:subtask_id in l:task.subtasks
    " Check if we can start more parallel tasks
    if len(s:active_tasks) >= s:max_parallel_tasks
      " Queue the task
      call add(s:task_queue, l:subtask_id)
    else
      call plugin_manager#tasks#start(l:subtask_id)
    endif
  endfor
endfunction

" Update parent task status based on subtasks
function! s:update_parent_task(parent_id) abort
  if !has_key(s:tasks, a:parent_id)
    return
  endif
  
  let l:parent = s:tasks[a:parent_id]
  let l:all_completed = 1
  let l:any_failed = 0
  let l:completed_count = 0
  
  " Check status of all subtasks
  for l:subtask_id in l:parent.subtasks
    if has_key(s:tasks, l:subtask_id)
      let l:subtask = s:tasks[l:subtask_id]
      
      if l:subtask.status == s:STATUS_COMPLETED
        let l:completed_count += 1
      elseif l:subtask.status == s:STATUS_FAILED
        let l:any_failed = 1
        let l:completed_count += 1
      elseif l:subtask.status != s:STATUS_CANCELLED
        let l:all_completed = 0
      endif
    endif
  endfor
  
  " Update progress in UI
  if !empty(l:parent.ui_job_id)
    call plugin_manager#ui#update_task(l:parent.ui_job_id, l:completed_count, 
          \ l:parent.name . ' (' . l:completed_count . '/' . len(l:parent.subtasks) . ')')
  endif
  
  " For sequence tasks, check if we need to start the next task
  if l:parent.type == s:TYPE_SEQUENCE && l:parent.status == s:STATUS_RUNNING
    let l:current_subtask_id = l:parent.subtasks[l:parent.current_index]
    let l:current_subtask = s:tasks[l:current_subtask_id]
    
    " If current subtask failed, mark parent as failed
    if l:current_subtask.status == s:STATUS_FAILED
      let l:parent.status = s:STATUS_FAILED
      let l:parent.error = 'Subtask ' . l:current_subtask.id . ' failed: ' . l:current_subtask.error
      let l:parent.end_time = localtime()
      
      " Update UI and trigger callbacks
      if !empty(l:parent.ui_job_id)
        call plugin_manager#ui#complete_task(l:parent.ui_job_id, 0, 'Task failed: ' . l:parent.error)
      endif
      
      call l:parent.on_failure(l:parent.id, l:parent.error, 1)
      call l:parent.on_complete(l:parent.id, 0, l:parent.error, 1)
      
      " If this is a subtask itself, update its parent
      if l:parent.parent_id > 0
        call s:update_parent_task(l:parent.parent_id)
      endif
      
      return
    endif
    
    " If current subtask completed successfully, start next subtask
    if l:current_subtask.status == s:STATUS_COMPLETED
      let l:parent.current_index += 1
      
      " If we've completed all subtasks, mark parent as completed
      if l:parent.current_index >= len(l:parent.subtasks)
        let l:parent.status = s:STATUS_COMPLETED
        let l:parent.end_time = localtime()
        
        " Collect all results
        let l:results = []
        for l:subtask_id in l:parent.subtasks
          if has_key(s:tasks, l:subtask_id)
            let l:subtask = s:tasks[l:subtask_id]
            call extend(l:results, l:subtask.results)
          endif
        endfor
        
        " Update UI and trigger callbacks
        if !empty(l:parent.ui_job_id)
          call plugin_manager#ui#complete_task(l:parent.ui_job_id, 1, 'Task completed successfully')
        endif
        
        call l:parent.on_success(l:parent.id, l:results, 0)
        call l:parent.on_complete(l:parent.id, 1, l:results, 0)
        
        " If this is a subtask itself, update its parent
        if l:parent.parent_id > 0
          call s:update_parent_task(l:parent.parent_id)
        endif
      else
        " Start the next subtask
        let l:next_subtask_id = l:parent.subtasks[l:parent.current_index]
        call plugin_manager#tasks#start(l:next_subtask_id)
      endif
    endif
  elseif l:all_completed && l:parent.type == s:TYPE_PARALLEL
    " For parallel tasks, check if all subtasks are completed
    let l:parent.end_time = localtime()
    
    " If any subtask failed, mark parent as failed
    if l:any_failed
      let l:parent.status = s:STATUS_FAILED
      let l:parent.error = 'One or more subtasks failed'
      
      " Update UI and trigger callbacks
      if !empty(l:parent.ui_job_id)
        call plugin_manager#ui#complete_task(l:parent.ui_job_id, 0, 'Task failed: ' . l:parent.error)
      endif
      
      call l:parent.on_failure(l:parent.id, l:parent.error, 1)
      call l:parent.on_complete(l:parent.id, 0, l:parent.error, 1)
    else
      let l:parent.status = s:STATUS_COMPLETED
      
      " Collect all results
      let l:results = []
      for l:subtask_id in l:parent.subtasks
        if has_key(s:tasks, l:subtask_id)
          let l:subtask = s:tasks[l:subtask_id]
          call extend(l:results, l:subtask.results)
        endif
      endfor
      
      " Update UI and trigger callbacks
      if !empty(l:parent.ui_job_id)
        call plugin_manager#ui#complete_task(l:parent.ui_job_id, 1, 'Task completed successfully')
      endif
      
      call l:parent.on_success(l:parent.id, l:results, 0)
      call l:parent.on_complete(l:parent.id, 1, l:results, 0)
    endif
    
    " If this is a subtask itself, update its parent
    if l:parent.parent_id > 0
      call s:update_parent_task(l:parent.parent_id)
    endif
  endif
endfunction

" Process next task in queue
function! s:process_task_queue() abort
  " Prevent recursive calls
  if s:is_queue_processing
    return
  endif
  
  let s:is_queue_processing = 1
  
  " Check if we have capacity for more tasks
  while len(s:active_tasks) < s:max_parallel_tasks && !empty(s:task_queue)
    let l:next_task_id = remove(s:task_queue, 0)
    call plugin_manager#tasks#start(l:next_task_id)
  endwhile
  
  let s:is_queue_processing = 0
endfunction

" Default callbacks
function! s:default_success_callback(task_id, result, status) abort
  " Default success handler does nothing
endfunction

function! s:default_failure_callback(task_id, error, status) abort
  " Default failure handler does nothing
endfunction

function! s:default_complete_callback(task_id, success, result, status) abort
  " Default completion handler does nothing
endfunction

function! s:default_progress_callback(task_id, current, total, message) abort
  " Update UI if a UI job ID is available
  let l:task = get(s:tasks, a:task_id, {})
  if !empty(l:task) && !empty(l:task.ui_job_id)
    call plugin_manager#ui#update_task(l:task.ui_job_id, a:current, a:message)
  endif
endfunction

" Additional public API functions

" Get task status
function! plugin_manager#tasks#status(task_id) abort
  if !has_key(s:tasks, a:task_id)
    return 'unknown'
  endif
  
  return s:tasks[a:task_id].status
endfunction

" Get task result
function! plugin_manager#tasks#result(task_id) abort
  if !has_key(s:tasks, a:task_id)
    return {'success': 0, 'output': 'Task not found', 'status': -1}
  endif
  
  let l:task = s:tasks[a:task_id]
  
  " If task is not completed, return empty result
  if l:task.status != s:STATUS_COMPLETED && l:task.status != s:STATUS_FAILED
    return {'success': 0, 'output': 'Task not completed', 'status': -1}
  endif
  
  " For single tasks, return the last result
  if l:task.type == s:TYPE_SINGLE && !empty(l:task.results)
    let l:last_result = l:task.results[-1]
    return {
          \ 'success': l:task.status == s:STATUS_COMPLETED,
          \ 'output': l:last_result.output,
          \ 'status': l:last_result.status
          \ }
  endif
  
  " For compound tasks, collect results from subtasks
  let l:outputs = []
  let l:success = l:task.status == s:STATUS_COMPLETED
  
  for l:subtask_id in l:task.subtasks
    if has_key(s:tasks, l:subtask_id)
      let l:subtask = s:tasks[l:subtask_id]
      if !empty(l:subtask.results)
        for l:result in l:subtask.results
          call add(l:outputs, l:result.output)
        endfor
      endif
    endif
  endfor
  
  return {
        \ 'success': l:success,
        \ 'output': join(l:outputs, "\n"),
        \ 'status': l:success ? 0 : 1
        \ }
endfunction

" Cancel a task
function! plugin_manager#tasks#cancel(task_id) abort
  if !has_key(s:tasks, a:task_id)
    return 0
  endif
  
  let l:task = s:tasks[a:task_id]
  
  " If task is already completed, do nothing
  if l:task.status == s:STATUS_COMPLETED || l:task.status == s:STATUS_FAILED || l:task.status == s:STATUS_CANCELLED
    return 0
  endif
  
  " Mark task as cancelled
  let l:task.status = s:STATUS_CANCELLED
  
  " Stop job if running
  if has_key(l:task, 'job_id') && l:task.job_id > 0
    call plugin_manager#async#job_stop(l:task.job_id)
  endif
  
  " Cancel all subtasks
  for l:subtask_id in l:task.subtasks
    call plugin_manager#tasks#cancel(l:subtask_id)
  endfor
  
  " Remove from active tasks
  if has_key(s:active_tasks, l:task.id)
    unlet s:active_tasks[l:task.id]
  endif
  
  " Update UI
  if !empty(l:task.ui_job_id)
    call plugin_manager#ui#complete_task(l:task.ui_job_id, 0, 'Task cancelled')
  endif
  
  return 1
endfunction

" Set maximum parallel tasks
function! plugin_manager#tasks#set_max_parallel(count) abort
  let s:max_parallel_tasks = a:count > 0 ? a:count : 1
endfunction