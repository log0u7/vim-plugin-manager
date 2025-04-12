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
- Asynchronous operations for better performance

## Requirements

- Vim 8.0+ or Neovim
- Git 2.40 or higher

## Installation

### Prerequisites

- Vim 8.0+ or Neovim
- Git 2.40 or higher

### Simple Installation

1. **Initialize your Vim configuration as a Git repository** (if not already done):

```bash
# If you don't already have a Git repository for your Vim configuration
cd ~/.vim     # For Vim (or ~/.config/nvim for Neovim)
git init
```

2. **Add the plugin manager as a submodule**:

```bash
# Add the plugin as a submodule directly to the appropriate location
git submodule add https://github.com/yourusername/vim-plugin-manager.git ~/.vim/pack/plugins/start/vim-plugin-manager
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
1. Copy your main configuration file (`.vimrc` or `init.vim`) into your `.vim` directory to ensure it's versioned along with everything else
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
- Version: 1.3.5