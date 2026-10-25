#!/usr/bin/env bash
#--------------------------------------------
# file:    pkg-backup.sh
# author:  Mike Redd
# version: 1.0
# desc:    Back up the list of installed packages (native + AUR) for
#          disaster recovery, and show how to restore them.
#--------------------------------------------

LIB_DIR="${LIB_DIR:-$HOME/lib}"
if [[ -f "$LIB_DIR/core.sh" ]]; then
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$LIB_DIR/core.sh")
else
    echo "Error: core.sh not found in $LIB_DIR" >&2; exit 1
fi
set +e +u 2>/dev/null || true

OUT_DIR="${PKG_BACKUP_DIR:-$HOME/backups/pkglists}"

have() { command -v "$1" >/dev/null 2>&1; }

ui_header "PACKAGE LIST BACKUP"

if ! have pacman; then
    ui_row "pacman" "not found" "$UI_RED"
    printf '  %sThis tool is for Arch-based systems.%s\n' "$UI_DIM" "$UI_R"
    echo; pause; exit 0
fi

mkdir -p -- "$OUT_DIR"
stamp="$(date +%Y%m%d_%H%M%S)"
native="$OUT_DIR/pkglist-native-$stamp.txt"
foreign="$OUT_DIR/pkglist-aur-$stamp.txt"

# Explicitly-installed native packages
pacman -Qqen > "$native" 2>/dev/null
# Foreign (AUR / non-repo) packages
pacman -Qqem > "$foreign" 2>/dev/null

ui_row "Native pkgs" "$(wc -l < "$native") -> $(basename "$native")" "$UI_GRN"
ui_row "AUR pkgs"    "$(wc -l < "$foreign") -> $(basename "$foreign")" "$UI_GRN"
ui_row "Saved in"    "$OUT_DIR" "$UI_GRY"

# Refresh stable "latest" symlinks/copies for easy scripting
cp -f "$native"  "$OUT_DIR/pkglist-native-latest.txt"  2>/dev/null
cp -f "$foreign" "$OUT_DIR/pkglist-aur-latest.txt"      2>/dev/null

ui_section "Restore on a fresh install"
printf '  Native:\n'
printf '    %ssudo pacman -S --needed - < pkglist-native-latest.txt%s\n' "$UI_DIM" "$UI_R"
printf '  AUR (with paru/yay):\n'
printf '    %sparu -S --needed - < pkglist-aur-latest.txt%s\n' "$UI_DIM" "$UI_R"

echo
pause
