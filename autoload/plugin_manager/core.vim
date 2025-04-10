" autoload/plugin_manager/core.vim - Core utilities and error handling for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4-dev

" ------------------------------------------------------------------------------
" ERROR HANDLING SYSTEM
" ------------------------------------------------------------------------------

" Create a standardized error with component information
function! plugin_manager#core#throw(component, message) abort
  throw 'PM_ERROR:' . a:component . ':' . a:message
endfunction

" Check if an error is a plugin manager error
function! plugin_manager#core#is_pm_error(error) abort
  return a:error =~# '^PM_ERROR:'
endfunction

" Format plugin manager error for user display
function! plugin_manager#core#format_error(error) abort
  if plugin_manager#core#is_pm_error(a:error)
    let l:parts = split(a:error, ':')
    return l:parts[2:]->join(':')
  endif
  return a:error
endfunction

" Handle errors consistently throughout the plugin
function! plugin_manager#core#handle_error(error, component) abort
  let l:error = plugin_manager#core#is_pm_error(a:error) 
          \ ? plugin_manager#core#format_error(a:error)
          \ : 'Unexpected error in ' . a:component . ': ' . a:error
  
  " Display error in UI if loaded
  if exists('*plugin_manager#ui#open_sidebar')
    call plugin_manager#ui#open_sidebar([
          \ 'Error in ' . a:component . ':',
          \ repeat('-', len(a:component) + 10),
          \ '',
          \ l:error
          \ ])
  else
    " Fallback if UI isn't loaded
    echohl ErrorMsg
    echomsg l:error
    echohl None
  endif
  
  return l:error
endfunction

" ------------------------------------------------------------------------------
" DIRECTORY AND PATH MANAGEMENT
" ------------------------------------------------------------------------------

" Ensure we're in the Vim config directory
function! plugin_manager#core#ensure_vim_directory() abort
  " Get current directory
  let l:current_dir = getcwd()
  
  " Get configured vim directory
  let l:vim_dir = plugin_manager#core#get_config('vim_dir', '')
  
  " Check if we're already in the vim directory
  if l:current_dir ==# l:vim_dir
    return 1
  endif
  
  " Check if the vim directory exists
  if !isdirectory(l:vim_dir)
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
  
  " Change to vim directory
  try
    execute 'cd ' . fnameescape(l:vim_dir)
  catch
    let l:error_lines = ['Error:', '------', '', 'Could not change to Vim directory: ' . l:vim_dir, 
          \ 'Error: ' . v:exception]
    
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
  endtry
  
  " Check if it's a git repository
  if !isdirectory('.git')
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

" Check if a path is a local filesystem path
function! plugin_manager#core#is_local_path(path) abort
  " Starts with '~' (home path)
  if a:path =~ '^\~\/'
    return 1
  endif
    
  " Absolute path (starts with '/' on Unix or drive letter on Windows)
  if a:path =~ '^\/\|^[A-Za-z]:[\\\/]'
    return 1
  endif
    
  " Relative path that exists locally
  let l:expanded_path = expand(a:path)
  if isdirectory(l:expanded_path)
    return 1
  endif
    
  return 0
endfunction

" Clean and normalize a path
function! plugin_manager#core#normalize_path(path) abort
  " Convert backslashes to forward slashes on Windows
  let l:path = a:path
  if has('win32') || has('win64')
    let l:path = substitute(l:path, '\\', '/', 'g')
  endif
  
  " Expand ~ in paths
  if l:path =~ '^\~\/'
    let l:path = expand(l:path)
  endif
  
  " Remove trailing slash
  let l:path = substitute(l:path, '\/\+$', '', '')
  
  " Remove duplicate slashes
  let l:path = substitute(l:path, '\/\+', '/', 'g')
  
  return l:path
endfunction

