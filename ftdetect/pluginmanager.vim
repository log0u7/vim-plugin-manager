" ftdetect/pluginmanager.vim - Filetype detection for PluginManager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: refacto2 v1.3.3 d4f8fda

augroup pluginmanager_ftdetect
  autocmd!
  execute 'autocmd BufNewFile,BufRead PluginManager set filetype=pluginmanager'
augroup END