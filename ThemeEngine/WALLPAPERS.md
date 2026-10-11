# Typezero ThemeEngine - Wallpaper Collections

A collection of 33 wallpapers designed for the 11 Typezero ThemeEngine color palettes.

Each theme contains three coordinated wallpapers for a triple-monitor setup.

## Collections

| Theme ID | Artwork |
| --- | --- |
| nord | Arctic landscapes |
| gruvbox | Warm pixel-art landscapes |
| papercolor | Origami aerial dogfights |
| obsidian-silver | Black-and-silver science fiction |
| catppuccin-mocha | Impressionistic cafe scenes |
| dustys-pink-af | 1980s tropical action scenes |
| everforest-dark | Enchanted elven village |
| kanagawa-paper | Edo-period Japanese woodblock scenes |
| molokai | Molokai-inspired Hawaiian island landscapes |
| oceanic-next | Abyssal underwater observatory |
| onedark | The Last Library |

## Monitor Layout

| File | Resolution | Aspect ratio |
| --- | --- | --- |
| left.png | 2560 x 1600 | 16:10 |
| center.png | 2560 x 1440 | 16:9 |
| right.png | 2560 x 1440 | 16:9 |

## Release Archive

The wallpapers are distributed separately from the Git source as a release ZIP.

Archive structure:

    manifest.json
    wallpapers/
        nord/
            left.png
            center.png
            right.png
        ...one folder per theme...

The manifest records each image's theme, path, dimensions, and SHA-256 checksum.

All 33 images have passed SHA-256 verification against the release manifest.

## Windows Installation

1. Download the wallpaper archive from the published release.
2. Verify its SHA-256 checksum.
3. Extract the archive into a directory of your choice.
4. Open DisplayFusion wallpaper settings.
5. Select a different image for each monitor.
6. Assign left.png, center.png, and right.png.
7. Save and apply the DisplayFusion wallpaper profile.

The images already have native monitor resolutions.

## Optional ThemeEngine Integration

ThemeEngine on Netzach supports mappings to saved DisplayFusion profiles.

For example, map the OneDark theme to a profile named Typezero-OneDark:

    themeengine wallpaper map onedark "Typezero-OneDark"
    themeengine wallpaper test onedark

The DisplayFusion profile must exist before mapping it.

Automatic wallpaper switching is optional and disabled by default.

## Privacy

The release archive contains approved wallpapers and their integrity manifest only.

No personal DisplayFusion configurations, machine-specific paths, credentials, secrets, or local backups are included.

## Artwork Terms

The approved Typezero wallpaper collection is distributed for personal,
non-commercial use.

You may download, display, and resize these wallpapers for personal use
on devices you own or personally use.

This permission does not authorize commercial exploitation, resale,
repackaging, rehosting, or public redistribution where permission from
a rights holder is legally required.

The artwork was created with AI image-generation assistance and human
creative direction. Copyright protection for AI-generated material may
vary by jurisdiction and by the degree of human authorship. These terms
do not assert exclusive rights in material that is ineligible for
copyright protection, nor do they restrict uses permitted by law.

These artwork terms do not modify the licenses of ThemeEngine software,
third-party color schemes, or other separately licensed materials.

The wallpapers are provided as-is, without warranty.
