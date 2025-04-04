" ftdetect/pluginmanager.vim - Filetype detection for PluginManager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.3

augroup pluginmanager_ftdetect
  autocmd!
  execute 'autocmd BufNewFile,BufRead PluginManager set filetype=pluginmanager'
augroup END