" Make a path relative to vim directory if possible
function! plugin_manager#core#make_relative_path(path) abort
  let l:vim_dir = plugin_manager#core#get_config('vim_dir', '')
  let l:norm_path = plugin_manager#core#normalize_path(a:path)
  let l:norm_vim_dir = plugin_manager#core#normalize_path(l:vim_dir)
  
  " Check if the path starts with vim_dir
  if l:norm_path =~# '^' . escape(l:norm_vim_dir, '/.\') . '\/'
    return substitute(l:norm_path, '^' . escape(l:norm_vim_dir, '/.\') . '\/', '', '')
  endif
  
  return l:norm_path
endfunction

" Ensure a directory exists, creating it if necessary
function! plugin_manager#core#ensure_directory(dir) abort
  let l:dir = plugin_manager#core#normalize_path(a:dir)
  
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

" Get a configuration value with fallback
function! plugin_manager#core#get_config(name, default) abort
  let l:var_name = 'g:plugin_manager_' . a:name
  return exists(l:var_name) ? eval(l:var_name) : a:default
endfunction

" Get all plugin manager configuration as a dictionary
function! plugin_manager#core#get_all_config() abort
  let l:config = {}
  
  " Core paths
  let l:config.vim_dir = plugin_manager#core#get_config('vim_dir', '')
  let l:config.plugins_dir = plugin_manager#core#get_config('plugins_dir', l:config.vim_dir . '/pack/plugins')
  let l:config.start_dir = plugin_manager#core#get_config('start_dir', 'start')
  let l:config.opt_dir = plugin_manager#core#get_config('opt_dir', 'opt')
  let l:config.vimrc_path = plugin_manager#core#get_config('vimrc_path', '')
  
  " UI settings
  let l:config.sidebar_width = plugin_manager#core#get_config('sidebar_width', 60)
  let l:config.fancy_ui = plugin_manager#core#get_config('fancy_ui', 1)
  
  " Git settings
  let l:config.default_git_host = plugin_manager#core#get_config('default_git_host', 'github.com')
  
  return l:config
endfunction

" Get plugin directory for specific type (start or opt)
function! plugin_manager#core#get_plugin_dir(type) abort
  let l:config = plugin_manager#core#get_all_config()
  
  if a:type ==# 'start' || a:type ==# 'opt'
    return l:config.plugins_dir . '/' . l:config[a:type . '_dir']
  endif
  
  " Default to start
  return l:config.plugins_dir . '/' . l:config.start_dir
endfunction

" ------------------------------------------------------------------------------
" URL AND PLUGIN NAME UTILITIES
" ------------------------------------------------------------------------------

" Regular expressions for URL and plugin short name validation
let s:url_regexp = '^https\?://.\+\|^git@.\+:.\\+$'
let s:short_name_regexp = '^[a-zA-Z0-9_.-]\+/[a-zA-Z0-9_.-]\+$'

" Convert a shortname like 'user/repo' to a full URL
function! plugin_manager#core#convert_to_full_url(shortname) abort
  " If it's a local path
  if plugin_manager#core#is_local_path(a:shortname)
    return 'local:' . expand(a:shortname)
  endif
      
  " If it's already a URL, return as is
  if a:shortname =~ s:url_regexp
    return a:shortname
  endif
      
  " If it's a user/repo format
  if a:shortname =~ s:short_name_regexp
    let l:host = plugin_manager#core#get_config('default_git_host', 'github.com')
    return 'https://' . l:host . '/' . a:shortname . '.git'
  endif
      
  " Return empty string for unrecognized format
  return ''
endfunction

" Extract plugin name from various formats
function! plugin_manager#core#extract_plugin_name(input) abort
  " For local paths
  if a:input =~ '^local:'
    let l:path = substitute(a:input, '^local:', '', '')
    return fnamemodify(l:path, ':t')
  endif
  
  " For URLs
  if a:input =~ s:url_regexp
    " Extract repo name from URL, preserving dots in the name
    let l:name = matchstr(a:input, '[^/]*$')  " Get everything after the last /
    return substitute(l:name, '\.git$', '', '')  " Remove .git extension if present
  endif
  
  " For user/repo format
  if a:input =~ s:short_name_regexp
    return matchstr(a:input, '[^/]*$')  " Get everything after the last /
  endif
  
  return a:input  " Return as is if format not recognized
endfunction

" ------------------------------------------------------------------------------
" FILE SYSTEM OPERATIONS
" ------------------------------------------------------------------------------

" Platform-independent file existence check
function! plugin_manager#core#file_exists(path) abort
  return filereadable(expand(a:path))
endfunction

" Platform-independent directory existence check
function! plugin_manager#core#dir_exists(path) abort
  return isdirectory(expand(a:path))
endfunction

" Platform-independent file or directory removal
function! plugin_manager#core#remove_path(path) abort
  let l:path = expand(a:path)
  
  if empty(l:path) || l:path ==# '/' || l:path =~# '^[A-Za-z]:[\\/]*$'
    " Safety check to prevent catastrophic removals
    return 0
  endif
  
  if plugin_manager#core#dir_exists(l:path)
    if has('win32') || has('win64')
      " Windows
      let l:cmd = 'rmdir /S /Q ' . shellescape(l:path)
    else
      " Unix
      let l:cmd = 'rm -rf ' . shellescape(l:path)
    endif
    
    let l:result = system(l:cmd)
    return v:shell_error == 0
  elseif plugin_manager#core#file_exists(l:path)
    if has('win32') || has('win64')
      " Windows
      let l:cmd = 'del /F /Q ' . shellescape(l:path)
    else
      " Unix
      let l:cmd = 'rm -f ' . shellescape(l:path)
    endif
    
    let l:result = system(l:cmd)
    return v:shell_error == 0
  endif
  
  " Path doesn't exist, so "removal" is successful
  return 1
endfunction

" ------------------------------------------------------------------------------
" PLUGIN OPTIONS PARSING
" ------------------------------------------------------------------------------

" Parse options from string to dictionary
function! plugin_manager#core#parse_options(options_str) abort
  let l:options = {}
  
  " Split by commas, but respect nested structures
  let l:option_parts = split(a:options_str, ',')
  
  for l:part in l:option_parts
    let l:kv_match = matchlist(l:part, '[''"]\?\(\w\+\)[''"]\?\s*:\s*\(.\{-}\)\s*$')
    if !empty(l:kv_match)
      let l:key = trim(l:kv_match[1])
      let l:value = trim(l:kv_match[2])
      
      " Remove quotes from string values
      if l:value =~ '^[''"].*[''"]$'
        let l:value = l:value[1:-2]
      endif
      
      let l:options[l:key] = l:value
    endif
  endfor
  
  return l:options
endfunction

" Process plugin options with defaults
function! plugin_manager#core#process_plugin_options(args) abort
  " Default options
  let l:options = {
      \ 'dir': '',
      \ 'load': 'start',
      \ 'branch': '',
      \ 'tag': '',
      \ 'exec': ''
      \ }
  
  " No options provided
  if empty(a:args)
    return l:options
  endif
  
  " Check if options were provided as a dictionary
  if type(a:args[0]) == v:t_dict
    " Update options with provided values
    for [l:key, l:val] in items(a:args[0])
      if has_key(l:options, l:key)
        let l:options[l:key] = l:val
      endif
    endfor
  elseif len(a:args) >= 1 && type(a:args[0]) == v:t_string
    " Old format with separate arguments
    " Custom name provided as first argument
    let l:options.dir = a:args[0]
    
    " Optional loading provided as second argument
    if len(a:args) >= 2 && a:args[1] ==# 'opt'
      let l:options.load = 'opt'
    endif
  endif
  
  return l:options
endfunction