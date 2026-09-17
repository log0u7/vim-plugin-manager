" autoload/plugin_manager/cmd/gc.vim - Orphaned plugin cleanup
" Maintainer: G.K.E. <gke@6admin.io>

" Collects registered submodules that are no longer declared in the vimrc
" Plugin lines (the same source of truth as update pin re-assertion).
" Deny by default: without a single declaration there is no intent to
" compare against, so the command refuses to guess.

" Compute orphaned modules from the given declarations and module map.
" Pure function (no I/O beyond its inputs) so it can be unit tested.
" decls:   list of {url, options} from plugin_manager#vimrc#parse_declarations()
" modules: dict from plugin_manager#git#parse_modules()
" Returns a list of {name, path, url}.
function! plugin_manager#cmd#gc#orphans(decls, modules) abort
  let l:declared_names = {}
  let l:declared_urls = {}
  for l:decl in a:decls
    let l:declared_names[plugin_manager#core#util#extract_plugin_name(l:decl.url)] = 1
    if !empty(get(l:decl.options, 'dir', ''))
      let l:declared_names[l:decl.options.dir] = 1
    endif
    let l:url = plugin_manager#core#util#convert_to_full_url(l:decl.url)
    if !empty(l:url)
      let l:declared_urls[l:url] = 1
    endif
  endfor

  " Never collect the manager itself or user-protected entries
  let l:protected = copy(get(g:, 'plugin_manager_gc_exclude', []))
  let l:self_name = fnamemodify(get(g:, 'plugin_manager_self_path', ''), ':t')
  if !empty(l:self_name)
    call add(l:protected, l:self_name)
  endif

  let l:orphans = []
  for [l:name, l:module] in items(a:modules)
    if !get(l:module, 'is_valid', 0)
      continue
    endif
    let l:short_name = get(l:module, 'short_name', '')
    if index(l:protected, l:short_name) != -1
      continue
    endif
    if has_key(l:declared_names, l:short_name)
      continue
    endif
    let l:url = get(l:module, 'url', '')
    if !empty(l:url) && has_key(l:declared_urls, l:url)
      continue
    endif
    call add(l:orphans, {'name': l:short_name,
          \ 'path': get(l:module, 'path', ''), 'url': l:url})
  endfor
  return l:orphans
endfunction

" :PluginManager gc [-f]
" Lists orphaned plugins and removes them after a single confirmation
" (skipped with -f). Each orphan goes through the standard removal
" mechanics (deinit, git rm, metadata cleanup, pointer commit).
function! plugin_manager#cmd#gc#execute(...) abort
  try
    call plugin_manager#core#util#require_vim_directory('gc')
    let l:force = a:0 > 0 && a:1 ==# '-f'

    let l:decls = plugin_manager#vimrc#parse_declarations()
    if !plugin_manager#vimrc#declarations_present()
      call plugin_manager#core#throw('gc', 'NO_DECLARATIONS',
            \ 'No Plugin declarations found in '
            \ . plugin_manager#core#util#get_config('vimrc_path', '')
            \ . ': refusing to guess what is orphaned')
    endif

    let l:orphans = plugin_manager#cmd#gc#orphans(l:decls, plugin_manager#git#parse_modules())
    if empty(l:orphans)
      call plugin_manager#ui#open_header('Plugin Manager GC:')
      call plugin_manager#ui#footer(
            \ [plugin_manager#ui#success('Nothing to collect: every registered plugin is declared')])
      return 1
    endif

    call plugin_manager#ui#open_header('Orphaned plugins (not declared in vimrc):')
    for l:orphan in l:orphans
      echomsg '  - ' . l:orphan.name . ' (' . l:orphan.path . ')'
    endfor

    if !l:force
      let l:response = input('Remove ' . len(l:orphans) . ' orphaned plugin(s)? [y/N] ')
      if l:response !~? '^y\(es\)\?$'
        call plugin_manager#ui#footer([plugin_manager#ui#info('GC cancelled')])
        return 0
      endif
    endif

    let l:removed = 0
    for l:orphan in l:orphans
      try
        call plugin_manager#cmd#remove#_force_remove(l:orphan.name, l:orphan.path)
        let l:removed += 1
      catch
        call plugin_manager#core#handle_error(v:exception, 'gc')
      endtry
    endfor

    call plugin_manager#ui#footer([plugin_manager#ui#success(
          \ l:removed . ' of ' . len(l:orphans) . ' orphaned plugin(s) removed')])
    return l:removed ==# len(l:orphans)
  catch
    call plugin_manager#core#handle_error(v:exception, 'gc')
    return 0
  endtry
endfunction

" vim:set ft=vim ts=2 sw=2 et:
