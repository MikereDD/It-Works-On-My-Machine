#!/usr/bin/env bash
#--------------------------------------------
# file:     pi-fw.sh
# author:   Mike Redd
# version:  2.1
# desc:     UFW firewall manager for Arakiel with SSHGuard
#--------------------------------------------

set -euo pipefail

readonly SSH_PORT="${SSH_PORT:-22}"
readonly LAN_NET="${LAN_NET:-192.168.4.0/24}"

# ── helpers ──────────────────────────────────────────────────────────────────

RED='\e[31m'; YEL='\e[33m'; GRN='\e[32m'; CYN='\e[36m'; RST='\e[0m'; BLD='\e[1m'

info()  { echo -e "${CYN}[*]${RST} $*"; }
ok()    { echo -e "${GRN}[+]${RST} $*"; }
warn()  { echo -e "${YEL}[!]${RST} $*"; }
err()   { echo -e "${RED}[x]${RST} $*" >&2; }
die()   { err "$*"; exit 1; }

pause() { read -rp $'\nPress Enter to continue...'; }

require_root() {
    [[ "${EUID}" -eq 0 ]] || die "Run with sudo/root"
}

require_ufw() {
    command -v ufw &>/dev/null || die "UFW is not installed. Run option 1 first."
}

validate_port() {
    local p="$1"
    [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 )) || die "Invalid port: $p"
}

validate_cidr() {
    [[ "$1" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]] \
        || die "Invalid CIDR: $1"
}

# ── functions ─────────────────────────────────────────────────────────────────

install_ufw() {
    if command -v ufw &>/dev/null; then
        ok "UFW is already installed"
        pause; return
    fi

    info "Updating package database and installing UFW..."
    pacman -Syu --noconfirm ufw
    systemctl enable --now ufw
    ok "UFW installed and enabled"
    pause
}

apply_base_rules() {
    require_ufw

    if ufw status | grep -q "Status: active"; then
        warn "Firewall is already active."
        read -rp "  Reset and re-apply base rules? (y/N): " answer
        [[ "${answer,,}" == "y" ]] || { info "Skipping base rules"; pause; return; }
    fi

    ufw --force reset

    ufw default deny incoming
    ufw default allow outgoing
    ufw limit "${SSH_PORT}/tcp"
    ufw allow from "$LAN_NET"
    ufw --force enable

    ok "Base rules applied"
    info "SSH rate-limited on port ${SSH_PORT}/tcp"
    info "LAN access allowed from ${LAN_NET}"
    pause
}

_insert_sshguard_rules() {
    local rules_file="/etc/ufw/before.rules"

    [[ -f "$rules_file" ]] && cp "$rules_file" \
        "${rules_file}.bak.$(date +%Y%m%d_%H%M%S.%N | cut -c1-21)"

    if grep -q "sshguard" "$rules_file" 2>/dev/null; then
        info "SSHGuard rules already present in before.rules"
        return
    fi

    if [[ ! -f "$rules_file" ]]; then
        cat > "$rules_file" << EOF
# Rules that execute before ufw's built-in rules

*filter
:ufw-before-input - [0:0]
:ufw-before-output - [0:0]
:ufw-before-forward - [0:0]
:sshguard - [0:0]

-A ufw-before-input -p tcp --dport ${SSH_PORT} -j sshguard

COMMIT
EOF
    else
        # Insert chain declaration + jump rule before the first COMMIT in *filter
        awk -v port="${SSH_PORT}" '
            /^\*filter/ { print; found_filter=1; next }
            found_filter && /^COMMIT/ && !inserted {
                print ":sshguard - [0:0]"
                print "-A ufw-before-input -p tcp --dport " port " -j sshguard"
                inserted=1
            }
            { print }
        ' "$rules_file" > "${rules_file}.tmp" && mv "${rules_file}.tmp" "$rules_file"
    fi
}

setup_sshguard() {
    require_ufw

    if ! command -v sshguard &>/dev/null; then
        info "Installing SSHGuard..."
        pacman -S --noconfirm sshguard
    else
        info "SSHGuard already installed, reconfiguring..."
    fi

    validate_cidr "$LAN_NET"
    _insert_sshguard_rules

    cat > /etc/sshguard/sshguard.conf << EOF
BACKEND="/usr/lib/sshguard/sshg-fw-iptables"
LOGREADER="LANG=C /usr/bin/journalctl -afb -p info -n1 -t sshd -o cat"
THRESHOLD=20
BLOCK_TIME=180
DETECTION_TIME=3600
WHITELIST_FILE=/etc/sshguard/whitelist
EOF

    mkdir -p /etc/sshguard
    printf '# Whitelist local network\n%s\n' "$LAN_NET" > /etc/sshguard/whitelist

    systemctl enable --now sshguard
    ufw reload

    ok "SSHGuard installed and configured"
    info "Whitelisted: $LAN_NET | Block time: 180s | Threshold: 20 pts"
    pause
}

