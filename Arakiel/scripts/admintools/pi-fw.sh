#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# file:     pi-fw.sh
# author:   Mike Redd
# version:  2.3
# desc:     UFW + SSHGuard firewall manager for Arakiel
#
# Firewall architecture
# ---------------------
# UFW:
#   Owns Arakiel's normal host access policy. Incoming traffic is denied by
#   default, SSH is rate-limited, and trusted LAN traffic is permitted.
#
# Tailscale:
#   Manages its own nftables rules independently of UFW. Do not duplicate
#   Tailscale's 100.64.0.0/10 handling here.
#
# SSHGuard:
#   Watches OpenSSH authentication logs and dynamically blocks attackers.
#   Current Arch Linux ARM uses /etc/sshguard.conf and provides a native
#   nftables backend at /usr/lib/sshguard/sshg-fw-nft-sets.
#
#   Do NOT use the legacy sshg-fw-iptables backend on Arakiel. iptables is the
#   nft compatibility implementation here, and that path previously failed to
#   initialize SSHGuard's firewall rules.
#
# Safety
# ------
# Applying base rules resets UFW. This does NOT replace service-specific rule
# management. Review the displayed warning before allowing a reset.
#
# SSHGuard's nftables tables are independent of UFW. A healthy daemon alone is
# therefore not sufficient proof that blocking works; status checks verify both
# the service and the IPv4/IPv6 nftables tables.
# -----------------------------------------------------------------------------

set -euo pipefail

readonly SCRIPT_VERSION="2.3"

readonly SSH_PORT="${SSH_PORT:-22}"
readonly LAN_NET="${LAN_NET:-192.168.4.0/24}"

# Netzach is Arakiel's trusted administration workstation over Tailscale.
# Keep this specific rather than whitelisting the entire 100.64.0.0/10 CGNAT
# range, which is larger than this Tailnet.
readonly NETZACH_TAILSCALE_IP="${NETZACH_TAILSCALE_IP:-100.101.247.28}"

readonly SSHGUARD_CONFIG="/etc/sshguard.conf"
readonly SSHGUARD_WHITELIST="/etc/sshguard/whitelist"
readonly SSHGUARD_BACKEND="/usr/lib/sshguard/sshg-fw-nft-sets"

# ── Shared UI ---------------------------------------------------------------

# Load Arakiel's shared UI/core when available. The firewall manager retains
# its compact [*]/[+]/[!]/[x] messages while borrowing the common palette.
LIB_DIR="${LIB_DIR:-$HOME/lib}"
if [[ -f "$LIB_DIR/core.sh" ]]; then
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$LIB_DIR/core.sh")
fi

RED="${UI_RED:-$'\e[31m'}"
YEL="${UI_YLW:-$'\e[33m'}"
GRN="${UI_GRN:-$'\e[32m'}"
CYN="${UI_CYN:-$'\e[36m'}"
RST="${UI_R:-$'\e[0m'}"
BLD=$'\e[1m'

info() { echo -e "${CYN}[*]${RST} $*"; }
ok()   { echo -e "${GRN}[+]${RST} $*"; }
warn() { echo -e "${YEL}[!]${RST} $*"; }
err()  { echo -e "${RED}[x]${RST} $*" >&2; }
die()  { err "$*"; exit 1; }

pause() {
    read -rp $'\nPress Enter to continue...'
}

# ── Validation --------------------------------------------------------------

require_root() {
    [[ "$EUID" -eq 0 ]] || die "Run with sudo/root"
}

require_ufw() {
    command -v ufw &>/dev/null ||
        die "UFW is not installed. Run option 1 first."
}

require_nft() {
    command -v nft &>/dev/null ||
        die "nftables is required for SSHGuard protection."
}

validate_port() {
    local port="$1"

    [[ "$port" =~ ^[0-9]+$ ]] &&
        (( port >= 1 && port <= 65535 )) ||
        die "Invalid port: $port"
}

