" Utility functions for vim-plugin-manager

" Function to ensure we're in the Vim config directory
function! plugin_manager#utils#ensure_vim_directory()
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
      call plugin_manager#ui#open_sidebar(l:error_lines)
      return 0
    endif
    
    " Change to vim directory
    execute 'cd ' . g:plugin_manager_vim_dir
    
    " Check if it's a git repository
    if !isdirectory('.git')
      let l:error_lines = ['Error:', '------', '', 'The Vim directory is not a git repository.', 
            \ 'Please initialize it with: git init ' . g:plugin_manager_vim_dir]
      call plugin_manager#ui#open_sidebar(l:error_lines)
      return 0
    endif
    
    return 1
  endfunction
  
  " Execute command with output in sidebar - redesigned for better efficiency
  function! plugin_manager#utils#execute_with_sidebar(title, cmd)
    " Ensure we're in the Vim directory
    if !plugin_manager#utils#ensure_vim_directory()
      return ''
    endif
    
    " Create initial header only once
    let l:header = [a:title, repeat('-', len(a:title)), '']
    let l:initial_message = l:header + ['Executing operation, please wait...']
    
    " Create or update sidebar window with initial message
    call plugin_manager#ui#open_sidebar(l:initial_message)
    
    " Execute command and collect output
    let l:output = system(a:cmd)
    let l:output_lines = split(l:output, "\n")
    
    " Prepare final output - reuse header
    let l:final_output = l:header + l:output_lines + ['', 'Press q to close this window...']
    
    " Update sidebar with final content - replace entire contents
    call plugin_manager#ui#update_sidebar(l:final_output, 0)
    
    return l:output
  endfunction
  
  " Convert short name to full URL
  function! plugin_manager#utils#convert_to_full_url(shortName)
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
  function! plugin_manager#utils#repository_exists(url)
    " Use git ls-remote to check if the repository exists
    let l:cmd = 'git ls-remote ' . a:url . ' > /dev/null 2>&1'
    let l:exitCode = system(l:cmd)
    
    " Return 0 if the command succeeded (repository exists), non-zero otherwise
    return v:shell_error == 0
  endfunction