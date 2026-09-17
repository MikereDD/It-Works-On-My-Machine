#!/usr/bin/env bash
#--------------------------------------------
# file:    backup.sh
# author:  Mike Redd
# version: 1.0
# desc:    Backup manager. Prefers restic; falls back to rsync mirror.
#          Config via env or ~/.config/backuprc:
#            BACKUP_REPO     restic repo (e.g. /mnt/nas/restic or sftp:...)
#            BACKUP_PATHS    space-separated paths to back up
#            RESTIC_PASSWORD_FILE  file holding the repo password
#            RSYNC_DEST      destination dir for the rsync fallback
#--------------------------------------------

LIB_DIR="${LIB_DIR:-$HOME/lib}"
if [[ -f "$LIB_DIR/core.sh" ]]; then
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$LIB_DIR/core.sh")
else
    echo "Error: core.sh not found in $LIB_DIR" >&2; exit 1
fi
set +e +u 2>/dev/null || true

# Config
RC="${BACKUPRC:-$HOME/.config/backuprc}"
[[ -f "$RC" ]] && { # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$RC"); }

BACKUP_REPO="${BACKUP_REPO:-}"
BACKUP_PATHS="${BACKUP_PATHS:-$HOME/scripts $HOME/lib $HOME/.config}"
RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-$HOME/.config/restic-pass}"
RSYNC_DEST="${RSYNC_DEST:-}"
RETENTION="${RETENTION:---keep-daily 7 --keep-weekly 4 --keep-monthly 6}"

have() { command -v "$1" >/dev/null 2>&1; }
export RESTIC_REPOSITORY="$BACKUP_REPO" RESTIC_PASSWORD_FILE

show_header() {
    ui_header "BACKUP"
    if have restic; then ui_row "Engine" "restic" "$UI_GRN"
    elif have rsync;  then ui_row "Engine" "rsync (fallback)" "$UI_YLW"
    else ui_row "Engine" "none (install restic or rsync)" "$UI_RED"; fi
    ui_row "Repo"  "${BACKUP_REPO:-<unset: set BACKUP_REPO>}" "$UI_GRY"
    ui_row "Paths" "$BACKUP_PATHS" "$UI_GRY"
    echo
}

restic_repo_ok() {
    [[ -n "$BACKUP_REPO" ]] || { core_error "BACKUP_REPO is not set (see ~/.config/backuprc)"; return 1; }
    [[ -f "$RESTIC_PASSWORD_FILE" ]] || { core_error "Password file missing: $RESTIC_PASSWORD_FILE"; return 1; }
    return 0
}

do_init()     { restic_repo_ok || { pause; return; }; restic init; pause; }
do_backup() {
    if have restic; then
        restic_repo_ok || { pause; return; }
        # shellcheck disable=SC2086
        restic backup $BACKUP_PATHS && printf '  %sBackup complete.%s\n' "$UI_GRN" "$UI_R"
    elif have rsync; then
        [[ -n "$RSYNC_DEST" ]] || { core_error "RSYNC_DEST is not set"; pause; return; }
        mkdir -p -- "$RSYNC_DEST"
        # shellcheck disable=SC2086
        rsync -aAX --delete --info=progress2 $BACKUP_PATHS "$RSYNC_DEST/" \
            && printf '  %sMirror complete -> %s%s\n' "$UI_GRN" "$RSYNC_DEST" "$UI_R"
    fi
    pause
}
do_list()     { have restic && restic_repo_ok && restic snapshots; pause; }
do_prune()    { have restic && restic_repo_ok && { # shellcheck disable=SC2086
                restic forget $RETENTION --prune; }; pause; }
do_check()    { have restic && restic_repo_ok && restic check; pause; }
do_restore() {
    have restic || { core_error "Restore here supports restic only"; pause; return; }
    restic_repo_ok || { pause; return; }
    restic snapshots
    read -rp "  Snapshot ID to restore (or 'latest'): " snap
    [[ -z "$snap" ]] && { pause; return; }
    read -rp "  Restore target directory: " tgt
    [[ -z "$tgt" ]] && { core_error "Target required"; pause; return; }
    mkdir -p -- "$tgt"
    restic restore "$snap" --target "$tgt" && printf '  %sRestored to %s%s\n' "$UI_GRN" "$tgt" "$UI_R"
    pause
}

while true; do
    show_header
    ui_option "1" "Run backup"
    ui_option "2" "List snapshots"
    ui_option "3" "Init repo (first time)"
    ui_option "4" "Prune (apply retention)"
    ui_option "5" "Check repo integrity"
    ui_option "6" "Restore snapshot"
    ui_option "q" "Back"
    echo
    read -rp "Select option: " choice
    case "$choice" in
        1) do_backup ;;
        2) do_list ;;
        3) do_init ;;
        4) do_prune ;;
        5) do_check ;;
        6) do_restore ;;
        q|Q) break ;;
        *) core_error "Invalid option"; sleep 1 ;;
    esac
done
