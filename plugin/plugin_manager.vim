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
let s:urlRegexp = 'https\?:\/\/\(www\.\)\?[-a-zA-Z0-9@:%._\\+~#=]\{1,256}\.[a-zA-Z0-9()]\{1,6}\b\([-a-zA-Z0-9()@:%_\\+.~#?&//=]*\)'
let s:shortNameRegexp = '^[a-zA-Z0-9_-]\+\/[a-zA-Z0-9_-]\+$'
let s:buffer_name = 'PluginManager'

" Variable to prevent multiple concurrent updates
let s:update_in_progress = 0

" Cache for gitmodules data
let s:gitmodules_cache = {}
let s:gitmodules_mtime = 0

" Define commands
command! -nargs=* PluginManager call plugin_manager#main(<f-args>)
command! -nargs=1 PluginManagerRemote call plugin_manager#modules#add_remote_backup(<f-args>)
command! PluginManagerToggle call plugin_manager#ui#toggle_sidebar()

" Main function to handle PluginManager commands
function! plugin_manager#main(...)
  if a:0 < 1
    call plugin_manager#ui#usage()
    return
  endif
  
  let l:command = a:1
  
  if l:command == "add" && a:0 >= 2
    call plugin_manager#modules#add(a:2, get(a:, 3, ""), get(a:, 4, ""))
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