show_status() {
    require_ufw
    echo
    echo -e "${BLD}══════════════════ UFW STATUS ══════════════════${RST}"
    ufw status verbose
    echo
    echo -e "${BLD}═══════════════ SSHGUARD STATUS ════════════════${RST}"
    if systemctl is-active --quiet sshguard 2>/dev/null; then
        ok "SSHGuard: active"
        echo "Blocked IPs:"
        iptables -L sshguard -n 2>/dev/null \
            | awk 'NR>2 && NF' \
            | head -20 \
            || info "(none)"
    else
        warn "SSHGuard: not active"
    fi
    echo -e "${BLD}══════════════════════════════════════════════════${RST}"
    pause
}

allow_port() {
    require_ufw
    local port proto

    read -rp "Port: " port
    validate_port "$port"

    read -rp "Protocol [tcp/udp/both]: " proto
    case "${proto,,}" in
        tcp)  ufw allow "${port}/tcp" ;;
        udp)  ufw allow "${port}/udp" ;;
        both) ufw allow "${port}/tcp"; ufw allow "${port}/udp" ;;
        *)    die "Invalid protocol: $proto" ;;
    esac

    ok "Port ${port}/${proto} allowed"
    pause
}

show_ports() {
    echo
    echo -e "${BLD}══════════ LISTENING PORTS ══════════${RST}"
    ss -tulpn | awk '
        NR==1 { printf "%-8s %-6s %-40s %s\n","State","Proto","Local addr","Process"; next }
        { printf "%-8s %-6s %-40s %s\n",$1,$2,$5,$7 }
    '
    pause
}

reset_firewall() {
    require_ufw
    warn "This will reset ALL firewall rules."
    read -rp "  Are you sure? (y/N): " confirm
    if [[ "${confirm,,}" == "y" ]]; then
        systemctl stop sshguard 2>/dev/null || true
        ufw --force reset
        ok "Firewall reset. Run '2) Apply Base Rules' to re-enable."
    else
        info "Cancelled"
    fi
    pause
}

disable_firewall() {
    require_ufw
    warn "Disabling the firewall leaves all ports exposed."
    read -rp "  Are you sure? (y/N): " confirm
    if [[ "${confirm,,}" == "y" ]]; then
        ufw disable
        systemctl stop sshguard 2>/dev/null || true
        ok "Firewall disabled"
    else
        info "Cancelled"
    fi
    pause
}

view_logs() {
    echo
    echo -e "${BLD}═══════ LAST 20 SSH ATTEMPTS ═══════${RST}"
    if journalctl -u sshd -n 20 --no-pager 2>/dev/null; then
        true
    else
        warn "No sshd journal entries found"
    fi

    echo
    echo -e "${BLD}══════════ SSHGUARD BLOCKS ══════════${RST}"
    if systemctl is-active --quiet sshguard 2>/dev/null; then
        journalctl -u sshguard -n 20 --no-pager 2>/dev/null || info "No SSHGuard logs yet"
    else
        warn "SSHGuard is not running"
    fi
    pause
}

# ── menu ──────────────────────────────────────────────────────────────────────

menu() {
    clear
    echo -e "${BLD}${CYN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║      Arakiel Firewall Manager  v2.1      ║"
    echo "  ╚══════════════════════════════════════════╝${RST}"
    echo
    local ufw_status ssg_status
    ufw_status=$(ufw status 2>/dev/null | grep -oP 'Status: \K\w+' || echo "unknown")
    ssg_status=$(systemctl is-active sshguard 2>/dev/null || echo "inactive")
    echo -e "  UFW: ${BLD}${ufw_status}${RST}    SSHGuard: ${BLD}${ssg_status}${RST}"
    echo
    echo -e "  ${BLD}Install / Configure${RST}"
    echo    "  1)  Install UFW"
    echo    "  2)  Apply base rules"
    echo    "  8)  Setup SSHGuard (brute-force protection)"
    echo
    echo -e "  ${BLD}Manage${RST}"
    echo    "  3)  Show status (UFW + SSHGuard)"
    echo    "  4)  Allow port"
    echo    "  5)  Show listening ports"
    echo    "  9)  View logs (SSH attempts + blocks)"
    echo
    echo -e "  ${BLD}Danger zone${RST}"
    echo    "  6)  Reset firewall"
    echo    "  7)  Disable firewall"
    echo
    echo    "  q)  Quit"
    echo
}

main() {
    require_root
    validate_port "$SSH_PORT"
    validate_cidr "$LAN_NET"

    while true; do
        menu
        read -rp "  Select option: " CHOICE

        case "$CHOICE" in
            1) install_ufw ;;
            2) apply_base_rules ;;
            3) show_status ;;
            4) allow_port ;;
            5) show_ports ;;
            6) reset_firewall ;;
            7) disable_firewall ;;
            8) setup_sshguard ;;
            9) view_logs ;;
            q|Q)
                info "Exiting. Firewall: $(ufw status 2>/dev/null | grep -oP 'Status: \K\w+' || echo 'unknown')"
                exit 0
                ;;
            *) err "Invalid option: '$CHOICE'"; pause ;;
        esac
    done
}

main "$@"