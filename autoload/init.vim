" Configuration for vim-plugin-manager
" Handles plugin initialization and configuration variables

" Configuration
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