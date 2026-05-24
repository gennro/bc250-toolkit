#!/bin/bash
# BC-250 40CU Unlock Manager for CachyOS

if [[ $EUID -ne 0 ]]; then echo "Please run as root"; exit 1; fi

# 1. Disclaimer
show_disclaimer() {
    echo "======================================================================"
    echo "TL;DR: WHAT THIS SCRIPT DOES"
    echo "======================================================================"
    echo "This script unlocks hidden Compute Units (CUs) on your BC-250 GPU."
    echo "It uses 'umr' to write to hardware registers that override the GPU's default power-gating."
    echo ""
    echo "======================================================================"
    echo "DISCLAIMER AND LIABILITY WAIVER"
    echo "======================================================================"
    echo "This script modifies low-level GPU registers to unlock additional CUs."
    echo "THERE IS NO WARRANTY, EXPRESS OR IMPLIED. USE AT YOUR OWN RISK."
    echo "Possible side effects: System instability, kernel panics, or graphical corruption."
    echo "I take no responsibility for any damage, data loss, or issues caused by this tool."
    echo "======================================================================"
    read -p "Do you accept these terms and wish to proceed? (y/n): " choice
    if [[ "$choice" != "y" ]]; then exit 1; fi
}

# Paths
SERVICE_NAME="bc250-unlock.service"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
WORKER_SCRIPT="/usr/local/bin/bc250-apply-unlock.sh"
UDEV_RULE="/etc/udev/rules.d/99-systemd-dri-devices.rules"

# 2. Logic (Install/Create)
install_umr() {
    if ! command -v paru &> /dev/null && ! command -v yay &> /dev/null; then
        pacman -S --needed --noconfirm base-devel git
        sudo -u $SUDO_USER git clone https://aur.archlinux.org/yay.git /tmp/yay
        pushd /tmp/yay && sudo -u $SUDO_USER makepkg -si --noconfirm && popd && rm -rf /tmp/yay
    fi
    local AUR=$(command -v paru || command -v yay)
    if ! pacman -Qi umr &> /dev/null; then $AUR -S --needed --noconfirm umr; fi
}

create_worker() {
    cat << 'EOF' > "$WORKER_SCRIPT"
#!/bin/bash
exec > >(logger -t bc250-unlock) 2>&1
umr -w *.gfx1013.mmRLC_PG_ALWAYS_ON_WGP_MASK 0x1f
umr -w *.gfx1013.mmCC_GC_SHADER_ARRAY_CONFIG 0x0
umr -w *.gfx1013.mmCC_GC_SHADER_ARRAY_CONFIG 0x0 -b 1 0 0xffffffff
umr -w *.gfx1013.mmCC_GC_SHADER_ARRAY_CONFIG 0x0 -b 1 1 0xffffffff
umr -w *.gfx1013.mmCC_GC_SHADER_ARRAY_CONFIG 0x0 -b 0 1 0xffffffff
umr -w *.gfx1013.mmCC_GC_SHADER_ARRAY_CONFIG 0x0 -b 0 0 0xffffffff
umr -w *.gfx1013.mmSPI_PG_ENABLE_STATIC_WGP_MASK 0x1f -b 0 0 0xffffffff
umr -w *.gfx1013.mmSPI_PG_ENABLE_STATIC_WGP_MASK 0x1f -b 0 1 0xffffffff
umr -w *.gfx1013.mmSPI_PG_ENABLE_STATIC_WGP_MASK 0x1f -b 1 0 0xffffffff
umr -w *.gfx1013.mmSPI_PG_ENABLE_STATIC_WGP_MASK 0x1f -b 1 1 0xffffffff
EOF
    chmod +x "$WORKER_SCRIPT"
}

create_service() {
    echo 'ACTION=="add", KERNEL=="card*", SUBSYSTEM=="drm", TAG+="systemd"' > "$UDEV_RULE"
    cat << EOF > "$SERVICE_PATH"
[Unit]
Description=BC-250 40CU Unlock
After=dev-dri-card0.device
Wants=dev-dri-card0.device
[Service]
Type=oneshot
ExecStart=$WORKER_SCRIPT
RemainAfterExit=yes
[Install]
WantedBy=graphical.target
EOF
    systemctl daemon-reload
}

# 3. Main
if ! grep -q "cachyos" /etc/os-release; then echo "CachyOS required."; exit 1; fi
show_disclaimer

echo "1) Install & Enable | 2) Uninstall | 3) Status & Logs"
read -p "Option: " opt
case $opt in
    1)
        if [ -f "$SERVICE_PATH" ]; then echo "Already installed."; else
            install_umr; create_worker; create_service
            # Added --no-block to prevent hanging
            systemctl enable --now $SERVICE_NAME --no-block
            echo "Service enabled and started in background."
        fi ;;
    2) [ -f "$SERVICE_PATH" ] && (systemctl disable --now $SERVICE_NAME; rm "$SERVICE_PATH" "$WORKER_SCRIPT" "$UDEV_RULE"; echo "Uninstalled.") || echo "Not installed." ;;
    3) [ -f "$SERVICE_PATH" ] && (systemctl status $SERVICE_NAME; journalctl -t bc250-unlock -n 20) || echo "Not installed." ;;
esac
