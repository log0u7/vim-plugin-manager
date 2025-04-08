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
syntax match PMSubHeader /^-\+$\|^[⎯]\+$/

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
syntax match PMChanged /\<LOCAL CHANGES\>\|\<+ LOCAL CHANGES\>/
syntax match PMDiverged /\<DIVERGED\>/
syntax match PMBranch /\<DIFFERENT BRANCH\>\|\<CUSTOM BRANCH\>/

" Unicode symbols - using more specific patterns to avoid false matches
syntax match PMSymbolSuccess /^.*\s\+✓/ contains=NONE
syntax match PMSymbolError /^.*\s\+✗/ contains=NONE
syntax match PMSymbolWarning /^.*\s\+⚠/ contains=NONE
syntax match PMSymbolInfo /^.*\s\+ℹ/ contains=NONE
syntax match PMSymbolArrow /^.*\s\+→/ contains=NONE
syntax match PMSymbolBullet /^\s*•\s/ contains=NONE

" Progress bars - very specific pattern
syntax match PMProgressBar /\[█\+░\+\]\|\[#\+-\+\]/

" Spinners - very specific pattern
syntax match PMSpinner /\s[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]\(\s\|$\)/ contains=NONE
syntax match PMSpinner /\s[|\/\\-]\(\s\|$\)/ contains=NONE

" Advanced error handling patterns
syntax match PMErrorType /^PM_ERROR:[a-z]\+:/
syntax match PMErrorComponent /\<git\>\|\<add\>\|\<remove\>\|\<update\>\|\<restore\>/ contained containedin=PMErrorType
syntax match PMErrorMessage /Unexpected error:/
syntax match PMStackTrace / at .*$/

" Paths
syntax match PMPath /\(\/\|\~\/\)[[:alnum:]_\-\.\/]\+\(\/\|\.vim\|\.txt\)\?/

" Color configuration
highlight default link PMHeader Title
highlight default link PMSubHeader Comment
highlight default link PMKeyword Statement
highlight default link PMOperation Function
highlight default link PMSecondaryOp Identifier

" Special highlighting for important operations
highlight default link PMUpdateOp MoreMsg
highlight default link PMInstallOp Type
highlight default link PMRemoveOp WarningMsg

highlight default link PMCommand Function
highlight default link PMUrl Underlined
highlight default link PMSuccess String
highlight default link PMOkStatus String
highlight default link PMWarning Todo
highlight default link PMError Error
highlight default link PMChanged WarningMsg
highlight default link PMDiverged Special
highlight default link PMBranch PreProc
highlight default link PMPath Directory

" Progress bar and Unicode symbols highlighting
highlight default link PMProgressBar Special
highlight default link PMSymbolSuccess String
highlight default link PMSymbolError Error
highlight default link PMSymbolWarning Todo
highlight default link PMSymbolInfo Identifier
highlight default link PMSymbolArrow Statement
highlight default link PMSymbolBullet Identifier
highlight default link PMSpinner Type

" Advanced error highlighting
highlight default link PMErrorType Error
highlight default link PMErrorComponent Statement
highlight default link PMErrorMessage ErrorMsg
highlight default link PMStackTrace Comment

let b:current_syntax = "pluginmanager"