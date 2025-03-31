" vim-plugin-manager.vim - Manage Vim plugins with git submodules
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.1

if exists('g:loaded_plugin_manager') || &cp
  finish
endif
let g:loaded_plugin_manager = 1

" Configuration
if !exists('g:plugin_manager_vim_dir')
  " Detect Vim directory based on platform and configuration
  if has('nvim')
    " Neovim default config directory
    if empty($XDG_CONFIG_HOME)
      let g:plugin_manager_vim_dir = expand('~/.config/nvim')
    else
      let g:plugin_manager_vim_dir = expand($XDG_CONFIG_HOME . '/nvim')
    endif
  else
    " Standard Vim directory
    if has('win32') || has('win64')
      let g:plugin_manager_vim_dir = expand('~/vimfiles')
    else
      let g:plugin_manager_vim_dir = expand('~/.vim')
    endif
  endif
endif

if !exists('g:plugin_manager_plugins_dir')
  let g:plugin_manager_plugins_dir = g:plugin_manager_vim_dir . "/pack/plugins"
endif

if !exists('g:plugin_manager_start_dir')
  let g:plugin_manager_start_dir = "start"
endif

if !exists('g:plugin_manager_opt_dir')
  let g:plugin_manager_opt_dir = "opt"
endif

if !exists('g:plugin_manager_vimrc_path')
  if has('nvim')
    let g:plugin_manager_vimrc_path = g:plugin_manager_vim_dir . '/init.vim'
  else
    let g:plugin_manager_vimrc_path = g:plugin_manager_vim_dir . '/vimrc'
  endif
endif

if !exists('g:plugin_manager_sidebar_width')
  let g:plugin_manager_sidebar_width = 60
endif

if !exists('g:plugin_manager_default_git_host')
  let g:plugin_manager_default_git_host = "github.com"
endif

" Internal variables
let s:urlRegexp = 'https\?:\/\/\(www\.\)\?[-a-zA-Z0-9@:%._\\+~#=]\{1,256}\.[a-zA-Z0-9()]\{1,6}\b\([-a-zA-Z0-9()@:%_\\+.~#?&//=]*\)'
let s:shortNameRegexp = '^[a-zA-Z0-9_-]\+\/[a-zA-Z0-9_-]\+$'
let s:buffer_name = 'PluginManager'
let s:command_output = []

" Function to ensure we're in the Vim config directory
function! s:EnsureVimDirectory()
  " Get current directory
  let l:current_dir = getcwd()
  
  " Check if we're already in the vim directory
  if l:current_dir == g:plugin_manager_vim_dir
    return 1
  endif
  
  " Check if the vim directory exists
  if !isdirectory(g:plugin_manager_vim_dir)
    let s:command_output = ['Error:', '------', '', 'Vim directory not found: ' . g:plugin_manager_vim_dir, 
          \ 'Please set g:plugin_manager_vim_dir to your Vim configuration directory.']
    call s:OpenSidebar(s:command_output)
    return 0
  endif
  
  " Change to vim directory
  execute 'cd ' . g:plugin_manager_vim_dir
  
  " Check if it's a git repository
  if !isdirectory('.git')
    let s:command_output = ['Error:', '------', '', 'The Vim directory is not a git repository.', 
          \ 'Please initialize it with: git init ' . g:plugin_manager_vim_dir]
    call s:OpenSidebar(s:command_output)
    return 0
  endif
  
  return 1
endfunction

" Execute command with output in sidebar
function! s:ExecuteWithSidebar(title, cmd)
  " Ensure we're in the Vim directory
  if !s:EnsureVimDirectory()
    return ''
  endif
  
  " Initialize output collection
  let s:command_output = [a:title, repeat('-', len(a:title)), '', 'Executing operation, please wait...']
  
  " Create or update sidebar window
  call s:OpenSidebar(s:command_output)
  
  " Execute command and collect output 
  let l:output = system(a:cmd)
  let s:command_output = [a:title, repeat('-', len(a:title)), '']
  call extend(s:command_output, split(l:output, "\n"))
  
  " Update sidebar with new content
  call add(s:command_output, '')
  call add(s:command_output, 'Press q to close this window...')
  call s:UpdateSidebar(s:command_output)
  
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
    setlocal updatetime=300
    
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
        \ "? - Show this help",
        \ "",
        \ "Configuration:",
        \ "-------------",
        \ "g:plugin_manager_vim_dir = \"" . g:plugin_manager_vim_dir . "\"",
        \ "g:plugin_manager_plugins_dir = \"" . g:plugin_manager_plugins_dir . "\"",
        \ "g:plugin_manager_vimrc_path = \"" . g:plugin_manager_vimrc_path . "\""
        \ ]
  
  call s:OpenSidebar(l:lines)
