" autoload/plugin_manager/core/cache.vim - Update check cache for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>

" ------------------------------------------------------------------------------
" UPDATE CHECK CACHE
" ------------------------------------------------------------------------------

function! plugin_manager#core#cache#get_path() abort
  let l:vim_dir = plugin_manager#core#util#get_config('vim_dir', '')
  return l:vim_dir . '/logs/update_check.json'
endfunction

" Read the cached update-check result.
" Returns a dict: {'timestamp': <int>, 'plugins': [ {name, behind}, ... ]}
" Returns an empty dict if no valid cache exists.
function! plugin_manager#core#cache#read() abort
  let l:path = plugin_manager#core#cache#get_path()
  if !filereadable(l:path)
    return {}
  endif
  try
    let l:content = join(readfile(l:path), "\n")
    if empty(l:content)
      return {}
    endif
    let l:data = json_decode(l:content)
    if type(l:data) != v:t_dict
      return {}
    endif
    return l:data
  catch
    return {}
  endtry
endfunction

" Write the update-check result to the cache.
" @param plugins: list of dicts {name, behind}
function! plugin_manager#core#cache#write(plugins) abort
  let l:path = plugin_manager#core#cache#get_path()
  let l:dir = fnamemodify(l:path, ':h')
  if !isdirectory(l:dir)
    try
      call mkdir(l:dir, 'p')
    catch
      return 0
    endtry
  endif
  let l:data = {'timestamp': localtime(), 'plugins': a:plugins}
  try
    call writefile([json_encode(l:data)], l:path)
    return 1
  catch
    return 0
  endtry
endfunction

" Decide whether a fresh check is due based on the configured interval.
" @param interval_hours: hours that must elapse before a new check
" Returns 1 if a check should run, 0 if the cache is still fresh.
function! plugin_manager#core#cache#due(interval_hours) abort
  let l:cache = plugin_manager#core#cache#read()
  if empty(l:cache) || !has_key(l:cache, 'timestamp')
    return 1
  endif
  let l:age = localtime() - l:cache.timestamp
  return l:age >= (a:interval_hours * 3600)
endfunction
