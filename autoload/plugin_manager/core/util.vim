" autoload/plugin_manager/core/util.vim - Utility functions for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>

" ------------------------------------------------------------------------------
" DIRECTORY AND PATH MANAGEMENT
" ------------------------------------------------------------------------------

" Pure validation: check that vim_dir exists and is a git repo, WITHOUT
" changing the process cwd.
function! plugin_manager#core#util#ensure_vim_directory() abort
  let l:vim_dir = plugin_manager#core#util#get_config('vim_dir', '')

  if empty(l:vim_dir) || !isdirectory(l:vim_dir)
    let l:error_lines = ['Error:', '------', '', 'Vim directory not found: ' . l:vim_dir,
    \ 'Please set g:plugin_manager_vim_dir to your Vim configuration directory.']
    if exists('*plugin_manager#ui#open_sidebar')
      call plugin_manager#ui#open_sidebar(l:error_lines)
    else
      echohl ErrorMsg
      for l:line in l:error_lines
        echomsg l:line
      endfor
      echohl None
    endif
    return 0
  endif

  if !isdirectory(l:vim_dir . '/.git')
    let l:error_lines = ['Error:', '------', '', 'The Vim directory is not a git repository.',
    \ 'Please initialize it with: git init ' . l:vim_dir]
    if exists('*plugin_manager#ui#open_sidebar')
      call plugin_manager#ui#open_sidebar(l:error_lines)
    else
      echohl ErrorMsg
      for l:line in l:error_lines
        echomsg l:line
      endfor
      echohl None
    endif
    return 0
  endif

  return 1
endfunction

function! plugin_manager#core#util#require_vim_directory(component) abort
  if !plugin_manager#core#util#ensure_vim_directory()
    call plugin_manager#core#throw(a:component, 'NOT_VIM_DIR', 'Not in Vim configuration directory')
  endif
endfunction

function! plugin_manager#core#util#is_local_path(path) abort
  if a:path =~ '^\~\/'
    return 1
  endif
  if a:path =~ '^\/'
    return 1
  endif
  let l:expanded_path = expand(a:path)
  if isdirectory(l:expanded_path)
    return 1
  endif
  return 0
endfunction

function! plugin_manager#core#util#normalize_path(path) abort
  let l:path = a:path
  if l:path =~ '^\~\/'
    let l:path = expand(l:path)
  endif
  let l:path = substitute(l:path, '\/\+$', '', '')
  let l:path = substitute(l:path, '\/\+', '/', 'g')
  return l:path
endfunction

function! plugin_manager#core#util#make_relative_path(path) abort
  let l:vim_dir = plugin_manager#core#util#get_config('vim_dir', '')
  let l:norm_path = plugin_manager#core#util#normalize_path(a:path)
  let l:norm_vim_dir = plugin_manager#core#util#normalize_path(l:vim_dir)
  if l:norm_path =~# '^' . escape(l:norm_vim_dir, '/.\*[]^$~') . '\/'
    return substitute(l:norm_path, '^' . escape(l:norm_vim_dir, '/.\*[]^$~') . '\/', '', '')
  endif
  return l:norm_path
endfunction

function! plugin_manager#core#util#ensure_directory(dir) abort
  let l:dir = plugin_manager#core#util#normalize_path(a:dir)
  if !isdirectory(l:dir)
    try
      call mkdir(l:dir, 'p')
      return 1
    catch
      " A silent mkdir failure cascades into confusing downstream errors:
      " warn so the real cause is visible.
      call plugin_manager#core#log#warn('util',
            \ 'mkdir failed: ' . l:dir . ': ' . v:exception)
      return 0
    endtry
  endif
  return 1
endfunction

" ------------------------------------------------------------------------------
" SHELL COMMAND EXECUTION (non-git)
" ------------------------------------------------------------------------------

" Run an arbitrary shell command scoped to a directory.
" Uses `cd <dir> && <cmd>` (POSIX subshell) which never changes Vim's
" process cwd. For git commands, use git#execute (which injects git -C).
"
" @param cmd  Shell command string.
" @param dir  Directory to scope the command in. Empty = run unscoped.
" @returns    {'success': bool, 'output': string}
function! plugin_manager#core#util#run_in_dir(cmd, dir) abort
  let l:full_cmd = empty(a:dir) ? a:cmd : 'cd ' . shellescape(a:dir) . ' && ' . a:cmd

  if plugin_manager#core#util#get_config('trace_commands', 0)
    call plugin_manager#core#log#trace('util',
          \ 'run_in_dir: ' . plugin_manager#core#util#sanitize_cmd(l:full_cmd))
  endif

  let l:output = system(l:full_cmd)
  return {'success': v:shell_error == 0, 'output': l:output}
endfunction

" ------------------------------------------------------------------------------
" CONFIGURATION MANAGEMENT
" ------------------------------------------------------------------------------

