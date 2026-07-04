# Cadence Help

Cadence is a small local music player with a dark owner-drawn interface, a real
library tree, a queue, saved playlists, album art, shuffle/repeat controls, last-session restore, queue right-click tools, safer config handling, clearer logging, and a live visualizer.

This file explains the visible buttons, right-click menus, and keyboard
shortcuts. Press `F1` or click the **Help** button in the app to open it.

## Main screen

### Album art
The square image in the upper-left shows the current track's cover art. When no
cover is found, it shows the Cadence icon as a clean placeholder.

Cadence tries cover art in this order:

1. Embedded artwork inside the audio file tag.
2. Local sidecar images near the track, such as `folder.jpg`, `cover.jpg`,
   `front.png`, `album.jpg`, or Windows Media Player `AlbumArt_*.jpg` files.
3. Cached/online lookup when online album art lookup is enabled.
4. A manually chosen image.

Right-click the album art box for album-art options:

| Option | What it does |
|--------|--------------|
| `Choose cover image for this album...` | Pick a local image and save it beside the album as the cover. |
| `Retry online art lookup` | Try the online lookup again for the current artist/album. |
| `Online album art lookup` | Toggle online lookup on or off. |

Hover the album-art box to see where the current art came from.

### Track information
The top text area shows the current track metadata:

| Line | Meaning |
|------|---------|
| Large title | Song title. Falls back to filename when tags are missing. |
| Second line | Artist. |
| Third line | Album. |

### Visualizer
The wide bar display reacts to the playing audio.

Right-click the visualizer to switch palettes:

| Palette | Description |
|---------|-------------|
| Monochrome | Default grey/white Cadence style. |
| Full spectrum | More colorful frequency bars. |
| Indigo | Blue/indigo themed bars. |

The chosen palette is saved in `cadence.config.json`.

### Seek bar and time
The horizontal bar under the visualizer is the track position.

| Control | Action |
|---------|--------|
| Drag the seek knob | Jump to another part of the current track. |
| Left time | Current playback position. |
| Right time | Total track duration. |

### Transport buttons
The center controls are the main playback buttons.

| Button | Action |
|--------|--------|
| Previous | Go to the previous queued track. |
| Play / Pause | Start playback, pause playback, or resume playback. |
| Next | Go to the next queued track. |
| Stop | Stop playback and reset the current track position. |

### Shuffle and repeat
The pill buttons under the transport controls control playback order.

| Button | Action |
|--------|--------|
| `SHUFFLE` | Toggle random track selection on or off. |
| `REPEAT OFF` | No repeat. Playback stops at the end of the queue. |
| `REPEAT ALL` | Repeat the full queue after the last track. |
| `REPEAT ONE` | Repeat the current track. |

Click the Repeat button to cycle through:

`REPEAT OFF` -> `REPEAT ALL` -> `REPEAT ONE`

Shuffle and repeat mode are saved in `cadence.config.json`.

### Volume
The slider on the right controls playback volume.

| Control | Action |
|---------|--------|
| Drag volume knob left | Lower volume. |
| Drag volume knob right | Raise volume. |
| `M` key | Mute / unmute. |

## Library tree
The library tree shows folders and audio files from your saved music roots.

| Action | Result |
|--------|--------|
| Expand a folder | Load child folders/files on demand. |
| Double-click an audio file | Play that file. |
| Double-click an `.m3u` / `.m3u8` file | Load/play the playlist. |
| Right-click a folder | Add that folder recursively to the queue. |

The Library button opens the library root menu.

| Library menu action | What it does |
|---------------------|--------------|
| Add root | Add a music folder as a top-level library root. |
| Remove selected root | Remove the selected saved root. |
| Clear roots | Remove all saved roots. |

Saved library roots are stored in `cadence.config.json`.

## Queue
The queue is the bottom list of tracks waiting to play.

| Action | Result |
|--------|--------|
| Double-click a queue item | Play that track. |
| Type in `Search queue...` | Filter the visible queue list. |
| Press `Esc` in search | Clear the search filter. |
| Right-click the queue | Open queue options. |
| Drag files/folders/playlists onto the window | Add them to the queue. |

Queue right-click options:

| Option | What it does |
|--------|--------------|
| Play selected | Play the selected queue item. |
| Remove selected from queue | Remove only the selected item. If it is currently playing, playback stops and the next nearby item is selected. |
| Open file location | Open File Explorer with the selected audio file highlighted. |
| Copy file path | Copy the selected track's full path to the clipboard. |
| Track info... | Show title, artist, album, duration, art source, file size, modified date, and full path. |
| Shuffle | Toggle shuffle on or off. |
| Repeat mode | Choose Off, All, or One. |
| Save current queue as playlist... | Save the queue as a named Cadence playlist in `cadence.playlists`. |
| Export queue as M3U file... | Save the current queue as a standalone `.m3u` / `.m3u8` playlist. |
| Clear queue | Remove all queue entries. |

The Clear button also removes all queue entries.

