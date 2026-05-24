#!/bin/bash
# BC-250 40CU Unlock Manager for CachyOS

if [[ $EUID -ne 0 ]]; then echo "Please run as root"; exit 1; fi

# Disclaimer (Original)
show_disclaimer() {
    echo "======================================================================"
    echo "TL;DR: WHAT THIS SCRIPT DOES"
    echo "======================================================================"
    echo "This script unlocks hidden Compute Units (CUs) on your BC-250 GPU."
    echo "It uses 'umr' to write to specific hardware registers that override"
    echo "the GPU's default power-gating configuration."
    echo ""
    echo "======================================================================"
    echo "DISCLAIMER AND LIABILITY WAIVER"
    echo "======================================================================"
    echo "This script modifies low-level GPU registers to unlock additional CUs."
    echo "THERE IS NO WARRANTY, EXPRESS OR IMPLIED. USE AT YOUR OWN RISK."
    echo "Possible side effects include:"
    echo " - System instability or kernel panics."
    echo " - Graphical corruption or visual artifacts."
    echo " - Potential hardware damage (though rare)."
    echo ""
    echo "I take no responsibility for any damage, data loss, or issues caused"
    echo "by the use of this tool. By continuing, you acknowledge these risks."
    echo "======================================================================"
    read -p "Do you accept these terms and wish to proceed? (y/n): " choice
    if [[ "$choice" != "y" ]]; then exit 1; fi
}

# Paths
SERVICE_NAME="bc250-unlock.service"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
WORKER_SCRIPT="/usr/local/bin/bc250-apply-unlock.sh"
UDEV_RULE="/etc/udev/rules.d/99-systemd-dri-devices.rules"

# Logic Functions
install_umr() {
    local AUR=$(command -v paru || command -v yay)
    if ! pacman -Qi umr &> /dev/null; then $AUR -S --needed --noconfirm umr; fi
}

unlock_manual() {
    echo "Applying temporary unlock..."
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
    echo "Done. Test your GPU now. A reboot will reset these settings."
}

create_service() {
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

# Main Execution
show_disclaimer
echo "1) Test Unlock (Temporary)"
echo "2) Install Permanent Service"
echo "3) Uninstall"
echo "4) Status & Logs"
read -p "Option: " opt
case $opt in
    1) install_umr; unlock_manual ;;
    2) install_umr; create_service; systemctl enable --now $SERVICE_NAME; echo "Permanent service enabled." ;;
    3) systemctl disable --now $SERVICE_NAME; rm -f "$SERVICE_PATH" "$WORKER_SCRIPT" "$UDEV_RULE"; echo "Uninstalled." ;;
    4)
        if [ -f "$SERVICE_PATH" ]; then
            systemctl status $SERVICE_NAME;
            journalctl -t bc250-unlock -n 20;
        else echo "Service not installed."; fi ;;
esac
