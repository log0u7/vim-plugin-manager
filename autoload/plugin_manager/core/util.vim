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
  if l:norm_path =~# '^' . escape(l:norm_vim_dir, '/.\') . '\/'
    return substitute(l:norm_path, '^' . escape(l:norm_vim_dir, '/.\') . '\/', '', '')
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
      return 0
    endtry
  endif
  return 1
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
" URL AND PLUGIN NAME UTILITIES
" ------------------------------------------------------------------------------

let s:url_regexp = '^https\?://.\+\|^git@.\+:.\+$'
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
  \ 'exec': ''
  \ }

  if empty(a:args)
    return l:options
  endif

  if type(a:args[0]) == v:t_dict
    for [l:key, l:val] in items(a:args[0])
      if has_key(l:options, l:key)
        if l:key ==# 'load' && l:val !=# 'start' && l:val !=# 'opt'
          echohl WarningMsg
          echomsg "Invalid 'load' value: " . l:val . ". Using default: 'start'"
          echohl None
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
    let l:options.dir = a:args[0]
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

  return l:options
endfunction