endfunction

" List all installed plugins
function! s:List()
  if !s:EnsureVimDirectory()
    return
  endif
  
  let l:output = system('grep ''url\|path'' .gitmodules | cut -d " " -f3 | awk ''NR%2{printf "%s\t=>\t",$0;next;}1'' | column -t')
  let l:lines = ['Installed Plugins:', '----------------', '']
  call extend(l:lines, split(l:output, "\n"))
  
  call s:OpenSidebar(l:lines)
endfunction

" Show the status of submodules
function! s:Status()
  if !s:EnsureVimDirectory()
    return
  endif
  
  let l:output = system('git submodule status')
  let l:lines = ['Submodule Status:', '----------------', '']
  call extend(l:lines, split(l:output, "\n"))
  
  call s:OpenSidebar(l:lines)
endfunction

" Show a summary of submodule changes
function! s:Summary()
  if !s:EnsureVimDirectory()
    return
  endif
  
  let l:output = system('git submodule summary')
  let l:lines = ['Submodule Summary:', '----------------', '']
  call extend(l:lines, split(l:output, "\n"))
  
  call s:OpenSidebar(l:lines)
endfunction

" Update all plugins
function! s:Update()
  if !s:EnsureVimDirectory()
    return
  endif
  
  let l:lines = ['Updating Plugins:', '----------------', '', 'Updating all plugins...']
  call s:OpenSidebar(l:lines)
  
  " Execute update commands
  call system('git submodule sync')
  call system('git submodule update --remote --merge')
  call system('git commit -am "Update Modules"')
  
  " Update sidebar with results
  let s:command_output = ['Updating Plugins:', '----------------', '', 'All plugins updated successfully.']
  call s:UpdateSidebar(s:command_output)
  
  " Generate helptags
  call s:GenerateHelptags()
endfunction

" Backup configuration to remote repositories
function! s:Backup()
  if !s:EnsureVimDirectory()
    return
  endif
  
  let l:lines = ['Backup Configuration:', '--------------------', '', 'Performing backup...']
  call s:OpenSidebar(l:lines)
  
  " Check if vimrc has been modified
  "let l:vimrcStatus = system('git status --porcelain ' . g:plugin_manager_vimrc_path)
  "let s:command_output = ['Backup Configuration:', '--------------------', '', 'Checking vimrc status...']
  
  " If vimrc has changes, commit them
  "if !empty(l:vimrcStatus)
  "  call add(s:command_output, 'Committing vimrc changes...')
  "  call system('git add ' . g:plugin_manager_vimrc_path)
  "  call system('git commit -m "Auto-backup: Updated vimrc"')
  "endif
  
  " Check for other pending changes
  "let l:gitStatus = system('git status --porcelain')
  "if !empty(l:gitStatus)
  "  call add(s:command_output, 'Committing pending changes...')
  "  call system('git add .')
  "  call system('git commit -m "Auto-backup: Saved pending changes"')
  "endif
  
  " Push changes to all configured remotes
  call add(s:command_output, 'Pushing changes to remote repositories...')
  let l:pushResult = system('git push --all')
  call add(s:command_output, l:pushResult)
  
  " Push tags as well
  "call add(s:command_output, 'Pushing tags...')
  "let l:tagResult = system('git push --tags')
  "if !empty(l:tagResult)
  "  call add(s:command_output, l:tagResult)
  "endif
  
  call add(s:command_output, 'Backup completed successfully.')
  call s:UpdateSidebar(s:command_output)
endfunction

" Generate helptags for a specific plugin
function! s:GenerateHelptag(pluginPath)
  let l:docPath = a:pluginPath . '/doc'
  if isdirectory(l:docPath)
    execute 'helptags ' . l:docPath
    call add(s:command_output, "Generated helptags for " . fnamemodify(a:pluginPath, ':t'))
  endif
endfunction

