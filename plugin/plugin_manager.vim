" vim-plugin-manager.vim - Manage Vim plugins with git submodules
" Maintainer: YOUR_NAME
" Version: 1.0

if exists('g:loaded_plugin_manager') || &cp
  finish
endif
let g:loaded_plugin_manager = 1

" Configuration
if !exists('g:plugin_manager_plugins_dir')
  let g:plugin_manager_plugins_dir = "pack/plugins"
endif

if !exists('g:plugin_manager_start_dir')
  let g:plugin_manager_start_dir = "start"
endif

if !exists('g:plugin_manager_opt_dir')
  let g:plugin_manager_opt_dir = "opt"
endif

if !exists('g:plugin_manager_vimrc_path')
  let g:plugin_manager_vimrc_path = expand('~/.vim/vimrc')
endif

if !exists('g:plugin_manager_sidebar_width')
  let g:plugin_manager_sidebar_width = 40
endif

if !exists('g:plugin_manager_default_git_host')
  let g:plugin_manager_default_git_host = "github.com"
endif

" Internal variables
let s:urlRegexp = 'https\?:\/\/\(www\.\)\?[-a-zA-Z0-9@:%._\\+~#=]\{1,256}\.[a-zA-Z0-9()]\{1,6}\b\([-a-zA-Z0-9()@:%_\\+.~#?&//=]*\)'
let s:shortNameRegexp = '^[a-zA-Z0-9_-]\+\/[a-zA-Z0-9_-]\+$'
let s:buffer_name = 'PluginManager'
let s:progress_timer = 0
let s:progress_step = 0
let s:progress_total = 0
let s:command_running = 0
let s:command_output = []

" Draw a progress bar
function! s:DrawProgressBar(current, total, width)
  let l:percent = a:current * 100 / a:total
  let l:done = a:current * a:width / a:total
  let l:bar = repeat('█', l:done) . repeat('░', a:width - l:done)
  return l:bar . ' ' . l:percent . '%'
endfunction

" Update the progress bar display
function! s:UpdateProgress(timer)
  let s:progress_step += 1
  if s:progress_step > s:progress_total
    let s:progress_step = 0
  endif
  
  let l:progress_line = s:DrawProgressBar(s:progress_step, s:progress_total, 30)
  let l:lines = deepcopy(s:command_output)
  
  if s:command_running
    call add(l:lines, '')
    call add(l:lines, 'Progress: ' . l:progress_line)
    call s:UpdateSidebar(l:lines)
  endif
endfunction

" Start the progress display
function! s:StartProgress(total)
  let s:progress_step = 0
  let s:progress_total = a:total
  let s:command_running = 1
  
  " Start timer for progress updates
  if s:progress_timer == 0
    let s:progress_timer = timer_start(100, function('s:UpdateProgress'), {'repeat': -1})
  endif
endfunction

" Stop the progress display
function! s:StopProgress()
  let s:command_running = 0
  
  " Stop timer
  if s:progress_timer != 0
    call timer_stop(s:progress_timer)
    let s:progress_timer = 0
  endif
  
  " Update sidebar one last time with 100% progress
  let l:progress_line = s:DrawProgressBar(s:progress_total, s:progress_total, 30)
  let l:lines = deepcopy(s:command_output)
  call add(l:lines, '')
  call add(l:lines, 'Progress: ' . l:progress_line . ' (Completed)')
  call add(l:lines, '')
  call add(l:lines, 'Press q to close this window...')
  call s:UpdateSidebar(l:lines)
endfunction

" Execute command with output in sidebar
function! s:ExecuteWithSidebar(title, cmd, progress_total)
  " Initialize output collection
  let s:command_output = [a:title, repeat('-', len(a:title)), '', 'Starting operation, please wait...']
  
  " Create or update sidebar window
  call s:OpenSidebar(s:command_output)
  
  " Start progress display
  call s:StartProgress(a:progress_total)
  
  " Execute command and collect output 
  let l:output = system(a:cmd)
  let s:command_output = [a:title, repeat('-', len(a:title)), '']
  call extend(s:command_output, split(l:output, "\n"))
  
  " Stop progress display
  call s:StopProgress()
  
  return l:output
endfunction

