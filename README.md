# Vim Plugin Manager

A lightweight Vim plugin manager that uses Git submodules and Vim 8's native package system.

> Note: PluginManager targets Vim only. Neovim already has mature, Lua-based
> managers (lazy.nvim, packer.nvim) as well as vim-plug, so it is not supported
> here. Neovim users should use one of those instead.

[![CI vader tests](https://github.com/log0u7/vim-plugin-manager/actions/workflows/test.yml/badge.svg)](https://github.com/log0u7/vim-plugin-manager/actions/workflows/test.yml)
[![Version](https://img.shields.io/github/v/tag/log0u7/vim-plugin-manager?style=flat&label=version&sort=semver)](https://github.com/log0u7/vim-plugin-manager/tags)
[![Vim](https://img.shields.io/badge/vim-%3E%3D8.2%20%28%2Bjob%20%2Bchannel%29-brightgreen)]()

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [Tips & Tricks](#tips--tricks)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Features

- Manage plugins through Git submodules
- Easy installation, removal, and updating of plugins
- Automatic generation of helptags
- Backup your entire Vim configuration to multiple remote repositories
- Works with Vim 8's native package loading system
- Full Git integration for plugin versioning
- Support for optional (lazy-loaded) plugins
- Interactive sidebar interface
- Modern, non-blocking UI with spinners (operations never freeze the editor)
- Asynchronous operations for better performance

## Requirements

- Vim 8.2+ (built with `+job` and `+channel` for async; falls back to
  synchronous execution otherwise)
- Git 2.40 or higher

## Installation

### Prerequisites

- Vim 8.2+
- Git 2.40 or higher

### Simple Installation

1. **Initialize your Vim configuration as a Git repository** (if not already done):

```bash
# If you don't already have a Git repository for your Vim configuration
cd ~/.vim
git init
```

2. **Add the plugin manager as a submodule**:

```bash
# Add the plugin as a submodule directly to the appropriate location
git submodule add https://github.com/log0u7/vim-plugin-manager.git ~/.vim/pack/plugins/start/vim-plugin-manager
```

3. **Generate helptags** (choose one method):

```bash
# From the command line
vim -c "helptags ~/.vim/pack/plugins/start/vim-plugin-manager/doc" -c q
```

Or after opening Vim:

```vim
:helptags ~/.vim/pack/plugins/start/vim-plugin-manager/doc
```

That's it! The plugin manager will automatically create necessary directories when you install plugins.

## Managing Your Configuration

### Custom Plugin Configurations

Since the plugin manager uses Git to manage your `.vim` directory, it can create and version control various subdirectories (like `.vim/plugin`, `.vim/ftdetect`, `.vim/ftplugin`, etc.) for its own configurations and mappings.

A good practice is to create your own configuration files for each plugin you install. For example:

```
~/.vim/plugin/nerdtree_config.vim
~/.vim/plugin/fzf_config.vim
~/.vim/plugin/fugitive_config.vim
```

These files will be automatically included in backups when using `:PluginManager backup` since the plugin manager will commit all changes in your Vim configuration directory before pushing to remote repositories. This ensures that all your custom configurations, mappings, and settings are properly versioned and backed up.

### Example Plugin Configurations

Here are some examples for common plugins:

**NERDTree Configuration** (`~/.vim/plugin/nerdtree_config.vim`):
```vim
" Custom NERDTree configuration
let g:NERDTreeShowHidden = 1
let g:NERDTreeMinimalUI = 1
let g:NERDTreeIgnore = ['^\.git$', '^\.DS_Store$']
nnoremap <leader>n :NERDTreeToggle<CR>
```

**FZF Configuration** (`~/.vim/plugin/fzf_config.vim`):
```vim
" Custom FZF configuration
let g:fzf_layout = { 'down': '~40%' }
nnoremap <leader>f :Files<CR>
nnoremap <leader>b :Buffers<CR>
nnoremap <leader>g :GFiles<CR>
```

**Fugitive Configuration** (`~/.vim/plugin/fugitive_config.vim`):
```vim
" Custom Fugitive configuration
nnoremap <leader>gs :Git<CR>
nnoremap <leader>gc :Git commit<CR>
nnoremap <leader>gp :Git push<CR>
```

### Using .gitignore

To exclude certain files from version control, create a `.gitignore` file in your Vim configuration directory:

```bash
# Create a .gitignore file
touch ~/.vim/.gitignore
```

Add the following content to exclude temporary files, undo history, swap files, and helptags:

```
# Ignore undo history
undodir/*
# Ignore swap files
*.swp
*.swo
.*.swp
.*.swo
swapdir/*
# Ignore helptags
doc/tags
**/doc/tags
# Ignore netrw history
.netrwhist
# Ignore session files
session/*
# Ignore local vimrc files
.exrc
.vimrc.local
```

Make sure to commit your `.gitignore` file:

```bash
git add .gitignore
git commit -m "Add .gitignore for Vim configuration"
```

### Alternative: Creating Your Own Plugin Structure

If you prefer, you can create your own plugin structure as a Git submodule:

```bash
# Create your custom Vim configuration repository
mkdir ~/my-vim-config
cd ~/my-vim-config
git init

# Create the standard Vim directory structure
mkdir -p plugin ftplugin ftdetect syntax autoload doc colors after

# Add your configurations to the appropriate directories
# For example:
touch plugin/mappings.vim
touch plugin/settings.vim
touch plugin/plugin_configs.vim

# Commit your changes
git add .
git commit -m "Initial setup of my Vim configuration"

# Push to your own repository (optional)
git remote add origin https://github.com/yourusername/my-vim-config.git
git push -u origin main

# Now add this as a submodule to your Vim configuration
# You can use either direct Git command:
cd ~/.vim
git submodule add https://github.com/yourusername/my-vim-config.git pack/personal/start/my-vim-config

# Or use PluginManager itself:
:PluginManager add https://github.com/yourusername/my-vim-config.git {'dir':'my-vim-config'}
```

This approach keeps your personal configurations organized and separate from the plugin manager and other plugins.

## Usage

### Installing Plugins

```vim
" Install a plugin from GitHub (username/repo format)
:PluginManager add tpope/vim-fugitive

" Install a plugin to start/ directory (auto-loaded) using full URL
:PluginManager add https://github.com/tpope/vim-fugitive.git

" Install with options (new format)
:PluginManager add tpope/vim-surround {'dir':'surround', 'load':'start', 'branch':'main'}

" Install as an optional plugin with a specific tag
:PluginManager add tpope/vim-commentary {'load':'opt', 'tag':'v1.3'}

" Install a plugin and run a command after installation
:PluginManager add junegunn/fzf {'exec':'./install --all'}

" For backward compatibility:
" Install with a custom name (old format)
:PluginManager add tpope/vim-surround surround

" Install as an optional plugin (old format)
:PluginManager add tpope/vim-commentary commentary opt

" Install a plugin from a custom URL (non-GitHub)
:PluginManager add https://gitlab.com/user/repo.git
```

### Declarative Plugin Configuration in vimrc

You can define all your plugins in your vimrc file using the declarative syntax. This is especially helpful for managing multiple plugins and ensuring your setup is reproducible:

```vim
" In your vimrc file:
PluginBegin
  " Basic syntax: Plugin 'username/repo'
  Plugin 'tpope/vim-fugitive'
  Plugin 'tpope/vim-surround'

  " With options:
  Plugin 'preservim/nerdtree', {'load': 'opt'}
  Plugin 'junegunn/fzf', {'dir': 'fzf', 'exec': './install --all'}
  Plugin 'fatih/vim-go', {'tag': 'v1.28'}
  Plugin 'neoclide/coc.nvim', {'branch': 'release'}

  " Local plugin (from filesystem):
  Plugin '~/projects/my-vim-plugin'
PluginEnd
```

When Vim loads your vimrc, all these plugins will be installed automatically if they don't exist yet. This allows you to easily manage your plugin collection and share your configuration with others.

### Removing Plugins

```vim
" With confirmation
:PluginManager remove fugitive

" Force remove without confirmation
:PluginManager remove surround -f
```

### Managing Plugins

```vim
" List all installed plugins
:PluginManager list

" Show status of all plugins
:PluginManager status

" Update all plugins
:PluginManager update

" Update a specific plugin
:PluginManager update vim-fugitive

" Check for available updates without installing them
:PluginManager check

" Show a summary of all plugin changes
:PluginManager summary

" Generate helptags for all plugins
:PluginManager helptags

" Generate helptags for a specific plugin
:PluginManager helptags vim-fugitive

" Reload a specific plugin
:PluginManager reload vim-fugitive

" Reload all Vim configuration
:PluginManager reload
```

### Backup and Restore

```vim
" Commit any changes to vimrc, custom configurations, and new plugins, then push to all remotes
:PluginManager backup

" Reinstall all plugins from .gitmodules
:PluginManager restore

" Add a new backup repository
:PluginManagerRemote https://github.com/yourusername/vim-config-backup.git
```

The backup command will:
1. Copy your main configuration file (`.vimrc`) into your `.vim` directory to ensure it's versioned along with everything else
2. Commit all changes in your Vim configuration directory, including:
   - Your custom plugin configurations in the `plugin/` directory
   - Any modifications to settings in `ftplugin/`, `syntax/`, `colors/`, etc.
   - New or modified mappings and commands
   - Any file not excluded by `.gitignore`

Note that while your own configuration files are backed up, changes inside plugin submodules themselves won't be included in the backup - these are tracked separately as Git submodules pointing to specific commits.

**Important Security Note**: Never store sensitive information (API keys, GPG keys, tokens, passwords) in your versioned configuration files. Instead:

1. Create separate configuration files for secrets:
   ```
   ~/.vim/plugin/fugitive-secrets.vim
   ~/.vim/plugin/api-secrets.vim
   ~/.vim/plugin/private-settings.vim
   ```

2. Exclude these files in your `.gitignore`:
   ```
   # Ignore secret configuration files
   plugin/*-secrets.vim
   plugin/private-*.vim
   ```

3. Or use a private repository if your entire configuration contains sensitive information


4. You also can reference external files from your main configuration:
```vim
" In your .vimrc
if filereadable(expand("~/api-secrets.vim"))
  source ~/api-secrets.vim
endif
```

### Update Notifications and Automatic Updates

PluginManager can check whether your plugins have updates available. The check
runs a background `git fetch` for each plugin and reports the ones that are
behind their remote branch in the sidebar.

All of this is **opt-in** and **disabled by default**: PluginManager never
performs network access on startup unless you explicitly enable it.

```vim
" Check on demand (manual)
:PluginManager check
```

To check automatically when Vim starts, enable it in your vimrc:

```vim
" Check for available updates on startup (default: 0/off)
let g:plugin_manager_check_on_startup = 1

" Hours between background checks; results are cached to avoid
" re-fetching on every launch (default: 24)
let g:plugin_manager_check_interval = 24

" Automatically install available updates on startup (default: 0/off)
" Implies check_on_startup behavior; honors pull_strategy and
" auto_commit_on_update.
let g:plugin_manager_auto_update = 1
```

When `check_on_startup` is enabled, PluginManager caches the last result and
only performs a new network fetch once `check_interval` hours have elapsed. With
`auto_update` enabled, available updates are installed in the background after
the check completes.

### Interactive Interface

```vim
" Toggle the plugin manager sidebar
:PluginManagerToggle
```

#### Sidebar Keyboard Shortcuts

- `q` - Close the sidebar
- `c` - Check for available updates
- `l` - List installed plugins
- `u` - Update all plugins
- `h` - Generate helptags for all plugins
- `s` - Show status of submodules
- `S` - Show summary of changes
- `b` - Backup configuration
- `r` - Restore all plugins
- `R` - Reload configuration
- `?` - Show usage information

### Backup Configuration to Multiple Repositories

```bash
cd ~/.vim
git remote rename origin genesis
git remote add origin your_repository_url

# Optional: Add backup repositories
git remote set-url origin --add --push second_repository_url
git remote set-url origin --add --push third_repository_url
```

## Configuration

You can customize the plugin manager by setting the following variables in your vimrc:

```vim
" Custom Vim configuration directory
let g:plugin_manager_vim_dir = '~/.vim'

" Custom plugin directory
let g:plugin_manager_plugins_dir = '~/.vim/pack/plugins'

" Custom directory for auto-loaded plugins
let g:plugin_manager_start_dir = 'start'

" Custom directory for optional (lazy-loaded) plugins
let g:plugin_manager_opt_dir = 'opt'

" Custom vimrc location
let g:plugin_manager_vimrc_path = '~/.vim/vimrc'

" Custom sidebar width (default: 80)
let g:plugin_manager_sidebar_width = 80

" Spinner style and refresh interval (ms) for the non-blocking UI
let g:plugin_manager_spinner_style = 'dots'  " dots, line, circle, triangle, box
let g:plugin_manager_spinner_interval = 80

" Default git host for short plugin names
let g:plugin_manager_default_git_host = 'github.com'

" Git pull strategy for updates: 'ff-only' (default), 'merge', or 'rebase'
let g:plugin_manager_pull_strategy = 'ff-only'

" Automatically commit submodule pointer changes after updates (default: 1)
let g:plugin_manager_auto_commit_on_update = 1

" Maximum number of concurrent async git jobs (default: 4)
let g:plugin_manager_max_concurrent_jobs = 4

" Timeout in seconds for a single async job (default: 60)
let g:plugin_manager_job_timeout = 60

" Update notifications (all opt-in, default off)
let g:plugin_manager_check_on_startup = 0
let g:plugin_manager_check_interval = 24
let g:plugin_manager_auto_update = 0

" Debugging and diagnostics (default off)
let g:plugin_manager_debug_mode = 0
let g:plugin_manager_trace_commands = 0
let g:plugin_manager_show_deprecation_warnings = 1
```

## Tips & Tricks

### Loading Optional Plugins

Optional plugins installed with the 'opt' parameter can be loaded with:

```vim
:packadd plugin-name
```

You can also load them conditionally in your vimrc:

```vim
if has('feature')
  packadd plugin-name
endif
```

### Using Plugin Options

The options system allows for flexible plugin installation almost like [junegunn/vim-plug](https://github.com/junegunn/vim-plug/):

```vim
" Install a plugin and specify a branch
:PluginManager add tpope/vim-fugitive {'branch': 'main'}

" Install a plugin to a specific directory and specific tag
:PluginManager add junegunn/fzf {'dir': 'myfzf', 'tag': 'v0.24.0'}

" Install a plugin and execute a command after installation
:PluginManager add junegunn/fzf {'exec': './install --all'}
```

### Managing Plugin Updates

When updating plugins, PluginManager will stash any local changes in the plugin repositories. If you've made custom modifications to plugins, consider using a different approach like git patches.

## Troubleshooting

### Issues with Plugin Installation

- Make sure your Vim configuration directory is a Git repository
- Check that you have write permissions to the plugin directories
- Verify the plugin URL is correct and accessible

### Plugin Not Loading

- For 'start' plugins, ensure they're in the correct directory
- For 'opt' plugins, make sure you're using `:packadd` to load them
- Reload your vimrc after installing new plugins

### Git-related Errors

- Most issues are related to Git submodule commands
- Run `:PluginManager status` to check the status of all modules
- Try running `:PluginManager restore` to reinitialize all modules

## Full Documentation

For detailed documentation, use the `:help plugin-manager` command after installation.

## License

PluginManager is released under the MIT License.

Copyright (c) 2018 - 2026 G.K.E. <gke@6admin.io>

## About

- Maintained by: G.K.E. <gke@6admin.io>
- Source: https://github.com/log0u7/vim-plugin-manager
- Version: 1.6.0