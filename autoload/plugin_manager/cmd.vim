" autoload/plugin_manager/cmd.vim - Command dispatcher for vim-plugin-manager
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.4-dev

" ------------------------------------------------------------------------------
" COMMAND DISPATCHER
" ------------------------------------------------------------------------------

" Main function to handle all plugin manager commands
    function! plugin_manager#cmd#dispatch(...) abort
        try
          if !plugin_manager#core#ensure_vim_directory()
            return
          endif
          
          if a:0 < 1
            call plugin_manager#ui#usage()
            return
          endif
          
          let l:command = a:1
          
          " Route command to appropriate API functions
          if l:command ==# 'add' && a:0 >= 2
            let l:url = a:2
            let l:options = a:0 > 2 ? a:3 : {}
            
            " Handle old style third argument
            if a:0 > 3 && a:4 ==# 'opt'
              if type(l:options) == v:t_dict
                let l:options.load = 'opt'
              else
                let l:dir = l:options
                let l:options = {'dir': l:dir, 'load': 'opt'}
              endif
            endif
            
            call plugin_manager#api#add(l:url, l:options)
          elseif l:command ==# 'remove' && a:0 >= 2
            let l:module_name = a:2
            let l:force_flag = a:0 > 2 ? a:3 : ''
            call plugin_manager#api#remove(l:module_name, l:force_flag)
          elseif l:command ==# 'list'
            call plugin_manager#api#list()
          elseif l:command ==# 'status'
            call plugin_manager#api#status()
          elseif l:command ==# 'update'
            let l:module_name = a:0 > 1 ? a:2 : 'all'
            call plugin_manager#api#update(l:module_name)
          elseif l:command ==# 'summary'
            call plugin_manager#api#summary()
          elseif l:command ==# 'backup'
            call plugin_manager#api#backup()
          elseif l:command ==# 'restore'
            call plugin_manager#api#restore()
          elseif l:command ==# 'helptags'
            let l:module_name = a:0 > 1 ? a:2 : ''
            call plugin_manager#api#helptags(l:module_name)
          elseif l:command ==# 'reload'
            let l:module_name = a:0 > 1 ? a:2 : ''
            call plugin_manager#api#reload(l:module_name)
          else
            call plugin_manager#ui#usage()
          endif
        catch
          " Handle errors properly
          call plugin_manager#core#handle_error(v:exception, "command:" . l:command)
        endtry
      endfunction