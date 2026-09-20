" Typezero ThemeEngine - generated Vim colorscheme
"
" This file is rendered from ThemeEngine's semantic palette. Do not put
" theme-specific colors here: individual themes own those values in theme.conf.
"
" The colorscheme intentionally uses GUI/true-color values so the same semantic
" palette is available to Vim on both Arakiel and Netzach. cterm fallbacks use
" standard terminal roles for environments where true color is unavailable.

highlight clear

if exists('syntax_on')
    syntax reset
endif

let g:colors_name = 'typezero'
set background=dark

" Core editor surfaces
highlight Normal       guifg={{TEXT}}          guibg={{BG}}          ctermfg=White      ctermbg=Black
highlight NormalNC     guifg={{MUTED}}         guibg={{BG}}          ctermfg=DarkGray   ctermbg=Black
highlight Cursor       guifg={{BG}}            guibg={{CURSOR}} ctermfg=Black    ctermbg=White
highlight CursorLine   guibg={{SURFACE}}                              ctermbg=DarkGray
highlight CursorColumn guibg={{SURFACE}}                              ctermbg=DarkGray
highlight ColorColumn  guibg={{SURFACE_ALT}}                          ctermbg=DarkGray
highlight LineNr       guifg={{MUTED}}         guibg={{BG}}          ctermfg=DarkGray   ctermbg=Black
highlight CursorLineNr guifg={{ACCENT_BRIGHT}} guibg={{SURFACE}} gui=bold ctermfg=Yellow cterm=bold
highlight SignColumn   guifg={{MUTED}}         guibg={{BG}}          ctermfg=DarkGray   ctermbg=Black
highlight VertSplit    guifg={{BORDER}}        guibg={{BG}}          ctermfg=DarkGray   ctermbg=Black
highlight WinSeparator guifg={{BORDER}}        guibg={{BG}}          ctermfg=DarkGray   ctermbg=Black

" Selection, search, and navigation
highlight Visual       guifg={{BRIGHT}}        guibg={{SELECTION}}      ctermfg=White      ctermbg=DarkGray
highlight Search       guifg={{BG}}            guibg={{WARNING}}     ctermfg=Black      ctermbg=Yellow
highlight IncSearch    guifg={{BG}}            guibg={{ACCENT_BRIGHT}} ctermfg=Black    ctermbg=Yellow
highlight MatchParen   guifg={{BRIGHT}}        guibg={{BORDER}} gui=bold ctermfg=White ctermbg=DarkGray cterm=bold
highlight Directory    guifg={{INFO}}                                 ctermfg=Blue

" Interface chrome
highlight StatusLine   guifg={{BG}}            guibg={{FOCUS}} gui=bold ctermfg=Black ctermbg=Yellow cterm=bold
highlight StatusLineNC guifg={{MUTED}}         guibg={{SURFACE_ALT}} ctermfg=DarkGray ctermbg=Black
highlight TabLine      guifg={{MUTED}}         guibg={{SURFACE}}     ctermfg=DarkGray ctermbg=Black
highlight TabLineSel   guifg={{BG}}            guibg={{FOCUS}} gui=bold ctermfg=Black ctermbg=Yellow cterm=bold
highlight TabLineFill  guibg={{SURFACE}}                              ctermbg=Black
highlight Pmenu        guifg={{TEXT}}          guibg={{SURFACE_ALT}} ctermfg=White ctermbg=DarkGray
highlight PmenuSel     guifg={{BG}}            guibg={{ACCENT}} gui=bold ctermfg=Black ctermbg=Yellow cterm=bold
highlight WildMenu     guifg={{BG}}            guibg={{ACCENT_BRIGHT}} ctermfg=Black ctermbg=Yellow

