" vim-plugin-manager.vim - Manage Vim plugins with git submodules
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 1.2

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
  else "TODO: correct default path is ~/.vimrc
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
    let l:error_lines = ['Error:', '------', '', 'Vim directory not found: ' . g:plugin_manager_vim_dir, 
          \ 'Please set g:plugin_manager_vim_dir to your Vim configuration directory.']
    call s:OpenSidebar(l:error_lines)
    return 0
  endif
  
  " Change to vim directory
  execute 'cd ' . g:plugin_manager_vim_dir
  
  " Check if it's a git repository
  if !isdirectory('.git')
    let l:error_lines = ['Error:', '------', '', 'The Vim directory is not a git repository.', 
          \ 'Please initialize it with: git init ' . g:plugin_manager_vim_dir]
    call s:OpenSidebar(l:error_lines)
    return 0
  endif
  
  return 1
endfunction

" Execute command with output in sidebar - redesigned for better efficiency
function! s:ExecuteWithSidebar(title, cmd)
  " Ensure we're in the Vim directory
  if !s:EnsureVimDirectory()
    return ''
  endif
  
  " Create initial header only once
  let l:header = [a:title, repeat('-', len(a:title)), '']
  let l:initial_message = l:header + ['Executing operation, please wait...']
  
  " Create or update sidebar window with initial message
  call s:OpenSidebar(l:initial_message)
  
  " Execute command and collect output
  let l:output = system(a:cmd)
  let l:output_lines = split(l:output, "\n")
  
  " Prepare final output - reuse header
  let l:final_output = l:header + l:output_lines + ['', 'Press q to close this window...']
  
  " Update sidebar with final content - replace entire contents
  call s:UpdateSidebar(l:final_output, 0)
  
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
  
  " Return empty string for calling function to handle not a valid format
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

" Open the sidebar window with optimized logic
function! s:OpenSidebar(lines)
  " Check if sidebar buffer already exists
  let l:buffer_exists = bufexists(s:buffer_name)
  let l:win_id = bufwinid(s:buffer_name)
  
  if l:win_id != -1
    " Sidebar window is already open, focus it
    call win_gotoid(l:win_id)
  else
    " Create a new window on the right
    execute 'silent! rightbelow ' . g:plugin_manager_sidebar_width . 'vnew ' . s:buffer_name
    " Set the filetype to trigger ftplugin and syntax files
    set filetype=pluginmanager
  endif
  
  " Update buffer content more efficiently
  call s:UpdateSidebar(a:lines, 0)
endfunction

" Update the sidebar content with better performance
function! s:UpdateSidebar(lines, append)
  " Find the sidebar buffer window
  let l:win_id = bufwinid(s:buffer_name)
  if l:win_id == -1
    " If the window doesn't exist, create it
    call s:OpenSidebar(a:lines)
    return
  endif
  
  " Focus the sidebar window
  call win_gotoid(l:win_id)
  
  " Only change modifiable state once
  setlocal modifiable
  
  " Update content based on append flag
  if a:append && !empty(a:lines)
    " More efficient append - don't write empty lines
    if line('$') > 0 && getline('$') != ''
      call append(line('$'), '')  " Add separator line
    endif
    call append(line('$'), a:lines)
  else
    " Replace existing content more efficiently
    silent! %delete _
    if !empty(a:lines)
      call setline(1, a:lines)
    endif
  endif
  
  " Set back to non-modifiable and move cursor to top
  setlocal nomodifiable
  call cursor(1, 1)
endfunction