# This deliberately performs stronger validation than the old shape-only
# regular expression. Each IPv4 octet must be 0-255 and the prefix 0-32.
validate_ipv4_cidr() {
    local cidr="$1"
    local address prefix octet
    local -a octets

    [[ "$cidr" == */* ]] || die "Invalid IPv4 CIDR: $cidr"

    address="${cidr%/*}"
    prefix="${cidr#*/}"

    [[ "$prefix" =~ ^[0-9]+$ ]] &&
        (( prefix >= 0 && prefix <= 32 )) ||
        die "Invalid IPv4 CIDR prefix: $cidr"

    IFS='.' read -r -a octets <<< "$address"
    (( ${#octets[@]} == 4 )) || die "Invalid IPv4 CIDR: $cidr"

    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]+$ ]] &&
            (( 10#$octet >= 0 && 10#$octet <= 255 )) ||
            die "Invalid IPv4 CIDR: $cidr"
    done
}

validate_ipv4() {
    validate_ipv4_cidr "$1/32"
}

# ── UFW ---------------------------------------------------------------------

install_ufw() {
    if command -v ufw &>/dev/null; then
        ok "UFW is already installed"
        pause
        return
    fi

    # Keep package installation separate from a full system upgrade. Firewall
    # installation should not unexpectedly upgrade the entire server.
    info "Installing UFW..."
    pacman -S --needed ufw
    systemctl enable --now ufw

    ok "UFW installed and enabled"
    pause
}

apply_base_rules() {
    require_ufw

    echo
    warn "Applying base rules resets ALL current UFW rules."
    warn "Any service-specific UFW rules must be recreated afterward."
    echo
    info "Base policy to be applied:"
    echo "  Incoming: deny"
    echo "  Outgoing: allow"
    echo "  SSH:      limit ${SSH_PORT}/tcp"
    echo "  LAN:      allow ${LAN_NET}"
    echo

    read -rp "  Reset UFW and apply these base rules? (y/N): " answer
    [[ "${answer,,}" == "y" ]] || {
        info "Base-rule reset cancelled"
        pause
        return
    }

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

allow_port() {
    require_ufw

    local port proto

    read -rp "Port: " port
    validate_port "$port"

    read -rp "Protocol [tcp/udp/both]: " proto

    case "${proto,,}" in
        tcp)
            ufw allow "${port}/tcp"
            ;;
        udp)
            ufw allow "${port}/udp"
            ;;
        both)
            ufw allow "${port}/tcp"
            ufw allow "${port}/udp"
            ;;
        *)
            die "Invalid protocol: $proto"
            ;;
    esac

    ok "Port ${port}/${proto} allowed"
    pause
}

show_ports() {
    echo
    echo -e "${BLD}══════════ LISTENING PORTS ══════════${RST}"

    ss -tulpn | awk '
        NR == 1 {
            printf "%-8s %-6s %-40s %s\n",
                   "State", "Proto", "Local addr", "Process"
            next
        }
        {
            printf "%-8s %-6s %-40s %s\n",
                   $1, $2, $5, $7
        }
    '

    pause
}

reset_firewall() {
    require_ufw

    warn "This will reset ALL UFW firewall rules."
    warn "SSHGuard uses separate nftables tables and is not a substitute"
    warn "for the normal UFW host policy."

    read -rp "  Are you sure? (y/N): " confirm

    if [[ "${confirm,,}" == "y" ]]; then
        ufw --force reset
        ok "UFW reset. Run '2) Apply base rules' to re-enable its policy."
    else
        info "Cancelled"
    fi

    pause
}

disable_firewall() {
    require_ufw

    warn "Disabling UFW removes Arakiel's normal host firewall policy."
    warn "SSHGuard only blocks detected attackers; it does NOT replace UFW."

    read -rp "  Are you sure? (y/N): " confirm

    if [[ "${confirm,,}" == "y" ]]; then
        ufw disable
        ok "UFW disabled"
    else
        info "Cancelled"
    fi

    pause
}

# ── SSHGuard ----------------------------------------------------------------

