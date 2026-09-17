" autoload/plugin_manager/lazy.vim - On-demand (lazy) plugin loading
" Maintainer: G.K.E. <gke@6admin.io>

" Implements vim-plug style lazy loading on top of Vim 8 native packages:
"   'on': ['Cmd', ...]   placeholder commands that packadd the plugin on
"                        first use, then re-dispatch the invocation
"   'for': ['ft', ...]   FileType autocmds that packadd the plugin
"
" Triggers are registered at declaration processing time, so they exist
" even when the plugin is still being installed (first run). Loading is
" idempotent: a loaded package never loads twice in a session.

" Registry: {'<name>': {'on': [], 'for': []}} and loaded packages
let s:lazy = {}
let s:loaded = {}

" Register a package for on-demand loading. Returns 1 when triggers were
" registered (i.e. on/for were present and non-empty). Invalid trigger
" names are skipped with a warning instead of throwing: one malformed
" declaration must never abort the whole declare batch.
function! plugin_manager#lazy#register(name, options) abort
  let l:opts_on = get(a:options, 'on', [])
  let l:opts_for = get(a:options, 'for', [])
  let l:cmds = s:valid_triggers('on', l:opts_on, '^[A-Za-z][A-Za-z0-9_#]*$')
  let l:fts = s:valid_triggers('for', l:opts_for, '^[A-Za-z0-9_.-]\+$')
  if empty(l:cmds) && empty(l:fts)
    return 0
  endif

  let l:entry = get(s:lazy, a:name, {'on': [], 'for': []})
  for l:cmd in l:cmds
    if type(l:cmd) == v:t_string && !empty(l:cmd) && index(l:entry.on, l:cmd) == -1
      call add(l:entry.on, l:cmd)
    endif
  endfor
  for l:ft in l:fts
    if type(l:ft) == v:t_string && !empty(l:ft) && index(l:entry.for, l:ft) == -1
      call add(l:entry.for, l:ft)
    endif
  endfor
  let s:lazy[a:name] = l:entry

  call s:register_command_triggers(a:name, l:entry.on)
  call s:register_filetype_triggers(a:name, l:entry.for)
  return 1
endfunction

" Filter a trigger list down to usable names: strings matching the given
" pattern. Anything else warns and is dropped (a non-list value yields []).
function! s:valid_triggers(kind, values, pattern) abort
  let l:valid = []
  if type(a:values) != v:t_list
    return l:valid
  endif
  for l:v in a:values
    if type(l:v) == v:t_string && l:v =~# a:pattern
      call add(l:valid, l:v)
    else
      echohl WarningMsg
      echomsg "PluginManager: invalid '" . a:kind . "' trigger "
            \ . string(l:v) . ' for ' . 'plugin, ignored'
      echohl None
    endif
  endfor
  return l:valid
endfunction

" Load a lazy package once. Returns 1 when the package is (or got) loaded.
" A missing package is reported but never fatal: the trigger survives so it
" can fire again after the plugin has been installed.
function! plugin_manager#lazy#load_package(name) abort
  if get(s:loaded, a:name, 0)
    return 1
  endif
  if !plugin_manager#core#util#dir_exists(
        \ plugin_manager#core#util#get_plugin_dir('opt') . '/' . a:name)
    echohl WarningMsg
    echomsg "PluginManager: plugin '" . a:name . "' is not installed yet"
    echohl None
    return 0
  endif
  let s:loaded[a:name] = 1
  execute 'packadd ' . fnameescape(a:name)
  " ftplugin files of the freshly loaded package must also apply to
  " buffers whose FileType event already fired.
  if !empty(&filetype)
    execute 'filetype detect'
  endif
  return 1
endfunction

" Placeholder invocation: drop the placeholder, load the package, then
" re-dispatch the original invocation against the real command.
" The placeholder must be deleted BEFORE loading: the plugin redefines the
" command with :command!, so deleting after load would remove the real one.
function! plugin_manager#lazy#invoke(cmd, name, mods, count, line1, line2, bang, args) abort
  if exists(':' . a:cmd)
    execute 'delcommand ' . a:cmd
  endif
  if !plugin_manager#lazy#load_package(a:name)
    " Load failed: restore the placeholder so the trigger can fire again
    call s:register_command_triggers(a:name, [a:cmd])
    return
  endif
  let l:range = a:count != -1 ? (a:line1 . ',' . a:line2) : ''
  try
    execute a:mods . ' ' . l:range . ' ' . a:cmd . (a:bang ? '!' : '') . ' ' . a:args
  catch
    echohl ErrorMsg
    echomsg 'PluginManager: command ' . a:cmd . ' is not provided by plugin ' . a:name
    echohl None
  endtry
endfunction

function! s:register_command_triggers(name, cmds) abort
  for l:cmd in a:cmds
    " An existing command is either the real plugin command (already
    " loaded) or a user-defined one; never shadow it.
    if exists(':' . l:cmd) == 2
      continue
    endif
    execute 'command! -nargs=* -bar -bang -range -complete=file ' . l:cmd
          \ . ' call plugin_manager#lazy#invoke(' . string(l:cmd) . ', '
          \ . string(a:name) . ', <q-mods>, <count>, <line1>, <line2>, <bang>0, <q-args>)'
  endfor
endfunction

function! s:register_filetype_triggers(name, fts) abort
  if empty(a:fts)
    return
  endif
  " Ensure the group exists: autocmd! on a missing group raises E216.
  augroup plugin_manager_lazy
  augroup END
  for l:ft in a:fts
    " Targeted removal: only this group's trigger for this filetype is
    " replaced, other plugins' FileType autocmds are untouched.
    execute 'autocmd! plugin_manager_lazy FileType ' . l:ft
    execute 'autocmd plugin_manager_lazy FileType ' . l:ft
          \ . ' call plugin_manager#lazy#load_package(' . string(a:name) . ')'
  endfor
  " Buffers already open with a matching filetype load immediately.
  for l:ft in a:fts
    for l:buf in range(1, bufnr('$'))
      if buflisted(l:buf) && getbufvar(l:buf, '&filetype') ==# l:ft
        call plugin_manager#lazy#load_package(a:name)
        break
      endif
    endfor
  endfor
endfunction

" Test-only entry point: reset the session registry.
function! plugin_manager#lazy#_reset() abort
  let s:lazy = {}
  let s:loaded = {}
endfunction

" vim:set ft=vim ts=2 sw=2 et:
