" tests/install_smoke.vim - Parallel (background) install smoke test for CI pty jobs
"
" This script MUST be run under a pty (e.g. via 'script -qec "vim -N -u ..."')
" so that Vim's event loop processes job callbacks.  Running under 'vim -es'
" (headless) will leave clone callbacks unfired and cause the test to fail.
"
" Exit codes:
"   0  all assertions passed
"   1  one or more assertions failed (see /tmp/pm_install_smoke.log)
"
" Usage (from the repo root):
"   script -qec "vim -N -u tests/install_smoke.vim" /dev/null

set nocompatible
" Isolation: never load the developer's own ~/.vim pack plugins or vimrc
" side effects; the smoke session gets everything from this repo and the
" fixture it builds itself.
set packpath=
let &rtp = expand('<sfile>:p:h:h') . ',' . $VIMRUNTIME

runtime! autoload/plugin_manager/**/*.vim
source plugin/plugin_manager.vim

" --------------------------------------------------------------------------
" State
" --------------------------------------------------------------------------
let g:_smoke_log  = []
let g:_smoke_pass = 0
let g:_smoke_fail = 0

let g:_smoke_root = tempname()
let g:_smoke_vim  = g:_smoke_root . '/vim'
let g:_smoke_src1 = g:_smoke_root . '/src1'
let g:_smoke_src2 = g:_smoke_root . '/src2'

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

function! s:git(...) abort
  return substitute(system('git -C ' . shellescape(g:_smoke_vim) . ' ' . join(a:000)), '\n$', '', '')
endfunction

" --------------------------------------------------------------------------
" Fixture: two bare repos (one tagged), a vim config repo with
" protocol.file.allow enabled so the submodule registration of local
" clones works on git >= 2.38.1.
" --------------------------------------------------------------------------
function! s:setup() abort
  call system('git init --bare ' . shellescape(g:_smoke_src1))
  call system('git init --bare ' . shellescape(g:_smoke_src2))
  for l:src in [g:_smoke_src1, g:_smoke_src2]
    call system('git init ' . shellescape(l:src . '_w'))
    call system('git -C ' . shellescape(l:src . '_w') . ' config user.email t@t.t')
    call system('git -C ' . shellescape(l:src . '_w') . ' config user.name T')
    call writefile(['v1'], l:src . '_w/f.txt')
    call system('git -C ' . shellescape(l:src . '_w') . ' add .')
    call system('git -C ' . shellescape(l:src . '_w') . ' commit -m v1')
    call system('git -C ' . shellescape(l:src . '_w') . ' tag v1')
    call system('git -C ' . shellescape(l:src . '_w') . ' push ' . shellescape(l:src) . ' HEAD:main')
    call system('git -C ' . shellescape(l:src) . ' symbolic-ref HEAD refs/heads/main')
  endfor

  call mkdir(g:_smoke_vim . '/pack/plugins', 'p')
  call system('git init ' . shellescape(g:_smoke_vim))
  call system('git -C ' . shellescape(g:_smoke_vim) . ' config user.email t@t.t')
  call system('git -C ' . shellescape(g:_smoke_vim) . ' config user.name T')
  call system('git -C ' . shellescape(g:_smoke_vim) . ' config protocol.file.allow always')
  call writefile(['# smoke vimrc'], g:_smoke_vim . '/vimrc')
  call system('git -C ' . shellescape(g:_smoke_vim) . ' add .')
  call system('git -C ' . shellescape(g:_smoke_vim) . ' commit -m init')

  let g:plugin_manager_vim_dir        = g:_smoke_vim
  let g:plugin_manager_plugins_dir    = g:_smoke_vim . '/pack/plugins'
  let g:plugin_manager_vimrc_path     = g:_smoke_root . '/absent.vimrc'
  let g:plugin_manager_enable_logging = 0
endfunction

" --------------------------------------------------------------------------
" Launch the declarative block (timer so the event loop is already running)
" --------------------------------------------------------------------------
function! s:launch(timer) abort
  call s:setup()
  call plugin_manager#api#begin()
  call plugin_manager#api#plugin('file://' . g:_smoke_src1, {'dir': 'smokeplug1'})
  call plugin_manager#api#plugin('file://' . g:_smoke_src2, {'dir': 'smokeplug2', 'tag': 'v1'})
  call plugin_manager#api#end()
endfunction

" --------------------------------------------------------------------------
" Assertions + exit (second timer, after the background installs completed)
" --------------------------------------------------------------------------
function! s:finish(timer) abort
  let l:p1 = g:_smoke_vim . '/pack/plugins/start/smokeplug1'
  let l:p2 = g:_smoke_vim . '/pack/plugins/start/smokeplug2'

  call s:assert_eq('smokeplug1 installed in background', 1, isdirectory(l:p1))
  call s:assert_eq('smokeplug2 installed in background', 1, isdirectory(l:p2))

  if isdirectory(l:p1) && isdirectory(l:p2)
    " Both registered as gitlinks in the vim config repo
    let l:gitlinks = s:git('ls-files', '-s', 'pack/plugins/start')
    call s:assert_eq('two gitlink entries committed', 2,
          \ len(split(substitute(l:gitlinks, '160000', "\n160000", 'g'), "\n")) - 1)
    call s:assert_eq('gitlink mode present', 1, l:gitlinks =~# '160000')

    " .gitmodules lists both plugins
    if filereadable(g:_smoke_vim . '/.gitmodules')
      let l:gm = join(readfile(g:_smoke_vim . '/.gitmodules'), "\n")
      call s:assert_eq('.gitmodules has smokeplug1', 1, l:gm =~# 'smokeplug1')
      call s:assert_eq('.gitmodules has smokeplug2', 1, l:gm =~# 'smokeplug2')
    else
      call s:fail('.gitmodules was never written')
    endif

    " The tag pin declared for smokeplug2 was applied at install time
    let l:wanted = substitute(system('git -C ' . shellescape(g:_smoke_src2 . '_w') . ' rev-parse v1'), '\n$', '', '')
    let l:got = substitute(system('git -C ' . shellescape(l:p2) . ' rev-parse HEAD'), '\n$', '', '')
    call s:assert_eq('tag pin checked out at install', l:wanted, l:got)
  endif

  let l:total = g:_smoke_pass + g:_smoke_fail
  let l:summary = 'install smoke: ' . g:_smoke_pass . '/' . l:total . ' passed'
  if g:_smoke_fail > 0
    let l:summary .= ' (' . g:_smoke_fail . ' FAILED)'
    " Dump the sidebar for diagnosis (clone/install error details)
    let l:sb = bufnr('PluginManager')
    if l:sb != -1
      call add(g:_smoke_log, '--- sidebar ---')
      call extend(g:_smoke_log, getbufline(l:sb, 1, '$'))
    endif
  endif
  call add(g:_smoke_log, l:summary)
  call writefile(g:_smoke_log, '/tmp/pm_install_smoke.log')

  call delete(g:_smoke_root, 'rf')

  if g:_smoke_fail > 0
    cquit 1
  else
    quit!
  endif
endfunction

" --------------------------------------------------------------------------
" Schedule: launch after 500 ms, assert after 8 s
" --------------------------------------------------------------------------
if !plugin_manager#async#supported()
  call writefile(['SKIP: +job/+channel not available'], '/tmp/pm_install_smoke.log')
  quit!
endif

call timer_start(500,  function('s:launch'))
call timer_start(8000, function('s:finish'))
