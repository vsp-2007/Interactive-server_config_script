#!/bin/bash
# Platform Detection Library - Pi Server Setup v2
# Provides unified platform detection for Raspberry Pi and generic Debian/Ubuntu

set -euo pipefail

# Platform detection results (global variables)
PLATFORM=""
IS_PI=false
IS_LAPTOP=false
IS_VM=false
ARCH=""
DISTRO=""
DISTRO_VERSION=""
DISTRO_CODENAME=""

# Detect platform and set global variables
detect_platform() {
    # Architecture
    ARCH=$(uname -m)
    case "${ARCH}" in
        aarch64|arm64) ARCH="arm64" ;;
        armv7l|armhf)  ARCH="armv7" ;;
        x86_64|amd64)  ARCH="amd64" ;;
        *)             ARCH="unknown" ;;
    esac
    
    # Distribution
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        DISTRO="${ID}"
        DISTRO_VERSION="${VERSION_ID}"
        DISTRO_CODENAME="${VERSION_CODENAME:-}"
    else
        DISTRO="unknown"
        DISTRO_VERSION="unknown"
        DISTRO_CODENAME="unknown"
    fi
    
    # Platform detection
    # Check for Raspberry Pi
    if [[ -f /proc/device-tree/model ]] && grep -qi "raspberry pi" /proc/device-tree/model 2>/dev/null; then
        PLATFORM="raspberry_pi"
        IS_PI=true
        local model
        model=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
        log_debug "Detected Raspberry Pi: ${model}"
    elif [[ -f /sys/firmware/devicetree/base/model ]] && grep -qi "raspberry pi" /sys/firmware/devicetree/base/model 2>/dev/null; then
        PLATFORM="raspberry_pi"
        IS_PI=true
        local model
        model=$(cat /sys/firmware/devicetree/base/model 2>/dev/null | tr -d '\0')
        log_debug "Detected Raspberry Pi: ${model}"
    # Check for laptop (battery present)
    elif [[ -d /sys/class/power_supply ]] && find /sys/class/power_supply -name "BAT*" -o -name "battery*" | grep -q . 2>/dev/null; then
        PLATFORM="laptop"
        IS_LAPTOP=true
        log_debug "Detected laptop (battery present)"
    # Check for VM
    elif systemd-detect-virt -q 2>/dev/null; then
        PLATFORM="vm"
        IS_VM=true
        local virt_type
        virt_type=$(systemd-detect-virt 2>/dev/null)
        log_debug "Detected VM: ${virt_type}"
    # Generic desktop/server
    else
        PLATFORM="generic"
        log_debug "Detected generic desktop/server"
    fi
    
    # Export for use in other scripts
    export PLATFORM IS_PI IS_LAPTOP IS_VM ARCH DISTRO DISTRO_VERSION DISTRO_CODENAME
    
    log_info "Platform: ${PLATFORM} (arch: ${ARCH}, distro: ${DISTRO} ${DISTRO_VERSION})"
}

# Platform-specific package adjustments
get_packages_for_platform() {
    local base_packages=("$@")
    local adjusted_packages=("${base_packages[@]}")
    
    if [[ "${IS_PI}" == "true" ]]; then
        # Pi-specific packages
        adjusted_packages+=(
            raspi-config
            rpi-eeprom
            linux-firmware-raspi2
        )
    fi
    
    if [[ "${IS_LAPTOP}" == "true" ]]; then
        # Laptop-specific packages
        adjusted_packages+=(
            tlp
            thermald
            powertop
            acpi
            acpid
        )
    fi
    
    if [[ "${IS_VM}" == "true" ]]; then
        # VM-specific packages
        adjusted_packages+=(
            qemu-guest-agent
            open-vm-tools
        )
    fi
    
    # Distro-specific adjustments
    case "${DISTRO}" in
        debian|ubuntu)
            # Modern CLI tools available in newer versions
            if [[ "${DISTRO_VERSION%%.*}" -ge 12 ]] 2>/dev/null || [[ "${DISTRO_CODENAME}" =~ ^(bookworm|trixie|noble|oracular)$ ]]; then
                adjusted_packages+=(
                    eza
                    bat
                    fd-find
                    ripgrep
                )
            fi
            ;;
    esac
    
    echo "${adjusted_packages[@]}"
}

# Platform-specific service management
get_services_to_disable() {
    local base_services=("$@")
    local adjusted_services=("${base_services[@]}")
    
    if [[ "${IS_PI}" == "true" ]]; then
        adjusted_services+=(
            bluetooth
            hciuart
            triggerhappy
        )
    fi
    
    if [[ "${IS_LAPTOP}" == "true" ]]; then
        adjusted_services+=(
            cups
            avahi-daemon
            # bluetooth - optional, comment out if you use it
        )
    fi
    
    if [[ "${IS_VM}" == "true" ]]; then
        adjusted_services+=(
            # VM-specific services to disable
        )
    fi
    
    echo "${adjusted_services[@]}"
}

