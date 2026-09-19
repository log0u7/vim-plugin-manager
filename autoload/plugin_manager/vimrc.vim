" autoload/plugin_manager/vimrc.vim - Parse Plugin declarations from the vimrc
" Maintainer: G.K.E. <gke@6admin.io>

" Extract Plugin declarations from the vimrc file (g:plugin_manager_vimrc_path).
" Returns a list of {url, options} dicts, the same shape declare.vim collects
" from a PluginBegin block. Returns [] when the vimrc is missing or unreadable.
"
" Only the dict options form is understood (the legacy positional form is
" deprecated and cannot be recovered reliably from a file: bare words do not
" eval). Lines that fail to evaluate are skipped with a logged warning,
" never fatal. The vimrc is already trusted content (Vim sources it), so
" eval() introduces no new trust boundary.

" True when at least one Plugin declaration was parsed from the vimrc.
" Consumers refuse to act (e.g. gc) when this is 0: an unreadable or
" declaration-free vimrc carries no information about the user's intent.
function! plugin_manager#vimrc#declarations_present() abort
  return !empty(plugin_manager#vimrc#parse_declarations())
endfunction

function! plugin_manager#vimrc#parse_declarations() abort
  let l:path = expand(plugin_manager#core#util#get_config('vimrc_path', ''))
  if empty(l:path) || !filereadable(l:path)
    return []
  endif

  let l:declarations = []
  for l:line in readfile(l:path)
    " Skip comments, blanks, and everything that is not a Plugin line.
    " PluginBegin / PluginEnd do not match (no whitespace after 'Plugin').
    if l:line =~# '^\s*"' || l:line !~# '^\s*Plugin\s\+.\+'
      continue
    endif
    let l:rest = substitute(l:line, '^\s*Plugin\s\+', '', '')
    let l:entry = s:eval_declaration(l:rest)
    if !empty(l:entry)
      call add(l:declarations, l:entry)
    endif
  endfor
  return l:declarations
endfunction

" Evaluate "'url', {options}" into {'url', 'options'}; {} on any failure.
function! s:eval_declaration(rest) abort
  let l:args = s:eval_args(a:rest)
  if empty(l:args)
    " Retry once with a trailing comment stripped: Plugin 'x' " comment
    let l:stripped = substitute(a:rest, '\s\+"[^"]*$', '', '')
    if l:stripped !=# a:rest
      let l:args = s:eval_args(l:stripped)
    endif
  endif
  if empty(l:args) || type(get(l:args, 0, '')) != v:t_string
    " Warn, not debug: a silently skipped declaration must be visible in a
    " default setup (debug_mode off), same contract as issue #5.
    call plugin_manager#core#log#warn('vimrc',
          \ 'skipping unparsable declaration: ' . a:rest)
    return {}
  endif
  " Normalize through the same option parser the :Plugin command uses, so
  " defaults are filled and unknown keys warn identically.
  return {'url': l:args[0],
        \ 'options': plugin_manager#core#util#process_plugin_options(l:args[1:])}
endfunction

function! s:eval_args(rest) abort
  try
    return eval('[' . a:rest . ']')
  catch
    return []
  endtry
endfunction

" vim:set ft=vim ts=2 sw=2 et:
