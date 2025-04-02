" syntax/pluginmanager.vim - Syntax coloration for PluginManager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.2

" Ensure it's loaded once
if exists("b:current_syntax")
  finish
endif

syntax clear

" Headers
syntax match PMHeader /^[A-Za-z0-9 ]\+:$/
syntax match PMSubHeader /^-\+$/

" Keywords
syntax keyword PMKeyword Usage Examples

" Commands
syntax match PMCommand /^\s*\(PluginManager\|add\|remove\|list\|status\|update\|summary\|backup\|helptags\|restore\)/

" URLs
syntax match PMUrl /https\?:\/\/\S\+/

" Success
syntax match PMSuccess /\<successfully\>/

" Error
syntax match PMError /\<Error\>/

" Color configuration
highlight default link PMHeader Title
highlight default link PMSubHeader Comment
highlight default link PMKeyword Statement
highlight default link PMCommand Function
highlight default link PMUrl Underlined
highlight default link PMSuccess String
highlight default link PMError Error

let b:current_syntax = "pluginmanager"
