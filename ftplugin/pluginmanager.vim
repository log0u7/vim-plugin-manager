" ftplugin/pluginmanager.vim - Buffers config for PluginManager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.2

" Ensure it's loaded once
if exists("b:did_ftplugin")
  finish
endif
let b:did_ftplugin = 1

" Buffer config
setlocal buftype=nofile
setlocal bufhidden=hide
setlocal noswapfile
setlocal nowrap
setlocal nobuflisted
setlocal nonumber
setlocal nofoldenable
setlocal updatetime=3000

" Buffer mapping for PluginManager
nnoremap <buffer> q :bd<CR>
nnoremap <buffer> l :call <SID>List()<CR>
nnoremap <buffer> u :call <SID>Update()<CR>
nnoremap <buffer> h :call <SID>GenerateHelptags()<CR>
nnoremap <buffer> s :call <SID>Status()<CR>
nnoremap <buffer> S :call <SID>Summary()<CR>
nnoremap <buffer> b :call <SID>Backup()<CR>
nnoremap <buffer> r :call <SID>Restore()<CR>
nnoremap <buffer> R :call <SID>Reload()<CR>
nnoremap <buffer> ? :call <SID>Usage()<CR>

" Local call function for main plugin
function! s:List()
  call PluginManager("list")
endfunction

function! s:Update()
  call PluginManager("update")
endfunction

function! s:GenerateHelptags()
  call PluginManager("helptags")
endfunction

function! s:Status()
  call PluginManager("status")
endfunction

function! s:Summary()
  call PluginManager("summary")
endfunction

function! s:Backup()
  call PluginManager("backup")
endfunction

function! s:Restore()
  call PluginManager("restore")
endfunction

function! s:Reload()
  call PluginManager("reload")
endfunction

function! s:Usage()
  call PluginManager()
endfunction



" Output Options
let b:undo_ftplugin = "setlocal buftype< bufhidden< swapfile< wrap< buflisted< number< foldenable< updatetime<"
