" syntax/pluginmanager.vim - Syntax coloration for PluginManager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4

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
syntax match PMCheckmark /✓/

" Warning and error messages
syntax match PMWarning /\<Warning\>\|\<BEHIND\>\|\<AHEAD\>/
syntax match PMError /\<Error\>\|\<MISSING\>\|\<failed\>\|\<errors\>/
syntax match PMErrorX /✗/
syntax match PMChanged /\<LOCAL CHANGES\>\|\<+ LOCAL CHANGES\>/
syntax match PMDiverged /\<DIVERGED\>/
syntax match PMBranch /\<DIFFERENT BRANCH\>/

" Progress indicators
syntax match PMProgressBar /\[=\+ *\]/
syntax match PMPercentage /\d\+%/
syntax match PMSpinner /[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]/

" Job progress section
syntax match PMJobHeader /^Job Progress:$/
syntax region PMJobSection start=/^Job Progress:$/ end=/^[A-Z]/ contains=PMSubHeader,PMSpinner,PMCheckmark,PMErrorX,PMSuccess,PMError

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
highlight default link PMCheckmark String  " Green
highlight default link PMErrorX WarningMsg " Red
highlight default link PMWarning Todo
highlight default link PMError Error
highlight default link PMChanged WarningMsg
highlight default link PMDiverged Special  " Purple/Magenta color for diverged state
highlight default link PMBranch PreProc    " Add the highlight for DIFFERENT BRANCH
highlight default link PMPath Directory

" Progress indicator highlighting
highlight default link PMProgressBar MoreMsg
highlight default link PMPercentage Type
highlight default link PMSpinner Special
highlight default link PMJobHeader Title

let b:current_syntax = "pluginmanager"