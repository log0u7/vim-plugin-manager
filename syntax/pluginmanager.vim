" syntax/pluginmanager.vim - Syntax coloration for PluginManager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3

" Ensure it's loaded once
if exists("b:current_syntax")
  finish
endif

syntax clear

" Headers
syntax match PMHeader /^[A-Za-z0-9 ]\+:$/
syntax match PMSubHeader /^-\+$/

" Keywords
syntax keyword PMKeyword Usage Examples Configuration

" Plugin management operations
syntax keyword PMOperation add install update remove restore reload backup
syntax keyword PMSecondaryOp list status summary helptags

" Special highlighting for important operations
syntax match PMUpdateOp /\<update\>\|\<updating\>/
syntax match PMInstallOp /\<install\>\|\<installing\>/
syntax match PMRemoveOp /\<remove\>\|\<removing\>/

" Commands
syntax match PMCommand /^\s*\(PluginManager\|PluginManagerRemote\|PluginManagerToggle\)/

" URLs
syntax match PMUrl /https\?:\/\/\S\+/

" Success messages and statuses
syntax match PMSuccess /\<successfully\>\|\<completed\>/
syntax match PMOkStatus /\<OK\>/

" Warning and error messages
syntax match PMWarning /\<Warning\>\|\<BEHIND\>\|\<AHEAD\>/
syntax match PMError /\<Error\>\|\<MISSING\>\|\<failed\>/
syntax match PMChanged /\<LOCAL CHANGES\>/
syntax match PMDiverged /\<DIVERGED\>/

" Paths
syntax match PMPath /\/\S\+\(\/\|\.\(vim\|txt\)\)\@=/

" Color configuration
highlight default link PMHeader Title
highlight default link PMSubHeader Comment
highlight default link PMKeyword Statement
highlight default link PMOperation Function
highlight default link PMSecondaryOp Identifier

" Special highlighting for important operations
highlight default link PMUpdateOp MoreMsg  " Green
highlight default link PMInstallOp Type    " Blue/Cyan
highlight default link PMRemoveOp WarningMsg " Red/Orange

highlight default link PMCommand Function
highlight default link PMUrl Underlined
highlight default link PMSuccess String
highlight default link PMOkStatus String
highlight default link PMWarning Todo
highlight default link PMError Error
highlight default link PMChanged WarningMsg
highlight default link PMDiverged Special  " Purple/Magenta color for diverged state
highlight default link PMPath Directory

let b:current_syntax = "pluginmanager"