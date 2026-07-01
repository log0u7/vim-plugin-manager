" syntax/pluginmanager.vim - Syntax highlighting for the PluginManager sidebar
" Maintainer: G.K.E. <gke@6admin.io>
" Version: 2.0.0

if exists("b:current_syntax")
  finish
endif

syntax clear

" ------------------------------------------------------------------------------
" HEADERS
" ------------------------------------------------------------------------------

" Section titles: lines ending with a colon (e.g. "Plugin status:")
syntax match PMHeader /^[A-Za-z0-9 ]\+:$/

" Separator line produced by s:symbols.separator (━ repeated or - repeated)
syntax match PMSeparator /^[━─\-]\+$/

" ------------------------------------------------------------------------------
" PLUGIN STATUS LINES
" The format is: <glyph> name......... status text
" Glyphs: ✓ ✗ ⚠ ℹ ○ → (or ASCII fallbacks + - ! i o >)
" ------------------------------------------------------------------------------

" Success / ok glyph at start of line (✓ or +)
syntax match PMSymbolOk    /^[✓+] / contains=NONE
" Failure glyph (✗ or x)
syntax match PMSymbolFail  /^[✗x] / contains=NONE
" Warning glyph (⚠ or !)
syntax match PMSymbolWarn  /^[⚠!] / contains=NONE
" Info glyph (ℹ or i)
syntax match PMSymbolInfo  /^[ℹi] / contains=NONE
" Pending / spinner characters at start of line
syntax match PMSpinner     /^[○o⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏⣾⣽⣻⢿⡿⣟⣯⣷◐◓◑◒◢◣◤◥▌▀▐▄|\/\\\-] / contains=NONE
" Arrow glyph (→ or ->)
syntax match PMSymbolArrow /^[→>][-> ] / contains=NONE
" Bullet glyph (• or *)
syntax match PMSymbolBullet /^\s*[•*] / contains=NONE

" Status text keywords that appear after the dots
syntax match PMStatusOk       /Up-to-date\|Installed\|Initialized\|Restored\|Synced\|Updated\|Committed\|Pushed\|Copied\|Reloaded\|Helptags generated\|Added/
syntax match PMStatusSkip     /On custom branch\|Already exists\|No changes\|No doc directory\|Skipped/
syntax match PMStatusWarn     /\<Missing\>\|commits behind\|No remotes\|Source not found\|timed out/
syntax match PMStatusFail     /\<Failed\>\|Update failed\|Push failed\|Commit failed\|Exec failed\|Installation failed\|Invalid URL format/
syntax match PMStatusProgress /Installing\|Removing\|Updating\|Checking\|Fetching updates\|Stashing changes\|Pulling changes\|Analyzing\|Generating helptags\|Backing up\|Committing\|Pushing\|Pending\|Reloading\|Processing\|Adding/

" Dots separating name from status (the padding in format_plugin_line)
syntax match PMDots /\.\{2,}/

" ------------------------------------------------------------------------------
" FOOTER SUMMARY LINES (lines starting with ✓/+/ℹ/i/✗/x/⚠/!)
" These are produced by ui#success(), ui#info(), ui#error(), ui#warning()
" ------------------------------------------------------------------------------

syntax match PMFooterOk   /^[✓+] .\+$/
syntax match PMFooterInfo /^[ℹi] .\+$/
syntax match PMFooterWarn /^[⚠!] .\+$/
syntax match PMFooterFail /^[✗x] .\+$/

" ------------------------------------------------------------------------------
" NOTIFICATIONS (show_update_notification output)
" ------------------------------------------------------------------------------

syntax match PMNotifTitle /^Update notification:$/
syntax match PMNotifCount /\d\+ plugin\(s\)\? ha\(ve\|s\) updates available/

" ------------------------------------------------------------------------------
" COMMANDS (usage block)
" ------------------------------------------------------------------------------

syntax match PMCommand /^\(PluginManager\|PluginManagerRemote\|PluginManagerToggle\|PluginBegin\|Plugin\|PluginEnd\)/
syntax match PMUsageCmd /^[a-z][a-z-]\+\s\+/

" ------------------------------------------------------------------------------
" PATHS AND URLs
" ------------------------------------------------------------------------------

syntax match PMUrl  /https\?:\/\/\S\+/
syntax match PMPath /\(pack\/plugins\/\(start\|opt\)\/\|~\/\|\.\.\?\/\)[[:alnum:]_\-\.\/]\+/

" ------------------------------------------------------------------------------
" HIGHLIGHT LINKS
" ------------------------------------------------------------------------------

highlight default link PMHeader        Title
highlight default link PMSeparator     Comment

highlight default link PMSymbolOk      String
highlight default link PMSymbolFail    Error
highlight default link PMSymbolWarn    Todo
highlight default link PMSymbolInfo    Identifier
highlight default link PMSymbolArrow   Statement
highlight default link PMSymbolBullet  Identifier
highlight default link PMSpinner       Type

highlight default link PMStatusOk      String
highlight default link PMStatusSkip    Comment
highlight default link PMStatusWarn    Todo
highlight default link PMStatusFail    Error
highlight default link PMStatusProgress Type

highlight default link PMDots          NonText

highlight default link PMFooterOk      String
highlight default link PMFooterInfo    Identifier
highlight default link PMFooterWarn    Todo
highlight default link PMFooterFail    Error

highlight default link PMNotifTitle    Title
highlight default link PMNotifCount    WarningMsg

highlight default link PMCommand       Function
highlight default link PMUsageCmd      Identifier

highlight default link PMUrl           Underlined
highlight default link PMPath          Directory

let b:current_syntax = "pluginmanager"
