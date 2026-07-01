" autoload/plugin_manager/cmd/health.vim - Health diagnostic command
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 2.0.0

" Run a set of read-only precondition checks and report results in the sidebar.
" Each check renders one line with an ok/warn/fail glyph.  A failed check is a
" reported line, not a thrown exception; the function never aborts mid-run.
function! plugin_manager#cmd#health#execute() abort
  try
    call plugin_manager#ui#open_header('Health check:')

    let l:vim_dir = plugin_manager#core#get_config('vim_dir', '')
    let l:ok    = 0
    let l:warn  = 0
    let l:fail  = 0

    " ------------------------------------------------------------------
    " 1. Git executable present
    " ------------------------------------------------------------------
    if executable('git')
      call s:report('ok', 'git executable', 'found')
      let l:ok += 1
    else
      call s:report('fail', 'git executable', 'not found in PATH')
      let l:fail += 1
    endif

    " ------------------------------------------------------------------
    " 2. Git version (minimum: 2.39, set by Debian Bookworm).
    "    The codebase uses no feature newer than git 1.9 in practice;
    "    2.39 is chosen to match the oldest fully-supported distribution
    "    in the CI matrix (Debian Bookworm ships 2.39.2).
    " ------------------------------------------------------------------
    if executable('git')
      let l:git_ver_out = system('git --version 2>/dev/null')
      " Output is 'git version X.Y.Z'
      let l:git_ver_parts = matchlist(l:git_ver_out,
            \ 'git version \(\d\+\)\.\(\d\+\)')
      if !empty(l:git_ver_parts)
        let l:git_major = str2nr(l:git_ver_parts[1])
        let l:git_minor = str2nr(l:git_ver_parts[2])
        let l:git_ver_str = l:git_ver_parts[1] . '.' . l:git_ver_parts[2]
        if l:git_major > 2 || (l:git_major == 2 && l:git_minor >= 39)
          call s:report('ok', 'git version', l:git_ver_str . ' (>= 2.39)')
          let l:ok += 1
        else
          call s:report('warn', 'git version',
                \ l:git_ver_str . ' (< 2.39 documented minimum)')
          let l:warn += 1
        endif
      else
        call s:report('warn', 'git version', 'could not parse: ' . trim(l:git_ver_out))
        let l:warn += 1
      endif
    endif

    " ------------------------------------------------------------------
    " 3. Async support (+job and +channel)
    " ------------------------------------------------------------------
    if has('job') && has('channel')
      call s:report('ok', 'async support', '+job +channel available')
      let l:ok += 1
    else
      call s:report('warn', 'async support',
            \ '+job or +channel missing - operations will run synchronously')
      let l:warn += 1
    endif

    " ------------------------------------------------------------------
    " 4. Vim version >= 8.2
    " ------------------------------------------------------------------
    if v:version >= 802
      call s:report('ok', 'Vim version',
            \ 'v' . (v:version / 100) . '.' . (v:version % 100) . ' (>= 8.2)')
      let l:ok += 1
    else
      call s:report('fail', 'Vim version',
            \ 'v' . (v:version / 100) . '.' . (v:version % 100) . ' (< 8.2 required)')
      let l:fail += 1
    endif

    " ------------------------------------------------------------------
    " 5. Encoding UTF-8
    " ------------------------------------------------------------------
    if &encoding ==# 'utf-8'
      call s:report('ok', 'encoding', 'utf-8')
      let l:ok += 1
    else
      call s:report('warn', 'encoding',
            \ &encoding . ' (utf-8 recommended for fancy UI)')
      let l:warn += 1
    endif

    " ------------------------------------------------------------------
    " 6. Vim directory is a git repository
    " ------------------------------------------------------------------
    if !empty(l:vim_dir) && isdirectory(l:vim_dir . '/.git')
      call s:report('ok', 'vim dir is git repo', l:vim_dir)
      let l:ok += 1
    elseif empty(l:vim_dir)
      call s:report('fail', 'vim dir', 'g:plugin_manager_vim_dir not set')
      let l:fail += 1
    else
      call s:report('fail', 'vim dir is git repo',
            \ l:vim_dir . '/.git not found')
      let l:fail += 1
    endif

    " ------------------------------------------------------------------
    " 7. Log directory writable
    " ------------------------------------------------------------------
    if !empty(l:vim_dir)
      let l:log_dir   = l:vim_dir . '/logs'
      let l:probe     = l:log_dir . '/.pm_health_probe'
      if !isdirectory(l:log_dir)
        call mkdir(l:log_dir, 'p')
      endif
      if writefile([], l:probe) == 0
        call delete(l:probe)
        call s:report('ok', 'log dir writable', l:log_dir)
        let l:ok += 1
      else
        call s:report('fail', 'log dir writable',
              \ 'cannot write to ' . l:log_dir)
        let l:fail += 1
      endif
    endif

    " ------------------------------------------------------------------
    " 8. Submodules initialized (no '-' prefix in git submodule status)
    " ------------------------------------------------------------------
    if !empty(l:vim_dir) && isdirectory(l:vim_dir . '/.git')
      let l:sub_res = plugin_manager#git#execute(
            \ 'git submodule status', l:vim_dir, 0, 0)
      if l:sub_res.success
        let l:uninit  = []
        let l:outofsync = []
        for l:sline in split(l:sub_res.output, "\n")
          if l:sline =~# '^-'
            call add(l:uninit, substitute(l:sline, '^-\S\+ \(\S\+\).*$', '\1', ''))
          elseif l:sline =~# '^+'
            call add(l:outofsync, substitute(l:sline, '^+\S\+ \(\S\+\).*$', '\1', ''))
          endif
        endfor
        if empty(l:uninit) && empty(l:outofsync)
          call s:report('ok', 'submodules', 'all initialized and in sync')
          let l:ok += 1
        else
          if !empty(l:uninit)
            call s:report('fail', 'submodules uninitialized',
                  \ join(l:uninit, ', '))
            let l:fail += 1
          endif
          if !empty(l:outofsync)
            call s:report('warn', 'submodules out of sync',
                  \ join(l:outofsync, ', '))
            let l:warn += 1
          endif
        endif
      else
        call s:report('warn', 'submodules', 'git submodule status failed')
        let l:warn += 1
      endif
    endif

    " ------------------------------------------------------------------
    " 9. Remotes configured
    " ------------------------------------------------------------------
    if !empty(l:vim_dir) && isdirectory(l:vim_dir . '/.git')
      let l:rmt_res = plugin_manager#git#execute(
            \ 'git remote', l:vim_dir, 0, 0)
      let l:remotes = filter(split(l:rmt_res.output, "\n"), '!empty(v:val)')
      if !empty(l:remotes)
        call s:report('ok', 'remotes', join(l:remotes, ', '))
        let l:ok += 1
      else
        call s:report('warn', 'remotes',
              \ 'no remotes configured (backup/push will fail)')
        let l:warn += 1
      endif
    endif

    " ------------------------------------------------------------------
    " Footer summary
    " ------------------------------------------------------------------
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
" PRIVATE HELPERS
" ------------------------------------------------------------------------------

" Render one check line using the UI operation API.
function! s:report(status, label, detail) abort
  let l:id = plugin_manager#ui#start_operation(a:label, '')
  let l:text = empty(a:detail) ? a:label : a:label . ': ' . a:detail
  call plugin_manager#ui#complete_operation(l:id, a:status, l:text)
endfunction
