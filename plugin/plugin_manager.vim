" vim-plugin-manager.vim - Manage Vim plugins with git submodules
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3

if exists('g:loaded_plugin_manager') || &cp
  finish
endif
let g:loaded_plugin_manager = 1

if !exists('g:plugin_manager_vim_dir')
  " Detect Vim directory based on platform and configuration
  if has('nvim')
    " Neovim default config directory
    if empty($XDG_CONFIG_HOME)
      let g:plugin_manager_vim_dir = expand('~/.config/nvim')
    else
      let g:plugin_manager_vim_dir = expand($XDG_CONFIG_HOME . '/nvim')
    endif
  else
    " Standard Vim directory
    if has('win32') || has('win64')
      let g:plugin_manager_vim_dir = expand('~/vimfiles')
    else
      let g:plugin_manager_vim_dir = expand('~/.vim')
    endif
  endif
endif

if !exists('g:plugin_manager_plugins_dir')
  let g:plugin_manager_plugins_dir = g:plugin_manager_vim_dir . "/pack/plugins"
endif

if !exists('g:plugin_manager_start_dir')
  let g:plugin_manager_start_dir = "start"
endif

if !exists('g:plugin_manager_opt_dir')
  let g:plugin_manager_opt_dir = "opt"
endif

if !exists('g:plugin_manager_vimrc_path')
  if has('nvim')
    let g:plugin_manager_vimrc_path = g:plugin_manager_vim_dir . '/init.vim'
  else
    let g:plugin_manager_vimrc_path = g:plugin_manager_vim_dir . '/vimrc'
  endif
endif

if !exists('g:plugin_manager_sidebar_width')
  let g:plugin_manager_sidebar_width = 60
endif

if !exists('g:plugin_manager_default_git_host')
  let g:plugin_manager_default_git_host = "github.com"
endif

" Internal variables (shared between files)
let g:pm_urlRegexp = '^https\?://.\+\|^git@.\+:.\\+$'
let g:pm_shortNameRegexp = '^[a-zA-Z0-9_.-]\+/[a-zA-Z0-9_.-]\+$'

" Cache for gitmodules data
let g:pm_gitmodules_cache = {}
let g:pm_gitmodules_mtime = 0

" Variables to track plugin block
let s:plugin_block_start = 0
let s:plugin_block_active = 0

" Define commands
command! -nargs=* PluginManager call plugin_manager#main(<f-args>)
command! -nargs=1 PluginManagerRemote call plugin_manager#modules#add_remote_backup(<f-args>)
command! PluginManagerToggle call plugin_manager#ui#toggle_sidebar()
command! -nargs=0 PluginBegin call s:plugin_begin()
command! -nargs=+ -complete=file Plugin call s:plugin(<args>)
command! -nargs=0 PluginEnd call s:plugin_end()

" Functions for plugin block commands
function! s:plugin_begin()
  let s:plugin_block_start = line('.')
  let s:plugin_block_active = 1
  " Placeholder function for when user calls PluginBegin in vimrc
endfunction
  
function! s:plugin(...)
  " Placeholder function for when user calls Plugin in vimrc
  " This allows the syntax to be parsed without errors
endfunction
  
function! s:plugin_end()
  if s:plugin_block_active
    let l:end_line = line('.')
    call plugin_manager#utils#process_plugin_block(s:plugin_block_start, l:end_line)
    let s:plugin_block_active = 0
  endif
  " Placeholder function for when user calls PluginEnd in vimrc
endfunction

" Main function to handle PluginManager commands
function! plugin_manager#main(...)
  if a:0 < 1
    call plugin_manager#ui#usage()
    return
  endif
    
  let l:command = a:1
    
  if l:command == "add" && a:0 >= 2
    " Pass all arguments starting from index 1
    call call('plugin_manager#modules#add', a:000[1:])
  elseif l:command == "remove" && a:0 >= 2
    call plugin_manager#modules#remove(a:2, get(a:, 3, ""))
  elseif l:command == "list"
    call plugin_manager#modules#list()
  elseif l:command == "status"
    call plugin_manager#modules#status()
  elseif l:command == "update"
    " Pass the optional module name if provided
    if a:0 >= 2
      call plugin_manager#modules#update(a:2)
    else
      call plugin_manager#modules#update('all')
    endif
  elseif l:command == "summary"
    call plugin_manager#modules#summary()
  elseif l:command == "backup"
    call plugin_manager#modules#backup()
  elseif l:command == "restore"
    call plugin_manager#modules#restore()
  elseif l:command == "helptags"
    " Pass the optional module name if provided
    if a:0 >= 2
      call plugin_manager#modules#generate_helptags(1, a:2)
    else 
      call plugin_manager#modules#generate_helptags()
    endif
  elseif l:command == "reload"
    " Pass the optional module name if provided
    if a:0 >= 2
      call plugin_manager#modules#reload(a:2)
    else
      call plugin_manager#modules#reload()
    endif
  else
    call plugin_manager#ui#usage()
  endif
endfunction