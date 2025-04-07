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
  try
    if s:plugin_block_active
      let l:end_line = line('.')
      call plugin_manager#utils#process_plugin_block(s:plugin_block_start, l:end_line)
      let s:plugin_block_active = 0
    endif
  catch
    let l:error = plugin_manager#utils#is_pm_error(v:exception) 
          \ ? plugin_manager#utils#format_error(v:exception)
          \ : 'Unexpected error during plugin processing: ' . v:exception
    
    call plugin_manager#ui#open_sidebar(['Plugin Processing Error:', repeat('-', 25), '', l:error])
  endtry
endfunction

" Stop all running jobs (useful for clean Vim exit)
function! plugin_manager#stop_all_jobs()
  if exists('*plugin_manager#jobs#stop_all')
    call plugin_manager#jobs#stop_all()
  endif
endfunction

" List all running jobs
function! plugin_manager#list_jobs()
  if exists('*plugin_manager#jobs#list')
    let l:jobs = plugin_manager#jobs#list()
    
    let l:header = 'Running Jobs:'
    let l:lines = [l:header, repeat('-', len(l:header)), '']
    
    if empty(l:jobs)
      call add(l:lines, 'No jobs are currently running.')
    else
      call add(l:lines, 'ID'.repeat(' ', 10).'Name'.repeat(' ', 16).'Description'.repeat(' ', 30).'Progress')
      call add(l:lines, repeat('-', 100))
      
      for l:job in l:jobs
        let l:id_col = l:job.id . repeat(' ', max([0, 12 - len(l:job.id)]))
        let l:name_col = l:job.name . repeat(' ', max([0, 20 - len(l:job.name)]))
        let l:desc_col = l:job.description . repeat(' ', max([0, 34 - len(l:job.description)]))
        let l:progress = l:job.progress > 0 ? l:job.progress . '%' : 'N/A'
        
        call add(l:lines, l:id_col . l:name_col . l:desc_col . l:progress)
      endfor
    endif
    
    call plugin_manager#ui#open_sidebar(l:lines)
  else
    call plugin_manager#ui#open_sidebar(['Jobs:', '-----', '', 'Asynchronous job support is not available.'])
  endif
endfunction

" Kill a specific job
function! plugin_manager#kill_job(job_id)
  if exists('*plugin_manager#jobs#stop')
    let l:result = plugin_manager#jobs#stop(a:job_id)
    
    if l:result
      call plugin_manager#ui#open_sidebar(['Kill Job:', '---------', '', 'Successfully stopped job ' . a:job_id])
    else
      call plugin_manager#ui#open_sidebar(['Kill Job:', '---------', '', 'Failed to stop job ' . a:job_id . '. Job not found.'])
    endif
  else
    call plugin_manager#ui#open_sidebar(['Kill Job:', '---------', '', 'Asynchronous job support is not available.'])
  endif
endfunction

" Add commands for job management
command! PluginManagerJobs call plugin_manager#list_jobs()
command! -nargs=1 PluginManagerKillJob call plugin_manager#kill_job(<f-args>)
command! PluginManagerStopJobs call plugin_manager#stop_all_jobs()

" Clean up jobs when exiting Vim
augroup PluginManagerJobsCleanup
  autocmd!
  autocmd VimLeave * call plugin_manager#stop_all_jobs()
augroup END