" ftdetect/pluginmanager.vim - Filetype detection for PluginManager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.2

augroup pluginmanager_ftdetect
  autocmd!
  autocmd BufNewFile,BufRead PluginManager set filetype=pluginmanager
augroup END
