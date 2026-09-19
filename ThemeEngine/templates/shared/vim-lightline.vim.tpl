" Typezero ThemeEngine - generated Lightline colorscheme
"
" This file is rendered from ThemeEngine's semantic palette. Mode colors map
" to semantic roles so Lightline follows the active ThemeEngine theme without
" depending on a third-party Vim colorscheme for its palette.

let s:bg        = ['{{BG}}', 0]
let s:surface   = ['{{SURFACE}}', 0]
let s:surface2  = ['{{SURFACE_ALT}}', 8]
let s:text      = ['{{TEXT}}', 7]
let s:muted     = ['{{MUTED}}', 8]
let s:accent    = ['{{ACCENT}}', 6]
let s:info      = ['{{INFO}}', 4]
let s:success   = ['{{SUCCESS}}', 2]
let s:warning   = ['{{WARNING}}', 3]
let s:error     = ['{{ERROR}}', 1]
let s:secondary = ['{{SECONDARY}}', 5]

let s:p = {
    \ 'normal':   {},
    \ 'inactive': {},
    \ 'insert':   {},
    \ 'replace':  {},
    \ 'visual':   {},
    \ 'terminal': {},
    \ 'tabline':  {}
    \ }

let s:p.normal.left    = [[s:bg, s:accent, 'bold'], [s:text, s:surface2]]
let s:p.normal.middle  = [[s:muted, s:surface]]
let s:p.normal.right   = [[s:text, s:surface2], [s:bg, s:accent]]
let s:p.normal.error   = [[s:bg, s:error]]
let s:p.normal.warning = [[s:bg, s:warning]]

let s:p.inactive.left   = [[s:muted, s:surface], [s:muted, s:surface]]
let s:p.inactive.middle = [[s:muted, s:surface]]
let s:p.inactive.right  = [[s:muted, s:surface], [s:muted, s:surface]]

let s:p.insert.left   = [[s:bg, s:info, 'bold'], [s:text, s:surface2]]
let s:p.replace.left  = [[s:bg, s:warning, 'bold'], [s:text, s:surface2]]
let s:p.visual.left   = [[s:bg, s:secondary, 'bold'], [s:text, s:surface2]]
let s:p.terminal.left = [[s:bg, s:success, 'bold'], [s:text, s:surface2]]

let s:p.tabline.left   = [[s:text, s:surface2]]
let s:p.tabline.middle = [[s:muted, s:surface]]
let s:p.tabline.right  = [[s:text, s:surface2]]
let s:p.tabline.tabsel = [[s:bg, s:accent, 'bold']]

let g:lightline#colorscheme#typezero#palette =
    \ lightline#colorscheme#flatten(s:p)
