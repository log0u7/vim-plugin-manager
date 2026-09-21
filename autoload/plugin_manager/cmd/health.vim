" autoload/plugin_manager/cmd/health.vim - Health diagnostic command
" Maintainer: G.K.E. <gke@6admin.io>

" Run a set of read-only precondition checks and report results in the sidebar.
" Each check renders one line with an ok/warn/fail glyph.  A failed check is a
" reported line, not a thrown exception; the function never aborts mid-run.
"
" Structure: s:checks() returns one Funcref per check.  Each Funcref takes the
" vim dir and returns a list of [status, label, detail] items (status
" 'ok'|'warn'|'fail'); an empty list means the check is not applicable.

function! plugin_manager#cmd#health#execute() abort
  try
    call plugin_manager#ui#open_header('Health check:')

    let l:vim_dir = plugin_manager#core#util#get_config('vim_dir', '')
    let l:ok    = 0
    let l:warn  = 0
    let l:fail  = 0

    for l:Check in s:checks()
      for l:result in l:Check(l:vim_dir)
        call s:report(l:result[0], l:result[1], l:result[2])
        if l:result[0] ==# 'ok'
          let l:ok += 1
        elseif l:result[0] ==# 'warn'
          let l:warn += 1
        else
          let l:fail += 1
        endif
      endfor
    endfor

    " Footer summary
    let l:total = l:ok + l:warn + l:fail
    let l:summary = l:ok . '/' . l:total . ' checks passed'
    if l:warn > 0
      let l:summary .= ', ' . l:warn . ' warning' . (l:warn == 1 ? '' : 's')
    endif
    if l:fail > 0
      let l:summary .= ', ' . l:fail . ' failure' . (l:fail == 1 ? '' : 's')
    endif

    if l:fail > 0
      call plugin_manager#ui#footer([plugin_manager#ui#error(l:summary)])
    elseif l:warn > 0
      call plugin_manager#ui#footer([plugin_manager#ui#warning(l:summary)])
    else
      call plugin_manager#ui#footer([plugin_manager#ui#success(l:summary)])
    endif

  catch
    call plugin_manager#core#handle_error(v:exception, 'health')
  endtry
endfunction

" ------------------------------------------------------------------------------
" CHECKS
" ------------------------------------------------------------------------------

" One Funcref per check, in report order.  Each takes the vim dir and
" returns a list of [status, label, detail] items ([] = not applicable).
function! s:checks() abort
  return [
        \ {-> executable('git')
        \      ? [['ok', 'git executable', 'found']]
        \      : [['fail', 'git executable', 'not found in PATH']]},
        \ function('s:check_git_version'),
        \ {-> (has('job') && has('channel'))
        \      ? [['ok', 'async support', '+job +channel available']]
        \      : [['warn', 'async support',
        \          '+job or +channel missing - operations will run synchronously']]},
        \ {-> v:version >= 802
        \      ? [['ok', 'Vim version',
        \          'v' . (v:version / 100) . '.' . (v:version % 100) . ' (>= 8.2)']]
        \      : [['fail', 'Vim version',
        \          'v' . (v:version / 100) . '.' . (v:version % 100) . ' (< 8.2 required)']]},
        \ {-> &encoding ==# 'utf-8'
        \      ? [['ok', 'encoding', 'utf-8']]
        \      : [['warn', 'encoding',
        \          &encoding . ' (utf-8 recommended for fancy UI)']]},
        \ {vim_dir -> empty(vim_dir)
        \      ? [['fail', 'vim dir', 'g:plugin_manager_vim_dir not set']]
        \      : (isdirectory(vim_dir . '/.git')
        \          ? [['ok', 'vim dir is git repo', vim_dir]]
        \          : [['fail', 'vim dir is git repo', vim_dir . '/.git not found']])},
        \ function('s:check_log_dir'),
        \ function('s:check_submodules'),
        \ {vim_dir -> empty(vim_dir) || !isdirectory(vim_dir . '/.git')
        \      ? []
        \      : (s:remote_names(vim_dir)->empty()
        \          ? [['warn', 'remotes', 'no remotes configured (backup/push will fail)']]
        \          : [['ok', 'remotes', s:remote_names(vim_dir)->join(', ')]])},
        \ ]
endfunction

