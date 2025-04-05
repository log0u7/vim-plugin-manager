# Vim Plugin Manager

A lightweight Vim/Neovim plugin manager that uses Git submodules and Vim 8's native package system.

## Features

- Manage plugins through Git submodules
- Easy installation, removal, and updating of plugins
- Automatic generation of helptags
- Backup your entire Vim configuration to multiple remote repositories
- Works with Vim 8's native package loading system
- Full Git integration for plugin versioning
- Support for optional (lazy-loaded) plugins
- Interactive sidebar interface
- Compatible with both Vim and Neovim

## Requirements

- Vim 8.0+ or Neovim
- Git 2.40 or higher

## Installation

### Starting from scratch

If you're starting a new Vim configuration:

```bash
# Create and initialize your Vim configuration repository
cd ~
git init .vim

# Create the necessary directories
mkdir -p ~/.vim/pack/plugins/{start,opt}
```

### If you already have a Vim configuration

If you already have a .vim directory that's a Git repository:

```bash
cd ~/.vim
```

### Installing the plugin manager

Add the plugin manager as a submodule:

```bash
git submodule add https://github.com/yourusername/vim-plugin-manager.git ~/.vim/pack/plugins/start/vim-plugin-manager
```

### Generate helptags
```bash
vim -c "helptags ~/.vim/pack/plugins/start/vim-plugin-manager/doc" -c q
```

Or after opening vim :
```vim
:helptags ~/.vim/pack/plugins/start/vim-plugin-manager/doc
```

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
" Commit any changes to vimrc and new plugins added, then push to all remotes
:PluginManager backup

" Reinstall all plugins from .gitmodules
:PluginManager restore

" Add a new backup repository
:PluginManagerRemote https://github.com/yourusername/vim-config-backup.git
```

### Interactive Interface

```vim
" Toggle the plugin manager sidebar
:PluginManagerToggle
```

#### Sidebar Keyboard Shortcuts

- `q` - Close the sidebar
- `l` - List installed plugins
- `u` - Update all plugins
- `h` - Generate helptags for all plugins
- `s` - Show status of submodules
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
" Custom Vim/Neovim configuration directory
let g:plugin_manager_vim_dir = '~/.vim'  " or '~/.config/nvim' for Neovim

" Custom plugin directory
let g:plugin_manager_plugins_dir = '~/.vim/pack/plugins'

" Custom directory for auto-loaded plugins
let g:plugin_manager_start_dir = 'start'

" Custom directory for optional (lazy-loaded) plugins
let g:plugin_manager_opt_dir = 'opt'

" Custom vimrc location
let g:plugin_manager_vimrc_path = '~/.vim/vimrc'  " or '~/.config/nvim/init.vim'

" Custom sidebar width
let g:plugin_manager_sidebar_width = 60

" Default git host for short plugin names
let g:plugin_manager_default_git_host = 'github.com'
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

Copyright (c) 2018 - 2025 G.K.E. <gke@6admin.io>

## About

- Maintained by: G.K.E. <gke@6admin.io>
- Source: https://github.com/username/vim-plugin-manager
- Version: 1.2