write_sshguard_config() {
    # SSHGuard 2.5.x on Arch Linux ARM reads /etc/sshguard.conf directly.
    # The older pi-fw.sh incorrectly wrote /etc/sshguard/sshguard.conf.
    [[ -f "$SSHGUARD_CONFIG" ]] &&
        cp -a "$SSHGUARD_CONFIG" \
            "${SSHGUARD_CONFIG}.bak.$(date +%Y%m%d-%H%M%S)"

    mkdir -p "$(dirname "$SSHGUARD_WHITELIST")"

    [[ -f "$SSHGUARD_WHITELIST" ]] &&
        cp -a "$SSHGUARD_WHITELIST" \
            "${SSHGUARD_WHITELIST}.bak.$(date +%Y%m%d-%H%M%S)"

    cat > "$SSHGUARD_CONFIG" <<EOF_CONFIG
#!/bin/sh
# SSHGuard configuration for Arakiel.
#
# UFW owns normal host policy. SSHGuard uses native nftables sets for dynamic
# brute-force bans. Do not change BACKEND to sshg-fw-iptables on this host.

BACKEND="$SSHGUARD_BACKEND"

# Current OpenSSH/systemd logging uses both sshd and sshd-session identifiers.
LOGREADER="LANG=C /usr/bin/journalctl -afb -p info -n1 -t sshd -t sshd-session -o cat"

THRESHOLD=20
BLOCK_TIME=180
DETECTION_TIME=3600

# Persist repeat-offender information across SSHGuard restarts.
BLACKLIST_FILE=120:/var/db/sshguard/blacklist.db

WHITELIST_FILE=$SSHGUARD_WHITELIST
EOF_CONFIG

    cat > "$SSHGUARD_WHITELIST" <<EOF_WHITELIST
# Arakiel's trusted local network.
$LAN_NET

# Netzach - trusted administration workstation over Tailscale.
$NETZACH_TAILSCALE_IP
EOF_WHITELIST
}

sshguard_table_exists() {
    local family="$1"
    nft list table "$family" sshguard &>/dev/null
}

sshguard_backend_healthy() {
    systemctl is-active --quiet sshguard &&
        sshguard_table_exists ip &&
        sshguard_table_exists ip6
}

setup_sshguard() {
    require_ufw
    require_nft

    validate_ipv4_cidr "$LAN_NET"
    validate_ipv4 "$NETZACH_TAILSCALE_IP"

    if ! command -v sshguard &>/dev/null; then
        info "Installing SSHGuard..."
        pacman -S --needed sshguard
    else
        info "SSHGuard already installed; applying Arakiel configuration..."
    fi

    [[ -x "$SSHGUARD_BACKEND" ]] ||
        die "Native SSHGuard nftables backend not found: $SSHGUARD_BACKEND"

    write_sshguard_config

    # Restart only SSHGuard. UFW does not need to be reloaded because the
    # native backend owns independent nftables tables named "sshguard".
    systemctl enable sshguard
    systemctl restart sshguard

    # Give the backend a moment to initialize its IPv4 and IPv6 tables.
    sleep 1

    if sshguard_backend_healthy; then
        ok "SSHGuard installed and configured"
        ok "Native nftables backend is healthy"
        info "Whitelisted LAN:     $LAN_NET"
        info "Whitelisted Netzach: $NETZACH_TAILSCALE_IP"
        info "Initial block time:  180 seconds"
        info "Attack threshold:     20 points"
    else
        err "SSHGuard daemon/backend health check FAILED."
        warn "The service may be running without functional blocking."
        echo
        systemctl status sshguard --no-pager -l || true
    fi

    pause
}