" Git version (minimum: 2.39, set by Debian Bookworm).
" The codebase uses no feature newer than git 1.9 in practice;
" 2.39 is chosen to match the oldest fully-supported distribution
" in the CI matrix (Debian Bookworm ships 2.39.2).
" Skipped entirely when git is not executable (check 1 already failed).
function! s:check_git_version(_) abort
  if !executable('git')
    return []
  endif
  " Route through git#execute like every other git invocation
  let l:git_ver_out = plugin_manager#git#execute('git --version', '', 0, 0).output
  " Output is 'git version X.Y.Z'
  let l:git_ver_parts = matchlist(l:git_ver_out,
        \ 'git version \(\d\+\)\.\(\d\+\)')
  if empty(l:git_ver_parts)
    return [['warn', 'git version', 'could not parse: ' . trim(l:git_ver_out)]]
  endif
  let l:git_major = str2nr(l:git_ver_parts[1])
  let l:git_minor = str2nr(l:git_ver_parts[2])
  let l:git_ver_str = l:git_ver_parts[1] . '.' . l:git_ver_parts[2]
  if l:git_major > 2 || (l:git_major == 2 && l:git_minor >= 39)
    return [['ok', 'git version', l:git_ver_str . ' (>= 2.39)']]
  endif
  return [['warn', 'git version',
        \ l:git_ver_str . ' (< 2.39 documented minimum)']]
endfunction

" Log directory writable (probed with a throwaway file).  Not applicable
" when the vim dir is not set (check 6 already reported that).
function! s:check_log_dir(vim_dir) abort
  if empty(a:vim_dir)
    return []
  endif
  let l:log_dir = a:vim_dir . '/logs'
  let l:probe   = l:log_dir . '/.pm_health_probe'
  if !isdirectory(l:log_dir)
    call mkdir(l:log_dir, 'p')
  endif
  if writefile([], l:probe) == 0
    call delete(l:probe)
    return [['ok', 'log dir writable', l:log_dir]]
  endif
  return [['fail', 'log dir writable', 'cannot write to ' . l:log_dir]]
endfunction

" Submodules initialized (no '-' prefix in git submodule status) and in
" sync (no '+' prefix).  Can report BOTH problems in one pass.  Not
" applicable outside a git repo.
function! s:check_submodules(vim_dir) abort
  if empty(a:vim_dir) || !isdirectory(a:vim_dir . '/.git')
    return []
  endif
  let l:sub_res = plugin_manager#git#execute(
        \ 'git submodule status', a:vim_dir, 0, 0)
  if !l:sub_res.success
    return [['warn', 'submodules', 'git submodule status failed']]
  endif
  let l:uninit    = []
  let l:outofsync = []
  for l:sline in split(l:sub_res.output, "\n")
    if l:sline =~# '^-'
      call add(l:uninit, substitute(l:sline, '^-\S\+ \(\S\+\).*$', '\1', ''))
    elseif l:sline =~# '^+'
      call add(l:outofsync, substitute(l:sline, '^+\S\+ \(\S\+\).*$', '\1', ''))
    endif
  endfor
  if empty(l:uninit) && empty(l:outofsync)
    return [['ok', 'submodules', 'all initialized and in sync']]
  endif
  let l:results = []
  if !empty(l:uninit)
    call add(l:results, ['fail', 'submodules uninitialized', join(l:uninit, ', ')])
  endif
  if !empty(l:outofsync)
    call add(l:results, ['warn', 'submodules out of sync', join(l:outofsync, ', ')])
  endif
  return l:results
endfunction

" Configured git remotes of the vim dir (empty list when none).
function! s:remote_names(vim_dir) abort
  let l:rmt_res = plugin_manager#git#execute('git remote', a:vim_dir, 0, 0)
  return filter(split(l:rmt_res.output, "\n"), '!empty(v:val)')
endfunction

" ------------------------------------------------------------------------------
" PRIVATE HELPERS
" ------------------------------------------------------------------------------

" Render one check line using the UI operation API.
function! s:report(status, label, detail) abort
  let l:id = plugin_manager#ui#start_operation(a:label, '')
  let l:text = empty(a:detail) ? a:label : a:label . ': ' . a:detail
  call plugin_manager#ui#complete_operation(l:id, a:status, l:text)
endfunction