" Display usage instructions
function! s:Usage()
  let l:lines = [
        \ "PluginManager Commands:",
        \ "---------------------",
        \ "add <plugin_url> [opt]       - Add a new plugin",
        \ "remove [plugin_name] [-f]    - Remove a plugin",
        \ "backup                       - Backup configuration",
        \ "reload [plugin]              - Reload configuration",        
        \ "list                         - List installed plugins",
        \ "status                       - Show status of submodules",
        \ "update [plugin_name|all]     - Update all plugins or a specific one",
        \ "helptags [plugin_name]       - Generate plugins helptags, optionally for a specific plugin",
        \ "summary                      - Show summary of changes",
        \ "restore                      - Reinstall all modules",
        \ "",
        \ "Sidebar Keyboard Shortcuts:",
        \ "-------------------------",
        \ "q - Close the sidebar",
        \ "l - List installed plugins",
        \ "u - Update all plugins",
        \ "h - Generate helptags for all plugins",
        \ "s - Show status of submodules",
        \ "S - Show summary of changes",        
        \ "b - Backup configuration",
        \ "r - Restore all plugins",
        \ "R - Reload configuration",
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
  
  " Fix: Check if .gitmodules exists
  if !filereadable('.gitmodules')
    let l:lines = ['Installed Plugins:', '----------------', '', 'No plugins installed (.gitmodules not found)']
    call s:OpenSidebar(l:lines)
    return
  endif
  
  let l:output = system('grep ''url\|path'' .gitmodules | cut -d " " -f3 | awk ''NR%2{printf "%s\t=>\t",$0;next;}1'' | sort | column -t')
  let l:lines = ['Installed Plugins:', '----------------', '']
  call extend(l:lines, split(l:output, "\n"))
  
  call s:OpenSidebar(l:lines)
endfunction

" Show the status of submodules
function! s:Status()
  if !s:EnsureVimDirectory()
    return
  endif
  
  " Fix: Check if .gitmodules exists
  if !filereadable('.gitmodules')
    let l:lines = ['Submodule Status:', '----------------', '', 'No submodules found (.gitmodules not found)']
    call s:OpenSidebar(l:lines)
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
  
  " Fix: Check if .gitmodules exists
  if !filereadable('.gitmodules')
    let l:lines = ['Submodule Summary:', '----------------', '', 'No submodules found (.gitmodules not found)']
    call s:OpenSidebar(l:lines)
    return
  endif
  
  let l:output = system('git submodule summary')
  let l:lines = ['Submodule Summary:', '----------------', '']
  call extend(l:lines, split(l:output, "\n"))
  
  call s:OpenSidebar(l:lines)
endfunction

  function! s:Update(...)
  " Prevent multiple concurrent update calls
  if exists('s:update_in_progress') && s:update_in_progress
    return
  endif
  let s:update_in_progress = 1

  if !s:EnsureVimDirectory()
    let s:update_in_progress = 0
    return
  endif
  
  " Fix: Check if .gitmodules exists
  if !filereadable('.gitmodules')
    let l:lines = ['Updating Plugins:', '----------------', '', 'No plugins to update (.gitmodules not found)']
    call s:OpenSidebar(l:lines)
    let s:update_in_progress = 0
    return
  endif
  
  " Initialize once before executing commands
  let l:header = ['Updating Plugins:', '----------------', '']
  
  " Check if a specific module was specified
  let l:specific_module = a:0 > 0 ? a:1 : 'all'
  
  if l:specific_module == 'all'
    let l:initial_message = l:header + ['Updating all plugins...']
    call s:OpenSidebar(l:initial_message)
    
    " Stash local changes in submodules first
     call s:UpdateSidebar(['Stashing local changes in submodules...'], 1)
    call system('git submodule foreach --recursive "git stash -q || true"')

    " Execute update commands
    call system('git submodule sync')
    let l:updateResult = system('git submodule update --remote --merge --force')
    
    " Fix: Check if commit is needed
    let l:gitStatus = system('git status -s')
    if !empty(l:gitStatus)
      call system('git commit -am "Update Modules"')
    endif
  else
    " Update a specific module
    let l:initial_message = l:header + ['Updating plugin: ' . l:specific_module . '...']
    call s:OpenSidebar(l:initial_message)
    
    " Find the module path
    let l:module_path = ''
    let l:grep_cmd = 'grep -A1 "path = .*' . l:specific_module . '" .gitmodules | grep "path =" | cut -d "=" -f2 | tr -d " "'
    let l:module_path = system(l:grep_cmd)
    let l:module_path = substitute(l:module_path, '\n$', '', '')
    
    if empty(l:module_path)
      call s:UpdateSidebar(['Error: Module "' . l:specific_module . '" not found.'], 1)
      let s:update_in_progress = 0
      return
    endif
    
    " Stash local changes in the specific submodule
    call s:UpdateSidebar(['Stashing local changes in module...'], 1)
    call system('cd "' . l:module_path . '" && git stash -q || true')
    
    " Update only this module
    call system('git submodule sync -- "' . l:module_path . '"')
    let l:updateResult = system('git submodule update --remote --merge --force -- "' . l:module_path . '"')
    
    " Check if commit is needed
    let l:gitStatus = system('git status -s')
    if !empty(l:gitStatus)
      call system('git commit -am "Update Module: ' . l:specific_module . '"')
    endif
  endif
  
  " Update with results
  let l:update_lines = []
  if !empty(l:updateResult)
    let l:update_lines += ['', 'Update details:', '']
    let l:update_lines += split(l:updateResult, "\n")
  endif
  
  " Add update success message
  if l:specific_module == 'all'
    let l:update_lines += ['', 'All plugins updated successfully.']
  else
    let l:update_lines += ['', 'Plugin "' . l:specific_module . '" updated successfully.']
  endif
  
  " Update sidebar with results
  call s:UpdateSidebar(l:update_lines, 1)
  
  " Generate helptags
  if l:specific_module == 'all'
    " Call with flag to indicate NOT to create a header - use our existing sidebar
    call s:GenerateHelptags(0)
  else
    " Generate helptags only for the specific module
    call s:GenerateHelptags(0, l:specific_module)
  endif
  
  " Reset update in progress flag
  let s:update_in_progress = 0
endfunction

" Generate helptags for a specific plugin
function! s:GenerateHelptag(pluginPath)
  let l:docPath = a:pluginPath . '/doc'
  if isdirectory(l:docPath)
    execute 'helptags ' . l:docPath
    return 1
  endif
  return 0
endfunction

"" Generate helptags for all installed plugins
function! s:GenerateHelptags(...)
  " Fix: Properly handle optional arguments
  let l:create_header = a:0 > 0 ? a:1 : 1
  let l:specific_module = a:0 > 1 ? a:2 : ''
  
  if !s:EnsureVimDirectory()
    return
  endif
    
  " Initialize output only if creating a new header
  if l:create_header
    let l:header = ['Generating Helptags:', '------------------', '', 'Generating helptags:']
    call s:OpenSidebar(l:header)
  else
    " If we're not creating a new header, just add a separator line
    call s:UpdateSidebar(['', 'Generating helptags:'], 1)
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
        if s:GenerateHelptag(l:plugin)
          let l:tagsGenerated = 1
          call add(l:generated_plugins, "Generated helptags for " . fnamemodify(l:plugin, ':t'))
        endif
      endfor
    else
      " Generate helptags for all plugins
      for l:plugin in glob(l:pluginsDir . '*/*', 0, 1)
        if s:GenerateHelptag(l:plugin)
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
  
  call s:UpdateSidebar(l:result_message, 1)
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
  
  " Fix: Better parameter handling
  let l:customName = a:0 >= 2 ? a:2 : ""
  let l:isOptional = a:0 >= 3 && a:3 != ""
  
  if l:isOptional
    " Install in opt directory
    if !empty(l:customName)
      let l:installDir = g:plugin_manager_plugins_dir . "/" . g:plugin_manager_opt_dir . "/" . l:customName
    else
      let l:installDir = g:plugin_manager_plugins_dir . "/" . g:plugin_manager_opt_dir . "/" . l:moduleName
    endif
  else
    " Install in start directory
    if !empty(l:customName)
      let l:installDir = g:plugin_manager_plugins_dir . "/" . g:plugin_manager_start_dir . "/" . l:customName
    else
      let l:installDir = g:plugin_manager_plugins_dir . "/" . g:plugin_manager_start_dir . "/" . l:moduleName
    endif
  endif
  
  call s:AddModule(l:moduleUrl, l:installDir)
  return 0
endfunction

" Add a new plugin
function! s:AddModule(moduleUrl, installDir)
  if !s:EnsureVimDirectory()
    return
  endif
  
  let l:header = ['Add Plugin:', '----------', '', 'Installing ' . a:moduleUrl . ' in ' . a:installDir . '...']
  call s:OpenSidebar(l:header)
  
  " Check if module directory exists and create if needed
  let l:parentDir = fnamemodify(a:installDir, ':h')
  if !isdirectory(l:parentDir)
    call mkdir(l:parentDir, 'p')
  endif
  
  " Fix: Check if submodule already exists
  let l:gitmoduleCheck = system('grep -c "' . a:installDir . '" .gitmodules 2>/dev/null')
  if shellescape(l:gitmoduleCheck) != 0
    call s:UpdateSidebar(['Error: Plugin already installed at this location :'. a:installDir], 1)
    return
  end
  
  " Execute git submodule add command
  let l:result = system('git submodule add "' . a:moduleUrl . '" "' . a:installDir . '"')
  if v:shell_error != 0
    let l:error_lines = ['Error installing plugin:']
    call extend(l:error_lines, split(l:result, "\n"))
    call s:UpdateSidebar(l:error_lines, 1)
    return
  endif
  
  call s:UpdateSidebar(['Committing changes...'], 1)
  
  let l:result = system('git commit -m "Added ' . a:moduleUrl . ' module"')
  let l:result_lines = []
  if v:shell_error != 0
    let l:result_lines += ['Error committing changes:']
    let l:result_lines += split(l:result, "\n")
  else
    let l:result_lines += ['Plugin installed successfully.', 'Generating helptags...']
    if s:GenerateHelptag(a:installDir)
      let l:result_lines += ['Helptags generated successfully.']
    else
      let l:result_lines += ['No documentation directory found.']
    endif
  endif
  
  call s:UpdateSidebar(l:result_lines, 1)
endfunction

" Handle 'remove' command - fixed to better handle different module naming patterns
function! s:Remove(...)
  if a:0 < 1
    let l:lines = ["Remove Plugin Usage:", "-----------------", "", "Usage: PluginManager remove <modulename> [-f]"]
    call s:OpenSidebar(l:lines)
    return 1
  endif
  
  let l:moduleName = a:1
  let l:removedPluginPath = ""
  
  " Check if .gitmodules exists, and try to find the module path from it
  if filereadable('.gitmodules')
    " Improved gitmodules search to handle spaces in paths
    let l:grep_cmd = 'grep -A1 "submodule.*' . l:moduleName . '" .gitmodules 2>/dev/null | grep "path" | head -n1 | cut -d "=" -f2'
    let l:removedPluginPath = substitute(system(l:grep_cmd), '^\s*\(.\{-}\)\s*$', '\1', '')
    
    " If that fails, try a manual search through the file
    if empty(l:removedPluginPath)
      let l:lines = readfile('.gitmodules')
      let l:in_module = 0
      let l:found_module = 0
      
      for l:line in l:lines
        if l:line =~ '\[submodule'
          let l:in_module = 1
          let l:found_module = l:line =~ l:moduleName
        elseif l:in_module && l:found_module && l:line =~ '\s*path\s*='
          let l:removedPluginPath = substitute(l:line, '\s*path\s*=\s*', '', '')
          break
        elseif l:in_module && l:line =~ '\[submodule'
          let l:in_module = 0
          let l:found_module = 0
        endif
      endfor
    endif
  endif
  
  " If not found in .gitmodules, try direct filesystem search
  if empty(l:removedPluginPath)
    " Try exact directory name match first
    let l:find_cmd = 'find ' . g:plugin_manager_plugins_dir . ' -type d -name "' . l:moduleName . '" | head -n1'
    let l:removedPluginPath = substitute(system(l:find_cmd), '\n$', '', '')
    
    " Then try partial name match if needed
    if empty(l:removedPluginPath)
      let l:find_cmd = 'find ' . g:plugin_manager_plugins_dir . ' -type d -name "*' . l:moduleName . '*" | head -n1'
      let l:removedPluginPath = substitute(system(l:find_cmd), '\n$', '', '')
    endif
  endif
  
  " Debug information 
  echo "Detected plugin path: " . l:removedPluginPath
  
  if !empty(l:removedPluginPath) && isdirectory(l:removedPluginPath)
    " Force flag provided or prompt for confirmation
    if a:0 >= 2 && a:2 == "-f"
      call s:RemoveModule(l:moduleName, l:removedPluginPath)
    else
      let l:response = input("Are you sure you want to remove " . l:removedPluginPath . "? [y/N] ")
      if l:response =~? '^y\(es\)\?$'
        call s:RemoveModule(l:moduleName, l:removedPluginPath)
      endif
    endif
  else
    " Provide more informative error for debugging
    let l:lines = ["Module Not Found:", "----------------", "", 
          \ "Unable to find module '" . l:moduleName . "'", "",
          \ "Debug info:", "- Plugins directory: " . g:plugin_manager_plugins_dir,
          \ "- Search command: find " . g:plugin_manager_plugins_dir . " -type d -name \"*" . l:moduleName . "*\""]
    
    " Add information about .gitmodules
    if filereadable('.gitmodules')
      let l:lines += ["- .gitmodules exists: Yes", 
            \ "- Search in .gitmodules: grep -A1 \"submodule.*" . l:moduleName . "\" .gitmodules"]
    else
      let l:lines += ["- .gitmodules exists: No"]
    endif
    
    " Add list of currently installed plugins for reference
    let l:installed = []
    if filereadable('.gitmodules')
      let l:lines += ["", "Installed plugins in .gitmodules:"]
      let l:installed = systemlist('grep "path = " .gitmodules | cut -d "=" -f2')
      let l:lines += l:installed
    endif
    
    " If nothing found in .gitmodules but directory exists, show filesystem plugins
    if empty(l:installed)
      let l:lines += ["", "Plugin directories found in filesystem:"]
      let l:fs_plugins = systemlist('find ' . g:plugin_manager_plugins_dir . ' -mindepth 2 -maxdepth 2 -type d | sort')
      let l:lines += l:fs_plugins
    endif
    
    call s:OpenSidebar(l:lines)
    return 1
  endif
  
  return 0
endfunction

" Remove an existing plugin - fixed to provide better error handling
function! s:RemoveModule(moduleName, removedPluginPath)
  if !s:EnsureVimDirectory()
    return
  endif
  
  let l:header = ['Remove Plugin:', '-------------', '', 'Removing ' . a:moduleName . ' from ' . a:removedPluginPath . '...']
  call s:OpenSidebar(l:header)
  
  " Execute deinit command with better error handling
  let l:result = system('git submodule deinit -f "' . a:removedPluginPath . '" 2>&1')
  let l:deinit_success = v:shell_error == 0
  
  if !l:deinit_success
    let l:error_lines = ['Warning during deinitializing submodule (continuing anyway):']
    call extend(l:error_lines, split(l:result, "\n"))
    call s:UpdateSidebar(l:error_lines, 1)
  else
    call s:UpdateSidebar(['Successfully deinitialized submodule.'], 1)
  endif
  
  call s:UpdateSidebar(['Removing repository...'], 1)
  
  " Try to remove repository even if deinit failed
  let l:result = system('git rm -f "' . a:removedPluginPath . '" 2>&1')
  if v:shell_error != 0
    let l:error_lines = ['Error removing repository:']
    call extend(l:error_lines, split(l:result, "\n"))
    call s:UpdateSidebar(l:error_lines, 1)
    
    " Try alternative removal method
    call s:UpdateSidebar(['Trying alternative removal method...'], 1)
    let l:result = system('rm -rf "' . a:removedPluginPath . '" 2>&1')
    if v:shell_error != 0
      call s:UpdateSidebar(['Alternative removal also failed.'], 1)
      return
    else
      call s:UpdateSidebar(['Directory removed manually. You may need to edit .gitmodules manually.'], 1)
    endif
  else
    call s:UpdateSidebar(['Repository removed successfully.'], 1)
  endif
  
  call s:UpdateSidebar(['Cleaning .git modules...'], 1)
  
  " Clean .git/modules directory
  if isdirectory('.git/modules/' . a:removedPluginPath)
    let l:result = system('rm -rf ".git/modules/' . a:removedPluginPath . '" 2>&1')
    if v:shell_error != 0
      let l:error_lines = ['Warning cleaning git modules (continuing anyway):']
      call extend(l:error_lines, split(l:result, "\n"))
      call s:UpdateSidebar(l:error_lines, 1)
    else
      call s:UpdateSidebar(['Git modules cleaned successfully.'], 1)
    endif
  else
    call s:UpdateSidebar(['No module directory to clean in .git/modules.'], 1)
  endif
  
  call s:UpdateSidebar(['Committing changes...'], 1)
  
  " Commit changes - create a forced commit even if nothing staged
  let l:result = system('git add -A && git commit -m "Removed ' . a:moduleName . ' module" || git commit --allow-empty -m "Removed ' . a:moduleName . ' module" 2>&1')
  if v:shell_error != 0
    let l:error_lines = ['Warning during commit (plugin still removed):']
    call extend(l:error_lines, split(l:result, "\n"))
    call s:UpdateSidebar(l:error_lines, 1)
  else
    call s:UpdateSidebar(['Changes committed successfully.'], 1)
  endif
  
  call s:UpdateSidebar(['Plugin removal completed.'], 1)
endfunction

" Backup configuration to remote repositories
function! s:Backup()
  if !s:EnsureVimDirectory()
    return
  endif
  
  let l:header = ['Backup Configuration:', '--------------------', '', 'Checking git status...']
  call s:OpenSidebar(l:header)
  
  " Fix: Check if there are changes to commit
  let l:gitStatus = system('git status -s')
  let l:status_lines = []
  if !empty(l:gitStatus)
    let l:status_lines += ['Committing local changes...']
    let l:commitResult = system('git commit -am "Automatic backup"')
    let l:status_lines += split(l:commitResult, "\n")
  else
    let l:status_lines += ['No local changes to commit.']
  endif
  
  call s:UpdateSidebar(l:status_lines, 1)
  
  " Push changes to all configured remotes
  call s:UpdateSidebar(['Pushing changes to remote repositories...'], 1)
  
  " Fix: Check if any remotes exist
  let l:remotesExist = system('git remote')
  if empty(l:remotesExist)
    call s:UpdateSidebar([
          \ 'No remote repositories configured.',
          \ 'Use PluginManagerRemote to add a remote repository.'
          \ ], 1)
    return
  endif
  
  let l:pushResult = system('git push --all')
  if v:shell_error != 0
    let l:error_lines = ['Error pushing to remote:']
    call extend(l:error_lines, split(l:pushResult, "\n"))
    call s:UpdateSidebar(l:error_lines, 1)
  else
    call s:UpdateSidebar(['Backup completed successfully.'], 1)
  endif
endfunction

" Restore all plugins from .gitmodules
function! s:Restore()
  if !s:EnsureVimDirectory()
    return
  endif
  
  let l:header = ['Restore Plugins:', '---------------', '', 'Checking for .gitmodules file...']
  call s:OpenSidebar(l:header)
  
  " First, check if .gitmodules exists
  if !filereadable('.gitmodules')
    call s:UpdateSidebar(['Error: .gitmodules file not found!'], 1)
    return
  endif
  
  " Initialize submodules if they haven't been yet
  call s:UpdateSidebar(['Initializing submodules...'], 1)
  let l:result = system('git submodule init')
  if v:shell_error != 0
    let l:error_lines = ['Error initializing submodules:']
    call extend(l:error_lines, split(l:result, "\n"))
    call s:UpdateSidebar(l:error_lines, 1)
    return
  endif
  
  " Fetch and update all submodules
  call s:UpdateSidebar(['Fetching and updating all submodules...'], 1)
  let l:result = system('git submodule update --init --recursive')
  if v:shell_error != 0
    let l:error_lines = ['Error updating submodules:']
    call extend(l:error_lines, split(l:result, "\n"))
    call s:UpdateSidebar(l:error_lines, 1)
    return
  endif
  
  " Make sure all submodules are at the correct commit
  call s:UpdateSidebar(['Ensuring all submodules are at the correct commit...'], 1)
  call system('git submodule sync')
  let l:result = system('git submodule update --init --recursive --force')
  if v:shell_error != 0
    let l:error_lines = ['Error during final submodule update:']
    call extend(l:error_lines, split(l:result, "\n"))
    call s:UpdateSidebar(l:error_lines, 1)
    return
  endif
  
  call s:UpdateSidebar(['All plugins have been restored successfully.', '', 'Generating helptags:'], 1)
  
  " Generate helptags for all plugins
  call s:GenerateHelptags(0)
endfunction

" Reload a specific plugin or all Vim configuration
function! s:Reload(...)
  if !s:EnsureVimDirectory()
    return
  endif
  
  let l:header = ['Reload:', '-------', '']
  
  " Check if a specific module was specified
  let l:specific_module = a:0 > 0 ? a:1 : ''
  
  if !empty(l:specific_module)
    " Reload a specific module
    call s:OpenSidebar(l:header + ['Reloading plugin: ' . l:specific_module . '...'])
    
    " Find the module path
    let l:grep_cmd = 'grep -A1 "path = .*' . l:specific_module . '" .gitmodules | grep "path =" | cut -d "=" -f2 | tr -d " "'
    let l:module_path = system(l:grep_cmd)
    let l:module_path = substitute(l:module_path, '\n$', '', '')
    
    if empty(l:module_path)
      call s:UpdateSidebar(['Error: Module "' . l:specific_module . '" not found.'], 1)
      return
    endif
    
    " Simple approach: remove and re-add to runtime path
    execute 'set rtp-=' . l:module_path
    execute 'set rtp+=' . l:module_path
    
    call s:UpdateSidebar(['Plugin "' . l:specific_module . '" reloaded.'], 1)
  else
    " Reload all Vim configuration
    call s:OpenSidebar(l:header + ['Reloading entire Vim configuration...'])
    
    " Source vimrc file - this is the simplest way to reload everything
    if filereadable(g:plugin_manager_vimrc_path)
      call s:UpdateSidebar(['Sourcing ' . g:plugin_manager_vimrc_path . '...'], 1)
      execute 'source ' . g:plugin_manager_vimrc_path
      call s:UpdateSidebar(['Vim configuration reloaded successfully.'], 1)
    else
      call s:UpdateSidebar(['Warning: Vimrc file not found at ' . g:plugin_manager_vimrc_path], 1)
    endif
  endif
endfunction

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
  
  let l:header = ['Add Remote Repository:', '---------------------', '', 'Adding backup repository: ' . l:repoUrl]
  call s:OpenSidebar(l:header)
  
  " Check if remote origin exists
  let l:originExists = system('git remote | grep -c "^origin$" || echo 0')
  if l:originExists == "0"
    call s:UpdateSidebar(['Adding origin remote...'], 1)
    let l:result = system('git remote add origin ' . l:repoUrl)
  else
    call s:UpdateSidebar(['Adding push URL to origin remote...'], 1)
    let l:result = system('git remote set-url origin --add --push ' . l:repoUrl)
  endif
  
  let l:result_lines = []
  if v:shell_error != 0
    let l:result_lines += ['Error adding remote:']
    let l:result_lines += split(l:result, "\n")
  else
    let l:result_lines += ['Repository added successfully.']
  endif
  
  call s:UpdateSidebar(l:result_lines, 1)
  
  " Display configured repositories
  call s:UpdateSidebar(['', 'Configured repositories:'], 1)
  let l:remotes = system('git remote -v')
  call s:UpdateSidebar(split(l:remotes, "\n"), 1)
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
      " Pass the optional module name if provided
      if a:0 >= 2
        call s:Update(a:2)
      else
        call s:Update('all')
      endif
    elseif l:command == "summary"
      call s:Summary()
    elseif l:command == "backup"
      call s:Backup()
    elseif l:command == "restore"
      call s:Restore()
    elseif l:command == "helptags"
      " Pass the optional module name if provided
      if a:0 >= 2
        call s:GenerateHelptags(1, a:2)
      else 
        call s:GenerateHelptags()
      endif
    elseif l:command == "reload"
      " Pass the optional module name if provided
      if a:0 >= 2
        call s:Reload(a:2)
      else
        call s:Reload()
      endif
    else
      call s:Usage()
    endif
  endfunction