## Playlists

The Playlists button manages custom playlists saved by Cadence. These are normal
`.m3u8` playlist files stored in `cadence.playlists` next to the script.

| Playlist menu action | What it does |
|----------------------|--------------|
| New empty playlist | Clears the current queue so you can build a new playlist. |
| Open playlist file... | Opens an `.m3u` / `.m3u8` file and replaces the queue. |
| Save current queue as playlist... | Saves the current queue as a named playlist inside `cadence.playlists`. |
| Export queue as M3U file... | Saves the current queue to any location you choose. |
| Load saved playlist | Replaces the queue with one of your saved Cadence playlists. |
| Add saved playlist to queue | Appends one of your saved Cadence playlists to the current queue. |
| Open playlists folder | Opens `cadence.playlists` in File Explorer. |
| Restore last session on launch | Saves and restores the queue, selected track, and playback position between launches. |

Saved Cadence playlists are regular local M3U8 files, so they can still be edited
or backed up outside the app.

## Last session restore

Cadence saves the current queue, selected track, and playback position when the
window closes. The next launch restores the queue and selected track without
autoplaying. Press **Play** to resume from the saved position.

Use **Playlists -> Restore last session on launch** to turn this behavior on or
off. If restored tracks no longer exist on disk, Cadence skips them.

## Bottom buttons

| Button | What it does |
|--------|--------------|
| Add Files | Add audio files, folders, or playlists to the queue. |
| Library | Add, remove, or clear saved library roots. |
| Playlists | Save, load, append, open custom playlists, or toggle last-session restore. |
| Clear | Clear the queue. |

## Help button

The Help button near the top-right opens an app menu.

| Help menu action | What it does |
|------------------|--------------|
| Open HELP.md | Opens this help file. |
| About Cadence | Shows the app version, dependency status, and important local paths. |
| Open app folder | Opens the Cadence folder in File Explorer. |
| Open startup log | Opens or creates `cadence-startup.log`. |

The version stamp at the bottom-right shows the running Cadence build.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `Space` | Play / pause. |
| `Ctrl+Left` | Previous track. |
| `Ctrl+Right` | Next track. |
| `M` | Mute / unmute. |
| `S` | Toggle shuffle. |
| `R` | Cycle repeat mode: Off -> All -> One. |
| `Ctrl+S` | Save the current queue as a named Cadence playlist. |
| `Ctrl+O` | Open a playlist file and replace the queue. |
| `Delete` | Remove the selected queue item. |
| `Ctrl+C` | Copy the selected queue item path. |
| `F1` | Open `HELP.md`. |
| `Esc` while in search box | Clear queue search. |
| Type in search box | Filter the queue. |

## Supported input

Cadence supports local files and local playlists.

| Type | Notes |
|------|-------|
| Audio files | MP3, FLAC, M4A/AAC, WAV, WMA, OGG, OPUS, depending on available codecs. |
| Folders | Scanned recursively when added. |
| `.m3u` / `.m3u8` | Local playlist import. Remote streams are skipped. |
| Drag-and-drop | Files, folders, and playlists can be dropped onto the window. |

## Runtime files

Cadence writes a few local runtime files next to the script.

| File/folder | Purpose |
|-------------|---------|
| `cadence.config.json` | Saved roots, volume, shuffle, repeat mode, palette, online art setting, and last-session snapshot. |
| `cadence.playlists` | Saved custom playlists created from the Playlists menu. |
| `cadence.art-cache` | Cached online album covers. |
| `cadence-startup.log` | Startup errors, exception logs, playlist/config notes, and album-art lookup notes. |
| `cadence.config.bad-*.json` | Automatic backup of an unreadable/corrupt config file. |
| `cadence.config.example.json` | Example config format for the repo. |

## Troubleshooting

### Settings reset or config looks corrupt
Cadence validates `cadence.config.json` at launch. If the file is empty,
malformed, or unreadable, Cadence backs it up as `cadence.config.bad-*.json`,
uses safe defaults, and writes the reason to `cadence-startup.log`.

### The app will not start
Run the unblock command from the Cadence folder:

```powershell
Get-ChildItem . -Recurse -Include *.ps1,*.dll | Unblock-File
.\cadence.ps1
```

Cadence expects Windows PowerShell 5.1 for the WinForms STA launch path.

### No album art appears
If no cover art is found, Cadence shows the Cadence icon placeholder instead of
a blank square. To add a real cover, try these in order:

1. Right-click the album-art box and choose `Retry online art lookup`.
2. Put a `folder.jpg` or `cover.jpg` inside the album folder.
3. Right-click the album-art box and choose `Choose cover image for this album...`.
4. Check `cadence-startup.log` for album-art lookup messages.

### The wrong track plays while search is active
Queue search uses an internal view-to-model map so the visible filtered row should
still play the correct file. If it does not, clear the search box and try again.

### Visualizer does not move
Playback should still work even if the visualizer tap fails. Check
`cadence-startup.log` for startup or compiler errors.