" Convert short name to full URL
function! s:ConvertToFullUrl(shortName)
  " If it's already a URL, return it as is
  if a:shortName =~ s:urlRegexp
    return a:shortName
  endif
  
  " Check if it's a user/repo format
  if a:shortName =~ s:shortNameRegexp
    return 'https://' . g:plugin_manager_default_git_host . '/' . a:shortName . '.git'
  endif
  
  " Return empty string if it's not a valid format
  return ''
endfunction

" Check if a repository exists
function! s:RepositoryExists(url)
  " Use git ls-remote to check if the repository exists
  let l:cmd = 'git ls-remote ' . a:url . ' > /dev/null 2>&1'
  let l:exitCode = system(l:cmd)
  
  " Return 0 if the command succeeded (repository exists), non-zero otherwise
  return v:shell_error == 0
endfunction

" Sidebar buffer mappings
function! s:SetupSidebarMappings()
  " Close the sidebar
  nnoremap <buffer> q :bd<CR>
  
  " Common Plugin Manager operations
  nnoremap <buffer> l :call <SID>List()<CR>
  nnoremap <buffer> u :call <SID>Update()<CR>
  nnoremap <buffer> s :call <SID>Status()<CR>
  nnoremap <buffer> b :call <SID>Backup()<CR>
  nnoremap <buffer> h :call <SID>GenerateHelptags()<CR>
  nnoremap <buffer> r :call <SID>Restore()<CR>
  nnoremap <buffer> ? :call <SID>Usage()<CR>
endfunction

" Open the sidebar window
function! s:OpenSidebar(lines)
  " Check if sidebar buffer already exists
  let l:buffer_exists = bufexists(s:buffer_name)
  let l:win_id = bufwinid(s:buffer_name)
  
  if l:win_id != -1
    " Sidebar window is already open, focus it
    call win_gotoid(l:win_id)
    
    " Clear existing content
    setlocal modifiable
    silent! %delete _
  else
    " Create a new window on the right
    execute 'silent! rightbelow ' . g:plugin_manager_sidebar_width . 'vnew ' . s:buffer_name
    
    " Set buffer options
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    setlocal nowrap
    setlocal nobuflisted
    setlocal nonumber
    setlocal filetype=pluginmanager
    setlocal nofoldenable
    
    " Setup mappings
    call s:SetupSidebarMappings()
  endif
  
  " Update buffer content
  call s:UpdateSidebar(a:lines)
  
  " Mark as non-modifiable once content is set
  setlocal nomodifiable
endfunction

" Update the sidebar content
function! s:UpdateSidebar(lines)
  " Find the sidebar buffer window
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1
    " If the window doesn't exist, create it
    call s:OpenSidebar(a:lines)
    return
  endif
  
  " Focus the sidebar window
  call win_gotoid(l:win_id)
  
  " Update content
  setlocal modifiable
  silent! %delete _
  call setline(1, a:lines)
  setlocal nomodifiable
  
  " Move cursor to top
  call cursor(1, 1)
endfunction

" Display usage instructions
function! s:Usage()
  let l:lines = [
        \ "PluginManager Commands:",
        \ "---------------------",
        \ "add <plugin> [modulename] [opt]  - Add a new plugin",
        \ "remove <modulename> [-f]         - Remove a plugin",
        \ "backup                           - Backup configuration",
        \ "list                             - List installed plugins",
        \ "status                           - Show status of submodules",
        \ "update                           - Update all plugins",
        \ "summary                          - Show summary of changes",
        \ "helptags                         - Generate help tags",
        \ "restore                          - Reinstall all modules",
        \ "",
        \ "Sidebar Keyboard Shortcuts:",
        \ "-------------------------",
        \ "q - Close the sidebar",
        \ "l - List installed plugins",
        \ "u - Update all plugins",
        \ "s - Show status of submodules",
        \ "b - Backup configuration",
        \ "h - Generate help tags",
        \ "r - Restore all plugins",
        \ "? - Show this help"
        \ ]
  
  call s:OpenSidebar(l:lines)
endfunction

" List all installed plugins
function! s:List()
  let l:output = system('grep ''url\|path'' .gitmodules | cut -d " " -f3 | awk ''NR%2{printf "%s\t=>\t",$0;next;}1'' | column -t')
  let l:lines = ['Installed Plugins:', '----------------', '']
  call extend(l:lines, split(l:output, "\n"))
  
  call s:OpenSidebar(l:lines)
endfunction

