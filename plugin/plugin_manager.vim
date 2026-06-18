" plugin/plugin_manager.vim - Main entry point for Vim Plugin Manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4.0

" Prevent loading the plugin multiple times
if exists('g:loaded_plugin_manager') || &cp
    finish
endif
let g:loaded_plugin_manager = 1

" ------------------------------------------------------------------------------
" ENVIRONMENT GUARD
" ------------------------------------------------------------------------------

" PluginManager targets Vim only. Neovim already has mature Lua-based managers
" (lazy.nvim, packer.nvim, vim-plug). Warn but keep loading in case the user
" really wants it.
if has('nvim')
    echohl WarningMsg
    echomsg 'PluginManager: Neovim is not supported. Use lazy.nvim, packer.nvim or vim-plug instead.'
    echohl None
endif

" Require Vim 8.2+ for the modern async UI (job/channel, popup, setbufline).
if v:version < 802
    echohl WarningMsg
    echomsg 'PluginManager: Vim 8.2 or newer is recommended. Some features may not work.'
    echohl None
endif

" ------------------------------------------------------------------------------
" CONFIGURATION VARIABLES
" ------------------------------------------------------------------------------

" Detect Vim configuration directory (Vim only)
if !exists('g:plugin_manager_vim_dir')
    if has('win32') || has('win64')
        let g:plugin_manager_vim_dir = expand('~/vimfiles')
    else
        let g:plugin_manager_vim_dir = expand('~/.vim')
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

" Path to vimrc
if !exists('g:plugin_manager_vimrc_path')
    let g:plugin_manager_vimrc_path = g:plugin_manager_vim_dir . '/vimrc'
endif

" Sidebar width
if !exists('g:plugin_manager_sidebar_width')
    let g:plugin_manager_sidebar_width = 80
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

" UI customization
if !exists('g:plugin_manager_spinner_style')
    let g:plugin_manager_spinner_style = 'dots'  " Options: dots, line, circle, triangle, box
endif

if !exists('g:plugin_manager_spinner_interval')
    let g:plugin_manager_spinner_interval = 80  " Spinner refresh interval in ms
endif

if !exists('g:plugin_manager_show_deprecation_warnings')
    let g:plugin_manager_show_deprecation_warnings = 1  " Enable deprecation warnings
endif

" Git behavior configuration
if !exists('g:plugin_manager_pull_strategy')
    let g:plugin_manager_pull_strategy = 'ff-only'  " Options: ff-only, merge, rebase
endif

if !exists('g:plugin_manager_auto_commit_on_update')
    let g:plugin_manager_auto_commit_on_update = 1  " Auto commit after updates
endif

" Job management
if !exists('g:plugin_manager_max_concurrent_jobs')
    let g:plugin_manager_max_concurrent_jobs = 4  " Maximum concurrent async jobs
endif

if !exists('g:plugin_manager_job_timeout')
    let g:plugin_manager_job_timeout = 60  " Default timeout in seconds for async jobs 
endif

" Update notifications and automatic updates (all opt-in, default off)
if !exists('g:plugin_manager_check_on_startup')
    let g:plugin_manager_check_on_startup = 0  " Check for updates on VimEnter
endif

if !exists('g:plugin_manager_check_interval')
    let g:plugin_manager_check_interval = 24  " Hours between background update checks
endif

if !exists('g:plugin_manager_auto_update')
    let g:plugin_manager_auto_update = 0  " Auto-install updates on startup
endif

" Debug options
if !exists('g:plugin_manager_debug_mode')
    let g:plugin_manager_debug_mode = 0  " Enable additional debug information
endif

if !exists('g:plugin_manager_trace_commands')
    let g:plugin_manager_trace_commands = 0  " Log all git commands to debug log
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

" ------------------------------------------------------------------------------
" UPDATE NOTIFICATIONS (opt-in)
" ------------------------------------------------------------------------------

" Only register the startup/periodic check when explicitly enabled. This keeps
" the plugin free of any network access by default.
if g:plugin_manager_check_on_startup
    augroup plugin_manager_startup_check
        autocmd!
        " Defer slightly so it never blocks Vim's startup
        autocmd VimEnter * call timer_start(500, {-> plugin_manager#cmd#check#startup()})
    augroup END

    " Periodic re-check using the configured interval (hours -> milliseconds).
    " The check itself still honors the cache, so this only fetches when due.
    if exists('*timer_start') && get(g:, 'plugin_manager_check_interval', 24) > 0
        let s:pm_check_period_ms = g:plugin_manager_check_interval * 3600 * 1000
        let g:plugin_manager_periodic_timer =
                    \ timer_start(s:pm_check_period_ms,
                    \ {-> plugin_manager#cmd#check#startup()}, {'repeat': -1})
    endif
endif

" vim:set ft=vim ts=2 sw=2 et: