#!/bin/bash
#--------------------------------------------
# file:     rp5-systeminfo.sh
# author:   Mike Redd
# version:  1.0
# desc:     Raspberry Pi 5 System Info Script for Arch Linux
#--------------------------------------------

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Function to print section headers
print_header() {
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${WHITE}  $1${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to print info line
print_info() {
    printf "${GREEN}%-25s${NC} ${WHITE}%s${NC}\n" "$1:" "$2"
}

# Function to print warning
print_warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

clear
echo -e "${BOLD}${MAGENTA}"
cat << "EOF"
   .~~.   .~~.
  '. \ ' ' / .'
   .~ .~~~..~.
  : .~.'~'.~. :
 ~ (   ) (   ) ~
( : '~'.~.'~' : )
 ~ .~ (   ) ~. ~
  (  : '~' :  )
   '~ .~~~. ~'
       '~'
EOF
echo -e "${NC}"
echo -e "${BOLD}${WHITE}        🍓 RASPBERRY PI 5 SYSTEM INFORMATION 🍓${NC}"
echo -e "${BOLD}${MAGENTA}════════════════════════════════════════════════════════════${NC}"
echo ""

#====================================================
# SYSTEM INFORMATION
#====================================================
print_header "📋 SYSTEM INFORMATION"

HOSTNAME=$(hostname)
KERNEL=$(uname -r)
ARCH=$(uname -m)
UPTIME=$(uptime -p 2>/dev/null || uptime | sed 's/.*up \([^,]*\),.*/\1/')
UPTIME_SINCE=$(uptime -s 2>/dev/null || echo "N/A")
OS_INFO=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d'"' -f2)
OS_INFO=${OS_INFO:-"Arch Linux"}

print_info "Hostname" "$HOSTNAME"
print_info "OS" "$OS_INFO"
print_info "Kernel" "$KERNEL"
print_info "Architecture" "$ARCH"
print_info "Uptime" "$UPTIME"
[ "$UPTIME_SINCE" != "N/A" ] && print_info "Up Since" "$UPTIME_SINCE"

#====================================================
# HARDWARE INFORMATION
#====================================================
print_header "🔧 HARDWARE INFORMATION"

# CPU Information
CPU_MODEL=$(cat /proc/cpuinfo 2>/dev/null | grep "model name" | head -1 | cut -d':' -f2 | sed 's/^ *//' || echo "N/A")
[ "$CPU_MODEL" = "N/A" ] && CPU_MODEL=$(cat /proc/cpuinfo 2>/dev/null | grep "Model" | head -1 | cut -d':' -f2 | sed 's/^ *//' || echo "N/A")
CPU_CORES=$(nproc 2>/dev/null || echo "N/A")
CPU_FREQ=$(cat /proc/cpuinfo 2>/dev/null | grep "cpu MHz" | head -1 | cut -d':' -f2 | sed 's/^ *//' || echo "N/A")
[ "$CPU_FREQ" != "N/A" ] && CPU_FREQ="${CPU_FREQ} MHz"

# CPU Temperature (Raspberry Pi specific)
CPU_TEMP="N/A"
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
    CPU_TEMP=$(echo "scale=1; $TEMP_RAW / 1000" | bc 2>/dev/null || echo "$((TEMP_RAW / 1000))")
    CPU_TEMP="${CPU_TEMP}°C"
fi

# GPU Temperature (if available)
GPU_TEMP="N/A"
if command -v vcgencmd >/dev/null 2>&1; then
    GPU_TEMP_RAW=$(vcgencmd measure_temp 2>/dev/null | cut -d'=' -f2 | cut -d"'" -f1)
    [ -n "$GPU_TEMP_RAW" ] && GPU_TEMP="${GPU_TEMP_RAW}°C"
fi

# Throttling status
THROTTLED="N/A"
if command -v vcgencmd >/dev/null 2>&1; then
    THROTTLE_HEX=$(vcgencmd get_throttled 2>/dev/null | cut -d'=' -f2)
    if [ -n "$THROTTLE_HEX" ]; then
        THROTTLE_DEC=$(printf "%d" "$THROTTLE_HEX" 2>/dev/null || echo "0")
        if [ "$THROTTLE_DEC" -eq 0 ]; then
            THROTTLED="${GREEN}No throttling${NC}"
        else
            THROTTLED="${RED}Throttled! (0x$THROTTLE_HEX)${NC}"
        fi
    fi
fi

print_info "CPU Model" "$CPU_MODEL"
print_info "CPU Cores" "$CPU_CORES"
print_info "CPU Frequency" "$CPU_FREQ"
print_info "CPU Temperature" "$CPU_TEMP"
print_info "GPU Temperature" "$GPU_TEMP"
[ "$THROTTLED" != "N/A" ] && echo -e "${GREEN}%-25s${NC} %b\n" "Throttling Status:" "$THROTTLED"

#====================================================
# MEMORY INFORMATION
#====================================================
print_header "💾 MEMORY INFORMATION"

# RAM
if command -v free >/dev/null 2>&1; then
    MEM_TOTAL=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
    MEM_USED=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3}')
    MEM_FREE=$(free -h 2>/dev/null | awk '/^Mem:/ {print $4}')
    MEM_AVAIL=$(free -h 2>/dev/null | awk '/^Mem:/ {print $7}')
    MEM_PERCENT=$(free 2>/dev/null | awk '/^Mem:/ {printf "%.1f", $3/$2 * 100.0}')

    print_info "Total RAM" "$MEM_TOTAL"
    print_info "Used RAM" "$MEM_USED (${MEM_PERCENT}%)"
    print_info "Free RAM" "$MEM_FREE"
    print_info "Available RAM" "$MEM_AVAIL"
else
    MEM_TOTAL=$(cat /proc/meminfo 2>/dev/null | grep MemTotal | awk '{print $2 $3}')
    MEM_FREE=$(cat /proc/meminfo 2>/dev/null | grep MemFree | awk '{print $2 $3}')
    print_info "Total RAM" "$MEM_TOTAL"
    print_info "Free RAM" "$MEM_FREE"
fi

# Swap
if command -v free >/dev/null 2>&1; then
    SWAP_TOTAL=$(free -h 2>/dev/null | awk '/^Swap:/ {print $2}')
    SWAP_USED=$(free -h 2>/dev/null | awk '/^Swap:/ {print $3}')
    SWAP_FREE=$(free -h 2>/dev/null | awk '/^Swap:/ {print $4}')

    if [ "$SWAP_TOTAL" != "0B" ] && [ -n "$SWAP_TOTAL" ]; then
        print_info "Total Swap" "$SWAP_TOTAL"
        print_info "Used Swap" "$SWAP_USED"
        print_info "Free Swap" "$SWAP_FREE"
    fi
fi

#====================================================
# STORAGE INFORMATION
#====================================================
print_header "💿 STORAGE INFORMATION"

if command -v df >/dev/null 2>&1; then
    echo -e "${BOLD}${BLUE}%-15s %-10s %-10s %-10s %-6s %s${NC}" "Filesystem" "Size" "Used" "Avail" "Use%" "Mounted on"
    echo -e "${CYAN}─────────────────────────────────────────────────────────────────────────${NC}"

    df -h 2>/dev/null | grep -E '^/dev/' | while read -r filesystem size used avail percent mount; do
        # Color code usage
        USE_NUM=$(echo "$percent" | tr -d '%')
        if [ "$USE_NUM" -ge 90 ] 2>/dev/null; then
            COLOR="${RED}"
        elif [ "$USE_NUM" -ge 75 ] 2>/dev/null; then
            COLOR="${YELLOW}"
        else
            COLOR="${GREEN}"
        fi

        printf "%-15s %-10s %-10s %-10s ${COLOR}%-6s${NC} %s\n"             "$filesystem" "$size" "$used" "$avail" "$percent" "$mount"
    done
else
    print_error "df command not available"
fi

#====================================================
# NETWORK INFORMATION
#====================================================
print_header "🌐 NETWORK INFORMATION"

# Hostname & IP
print_info "Hostname" "$(hostname)"

# IP Addresses
if command -v ip >/dev/null 2>&1; then
    IP_ADDR=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -1)
    [ -z "$IP_ADDR" ] && IP_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
    print_info "IPv4 Address" "${IP_ADDR:-N/A}"

    IP6_ADDR=$(ip -6 addr show 2>/dev/null | grep -oP '(?<=inet6\s)[\da-f:]+' | grep -v "::1" | head -1)
    [ -n "$IP6_ADDR" ] && print_info "IPv6 Address" "$IP6_ADDR"

    # Gateway
    GATEWAY=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
    [ -n "$GATEWAY" ] && print_info "Default Gateway" "$GATEWAY"

    # MAC Address
    MAC_ADDR=$(ip link show 2>/dev/null | grep "link/ether" | awk '{print $2}' | head -1)
    [ -n "$MAC_ADDR" ] && print_info "MAC Address" "$MAC_ADDR"

    # Network interfaces
    echo ""
    echo -e "${BOLD}${BLUE}Network Interfaces:${NC}"
    ip -brief addr show 2>/dev/null | grep -v "lo" | while read -r iface state ip4 ip6; do
        printf "  ${CYAN}%-10s${NC} %-8s %s\n" "$iface" "$state" "$ip4"
    done
elif command -v ifconfig >/dev/null 2>&1; then
    IP_ADDR=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)
    print_info "IPv4 Address" "${IP_ADDR:-N/A}"
fi

#====================================================
# RASPBERRY PI SPECIFIC INFORMATION
#====================================================
print_header "🍓 RASPBERRY PI SPECIFIC"

# Check if vcgencmd is available
if command -v vcgencmd >/dev/null 2>&1; then
    # Core voltage
    CORE_VOLT=$(vcgencmd measure_volts core 2>/dev/null | cut -d'=' -f2)
    [ -n "$CORE_VOLT" ] && print_info "Core Voltage" "$CORE_VOLT"

    # SDRAM voltages
    for volt in sdram_c sdram_i sdram_p; do
        VOLT_VAL=$(vcgencmd measure_volts "$volt" 2>/dev/null | cut -d'=' -f2)
        [ -n "$VOLT_VAL" ] && print_info "SDRAM ${volt##*_} Voltage" "$VOLT_VAL"
    done

    # Clock frequencies
    echo ""
    echo -e "${BOLD}${BLUE}Clock Frequencies:${NC}"
    for clock in arm core h264 isp v3d uart pwm emmc pixel vec hdmi dpi; do
        FREQ=$(vcgencmd measure_clock "$clock" 2>/dev/null | cut -d'=' -f2)
        if [ -n "$FREQ" ] && [ "$FREQ" != "0" ]; then
            FREQ_MHZ=$(echo "scale=2; $FREQ / 1000000" | bc 2>/dev/null || echo "$((FREQ / 1000000))")
            printf "  ${CYAN}%-10s${NC} %s MHz\n" "$clock:" "$FREQ_MHZ"
        fi
    done

    # Codecs
    echo ""
    echo -e "${BOLD}${BLUE}Codec Status:${NC}"
    for codec in H264 MPG2 WVC1 MPG4 WMV9 MJPG; do
        STATUS=$(vcgencmd codec_enabled "$codec" 2>/dev/null | cut -d'=' -f2)
        if [ -n "$STATUS" ]; then
            if [ "$STATUS" = "enabled" ]; then
                printf "  ${GREEN}%-10s${NC} %s\n" "$codec:" "$STATUS"
            else
                printf "  ${RED}%-10s${NC} %s\n" "$codec:" "$STATUS"
            fi
        fi
    done

    # Memory split
    echo ""
    MEM_ARM=$(vcgencmd get_mem arm 2>/dev/null | cut -d'=' -f2)
    MEM_GPU=$(vcgencmd get_mem gpu 2>/dev/null | cut -d'=' -f2)
    [ -n "$MEM_ARM" ] && print_info "ARM Memory" "$MEM_ARM"
    [ -n "$MEM_GPU" ] && print_info "GPU Memory" "$MEM_GPU"

    # Boot configuration
    echo ""
    BOOT_CONFIG=$(vcgencmd get_config int 2>/dev/null)
    if [ -n "$BOOT_CONFIG" ]; then
        echo -e "${BOLD}${BLUE}Boot Configuration (int):${NC}"
        echo "$BOOT_CONFIG" | head -20 | while read -r line; do
            printf "  ${CYAN}%s${NC}\n" "$line"
        done
    fi