" Show the status of submodules
function! s:Status()
  let l:output = system('git submodule status')
  let l:lines = ['Submodule Status:', '----------------', '']
  call extend(l:lines, split(l:output, "\n"))
  
  call s:OpenSidebar(l:lines)
endfunction

" Show a summary of submodule changes
function! s:Summary()
  let l:output = system('git submodule summary')
  let l:lines = ['Submodule Summary:', '----------------', '']
  call extend(l:lines, split(l:output, "\n"))
  
  call s:OpenSidebar(l:lines)
endfunction

" Update all plugins
function! s:Update()
  let l:lines = ['Updating Plugins:', '----------------', '', 'Updating all plugins...']
  call s:OpenSidebar(l:lines)
  
  " Count the number of submodules for progress calculation
  let l:submodule_count = system('grep "path" .gitmodules | wc -l')
  let l:submodule_count = str2nr(trim(l:submodule_count))
  
  " Start progress
  call s:StartProgress(l:submodule_count > 0 ? l:submodule_count : 10)
  
  " Execute update commands
  call system('git submodule sync')
  call system('git submodule update --remote --merge')
  call system('git commit -am "Update Modules"')
  
  " Update sidebar with results
  let s:command_output = ['Updating Plugins:', '----------------', '', 'All plugins updated successfully.']
  
  " Stop progress and show final state
  call s:StopProgress()
  
  " Generate helptags
  call s:GenerateHelptags()
endfunction

" Backup configuration to remote repositories
function! s:Backup()
  let l:lines = ['Backup Configuration:', '--------------------', '', 'Performing backup...']
  call s:OpenSidebar(l:lines)
  
  " Start progress
  call s:StartProgress(4)  " 4 steps: check vimrc, commit changes, push commits, push tags
  
  " Check if vimrc has been modified
  let l:vimrcStatus = system('git status --porcelain ' . g:plugin_manager_vimrc_path)
  let s:command_output = ['Backup Configuration:', '--------------------', '', 'Checking vimrc status...']
  call s:UpdateProgress(0)  " Update progress
  
  " If vimrc has changes, commit them
  if !empty(l:vimrcStatus)
    call add(s:command_output, 'Committing vimrc changes...')
    call s:UpdateProgress(0)  " Update progress
    call system('git add ' . g:plugin_manager_vimrc_path)
    call system('git commit -m "Auto-backup: Updated vimrc"')
  endif
  
  " Check for other pending changes
  let l:gitStatus = system('git status --porcelain')
  if !empty(l:gitStatus)
    call add(s:command_output, 'Committing pending changes...')
    call s:UpdateProgress(0)  " Update progress
    call system('git add .')
    call system('git commit -m "Auto-backup: Saved pending changes"')
  endif
  
  " Push changes to all configured remotes
  call add(s:command_output, 'Pushing changes to remote repositories...')
  call s:UpdateProgress(0)  " Update progress
  let l:pushResult = system('git push --all')
  call add(s:command_output, l:pushResult)
  
  " Push tags as well
  call add(s:command_output, 'Pushing tags...')
  let l:tagResult = system('git push --tags')
  if !empty(l:tagResult)
    call add(s:command_output, l:tagResult)
  endif
  
  call add(s:command_output, 'Backup completed successfully.')
  
  " Stop progress and show final state
  call s:StopProgress()
endfunction

" Generate helptags for a specific plugin
function! s:GenerateHelptag(pluginPath)
  let l:docPath = a:pluginPath . '/doc'
  if isdirectory(l:docPath)
    execute 'helptags ' . l:docPath
    call add(s:command_output, "Generated helptags for " . fnamemodify(a:pluginPath, ':t'))
    call s:UpdateProgress(0)  " Update progress
  endif
endfunction

