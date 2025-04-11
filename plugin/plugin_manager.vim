" plugin/plugin_manager.vim - Main entry point for Vim Plugin Manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3.4

" Prevent loading the plugin multiple times
if exists('g:loaded_plugin_manager') || &cp
    finish
endif
let g:loaded_plugin_manager = 1

" ------------------------------------------------------------------------------
" CONFIGURATION VARIABLES
" ------------------------------------------------------------------------------

" Detect Vim directory based on platform
if !exists('g:plugin_manager_vim_dir')
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

" Plugin directory configuration
if !exists('g:plugin_manager_plugins_dir')
    let g:plugin_manager_plugins_dir = g:plugin_manager_vim_dir . "/pack/plugins"
endif

" Directory for auto-loaded plugins
if !exists('g:plugin_manager_start_dir')
    let g:plugin_manager_start_dir = "start"
endif

" Directory for optional (lazy-loaded) plugins
if !exists('g:plugin_manager_opt_dir')
    let g:plugin_manager_opt_dir = "opt"
endif

" Path to vimrc/init.vim
if !exists('g:plugin_manager_vimrc_path')
    if has('nvim')
        let g:plugin_manager_vimrc_path = g:plugin_manager_vim_dir . '/init.vim'
    else
        let g:plugin_manager_vimrc_path = g:plugin_manager_vim_dir . '/vimrc'
    endif
endif

" Sidebar width
if !exists('g:plugin_manager_sidebar_width')
    let g:plugin_manager_sidebar_width = 60
endif

" Use fancy UI elements if possible
if !exists('g:plugin_manager_fancy_ui')
    let g:plugin_manager_fancy_ui = has('multi_byte') && &encoding ==# 'utf-8'
endif

" Default git host for short plugin names
if !exists('g:plugin_manager_default_git_host')
    let g:plugin_manager_default_git_host = "github.com"
endif

" Enable/disable automatic error logging
if !exists('g:plugin_manager_enable_logging')
    let g:plugin_manager_enable_logging = 1
endif

" Maximum log file size in KB before rotation (default: 1MB)
if !exists('g:plugin_manager_max_log_size')
    let g:plugin_manager_max_log_size = 1024
endif

" Number of log files to keep in rotation
if !exists('g:plugin_manager_log_history_count')
    let g:plugin_manager_log_history_count = 3
endif


" ------------------------------------------------------------------------------
" COMMAND DEFINITIONS
" ------------------------------------------------------------------------------

" Main command for plugin operations
command! -nargs=* PluginManager call plugin_manager#cmd#dispatch(<f-args>)

" Command to add remote repositories
command! -nargs=1 PluginManagerRemote call plugin_manager#api#add_remote(<f-args>)

" Command to toggle the sidebar
command! PluginManagerToggle call plugin_manager#ui#toggle_sidebar()

" Commands for declarative plugin configuration
command! -nargs=0 PluginBegin call plugin_manager#api#begin()
command! -nargs=+ -complete=file Plugin call plugin_manager#api#plugin(<args>)
command! -nargs=0 PluginEnd call plugin_manager#api#end()

" Commands for log management
command! PluginManagerViewLog call plugin_manager#core#view_log()
command! PluginManagerClearLog call plugin_manager#core#clear_log()

" vim:set ft=vim ts=2 sw=2 et: