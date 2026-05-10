#!/usr/bin/env bash
#--------------------------------------------
# file:     pi-fw.sh
# author:   Mike Redd
# version:  2.0
# desc:     UFW firewall manager for Arakiel with SSHGuard
#--------------------------------------------

set -u

SSH_PORT="${SSH_PORT:-22}"
LAN_NET="${LAN_NET:-192.168.4.0/24}"

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "[x] Run with sudo/root"
        exit 1
    fi
}

pause() {
    read -rp "Press Enter to continue..."
}

install_ufw() {
    echo "[*] Updating package database..."
    pacman -Sy --noconfirm

    echo "[*] Installing UFW..."
    pacman -S --noconfirm ufw

    systemctl enable ufw

    echo "[+] UFW installed and enabled"

    pause
}

apply_base_rules() {

    if ufw status | grep -q "active"; then
        echo "[!] Firewall is already active. Reset first? (y/n)"
        read -r answer

        if [[ "$answer" == "y" ]]; then
            ufw --force reset
        else
            echo "[*] Skipping base rules"
            pause
            return
        fi
    fi

    ufw --force reset

    ufw default deny incoming
    ufw default allow outgoing

    # SSH rate limiting
    ufw limit "${SSH_PORT}/tcp"

    # Allow LAN access
    ufw allow from "$LAN_NET"

    ufw --force enable

    echo "[*] Base rules applied"
    echo "[*] SSH is rate-limited (${SSH_PORT}/tcp)"
    echo "[*] LAN access allowed from ${LAN_NET}"

    pause
}

setup_sshguard() {

    echo "[*] Installing SSHGuard..."

    pacman -S --noconfirm sshguard

    echo "[*] Configuring UFW before.rules for SSHGuard..."

    if [[ -f /etc/ufw/before.rules ]]; then
        cp /etc/ufw/before.rules \
           /etc/ufw/before.rules.bak.$(date +%Y%m%d_%H%M%S)
    fi

    if ! grep -q "sshguard" /etc/ufw/before.rules 2>/dev/null; then

        if [[ ! -f /etc/ufw/before.rules ]]; then

            cat > /etc/ufw/before.rules << EOF
# Rules that execute before ufw's built-in rules

*nat
:PREROUTING ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
COMMIT

*filter
:ufw-before-input - [0:0]
:ufw-before-output - [0:0]
:ufw-before-forward - [0:0]
:sshguard - [0:0]

-A ufw-before-input -p tcp --dport ${SSH_PORT} -j sshguard

COMMIT
EOF

        else

            sed -i \
            '/^COMMIT$/i # SSHGuard chain\n:sshguard - [0:0]\n-A ufw-before-input -p tcp --dport '"${SSH_PORT}"' -j sshguard\n' \
            /etc/ufw/before.rules

        fi
    fi

    cat > /etc/sshguard/sshguard.conf << EOF
# SSHGuard configuration

BACKEND="/usr/lib/sshguard/sshg-fw-iptables"
LOGREADER="LANG=C /usr/bin/journalctl -afb -p info -n1 -t sshd -o cat"

THRESHOLD=20
BLOCK_TIME=180
DETECTION_TIME=3600

WHITELIST_FILE=/etc/sshguard/whitelist
EOF

    echo "# Whitelist local network" > /etc/sshguard/whitelist
    echo "$LAN_NET" >> /etc/sshguard/whitelist

    systemctl enable sshguard
    systemctl start sshguard

    ufw reload

    echo "[+] SSHGuard installed and configured"
    echo "[*] Whitelisted: $LAN_NET"
    echo "[*] Block time: 180 seconds"

    pause
}

show_status() {

    echo "========== UFW STATUS =========="
    ufw status verbose

    echo
    echo "========== SSHGUARD STATUS =========="

    if systemctl is-active --quiet sshguard; then

        echo "SSHGuard: active"
        echo "Blocked IPs:"

        iptables -L sshguard -n 2>/dev/null \
            | grep -v "Chain\|target\|pkts" \
            | head -20

    else
        echo "SSHGuard: not active"
    fi

    echo "================================="

    pause
}

allow_port() {

    read -rp "Port: " PORT
    read -rp "Protocol [tcp/udp/both]: " PROTO

    case "$PROTO" in

        tcp)
            ufw allow "${PORT}/tcp"
            ;;

        udp)
            ufw allow "${PORT}/udp"
            ;;

        both)
            ufw allow "${PORT}/tcp"
            ufw allow "${PORT}/udp"
            ;;

        *)
            echo "[x] Invalid protocol"
            ;;
    esac

    echo "[+] Port allowed"

    pause
}

show_ports() {

    ss -tulpn

    pause
}

reset_firewall() {

    echo "[!] This will reset ALL firewall rules"

    read -rp "Are you sure? (y/n): " confirm

    if [[ "$confirm" == "y" ]]; then

        ufw --force reset

        echo "[*] Firewall reset. Run '2) Apply Base Rules' to re-enable"

    fi

    pause
}

disable_firewall() {

    echo "[!] Disabling firewall leaves ports exposed"

    read -rp "Are you sure? (y/n): " confirm

    if [[ "$confirm" == "y" ]]; then

        ufw disable
        systemctl stop sshguard

        echo "[*] Firewall disabled"

    fi

    pause
}

view_logs() {

    echo "========== LAST 20 SSH ATTEMPTS =========="

    journalctl -u sshd -n 20 --no-pager

    echo
    echo "========== SSHGUARD BLOCKS =========="

    journalctl -u sshguard -n 10 --no-pager 2>/dev/null \
        || echo "No SSHGuard logs found"

    pause
}

menu() {

    clear

    echo "=========================================="
    echo "       Arakiel Firewall Manager v2.0      "
    echo "=========================================="
    echo
    echo "1)  Install UFW"
    echo "2)  Apply Base Rules"
    echo "3)  Show Status (UFW + SSHGuard)"
    echo "4)  Allow Port"
    echo "5)  Show Listening Ports"
    echo "6)  Reset Firewall"
    echo "7)  Disable Firewall"
    echo "8)  Setup SSHGuard (Brute-force protection)"
    echo "9)  View Logs (SSH attempts + blocks)"
    echo "q)  Quit"
    echo
}

main() {

    require_root

    while true; do

        menu

        read -rp "Select option: " CHOICE

        case "$CHOICE" in

            1)
                install_ufw
                ;;

            2)
                apply_base_rules
                ;;

            3)
                show_status
                ;;

            4)
                allow_port
                ;;

            5)
                show_ports
                ;;

            6)
                reset_firewall
                ;;

            7)
                disable_firewall
                ;;

            8)
                setup_sshguard
                ;;

            9)
                view_logs
                ;;

            q|Q)
                echo "[*] Exiting. Firewall status:"
                ufw status | head -1
                exit 0
                ;;

            *)
                echo "[x] Invalid option"
                pause
                ;;
        esac

    done
}

main "$@"