" Generate helptags for all installed plugins
function! s:GenerateHelptags()
  let l:lines = ['Generating Helptags:', '------------------', '', 'Generating helptags for all plugins...']
  call s:OpenSidebar(l:lines)
  
  " Initialize output
  let s:command_output = ['Generating Helptags:', '------------------', '', 'Generating helptags:']
  
  " Count plugins for progress
  let l:startPath = g:plugin_manager_plugins_dir . '/' . g:plugin_manager_start_dir
  let l:optPath = g:plugin_manager_plugins_dir . '/' . g:plugin_manager_opt_dir
  let l:plugin_count = 0
  
  if isdirectory(l:startPath)
    let l:plugin_count += len(glob(l:startPath . '/*', 0, 1))
  endif
  
  if isdirectory(l:optPath)
    let l:plugin_count += len(glob(l:optPath . '/*', 0, 1))
  endif
  
  " Start progress
  call s:StartProgress(l:plugin_count > 0 ? l:plugin_count : 5)
  
  " Generate for plugins in 'start' directory
  if isdirectory(l:startPath)
    for l:plugin in glob(l:startPath . '/*', 0, 1)
      call s:GenerateHelptag(l:plugin)
    endfor
  endif
  
  " Generate for plugins in 'opt' directory
  if isdirectory(l:optPath)
    for l:plugin in glob(l:optPath . '/*', 0, 1)
      call s:GenerateHelptag(l:plugin)
    endfor
  endif
  
  call add(s:command_output, "Helptags generation complete.")
  
  " Stop progress and show final state
  call s:StopProgress()
endfunction

" Add a new plugin
function! s:AddModule(moduleUrl, installDir)
  let l:lines = ['Add Plugin:', '----------', '', 'Installing ' . a:moduleUrl . ' in ' . a:installDir . '...']
  call s:OpenSidebar(l:lines)
  
  " Start progress
  call s:StartProgress(3)  " 3 steps: clone, commit, generate tags
  
  " Execute commands
  let s:command_output = ['Add Plugin:', '----------', '', 'Installing ' . a:moduleUrl . '...']
  call s:UpdateProgress(0)  " Update progress
  
  call system('git submodule add "' . a:moduleUrl . '" "' . a:installDir . '"')
  call add(s:command_output, 'Committing changes...')
  call s:UpdateProgress(0)  " Update progress
  
  call system('git commit -m "Added ' . a:moduleUrl . ' module"')
  call add(s:command_output, 'Plugin installed successfully.')
  call s:UpdateProgress(0)  " Update progress
  
  " Generate helptags for the new plugin
  call add(s:command_output, 'Generating helptags...')
  call s:GenerateHelptag(a:installDir)
  
  " Stop progress and show final state
  call s:StopProgress()
endfunction

" Remove an existing plugin
function! s:RemoveModule(moduleName, removedPluginPath)
  let l:lines = ['Remove Plugin:', '-------------', '', 'Removing ' . a:moduleName . ' from ' . a:removedPluginPath . '...']
  call s:OpenSidebar(l:lines)
  
  " Start progress
  call s:StartProgress(4)  " 4 steps: deinit, remove, clean modules, commit
  
  " Execute commands
  let s:command_output = ['Remove Plugin:', '-------------', '', 'Removing module ' . a:moduleName . '...']
  call s:UpdateProgress(0)  " Update progress
  
  call system('git submodule deinit "' . a:removedPluginPath . '"')
  call add(s:command_output, 'Removing repository...')
  call s:UpdateProgress(0)  " Update progress
  
  call system('git rm -rf "' . a:removedPluginPath . '"')
  call add(s:command_output, 'Cleaning .git modules...')
  call s:UpdateProgress(0)  " Update progress
  
  call system('rm -rf .git/modules/"' . a:removedPluginPath . '"')
  call add(s:command_output, 'Committing changes...')
  call s:UpdateProgress(0)  " Update progress
  
  call system('git commit -m "Removed ' . a:moduleName . ' modules"')
  call add(s:command_output, 'Plugin removed successfully.')
  
  " Stop progress and show final state
  call s:StopProgress()
endfunction

" Restore all plugins from .gitmodules
function! s:Restore()
  let l:lines = ['Restore Plugins:', '---------------', '', 'Restoring all plugins...']
  call s:OpenSidebar(l:lines)
  
  " Initialize output
  let s:command_output = ['Restore Plugins:', '---------------', '', 'Checking for .gitmodules file...']
  
  " First, check if .gitmodules exists
  if !filereadable('.gitmodules')
    call add(s:command_output, 'Error: .gitmodules file not found!')
    call s:StopProgress()
    return
  endif
  
  " Count the number of submodules for progress calculation
  let l:submodule_count = system('grep "path" .gitmodules | wc -l')
  let l:submodule_count = str2nr(trim(l:submodule_count))
  
  " Start progress
  call s:StartProgress(l:submodule_count > 0 ? l:submodule_count : 5)
  
  " Initialize submodules if they haven't been yet
  call add(s:command_output, 'Initializing submodules...')
  call s:UpdateProgress(0)  " Update progress
  call system('git submodule init')
  
  " Fetch and update all submodules
  call add(s:command_output, 'Fetching and updating all submodules...')
  call s:UpdateProgress(0)  " Update progress
  call system('git submodule update --init --recursive')
  
  " Make sure all submodules are at the correct commit
  call add(s:command_output, 'Ensuring all submodules are at the correct commit...')
  call s:UpdateProgress(0)  " Update progress
  call system('git submodule sync')
  call system('git submodule update --init --recursive --force')
  
  call add(s:command_output, 'All plugins have been restored successfully.')
  
  " Stop progress
  call s:StopProgress()
  
  " Generate helptags for all plugins
  call s:GenerateHelptags()
