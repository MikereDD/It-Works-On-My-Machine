# Vim Cheatsheet — Arakiel (Pi 5 / Arch)

**Leader = `,`**  ·  **LocalLeader = `\`**
So `,w` means *press comma, then w*.

---

## ALE — Lint & Fix
| Key | Action |
|-----|--------|
| `[a` / `]a` | Prev / next warning |
| `[e` / `]e` | Prev / next error |
| `,af` | Fix (ALEFix) |
| `,at` | Toggle ALE |
| `,ad` | Show detail |

## Search in Files — CtrlSF
| Key | Action |
|-----|--------|
| `,s` (normal) | Open CtrlSF prompt |
| `,s` (visual) | Search selected word |

## Fuzzy Find — FZF
| Key | Action |
|-----|--------|
| `,ff` | Files |
| `,fg` | Ripgrep content (Rg) |
| `,fb` | Buffers |
| `,fh` | File history |
| `,fl` | Lines (all buffers) |
| `,f/` | Lines (current buffer) |
| `,fc` | Commits |
| `,fm` | Key mappings |
| `,fH` | Help tags |

## Git — Fugitive / rhubarb
| Key | Action |
|-----|--------|
| `,gs` | Status |
| `,gd` | Diff split |
| `,gb` | Blame |
| `,gl` | Log |
| `,gw` | Stage file (Gwrite) |
| `,gc` | Commit |
| `,gp` | Push |
| `,gP` | Pull |
| `,gf` | Fetch |
| `,gB` | Open on GitHub (GBrowse) |

## Git Hunks — GitGutter
| Key | Action |
|-----|--------|
| `]h` / `[h` | Next / prev hunk |
| `,gh` | Toggle line highlights |
| `,ghp` | Preview hunk |
| `,gu` | Undo hunk |

## Jumps — EasyMotion
| Key | Action |
|-----|--------|
| `s` | 2-char search jump |
| `S` | 2-char jump across windows |
| `,j` / `,k` | Jump down / up |

> Note: `s` / `S` here replace vim-surround's `s`/`S`. Surround's `cs` `ds` `ys` still work.

## Word Motion
| Key | Action |
|-----|--------|
| `,,w` `,,b` `,,e` | Sub-word motions (camelCase / snake_case aware) |

## File Tree — NERDTree
| Key | Action |
|-----|--------|
| `,n` | Toggle tree |
| `,nf` | Reveal current file |

## Tags / Symbols — Tagbar
| Key | Action |
|-----|--------|
| `,t` | Toggle Tagbar |

## Marks — vim-signature (prefix `m`)
| Key | Action |
|-----|--------|
| `ma`…`mz` | Set named mark (built-in) |
| `m,` | Place next available mark |
| `m.` | Toggle mark at line |
| `m-` | Purge marks at line |
| `dm` | Delete a mark |
| `m/` | List buffer marks |
| `m?` | List global marks |

## Undo / Sessions / Build
| Key | Action |
|-----|--------|
| `,u` | Undotree toggle |
| `,os` | Start session (Obsession) |
| `,oo` | Load a session |
| `,m` | Build (`:Make`) |
| `,d` | Dispatch prompt |

---

## Movement (remapped)
| Key | Action |
|-----|--------|
| `j` / `k` | Move by *display* line (wrap-aware) |
| `H` | First non-blank of line |
| `L` | End of line |
| `n` / `N` | Next / prev match, re-centered |
| `g.` | Jump to last edit |
| `g,` | Jump to last insert |
| `gV` | Reselect last inserted/pasted text |

## Splits
| Key | Action |
|-----|--------|
| `Ctrl-Left` / `Ctrl-Right` | Shrink / grow width |
| `Ctrl-Up` / `Ctrl-Down` | Grow / shrink height |
| `,z` | Zoom (close other windows) |

## Editing
| Key | Action |
|-----|--------|
| `Y` | Yank to end of line |
| `<` / `>` (visual) | Indent, keep selection |
| `=` (visual) | Reindent, keep selection |
| `,=` | Reindent whole file (cursor kept) |
| `,W` | Strip trailing whitespace |
| `,p` | Toggle paste mode |
| `,i` | Toggle invisible chars |
| `Q` (normal) | Replay macro `@q` |
| `Q` (visual) | Run macro `@q` on each line |

## Files / Buffers / Quit
| Key | Action |
|-----|--------|
| `,w` | Save if changed (update) |
| `,q` | Quit |
| `,Q` | Delete buffer (keep split) |
| `,bq` | Delete current buffer, keep window |
| `,/` | Clear search highlight |
| `,D` | Diff off + nowrap |
| `,ev` | Edit vimrc |
| `,sv` | Source vimrc |
| `,nu` | Cycle line-number modes |
| `:w!!` | Sudo-save (command line) |

---

## Typo-proof commands
`:W` `:Wq` `:WQ` `:Q` `:Qa` `:QA` all work like their lowercase versions.

## Caveats
- `Ctrl-arrow` split resizing needs a terminal that sends those keys (URxvt/Alacritty do; tmux may need passthrough).
- `s`/`S` are EasyMotion, not surround (see note above).
- Built-in named marks (`ma` then `` `a ``) still work alongside Signature.