show_sshguard_status() {
    echo -e "${BLD}═══════════════ SSHGUARD STATUS ════════════════${RST}"

    if systemctl is-active --quiet sshguard 2>/dev/null; then
        ok "Daemon: active"
    else
        warn "Daemon: inactive"
        return
    fi

    if sshguard_table_exists ip; then
        ok "IPv4 nftables protection: active"
    else
        err "IPv4 nftables protection: MISSING"
    fi

    if sshguard_table_exists ip6; then
        ok "IPv6 nftables protection: active"
    else
        err "IPv6 nftables protection: MISSING"
    fi

    if sshguard_backend_healthy; then
        ok "Firewall backend: healthy"
    else
        err "Firewall backend: BROKEN"
    fi

    echo
    echo "IPv4 attackers:"
    if sshguard_table_exists ip; then
        nft list set ip sshguard attackers 2>/dev/null ||
            warn "Unable to read IPv4 attackers set"
    else
        info "(SSHGuard IPv4 table does not exist)"
    fi

    echo
    echo "IPv6 attackers:"
    if sshguard_table_exists ip6; then
        nft list set ip6 sshguard attackers 2>/dev/null ||
            warn "Unable to read IPv6 attackers set"
    else
        info "(SSHGuard IPv6 table does not exist)"
    fi
}

show_status() {
    require_ufw

    echo
    echo -e "${BLD}══════════════════ UFW STATUS ══════════════════${RST}"
    ufw status verbose

    echo
    show_sshguard_status

    echo -e "${BLD}══════════════════════════════════════════════════${RST}"
    pause
}

view_logs() {
    echo
    echo -e "${BLD}═══════ LAST 20 SSH ATTEMPTS ═══════${RST}"

    journalctl -u sshd -n 20 --no-pager 2>/dev/null ||
        warn "No sshd journal entries found"

    echo
    echo -e "${BLD}══════════ SSHGUARD EVENTS ══════════${RST}"

    if systemctl is-active --quiet sshguard 2>/dev/null; then
        journalctl -u sshguard -n 30 --no-pager 2>/dev/null ||
            info "No SSHGuard logs yet"
    else
        warn "SSHGuard is not running"
    fi

    pause
}

# ── Menu --------------------------------------------------------------------

menu() {
    clear

    printf "%s%s" "$BLD" "$CYN"
    printf "  ╔══════════════════════════════════════════╗\n"
    printf "  ║      Arakiel Firewall Manager  v%-4s     ║\n" "$SCRIPT_VERSION"
    printf "  ╚══════════════════════════════════════════╝%s\n" "$RST"
    echo

    local ufw_status="unknown"
    local sshguard_status="inactive"
    local backend_status="missing"

    if command -v ufw &>/dev/null; then
        ufw_status="$(
            ufw status 2>/dev/null |
                awk -F': ' '/^Status:/ { print $2; exit }'
        )"
        [[ -n "$ufw_status" ]] || ufw_status="unknown"
    fi

    if systemctl is-active --quiet sshguard 2>/dev/null; then
        sshguard_status="active"

        if sshguard_backend_healthy; then
            backend_status="healthy"
        else
            backend_status="BROKEN"
        fi
    fi

    echo -e \
        "  UFW: ${BLD}${ufw_status}${RST}    " \
        "SSHGuard: ${BLD}${sshguard_status}${RST}    " \
        "Backend: ${BLD}${backend_status}${RST}"

    echo
    echo -e "  ${BLD}Install / Configure${RST}"
    echo    "  1)  Install UFW"
    echo    "  2)  Apply base UFW rules"
    echo    "  8)  Setup / repair SSHGuard"

    echo
    echo -e "  ${BLD}Manage${RST}"
    echo    "  3)  Show firewall status"
    echo    "  4)  Allow port"
    echo    "  5)  Show listening ports"
    echo    "  9)  View SSH / SSHGuard logs"

    echo
    echo -e "  ${BLD}Danger zone${RST}"
    echo    "  6)  Reset UFW"
    echo    "  7)  Disable UFW"

    echo
    echo    "  q)  Quit"
    echo
}

main() {
    require_root
    validate_port "$SSH_PORT"
    validate_ipv4_cidr "$LAN_NET"
    validate_ipv4 "$NETZACH_TAILSCALE_IP"

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
                info "Exiting firewall manager"
                exit 0
                ;;
            *)
                err "Invalid option: '$CHOICE'"
                pause
                ;;
        esac
    done
}

main "$@"
