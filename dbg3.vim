set nocompatible
set rtp^=/home/logout/projets/wt/vim-plugin-manager/detached-hint
let g:o = []
try
  let g:tmp = '/tmp/pm-dbg-det'
  call delete(g:tmp, 'rf')
  call mkdir(g:tmp . '/.git', 'p')
  call writefile(['[submodule "detached"]', '  path = pack/plugins/start/detached', '  url = https://github.com/user/detached.git'], g:tmp . '/.gitmodules')
  let g:plugin_manager_vim_dir = g:tmp
  let g:plugin_manager_plugins_dir = g:tmp . '/pack/plugins'
  let g:plugin_manager_test_force_sync = 1
  let g:m = g:tmp . '/pack/plugins/start/detached'
  call mkdir(g:m, 'p')
  call system('git init -q ' . shellescape(g:m))
  call system('git -C ' . shellescape(g:m) . ' symbolic-ref HEAD refs/heads/main')
  call system('git -C ' . shellescape(g:m) . ' config user.email t@t')
  call system('git -C ' . shellescape(g:m) . ' config user.name T')
  call writefile(['v1'], g:m . '/f')
  call system('git -C ' . shellescape(g:m) . ' add .')
  call system('git -C ' . shellescape(g:m) . ' commit -qm v1')
  call system('git -C ' . shellescape(g:m) . ' tag v0.9.9')
  call writefile(['v2'], g:m . '/f')
  call system('git -C ' . shellescape(g:m) . ' commit -qam v2')
  call system('git -C ' . shellescape(g:m) . ' remote add origin ' . shellescape(g:m))
  call system('git -C ' . shellescape(g:m) . ' checkout -q --detach HEAD')
  call add(g:o, 'valid=' . string(map(plugin_manager#git#valid_modules(), 'v:val.short_name')))
  call plugin_manager#cmd#status#execute()
  call add(g:o, join(getbufline(bufnr('PluginManager'), 1, '$'), "\n"))
  " now remove tag and re-run
  call system('git -C ' . shellescape(g:m) . ' tag -d v0.9.9')
  call plugin_manager#git#refresh_modules_cache()
  call add(g:o, 'valid2=' . string(map(plugin_manager#git#valid_modules(), 'v:val.short_name')))
  call plugin_manager#cmd#status#execute()
  call add(g:o, join(getbufline(bufnr('PluginManager'), 1, '$'), "\n"))
catch
  call add(g:o, 'ERR: ' . v:exception . ' @ ' . v:throwpoint)
endtry
call writefile(g:o, 'dbg3.out')
qa!