else
    print_warn "vcgencmd not found. Install 'raspberrypi-utils' for full Pi info."
    print_info "Pi Model" "$(cat /proc/device-tree/model 2>/dev/null | tr '\0' '\n' || echo "Unknown")"
fi

#====================================================
# POWER & PERFORMANCE
#====================================================
print_header "⚡ POWER & PERFORMANCE"

# CPU Governor
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
    print_info "CPU Governor" "$GOVERNOR"
fi

# Current CPU frequencies
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
    echo ""
    echo -e "${BOLD}${BLUE}Per-Core Frequencies:${NC}"
    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
        CPU_NUM=$(basename "$cpu" | sed 's/cpu//')
        FREQ_FILE="$cpu/cpufreq/scaling_cur_freq"
        if [ -f "$FREQ_FILE" ]; then
            FREQ_KHZ=$(cat "$FREQ_FILE" 2>/dev/null)
            FREQ_MHZ=$(echo "scale=0; $FREQ_KHZ / 1000" | bc 2>/dev/null || echo "$((FREQ_KHZ / 1000))")
            printf "  ${CYAN}CPU %-2s${NC} %s MHz\n" "$CPU_NUM:" "$FREQ_MHZ"
        fi
    done
fi

# Power supply (if available on Pi)
if [ -f /sys/class/power_supply/BAT0/capacity ]; then
    BATT_LEVEL=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
    BATT_STATUS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null)
    [ -n "$BATT_LEVEL" ] && print_info "Battery" "$BATT_LEVEL% ($BATT_STATUS)"
fi

#====================================================
# PROCESS INFORMATION
#====================================================
print_header "📊 TOP PROCESSES (by CPU)"

if command -v ps >/dev/null 2>&1; then
    echo -e "${BOLD}${BLUE}%-8s %-8s %-6s %-6s %s${NC}" "PID" "USER" "%CPU" "%MEM" "COMMAND"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────${NC}"
    ps aux 2>/dev/null | sort -rk 3,3 | head -6 | tail -5 | while read -r user pid cpu mem vsz rss tty stat start time command; do
        printf "%-8s %-8s %-6s %-6s %s\n" "$pid" "$user" "$cpu" "$mem" "$command"
    done
else
    print_error "ps command not available"
fi

#====================================================
# SYSTEM SERVICES
#====================================================
print_header "🔌 SYSTEM SERVICES"

if command -v systemctl >/dev/null 2>&1; then
    # Failed services
    FAILED=$(systemctl --failed --no-pager 2>/dev/null | grep "loaded units" | awk '{print $1}')
    if [ -n "$FAILED" ] && [ "$FAILED" != "0" ]; then
        print_error "$FAILED failed services"
        systemctl --failed --no-pager 2>/dev/null | grep "●" | head -5 | while read -r line; do
            echo -e "  ${RED}$line${NC}"
        done
    else
        print_success "All services running normally"
    fi

    # Critical services status
    echo ""
    echo -e "${BOLD}${BLUE}Critical Services:${NC}"
    for service in sshd NetworkManager systemd-networkd systemd-resolved bluetooth avahi-daemon; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            printf "  ${GREEN}%-20s${NC} %s\n" "$service" "active"
        elif systemctl list-unit-files 2>/dev/null | grep -q "^$service"; then
            printf "  ${RED}%-20s${NC} %s\n" "$service" "inactive"
        fi
    done
else
    print_warn "systemctl not available (not using systemd?)"
fi