function! plugin_manager#core#util#get_config(name, default) abort
  return get(g:, 'plugin_manager_' . a:name, a:default)
endfunction

function! plugin_manager#core#util#get_pull_flag() abort
  let l:strategy = plugin_manager#core#util#get_config('pull_strategy', 'ff-only')
  if l:strategy ==# 'merge'
    return '--no-rebase'
  elseif l:strategy ==# 'rebase'
    return '--rebase'
  endif
  return '--ff-only'
endfunction

function! plugin_manager#core#util#should_auto_commit() abort
  return plugin_manager#core#util#get_config('auto_commit_on_update', 1)
endfunction

function! plugin_manager#core#util#get_plugin_dir(type) abort
  let l:plugins_dir = plugin_manager#core#util#get_config('plugins_dir', '')
  let l:start_dir   = plugin_manager#core#util#get_config('start_dir', 'start')
  let l:opt_dir     = plugin_manager#core#util#get_config('opt_dir', 'opt')
  if a:type ==# 'opt'
    return l:plugins_dir . '/' . l:opt_dir
  endif
  return l:plugins_dir . '/' . l:start_dir
endfunction

" ------------------------------------------------------------------------------
" UNTRUSTED INPUT VALIDATION (issue #9)
"
" Contract: warn + safe fallback (empty string), never a hard throw.  The
" degraded state is visible in the log, the operation stays usable.
" ------------------------------------------------------------------------------

" Strip https/http userinfo (user:token@) from a URL: logs, error messages
" and commit texts must never carry credentials.
" Strip userinfo from an https/http URL (single occurrence or all with
" a:flags='g', for command strings embedding several URLs).
function! s:sanitize_url_impl(url, flags) abort
  return substitute(a:url, '\(https\?://\)[^/@]*@', '\1', a:flags)
endfunction

function! plugin_manager#core#util#sanitize_url(url) abort
  return s:sanitize_url_impl(a:url, '')
endfunction

" Strip userinfo from every https/http URL inside a command string (traces
" and error messages embed whole commands).
function! plugin_manager#core#util#sanitize_cmd(cmd) abort
  return s:sanitize_url_impl(a:cmd, 'g')
endfunction

" Validate a branch name coming from .gitmodules or user declarations.
" Returns the value when it is a plain refname, '' otherwise (callers fall
" back to default branch resolution).  A leading dash is parsed by git as an
" option (--upload-pack = remote code execution, proven in issue #9);
" anything outside ^[A-Za-z0-9._/-]+$ is not a refname git would track.
function! plugin_manager#core#util#sanitize_branch(branch) abort
  " First character may not be '-': a leading dash is parsed by git as an
  " option (--upload-pack = remote code execution, proven in issue #9).
  if a:branch =~# '^[A-Za-z0-9._/][A-Za-z0-9._/-]*$'
    return a:branch
  endif
  call plugin_manager#core#log#warn('util', 'untrusted branch ignored: ' . a:branch)
  return ''
endfunction

" Validate a module path coming from .gitmodules before it is used as a
" pathspec (git rm / git submodule deinit) or a filesystem target.  Returns
" the value when it is a repo-relative path under plugins_dir, '' otherwise.
" Glob characters as a pathspec expand to unrelated files ('*' removes
" everything); '..' and absolute paths escape the config repo.
function! plugin_manager#core#util#validate_module_path(path) abort
  if empty(a:path) || a:path =~# '^-' || a:path =~# '^[/~]'
        \ || a:path =~# '[*?\[]' || a:path =~# '\.\.'
    call plugin_manager#core#log#warn('util',
          \ 'untrusted module path ignored: ' . a:path)
    return ''
  endif
  " plugins_dir may be configured absolute: compare in repo-relative form.
  let l:plugins_dir = plugin_manager#core#util#make_relative_path(
        \ plugin_manager#core#util#get_config('plugins_dir', ''))
  if stridx(a:path, l:plugins_dir . '/') != 0
    call plugin_manager#core#log#warn('util',
          \ 'untrusted module path ignored: ' . a:path)
    return ''
  endif
  return a:path
endfunction

" Validate a `dir` option (custom install name).  Returns the value when it
" is a plain basename, '' otherwise (callers fall back to the default plugin
" name).  '..' and absolute paths would clone outside plugins_dir.
function! plugin_manager#core#util#validate_dir_name(dir) abort
  if empty(a:dir) || a:dir =~# '\.\.' || a:dir =~# '^[/~]'
        \ || fnamemodify(a:dir, ':t') !=# a:dir
    call plugin_manager#core#log#warn('util',
          \ 'untrusted dir option ignored: ' . a:dir)
    return ''
  endif
  return a:dir
endfunction

" ------------------------------------------------------------------------------
" URL AND PLUGIN NAME UTILITIES
" ------------------------------------------------------------------------------

