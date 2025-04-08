" autoload/plugin_manager/modules/helptags.vim - Functions for generating helptags

" Generate helptags for a specific plugin
function! s:generate_helptag(pluginPath)
    let l:docPath = a:pluginPath . '/doc'
    if isdirectory(l:docPath)
        execute 'helptags ' . l:docPath
        return 1
    endif
    return 0
endfunction
    
" Generate helptags for all installed plugins
function! plugin_manager#modules#helptags#generate(...)
    " Fix: Properly handle optional arguments
    let l:create_header = a:0 > 0 ? a:1 : 1
    let l:specific_module = a:0 > 1 ? a:2 : ''
    
    if !plugin_manager#utils#ensure_vim_directory()
        return
    endif
        
    " Initialize output only if creating a new header
    if l:create_header
        let l:header = 'Generating Helptags:'
        let l:line = [l:header, repeat('-', len(l:header)), '', 'Generating helptags:']
        call plugin_manager#ui#open_sidebar(l:line)
    else
        " If we're not creating a new header, just add a separator line
        call plugin_manager#ui#update_sidebar(['', 'Generating helptags:'], 1)
    endif
    
    " Fix: Check if plugins directory exists
    let l:pluginsDir = g:plugin_manager_plugins_dir . '/'
    let l:tagsGenerated = 0
    let l:generated_plugins = []
    
    if isdirectory(l:pluginsDir)
        if !empty(l:specific_module)
        " Find the specific plugin path
        let l:plugin_pattern = l:pluginsDir . '*/*' . l:specific_module . '*'
        for l:plugin in glob(l:plugin_pattern, 0, 1)
            if s:generate_helptag(l:plugin)
            let l:tagsGenerated = 1
            call add(l:generated_plugins, "Generated helptags for " . fnamemodify(l:plugin, ':t'))
            endif
        endfor
        else
        " Generate helptags for all plugins
        for l:plugin in glob(l:pluginsDir . '*/*', 0, 1)
            if s:generate_helptag(l:plugin)
            let l:tagsGenerated = 1
            call add(l:generated_plugins, "Generated helptags for " . fnamemodify(l:plugin, ':t'))
            endif
        endfor
        endif
    endif
    
    let l:result_message = []
    if l:tagsGenerated
        call extend(l:result_message, l:generated_plugins)
        call add(l:result_message, "Helptags generated successfully.")
    else
        call add(l:result_message, "No documentation directories found.")
    endif
    
    call plugin_manager#ui#update_sidebar(l:result_message, 1)
endfunction