#====================================================
# USB DEVICES
#====================================================
print_header "🔌 USB DEVICES"

if [ -f /sys/kernel/debug/usb/devices ]; then
    echo -e "${BOLD}${BLUE}Connected USB Devices:${NC}"
    lsusb 2>/dev/null | while read -r line; do
        printf "  ${CYAN}%s${NC}\n" "$line"
    done
else
    print_warn "USB debug info not available (may need root)"
    lsusb 2>/dev/null | head -10 | while read -r line; do
        printf "  %s\n" "$line"
    done
fi

#====================================================
# I2C & SPI (Common for Pi projects)
#====================================================
print_header "🔌 I2C / SPI / GPIO"

# I2C
if [ -d /sys/class/i2c-dev ]; then
    I2C_DEVS=$(ls /sys/class/i2c-dev/ 2>/dev/null | wc -l)
    print_info "I2C Devices" "$I2C_DEVS bus(es) available"
    ls /sys/class/i2c-dev/ 2>/dev/null | while read -r dev; do
        printf "  ${CYAN}%s${NC}\n" "$dev"
    done
fi

# SPI
if [ -d /sys/class/spi_master ]; then
    SPI_DEVS=$(ls /sys/class/spi_master/ 2>/dev/null | wc -l)
    print_info "SPI Devices" "$SPI_DEVS master(s) available"
fi

# GPIO
if [ -d /sys/class/gpio ]; then
    GPIO_COUNT=$(ls /sys/class/gpio/ 2>/dev/null | grep -c "gpio[0-9]" || echo "0")
    print_info "GPIO" "$GPIO_COUNT pin(s) exported"
fi

#====================================================
# DISK I/O & PERFORMANCE
#====================================================
print_header "📈 DISK I/O STATISTICS"

if [ -f /proc/diskstats ]; then
    echo -e "${BOLD}${BLUE}%-10s %-12s %-12s %-12s %-12s${NC}" "Device" "Reads" "Read(MB)" "Writes" "Write(MB)"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"

    cat /proc/diskstats 2>/dev/null | while read -r major minor name reads read_merges read_sectors read_ms writes write_merges write_sectors write_ms; do
        # Skip loop devices and ram disks
        case "$name" in
            ram*|loop*) continue ;;
        esac

        # Calculate MB (sectors are 512 bytes)
        READ_MB=$(echo "scale=2; $read_sectors * 512 / 1048576" | bc 2>/dev/null || echo "0")
        WRITE_MB=$(echo "scale=2; $write_sectors * 512 / 1048576" | bc 2>/dev/null || echo "0")

        printf "%-10s %-12s %-12s %-12s %-12s\n"             "$name" "$reads" "$READ_MB" "$writes" "$WRITE_MB"
    done | head -10
else
    print_warn "/proc/diskstats not available"
fi

#====================================================
# LOAD AVERAGE & PROCESSES
#====================================================
print_header "📉 LOAD AVERAGE"

LOAD=$(cat /proc/loadavg 2>/dev/null)
if [ -n "$LOAD" ]; then
    LOAD1=$(echo "$LOAD" | awk '{print $1}')
    LOAD5=$(echo "$LOAD" | awk '{print $2}')
    LOAD15=$(echo "$LOAD" | awk '{print $3}')
    RUNNING=$(echo "$LOAD" | awk '{print $4}' | cut -d'/' -f1)
    TOTAL=$(echo "$LOAD" | awk '{print $4}' | cut -d'/' -f2)
    LAST_PID=$(echo "$LOAD" | awk '{print $5}')

    print_info "1 min" "$LOAD1"
    print_info "5 min" "$LOAD5"
    print_info "15 min" "$LOAD15"
    print_info "Running/Total" "$RUNNING / $TOTAL processes"
    print_info "Last PID" "$LAST_PID"
fi

#====================================================
# FOOTER
#====================================================
echo ""
echo -e "${BOLD}${MAGENTA}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${WHITE}           Script completed at $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${BOLD}${MAGENTA}════════════════════════════════════════════════════════════${NC}"
echo ""