" Messages and diagnostics
highlight Error        guifg={{ERROR}}         guibg={{BG}} gui=bold ctermfg=Red cterm=bold
highlight ErrorMsg     guifg={{ERROR}}         guibg={{BG}} gui=bold ctermfg=Red cterm=bold
highlight WarningMsg   guifg={{WARNING}}                              ctermfg=Yellow
highlight MoreMsg      guifg={{SUCCESS}}                              ctermfg=Green
highlight Question     guifg={{SUCCESS}}                              ctermfg=Green
highlight Title        guifg={{ACCENT_BRIGHT}} gui=bold               ctermfg=Yellow cterm=bold

" Syntax roles
highlight Comment      guifg={{MUTED}} gui=italic                     ctermfg=DarkGray
highlight Constant     guifg={{SECONDARY}}                            ctermfg=Magenta
highlight String       guifg={{SUCCESS}}                              ctermfg=Green
highlight Character    guifg={{SUCCESS}}                              ctermfg=Green
highlight Number       guifg={{SECONDARY}}                            ctermfg=Magenta
highlight Boolean      guifg={{SECONDARY}} gui=bold                   ctermfg=Magenta cterm=bold
highlight Float        guifg={{SECONDARY}}                            ctermfg=Magenta

highlight Identifier   guifg={{INFO}}                                 ctermfg=Blue
highlight Function     guifg={{ACCENT_BRIGHT}}                        ctermfg=Yellow

highlight Statement    guifg={{ACCENT}} gui=bold                      ctermfg=Yellow cterm=bold
highlight Conditional  guifg={{ACCENT}} gui=bold                      ctermfg=Yellow cterm=bold
highlight Repeat       guifg={{ACCENT}} gui=bold                      ctermfg=Yellow cterm=bold
highlight Label        guifg={{ACCENT}}                               ctermfg=Yellow
highlight Operator     guifg={{TEXT}}                                 ctermfg=White
highlight Keyword      guifg={{ACCENT}} gui=bold                      ctermfg=Yellow cterm=bold
highlight Exception    guifg={{ERROR}} gui=bold                       ctermfg=Red cterm=bold

highlight PreProc      guifg={{INFO}}                                 ctermfg=Blue
highlight Include      guifg={{INFO}}                                 ctermfg=Blue
highlight Define       guifg={{INFO}}                                 ctermfg=Blue
highlight Macro        guifg={{INFO}}                                 ctermfg=Blue
highlight PreCondit    guifg={{INFO}}                                 ctermfg=Blue

highlight Type         guifg={{WARNING}}                              ctermfg=Yellow
highlight StorageClass guifg={{WARNING}}                              ctermfg=Yellow
highlight Structure    guifg={{WARNING}}                              ctermfg=Yellow
highlight Typedef      guifg={{WARNING}}                              ctermfg=Yellow

highlight Special      guifg={{SECONDARY}}                            ctermfg=Magenta
highlight SpecialChar  guifg={{SECONDARY}}                            ctermfg=Magenta
highlight Tag          guifg={{ACCENT_BRIGHT}}                        ctermfg=Yellow
highlight Delimiter    guifg={{TEXT}}                                 ctermfg=White
highlight SpecialComment guifg={{MUTED}} gui=italic                  ctermfg=DarkGray
highlight Debug        guifg={{ERROR}}                                ctermfg=Red

highlight Underlined   guifg={{INFO}} gui=underline                  ctermfg=Blue cterm=underline
highlight Ignore       guifg={{MUTED}}                               ctermfg=DarkGray
highlight Todo         guifg={{BG}} guibg={{WARNING}} gui=bold       ctermfg=Black ctermbg=Yellow cterm=bold

" Diff and version-control roles use ThemeEngine semantic colors rather than
" introducing colors that could conflict with the active Typezero palette.
highlight DiffAdd      guifg={{SUCCESS}} guibg={{SURFACE}}           ctermfg=Green
highlight DiffChange   guifg={{INFO}}    guibg={{SURFACE}}           ctermfg=Blue
highlight DiffDelete   guifg={{ERROR}}   guibg={{SURFACE}}           ctermfg=Red
highlight DiffText     guifg={{BRIGHT}}  guibg={{BORDER}} gui=bold   ctermfg=White cterm=bold
