" Enhanced syntax/pluginmanager.vim - Better syntax highlighting for PluginManager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3.5

" Ensure it's loaded once
if exists("b:current_syntax")
  finish
endif

syntax clear

" Headers and Titles
syntax match PMHeader /^[A-Za-z0-9 ]\+:$/
syntax match PMSubHeader /^-\+$\|^[⎯]\+$/
syntax match PMTitle /^[A-Za-z0-9 ]\+[A-Za-z0-9 :]\+$/

" Keywords
syntax keyword PMKeyword Usage Examples Configuration Commands Options

" Plugin management operations
syntax keyword PMOperation add install update remove restore reload backup
syntax keyword PMSecondaryOp list status summary helptags

" Special highlighting for important operations
syntax match PMUpdateOp /\<update\>\|\<updating\>/
syntax match PMInstallOp /\<install\>\|\<installing\>/
syntax match PMRemoveOp /\<remove\>\|\<removing\>/

" Commands
syntax match PMCommand /^\s*\(PluginManager\|PluginManagerRemote\|PluginManagerToggle\)/

" URLs and repositories
syntax match PMUrl /https\?:\/\/\S\+/
syntax match PMRepository /[a-zA-Z0-9_.-]\+\/[a-zA-Z0-9_.-]\+/

" Success messages and statuses
syntax match PMSuccess /\<successfully\>\|\<completed\>/
syntax match PMOkStatus /\<OK\>/

" Warning and error messages
syntax match PMWarning /\<Warning\>\|\<BEHIND\>\|\<AHEAD\>/
syntax match PMError /\<Error\>\|\<MISSING\>\|\<failed\>/
syntax match PMChanged /\<LOCAL CHANGES\>\|\<\+ LOCAL CHANGES\>/
syntax match PMDiverged /\<DIVERGED\>/
syntax match PMBranch /\<DIFFERENT BRANCH\>\|\<CUSTOM BRANCH\>/

" Error codes in the enhanced error system
syntax match PMErrorCode /[A-Z_]\+:/ contained
syntax match PMErrorMessage /[A-Z_]\+: .*/ contains=PMErrorCode

" Unicode symbols - using more specific patterns to avoid false matches
syntax match PMSymbolSuccess /^.*\s\+✓/ contains=NONE
syntax match PMSymbolError /^.*\s\+✗/ contains=NONE
syntax match PMSymbolWarning /^.*\s\+⚠/ contains=NONE
syntax match PMSymbolInfo /^.*\s\+ℹ/ contains=NONE
syntax match PMSymbolArrow /^.*\s\+→/ contains=NONE
syntax match PMSymbolBullet /^\s*•\s/ contains=NONE

" Progress indicators
syntax match PMProgressBar /\[█\+░\+\]\|\[#\+-\+\]/ 
syntax match PMPercentage /\d\+%/ contained
syntax match PMProgressComplete /\[\(█\+\|#\+\)\] \d\+%/ contains=PMProgressBar,PMPercentage

" Spinners - multiple patterns for different spinner styles
syntax match PMSpinner /\s[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]\(\s\|$\)/ contains=NONE
syntax match PMSpinner /\s[|\/\\-]\(\s\|$\)/ contains=NONE
syntax match PMSpinner /\s[⣾⣽⣻⢿⡿⣟⣯⣷]\(\s\|$\)/ contains=NONE
syntax match PMSpinner /\s[◐◓◑◒]\(\s\|$\)/ contains=NONE
syntax match PMSpinner /\s[◴◷◶◵]\(\s\|$\)/ contains=NONE

" Asynchronous task indicators
syntax match PMAsyncTask /^\s*\[\w\+\]/ contains=NONE
syntax match PMAsyncComplete /\[DONE\]/ contained
syntax match PMAsyncFailed /\[FAILED\]/ contained
syntax match PMAsyncRunning /\[RUNNING\]/ contained
syntax match PMAsyncStatus /\[\(DONE\|FAILED\|RUNNING\)\]/ contains=PMAsyncComplete,PMAsyncFailed,PMAsyncRunning

" Additional features for time information
syntax match PMTimestamp /\[\d\d:\d\d:\d\d\]/ contains=NONE
syntax match PMElapsedTime /(\d\+\.\d\+s)/ contains=NONE

" Path highlighting for different scenarios
syntax match PMPluginPath /\(pack\/plugins\/\(start\|opt\)\/[[:alnum:]_\-\.\/]\+\)/ contains=NONE
syntax match PMPath /\(\/\|\~\/\)\?[[:alnum:]_\-\.]\+\/[[:alnum:]_\-\.\/]\+/

" Color configuration - enhanced with more specific highlighting
highlight default link PMHeader Title
highlight default link PMSubHeader Comment
highlight default link PMTitle Statement
highlight default link PMKeyword Statement
highlight default link PMOperation Function
highlight default link PMSecondaryOp Identifier

" Special highlighting for important operations
highlight default link PMUpdateOp MoreMsg
highlight default link PMInstallOp Type
highlight default link PMRemoveOp WarningMsg

highlight default link PMCommand Function
highlight default link PMUrl Underlined
highlight default link PMRepository Special
highlight default link PMSuccess String
highlight default link PMOkStatus String
highlight default link PMWarning Todo
highlight default link PMError Error
highlight default link PMChanged WarningMsg
highlight default link PMDiverged Special
highlight default link PMBranch PreProc
highlight default link PMPath Directory

" Error system highlighting
highlight default link PMErrorCode Error
highlight default link PMErrorMessage ErrorMsg

" Progress indicators highlighting
highlight default link PMProgressBar Special
highlight default link PMPercentage Number
highlight default link PMProgressComplete Special
highlight default link PMSpinner Type
highlight default link PMAsyncTask Identifier
highlight default link PMAsyncComplete String
highlight default link PMAsyncFailed Error
highlight default link PMAsyncRunning Special
highlight default link PMAsyncStatus Special
highlight default link PMTimestamp Number
highlight default link PMElapsedTime Comment

" Unicode symbol highlighting
highlight default link PMSymbolSuccess String
highlight default link PMSymbolError Error
highlight default link PMSymbolWarning Todo
highlight default link PMSymbolInfo Identifier
highlight default link PMSymbolArrow Statement
highlight default link PMSymbolBullet Identifier

" Plugin path highlighting
highlight default link PMPluginPath Directory

let b:current_syntax = "pluginmanager"