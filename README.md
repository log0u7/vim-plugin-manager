# Vim Plugin Manager

A lightweight Vim plugin manager that uses Git submodules and Vim 8's native package system.

## Features

- Manage plugins through Git submodules
- Easy installation, removal, and updating of plugins
- Automatic generation of helptags
- Backup your entire Vim configuration to multiple remote repositories
- Works with Vim 8's native package loading system

## Requirements

- Vim 8.0 or higher
- Git 2.40 or higher

## Installation

1. Clone your Vim configuration repository (or create a new one):

```bash
# If you already have a .vim Git repository:
cd ~/.vim

# If you're starting from scratch:
cd ~
git init .vim
```

2. Install the plugin manager:

```bash
git submodule add https://github.com/yourusername/vim-plugin-manager.git ~/.vim/pack/plugins/start/vim-plugin-manager
```


3. Generate helptags

```vim
:helptags ~/.vim/pack/plugins/start/vim-plugin-manager/doc
```

## Usage

### Installing Plugins

```vim
" Install a plugin to start/ directory (auto-loaded)
:PluginManager add https://github.com/tpope/vim-fugitive.git

" Install with a custom name
:PluginManager add https://github.com/tpope/vim-surround.git surround

" Install as an optional plugin (need to :packadd to use)
:PluginManager add https://github.com/tpope/vim-commentary.git commentary opt
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

" Show a summary of all plugin changes
:PluginManager summary

" Generate helptags for all plugins
:PluginManager helptags
```

### Backup Your Configuration

Backups are based on git submodule see: myvim
```bash
cd ~/.vim
git remote rename origin genesis
git remote add origin your_repository_url

# Optional: Add backup repositories
git remote set-url origin --add --push second_repository_url
git remote set-url origin --add --push third_repository_url
``` 

```vim
" Commit any changes to vimrc and new plugins added, then push to all remotes
:PluginManager backup

" Add a new backup repository
:PluginManagerRemote https://github.com/yourusername/vim-config-backup.git
```

## Configuration

You can customize the plugin manager by setting the following variables in your vimrc:

```vim
" Custom plugin directory
let g:plugin_manager_plugins_dir = "pack/bundle"

" Custom vimrc location
let g:plugin_manager_vimrc_path = "~/.vim/config/main.vim"
```

## Full Documentation

For detailed documentation, use the `:help plugin-manager` command after installation.
