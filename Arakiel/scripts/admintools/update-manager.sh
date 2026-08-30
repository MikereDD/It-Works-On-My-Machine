#!/usr/bin/env bash
#--------------------------------------------
# file:    update-manager.sh
# author:  Mike Redd
# version: 1.0
# desc:    Arch Linux update manager: check/apply pacman + AUR updates,
#          remove orphans, clean the package cache, and flag when a
#          reboot is needed (kernel/firmware changed).
#--------------------------------------------

LIB_DIR="${LIB_DIR:-$HOME/lib}"
if [[ -f "$LIB_DIR/core.sh" ]]; then
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$LIB_DIR/core.sh")
else
    echo "Error: core.sh not found in $LIB_DIR" >&2; exit 1
fi
set +e +u 2>/dev/null || true

have() { command -v "$1" >/dev/null 2>&1; }
AUR=""
for h in paru yay; do have "$h" && { AUR="$h"; break; }; done

# sudo prefix unless already root
SUDO=""
[[ "${EUID:-$(id -u)}" -ne 0 ]] && SUDO="sudo"

show_header() {
    ui_header "UPDATE MANAGER (Arch)"
    ui_row "AUR helper" "${AUR:-none}" "$UI_GRY"
    echo
}

check_updates() {
    show_header
    if ! have pacman; then core_error "pacman not found — this tool is for Arch."; pause; return; fi

    ui_section "Official repos"
    if have checkupdates; then
        local out; out="$(checkupdates 2>/dev/null)"
        if [[ -n "$out" ]]; then
            printf '%s\n' "$out" | sed 's/^/  /'
            printf '  %s%d package(s) to update%s\n' "$UI_YLW" "$(printf '%s\n' "$out" | wc -l)" "$UI_R"
        else
            printf '  %sUp to date.%s\n' "$UI_GRN" "$UI_R"
        fi
    else
        printf '  %scheckupdates not found (install pacman-contrib).%s\n' "$UI_DIM" "$UI_R"
    fi

    if [[ -n "$AUR" ]]; then
        ui_section "AUR"
        "$AUR" -Qua 2>/dev/null | sed 's/^/  /' || printf '  %sUp to date.%s\n' "$UI_GRN" "$UI_R"
    fi
    echo; pause
}

apply_updates() {
    show_header
    have pacman || { core_error "pacman not found"; pause; return; }
    printf '  %sUpdating official packages...%s\n' "$UI_CYN" "$UI_R"
    $SUDO pacman -Syu
    if [[ -n "$AUR" ]]; then
        printf '  %sUpdating AUR packages...%s\n' "$UI_CYN" "$UI_R"
        "$AUR" -Sua
    fi
    check_reboot
    pause
}

remove_orphans() {
    show_header
    local orphans; orphans="$(pacman -Qtdq 2>/dev/null)"
    if [[ -z "$orphans" ]]; then
        printf '  %sNo orphaned packages.%s\n' "$UI_GRN" "$UI_R"
    else
        printf '  Orphans:\n'; printf '%s\n' "$orphans" | sed 's/^/    /'
        read -rp "  Remove these? (y/N): " ok
        # shellcheck disable=SC2086
        [[ "${ok,,}" == "y" ]] && $SUDO pacman -Rns $orphans
    fi
    pause
}

clean_cache() {
    show_header
    if have paccache; then
        printf '  Keeping the last 2 versions of each package...\n'
        $SUDO paccache -rk2
        printf '  Removing cached versions of uninstalled packages...\n'
        $SUDO paccache -ruk0
    else
        printf '  %spaccache not found (install pacman-contrib).%s\n' "$UI_DIM" "$UI_R"
        read -rp "  Run 'pacman -Sc' instead? (y/N): " ok
        [[ "${ok,,}" == "y" ]] && $SUDO pacman -Sc
    fi
    pause
}

check_reboot() {
    ui_section "Reboot check"
    local running newest
    running="$(uname -r)"
    # newest installed kernel image version (best-effort)
    newest="$(pacman -Q linux 2>/dev/null | awk '{print $2}')"
    ui_row "Running kernel" "$running" "$UI_GRY"
    [[ -n "$newest" ]] && ui_row "Installed linux" "$newest" "$UI_GRY"
    if [[ -n "$newest" && "$running" != *"$(echo "$newest" | cut -d- -f1)"* ]]; then
        printf '  %sKernel changed — a reboot is recommended.%s\n' "$UI_YLW" "$UI_R"
    else
        printf '  %sNo reboot indicated.%s\n' "$UI_GRN" "$UI_R"
    fi
}

while true; do
    show_header
    ui_option "1" "Check for updates"
    ui_option "2" "Apply updates (pacman + AUR)"
    ui_option "3" "Remove orphaned packages"
    ui_option "4" "Clean package cache"
    ui_option "5" "Reboot needed?"
    ui_option "q" "Back"
    echo
    read -rp "Select option: " choice
    case "$choice" in
        1) check_updates ;;
        2) apply_updates ;;
        3) remove_orphans ;;
        4) clean_cache ;;
        5) show_header; check_reboot; echo; pause ;;
        q|Q) break ;;
        *) core_error "Invalid option"; sleep 1 ;;
    esac
done