endfunction

" Handle 'add' command
function! s:Add(...)
  if a:0 < 1
    let l:lines = ["Add Plugin Usage:", "---------------", "", "Usage: PluginManager add <plugin> [modulename] [opt]"]
    call s:OpenSidebar(l:lines)
    return 1
  endif
  
  let l:pluginInput = a:1
  let l:moduleUrl = s:ConvertToFullUrl(l:pluginInput)
  
  " Check if URL is valid
  if empty(l:moduleUrl)
    let l:lines = ["Invalid Plugin Format:", "--------------------", "", l:pluginInput . " is not a valid plugin name or URL.", "Use format 'user/repo' or complete URL."]
    call s:OpenSidebar(l:lines)
    return 1
  endif
  
  " Check if repository exists
  if !s:RepositoryExists(l:moduleUrl)
    let l:lines = ["Repository Not Found:", "--------------------", "", "Repository not found: " . l:moduleUrl]
    
    " If it was a short name, suggest using a full URL
    if l:pluginInput =~ s:shortNameRegexp
      call add(l:lines, "This plugin was not found on " . g:plugin_manager_default_git_host . ".")
      call add(l:lines, "Try using a full URL to the repository if it's hosted elsewhere.")
    endif
    
    call s:OpenSidebar(l:lines)
    return 1
  endif
  
  " If we got here, the repository exists
  let l:moduleName = fnamemodify(l:moduleUrl, ':t:r')  " Remove .git from the end if present
  
  " Check if a custom module name was provided
  let l:installDir = ""
  
  if a:0 >= 3 && a:3 != ""
    " Install in opt directory with specified name
    if a:2 != ""
      let l:installDir = g:plugin_manager_plugins_dir . "/" . g:plugin_manager_opt_dir . "/" . a:2
    else
      let l:installDir = g:plugin_manager_plugins_dir . "/" . g:plugin_manager_opt_dir . "/" . l:moduleName
    endif
  else
    " Install in start directory
    if a:0 >= 2 && a:2 != ""
      let l:installDir = g:plugin_manager_plugins_dir . "/" . g:plugin_manager_start_dir . "/" . a:2
    else
      let l:installDir = g:plugin_manager_plugins_dir . "/" . g:plugin_manager_start_dir . "/" . l:moduleName
    endif
  endif
  
  call s:AddModule(l:moduleUrl, l:installDir)
  return 0
endfunction

" Handle 'remove' command
function! s:Remove(...)
  if a:0 < 1
    let l:lines = ["Remove Plugin Usage:", "-----------------", "", "Usage: PluginManager remove <modulename> [-f]"]
    call s:OpenSidebar(l:lines)
    return 1
  endif
  
  let l:moduleName = a:1
  let l:removedPluginPath = system('find ' . g:plugin_manager_plugins_dir . ' -type d -name "*' . l:moduleName . '*" | head -n1')
  let l:removedPluginPath = substitute(l:removedPluginPath, '\n$', '', '')
  
  if !empty(l:removedPluginPath) && filereadable(l:removedPluginPath . '/.git')
    if a:0 < 2
      let l:response = input("Are you sure you want to remove " . l:removedPluginPath . "? [y/N] ")
      if l:response =~? '^y\(es\)\?$'
        call s:RemoveModule(l:moduleName, l:removedPluginPath)
      endif
    elseif a:0 >= 2 && a:2 == "-f"
      call s:RemoveModule(l:moduleName, l:removedPluginPath)
    endif
  else
    let l:lines = ["Module Not Found:", "----------------", "", "Unable to find module " . l:moduleName]
    call s:OpenSidebar(l:lines)
    return 1
  endif
  
  return 0