# Platform-specific optimizations
apply_platform_optimizations() {
    log_info "Applying ${PLATFORM}-specific optimizations..."
    
    # Common optimizations for all platforms
    apply_common_optimizations
    
    case "${PLATFORM}" in
        raspberry_pi)
            apply_pi_optimizations
            ;;
        laptop)
            apply_laptop_optimizations
            ;;
        vm)
            apply_vm_optimizations
            ;;
        generic)
            apply_generic_optimizations
            ;;
    esac
}

apply_common_optimizations() {
    # Kernel parameters for performance
    cat > /etc/sysctl.d/99-pi-server.conf <<'EOF'
# Network optimizations
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr

# Filesystem optimizations
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50

# Security
kernel.unprivileged_bpf_disabled = 1
kernel.kptr_restrict = 2
vm.unprivileged_userfaultfd = 0
EOF
    
    sysctl --system >/dev/null 2>&1 || true
}

apply_pi_optimizations() {
    log_info "Applying Raspberry Pi optimizations..."
    
    # Swap optimization for Pi - only if dphys-swapfile exists
    if [[ -f /etc/dphys-swapfile ]]; then
        local current_swap
        current_swap=$(grep "^CONF_SWAPSIZE=" /etc/dphys-swapfile | cut -d= -f2)
        if [[ -z "${current_swap}" ]] || [[ "${current_swap}" -lt 1024 ]]; then
            log_info "Increasing swap to 1GB..."
            sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=1024/' /etc/dphys-swapfile
            systemctl restart dphys-swapfile
        fi
    fi
    
    # GPU memory split (headless server) - only if /boot/config.txt exists
    if [[ -f /boot/config.txt ]] && ! grep -q "^gpu_mem=" /boot/config.txt; then
        echo "gpu_mem=16" >> /boot/config.txt
        log_info "Set GPU memory to 16MB (headless)"
    fi
    
    # Disable HDMI if headless - only if /boot/config.txt exists
    if [[ -f /boot/config.txt ]] && ! grep -q "^hdmi_blanking=" /boot/config.txt; then
        echo "hdmi_blanking=1" >> /boot/config.txt
    fi
}

apply_laptop_optimizations() {
    log_info "Applying laptop/desktop optimizations..."
    
    # Power management
    if ! command -v tlp >/dev/null 2>&1; then
        if apt-get install -y -qq tlp 2>/dev/null; then
            systemctl enable tlp
            systemctl start tlp
            log_success "TLP installed and enabled for power management"
        fi
    else
        systemctl enable tlp
        systemctl start tlp
    fi
    
    # Thermal management
    if apt-get install -y -qq thermald 2>/dev/null; then
        systemctl enable thermald
        systemctl start thermald
        log_success "thermald installed and enabled"
    fi
    
    # Configure lid switch behavior (don't sleep on lid close if server)
    if [[ -f /etc/systemd/logind.conf ]]; then
        sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
        sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
        sed -i 's/^#\?HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' /etc/systemd/logind.conf
        systemctl restart systemd-logind
    fi
    
    # Battery charge threshold (if supported)
    if [[ -f /sys/class/power_supply/BAT0/charge_control_end_threshold ]]; then
        echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold 2>/dev/null || true
        log_info "Set battery charge threshold to 80%"
    fi
}

apply_vm_optimizations() {
    log_info "Applying VM optimizations..."
    
    # Install guest agent
    case "${DISTRO}" in
        debian|ubuntu)
            apt-get install -y -qq qemu-guest-agent 2>/dev/null && systemctl enable --now qemu-guest-agent
            ;;
    esac
    
    # Disable unnecessary services in VM
    local vm_disable=(
        bluetooth
        cups
        avahi-daemon
    )
    for svc in "${vm_disable[@]}"; do
        systemctl disable "${svc}" 2>/dev/null || true
        systemctl stop "${svc}" 2>/dev/null || true
    done
}

apply_generic_optimizations() {
    log_info "Applying generic server optimizations..."
    
    # Create swap file if not present and not using dphys-swapfile
    if [[ ! -f /etc/dphys-swapfile ]] && [[ ! -f /swapfile ]] && ! swapon --show | grep -q "^/swapfile"; then
        local swap_size_gb=2
        log_info "Creating ${swap_size_gb}GB swap file..."
        fallocate -l "${swap_size_gb}G" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
        log_success "Swap file created"
    fi
}