" Generate helptags for all installed plugins
function! s:GenerateHelptags()
  if !s:EnsureVimDirectory()
    return
  endif
  
  let l:lines = ['Generating Helptags:', '------------------', '', 'Generating helptags for all plugins...']
  call s:OpenSidebar(l:lines)
  
  " Initialize output
  let s:command_output = ['Generating Helptags:', '------------------', '', 'Generating helptags:']
  
  " Generate for plugins in 'start' directory
  let l:startPath = g:plugin_manager_plugins_dir . '/' . g:plugin_manager_start_dir
  if isdirectory(l:startPath)
    for l:plugin in glob(l:startPath . '/*', 0, 1)
      call s:GenerateHelptag(l:plugin)
    endfor
  endif
  
  " Generate for plugins in 'opt' directory
  let l:optPath = g:plugin_manager_plugins_dir . '/' . g:plugin_manager_opt_dir
  if isdirectory(l:optPath)
    for l:plugin in glob(l:optPath . '/*', 0, 1)
      call s:GenerateHelptag(l:plugin)
    endfor
  endif
  
  call add(s:command_output, "Helptags generation complete.")
  call s:UpdateSidebar(s:command_output)
endfunction

" Add a new plugin
function! s:AddModule(moduleUrl, installDir)
  if !s:EnsureVimDirectory()
    return
  endif
  
  let l:lines = ['Add Plugin:', '----------', '', 'Installing ' . a:moduleUrl . ' in ' . a:installDir . '...']
  call s:OpenSidebar(l:lines)
  
  " Execute commands
  let s:command_output = ['Add Plugin:', '----------', '', 'Installing ' . a:moduleUrl . '...']
  
  call system('git submodule add "' . a:moduleUrl . '" "' . a:installDir . '"')
  call add(s:command_output, 'Committing changes...')
  
  call system('git commit -m "Added ' . a:moduleUrl . ' module"')
  call add(s:command_output, 'Plugin installed successfully.')
  
  " Generate helptags for the new plugin
  call add(s:command_output, 'Generating helptags...')
  call s:GenerateHelptag(a:installDir)
  
  call s:UpdateSidebar(s:command_output)
endfunction

" Remove an existing plugin
function! s:RemoveModule(moduleName, removedPluginPath)
  if !s:EnsureVimDirectory()
    return
  endif
  
  let l:lines = ['Remove Plugin:', '-------------', '', 'Removing ' . a:moduleName . ' from ' . a:removedPluginPath . '...']
  call s:OpenSidebar(l:lines)
  
  " Execute commands
  let s:command_output = ['Remove Plugin:', '-------------', '', 'Removing module ' . a:moduleName . '...']
  
  call system('git submodule deinit "' . a:removedPluginPath . '"')
  call add(s:command_output, 'Removing repository...')
  
  call system('git rm -rf "' . a:removedPluginPath . '"')
  call add(s:command_output, 'Cleaning .git modules...')
  
  call system('rm -rf .git/modules/"' . a:removedPluginPath . '"')
  call add(s:command_output, 'Committing changes...')
  
  call system('git commit -m "Removed ' . a:moduleName . ' modules"')
  call add(s:command_output, 'Plugin removed successfully.')
  
  call s:UpdateSidebar(s:command_output)
endfunction

" Restore all plugins from .gitmodules
function! s:Restore()
  if !s:EnsureVimDirectory()
    return
  endif
  
  let l:lines = ['Restore Plugins:', '---------------', '', 'Restoring all plugins...']
  call s:OpenSidebar(l:lines)
  
  " Initialize output
  let s:command_output = ['Restore Plugins:', '---------------', '', 'Checking for .gitmodules file...']
  
  " First, check if .gitmodules exists
  if !filereadable('.gitmodules')
    call add(s:command_output, 'Error: .gitmodules file not found!')
    call s:UpdateSidebar(s:command_output)
    return
  endif
  
  " Initialize submodules if they haven't been yet
  call add(s:command_output, 'Initializing submodules...')
  call system('git submodule init')
  
  " Fetch and update all submodules
  call add(s:command_output, 'Fetching and updating all submodules...')
  call system('git submodule update --init --recursive')
  
  " Make sure all submodules are at the correct commit
  call add(s:command_output, 'Ensuring all submodules are at the correct commit...')
  call system('git submodule sync')
  call system('git submodule update --init --recursive --force')
  
  call add(s:command_output, 'All plugins have been restored successfully.')
  call s:UpdateSidebar(s:command_output)
  
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
  if !s:EnsureVimDirectory()
    return
  endif
  
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
  
  " Add remote
  let s:command_output = ['Add Remote Repository:', '---------------------', '', 'Adding repository...']
  call system('git remote set-url origin --add --push ' . l:repoUrl)
  
  " Display configured remotes
  call add(s:command_output, 'Repository added successfully.')
  call add(s:command_output, '')
  call add(s:command_output, 'Configured repositories:')
  let l:remotes = system('git remote -v')
  call extend(s:command_output, split(l:remotes, "\n"))
  
  call s:UpdateSidebar(s:command_output)
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