endfunction

" Syntax highlighting for PluginManager buffer
function! s:SetupPluginManagerSyntax()
  if exists('b:current_syntax') && b:current_syntax == 'pluginmanager'
    return
  endif
  
  syntax clear
  
  " Headers
  syntax match PMHeader /^[A-Za-z0-9 ]\+:$/
  syntax match PMSubHeader /^-\+$/
  
  " Progress bar
  syntax match PMProgressBar /█\+░\*/
  syntax match PMPercentage /[0-9]\+%/
  
  " Keywords
  syntax keyword PMKeyword Usage Examples
  syntax match PMCommand /^\s*\(PluginManager\|add\|remove\|list\|status\|update\|summary\|backup\|helptags\|restore\)/
  
  " URLs
  syntax match PMUrl /https\?:\/\/\S\+/
  
  " Success messages
  syntax match PMSuccess /\<successfully\>/
  
  " Set highlighting
  highlight default link PMHeader Title
  highlight default link PMSubHeader Comment
  highlight default link PMProgressBar Special
  highlight default link PMPercentage Number
  highlight default link PMKeyword Statement
  highlight default link PMCommand Function
  highlight default link PMUrl Underlined
  highlight default link PMSuccess String
  
  let b:current_syntax = 'pluginmanager'
endfunction

" Setup autocmd for PluginManager syntax
augroup PluginManagerSyntax
  autocmd!
  autocmd BufNewFile,BufRead,BufEnter PluginManager call s:SetupPluginManagerSyntax()
augroup END

" Function to toggle the Plugin Manager sidebar
function! s:TogglePluginManager()
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id != -1
    " Sidebar is visible, close it
    execute 'bd ' . bufnr(s:buffer_name)
  else
    " Open sidebar with usage info
    call s:Usage()
  endif
endfunction

" Function to add a backup remote repository
function! s:AddRemoteBackup(...)
  if a:0 < 1
    let l:lines = ["Remote Backup Usage:", "-------------------", "", "Usage: PluginManagerRemote <repository_url>"]
    call s:OpenSidebar(l:lines)
    return
  endif
  
  let l:repoUrl = a:1
  if l:repoUrl !~ s:urlRegexp
    let l:lines = ["Invalid URL:", "-----------", "", l:repoUrl . " is not a valid url"]
    call s:OpenSidebar(l:lines)
    return
  endif
  
  let l:lines = ['Add Remote Repository:', '---------------------', '', 'Adding backup repository: ' . l:repoUrl]
  call s:OpenSidebar(l:lines)
  
  " Start progress
  call s:StartProgress(2)  " 2 steps: add remote, verify
  
  " Add remote
  let s:command_output = ['Add Remote Repository:', '---------------------', '', 'Adding repository...']
  call s:UpdateProgress(0)  " Update progress
  call system('git remote set-url origin --add --push ' . l:repoUrl)
  
  " Display configured remotes
  call add(s:command_output, 'Repository added successfully.')
  call add(s:command_output, '')
  call add(s:command_output, 'Configured repositories:')
  let l:remotes = system('git remote -v')
  call extend(s:command_output, split(l:remotes, "\n"))
  call s:UpdateProgress(0)  " Update progress
  
  " Stop progress
  call s:StopProgress()
endfunction

" Define commands
command! -nargs=* PluginManager call PluginManager(<f-args>)
command! -nargs=1 PluginManagerRemote call s:AddRemoteBackup(<f-args>)
command! PluginManagerToggle call s:TogglePluginManager()

" Main function to handle PluginManager commands
  function! PluginManager(...)
    if a:0 < 1
      call s:Usage()
      return
    endif
    
    let l:command = a:1
    
    if l:command == "add" && a:0 >= 2
      call s:Add(a:2, get(a:, 3, ""), get(a:, 4, ""))
    elseif l:command == "remove" && a:0 >= 2
      call s:Remove(a:2, get(a:, 3, ""))
    elseif l:command == "list"
      call s:List()
    elseif l:command == "status"
      call s:Status()
    elseif l:command == "update"
      call s:Update()
    elseif l:command == "summary"
      call s:Summary()
    elseif l:command == "backup"
      call s:Backup()
    elseif l:command == "helptags"
      call s:GenerateHelptags()
    elseif l:command == "restore"
      call s:Restore()
    else
      call s:Usage()
    endif
  endfunction