# Platform-specific user groups
get_extra_user_groups() {
    local base_groups=("$@")
    local adjusted_groups=("${base_groups[@]}")
    
    if [[ "${IS_PI}" == "true" ]]; then
        adjusted_groups+=(
            gpio
            i2c
            spi
            video
            render
        )
    fi
    
    if [[ "${IS_LAPTOP}" == "true" ]]; then
        adjusted_groups+=(
            video
            render
            audio
        )
    fi
    
    echo "${adjusted_groups[@]}"
}

# Platform-specific VNC setup
configure_vnc() {
    case "${PLATFORM}" in
        raspberry_pi)
            if command -v raspi-config >/dev/null; then
                log_info "Configuring RealVNC..."
                local vnc_state
                vnc_state=$(raspi-config nonint get_vnc 2>/dev/null || echo "1")
                if [[ "${vnc_state}" -eq 0 ]]; then
                    log_info "RealVNC is already enabled"
                else
                    raspi-config nonint do_vnc 0
                    log_success "RealVNC enabled"
                fi
            fi
            ;;
        laptop|generic)
            # Install and configure TigerVNC or similar for non-Pi
            log_info "VNC: Consider installing TigerVNC for remote desktop"
            log_info "  apt-get install tigervnc-standalone-server"
            ;;
        vm)
            log_info "VNC: VMs typically use console/spice/qxl instead"
            ;;
    esac
}

# Platform-specific temperature reading
get_temperature() {
    case "${PLATFORM}" in
        raspberry_pi)
            if command -v vcgencmd >/dev/null; then
                vcgencmd measure_temp 2>/dev/null | sed 's/temp=//' || echo "N/A"
            else
                echo "N/A"
            fi
            ;;
        laptop|generic|vm)
            # Try thermal zones
            if [[ -d /sys/class/thermal ]]; then
                local max_temp=0
                for zone in /sys/class/thermal/thermal_zone*; do
                    if [[ -f "${zone}/temp" ]]; then
                        local temp
                        temp=$(cat "${zone}/temp" 2>/dev/null || echo 0)
                        # Convert millidegrees to degrees
                        temp=$((temp / 1000))
                        if [[ ${temp} -gt ${max_temp} ]]; then
                            max_temp=${temp}
                        fi
                    fi
                done
                if [[ ${max_temp} -gt 0 ]]; then
                    echo "${max_temp}°C"
                else
                    echo "N/A"
                fi
            else
                echo "N/A"
            fi
            ;;
    esac
}

# Platform-specific swap configuration
configure_swap() {
    case "${PLATFORM}" in
        raspberry_pi)
            # Use dphys-swapfile
            if [[ -f /etc/dphys-swapfile ]]; then
                local current_swap
                current_swap=$(grep "^CONF_SWAPSIZE=" /etc/dphys-swapfile | cut -d= -f2)
                if [[ -z "${current_swap}" ]] || [[ "${current_swap}" -lt 2048 ]]; then
                    log_info "Increasing swap to 2GB..."
                    sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
                    systemctl restart dphys-swapfile
                fi
            fi
            ;;
        laptop|generic|vm)
            # Use swap file
            if [[ ! -f /swapfile ]] && ! swapon --show | grep -q "^/swapfile"; then
                local swap_size_gb=2
                # For systems with lots of RAM, use smaller swap
                local total_mem_gb
                total_mem_gb=$(free -g | awk '/^Mem:/{print $2}')
                if [[ ${total_mem_gb} -ge 16 ]]; then
                    swap_size_gb=1
                elif [[ ${total_mem_gb} -ge 8 ]]; then
                    swap_size_gb=2
                fi
                
                log_info "Creating ${swap_size_gb}GB swap file..."
                fallocate -l "${swap_size_gb}G" /swapfile 2>/dev/null || {
                    # fallocate might fail on some filesystems, use dd as fallback
                    dd if=/dev/zero of=/swapfile bs=1G count="${swap_size_gb}" 2>/dev/null
                }
                chmod 600 /swapfile
                mkswap /swapfile
                swapon /swapfile
                echo "/swapfile none swap sw 0 0" >> /etc/fstab
                log_success "Swap file created (${swap_size_gb}GB)"
            fi
            ;;
    esac
}

# Initialize platform detection on source
detect_platform

# Export functions for use in other scripts
export -f detect_platform
export -f get_packages_for_platform
export -f get_services_to_disable
export -f apply_platform_optimizations
export -f configure_vnc
export -f get_temperature
export -f configure_swap
export -f get_extra_user_groups