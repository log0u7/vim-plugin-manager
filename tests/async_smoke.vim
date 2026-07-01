" tests/async_smoke.vim - Real async smoke test for CI pty jobs
"
" This script MUST be run under a pty (e.g. via 'script -qec "vim -N -u ..."')
" so that Vim's event loop processes job callbacks.  Running under 'vim -es'
" (headless) will leave callbacks unfired and cause the test to fail.
"
" Exit codes:
"   0  all assertions passed
"   1  one or more assertions failed (see /tmp/pm_async_smoke.log for details)
"
" Usage (from the repo root):
"   script -qec "vim -N -u tests/async_smoke.vim" /dev/null

set nocompatible
let &rtp = expand('<sfile>:p:h:h') . ',' . &rtp

runtime! autoload/plugin_manager/core.vim
runtime! autoload/plugin_manager/async.vim

" --------------------------------------------------------------------------
" State
" --------------------------------------------------------------------------
let g:_smoke_log   = []
let g:_smoke_pass  = 0
let g:_smoke_fail  = 0
let g:_cb_start_job = []   " collects results from start_job opts.callback
let g:_cb_async_git = []   " collects results from async#git callback
let g:_cb_queue     = []   " collects results from queued jobs

function! s:ok(msg) abort
  call add(g:_smoke_log, 'PASS: ' . a:msg)
  let g:_smoke_pass += 1
endfunction

function! s:fail(msg) abort
  call add(g:_smoke_log, 'FAIL: ' . a:msg)
  let g:_smoke_fail += 1
endfunction

function! s:assert_eq(desc, expected, actual) abort
  if a:expected ==# a:actual
    call s:ok(a:desc)
  else
    call s:fail(a:desc . ' | expected=' . string(a:expected) . ' got=' . string(a:actual))
  endif
endfunction

" --------------------------------------------------------------------------
" Launch all jobs (timer so the event loop is already running)
" --------------------------------------------------------------------------
function! s:launch(timer) abort
  " 1. start_job with callback in opts dict (the bug-path, now fixed)
  call plugin_manager#async#start_job('echo start_job_output', {
        \ 'callback': {r -> add(g:_cb_start_job, r)}
        \ })

  " 2. async#git (the production code path)
  call plugin_manager#async#git('echo async_git_output', {
        \ 'callback': {r -> add(g:_cb_async_git, r)}
        \ })

  " 3. Queued jobs: limit concurrency to 1, launch 3 jobs in sequence
  let g:plugin_manager_max_concurrent_jobs = 1
  call plugin_manager#async#start_job('echo q0', {'callback': {r -> add(g:_cb_queue, r.status)}})
  call plugin_manager#async#start_job('echo q1', {'callback': {r -> add(g:_cb_queue, r.status)}})
  call plugin_manager#async#start_job('echo q2', {'callback': {r -> add(g:_cb_queue, r.status)}})
endfunction

" --------------------------------------------------------------------------
" Assertions + exit (second timer, after jobs should have completed)
" --------------------------------------------------------------------------
function! s:finish(timer) abort
  " Reset concurrency limit
  let g:plugin_manager_max_concurrent_jobs = 4

  " --- Check 1: start_job opts.callback fired ---
  call s:assert_eq('start_job callback fired', 1, len(g:_cb_start_job))
  if len(g:_cb_start_job) > 0
    call s:assert_eq('start_job status=0', 0, g:_cb_start_job[0].status)
    call s:assert_eq('start_job output contains echo',
          \ 1, g:_cb_start_job[0].output =~# 'start_job_output')
    call s:assert_eq('start_job cmd field present',
          \ 1, has_key(g:_cb_start_job[0], 'cmd'))
  endif

  " --- Check 2: async#git callback fired ---
  call s:assert_eq('async#git callback fired', 1, len(g:_cb_async_git))
  if len(g:_cb_async_git) > 0
    call s:assert_eq('async#git status=0', 0, g:_cb_async_git[0].status)
    call s:assert_eq('async#git output contains echo',
          \ 1, g:_cb_async_git[0].output =~# 'async_git_output')
  endif

  " --- Check 3: queued jobs (max_concurrent=1) all completed ---
  call s:assert_eq('all 3 queued jobs completed', 3, len(g:_cb_queue))
  if len(g:_cb_queue) >= 3
    call s:assert_eq('queued job 0 status=0', 0, g:_cb_queue[0])
    call s:assert_eq('queued job 1 status=0', 0, g:_cb_queue[1])
    call s:assert_eq('queued job 2 status=0', 0, g:_cb_queue[2])
  endif

  " --- Write result file ---
  let l:total = g:_smoke_pass + g:_smoke_fail
  let l:summary = 'async smoke: ' . g:_smoke_pass . '/' . l:total . ' passed'
  if g:_smoke_fail > 0
    let l:summary .= ' (' . g:_smoke_fail . ' FAILED)'
  endif
  call add(g:_smoke_log, l:summary)
  call writefile(g:_smoke_log, '/tmp/pm_async_smoke.log')

  " Exit 0 on success, 1 on failure
  if g:_smoke_fail > 0
    cquit 1
  else
    quit!
  endif
endfunction

" --------------------------------------------------------------------------
" Schedule: launch after 500 ms, assert after 6 s
" --------------------------------------------------------------------------
if !plugin_manager#async#supported()
  call writefile(['SKIP: +job/+channel not available'], '/tmp/pm_async_smoke.log')
  quit!
endif

call timer_start(500,  function('s:launch'))
call timer_start(6000, function('s:finish'))