let s:url_regexp = '^https\?://.\+\|^git@.\+:.\+\|^file://.\+'
let s:short_name_regexp = '^[a-zA-Z0-9_.-]\+/[a-zA-Z0-9_.-]\+$'

function! plugin_manager#core#util#convert_to_full_url(shortname) abort
  if plugin_manager#core#util#is_local_path(a:shortname)
    return 'local:' . expand(a:shortname)
  endif
  if a:shortname =~ s:url_regexp
    return a:shortname
  endif
  if a:shortname =~ s:short_name_regexp
    let l:host = plugin_manager#core#util#get_config('default_git_host', 'github.com')
    return 'https://' . l:host . '/' . a:shortname . '.git'
  endif
  return ''
endfunction

function! plugin_manager#core#util#extract_plugin_name(input) abort
  if a:input =~ '^local:'
    let l:path = substitute(a:input, '^local:', '', '')
    return fnamemodify(l:path, ':t')
  endif
  if a:input =~ s:url_regexp
    let l:name = matchstr(a:input, '[^/]*$')
    return substitute(l:name, '\.git$', '', '')
  endif
  if a:input =~ s:short_name_regexp
    return matchstr(a:input, '[^/]*$')
  endif
  return a:input
endfunction

" ------------------------------------------------------------------------------
" FILE SYSTEM OPERATIONS
" ------------------------------------------------------------------------------

function! plugin_manager#core#util#file_exists(path) abort
  return filereadable(expand(a:path))
endfunction

function! plugin_manager#core#util#dir_exists(path) abort
  return isdirectory(expand(a:path))
endfunction

" File or directory removal using Vim's native delete().
" Safety contract: refuses to delete if the resolved path is:
"   - empty or the filesystem root (/)
"   - the user home directory (expand('~'))
"   - equal to or a parent of the configured vim_dir
"   - contains traversal components (..)
function! plugin_manager#core#util#remove_path(path) abort
  let l:path = expand(a:path)

  if empty(l:path) || l:path ==# '/'
    return 0
  endif
  let l:home = expand('~')
  if l:path ==# l:home
    return 0
  endif
  if l:path =~# '\.\.'
    return 0
  endif

  let l:vim_dir = expand(plugin_manager#core#util#get_config('vim_dir', ''))
  if !empty(l:vim_dir)
    if l:path ==# l:vim_dir || stridx(l:path, l:vim_dir . '/') != 0
      return 0
    endif
  endif

  if plugin_manager#core#util#dir_exists(l:path)
    return delete(l:path, 'rf') == 0
  elseif plugin_manager#core#util#file_exists(l:path)
    return delete(l:path) == 0
  endif
  return 1
endfunction

" ------------------------------------------------------------------------------
" PLUGIN OPTIONS PARSING
" ------------------------------------------------------------------------------

function! plugin_manager#core#util#process_plugin_options(args) abort
  let l:options = {
  \ 'dir': '',
  \ 'load': 'start',
  \ 'branch': '',
  \ 'tag': '',
  \ 'commit': '',
  \ 'exec': '',
  \ 'on': [],
  \ 'for': []
  \ }

  if empty(a:args)
    return l:options
  endif

  if type(a:args[0]) == v:t_dict
    for [l:key, l:val] in items(a:args[0])
      if has_key(l:options, l:key)
        if (l:key ==# 'on' || l:key ==# 'for') && type(l:val) != v:t_list
          echohl WarningMsg
          echomsg "Invalid '" . l:key . "' value: must be a list. Ignored."
          echohl None
        elseif l:key ==# 'load' && l:val !=# 'start' && l:val !=# 'opt'
          echohl WarningMsg
          echomsg "Invalid 'load' value: " . l:val . ". Using default: 'start'"
          echohl None
        elseif l:key ==# 'dir'
          " Traversal guard: dir is a clone/install target (issue #9).
          let l:options.dir = plugin_manager#core#util#validate_dir_name(l:val)
        else
          let l:options[l:key] = l:val
        endif
      else
        echohl WarningMsg
        echomsg "Unknown option '" . l:key . "' ignored"
        echohl None
      endif
    endfor
  elseif len(a:args) >= 1 && type(a:args[0]) == v:t_string
    let l:options.dir = plugin_manager#core#util#validate_dir_name(a:args[0])
    if len(a:args) >= 2 && a:args[1] ==# 'opt'
      let l:options.load = 'opt'
    endif
    if get(g:, 'plugin_manager_show_deprecation_warnings', 1)
      echohl WarningMsg
      echomsg "Warning: Using deprecated format for plugin options."
      echomsg "Please use dictionary format: {'dir':'name', 'load':'start|opt', ...}"
      echohl None
    endif
  endif

  " On-demand options imply optional loading: a 'start' plugin would load
  " at startup and the lazy triggers would never be the entry point.
  if !empty(l:options.on) || !empty(l:options.for)
    let l:options.load = 'opt'
  endif

  return l:options
endfunction
