#!/usr/bin/env bash
#
# nitro-control uninstaller. Removes everything install.sh added and restores
# the stock acer_wmi driver.
#
# Usage:  sudo ./uninstall.sh [--purge] [--keep-config]
#   --purge        also dnf-remove akmod-acer-wmi-battery and python3-pyside6
#   --keep-config  keep /etc/nitro-control and ~/.config/nitro-control
#
set -uo pipefail

LOG="/var/log/nitro-control-install.log"
GROUP="nitro"
FACER_VER="0.2"
PURGE=0 KEEP_CONFIG=0

for a in "$@"; do
  case "$a" in
    --purge) PURGE=1 ;;
    --keep-config) KEEP_CONFIG=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -n 12; exit 0 ;;
    *) echo "unknown flag: $a"; exit 2 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0 $*"; exit 1; }
log() { echo "$(date '+%F %T') [uninstall] $*" | tee -a "$LOG"; }
target_user() { echo "${SUDO_USER:-$(logname 2>/dev/null || echo root)}"; }

log "starting uninstall (purge=$PURGE keep_config=$KEEP_CONFIG)"

# 1. stop services
systemctl disable --now nitro-control.service 2>/dev/null || true
rm -f /etc/systemd/system/nitro-control.service
rm -f /usr/lib/systemd/system-sleep/nitro-control
rm -f /etc/udev/rules.d/99-nitro-control.rules
systemctl daemon-reload 2>/dev/null || true
udevadm control --reload 2>/dev/null || true
log "removed systemd unit, sleep hook, udev rule"

# 2. stop any running GUI/daemon (by exact pids, never pattern-kill blindly)
for p in $(ps -C python3 -o pid=,args= 2>/dev/null | grep -E 'nitro-control-gui|/usr/local/bin/nitro-rgb-fx' | awk '{print $1}'); do
  kill "$p" 2>/dev/null || true
done

# 3a. EC backlight timeout: hand blanking back to the firmware before unloading,
#     otherwise the machine is left with no idle blanking at all.
rm -f /etc/modules-load.d/nitro-kbd-timeout.conf
[ -w /sys/kernel/nitro_kbd/backlight_timeout ] && \
  echo 30 > /sys/kernel/nitro_kbd/backlight_timeout 2>/dev/null || true
if command -v dkms >/dev/null && dkms status nitro-kbd-timeout/1.0 2>/dev/null | grep -q nitro-kbd; then
  dkms remove -m nitro-kbd-timeout -v 1.0 --all 2>/dev/null || true
  log "removed nitro-kbd-timeout DKMS module"
fi
rm -rf /usr/src/nitro-kbd-timeout-1.0
rmmod nitro_kbd_timeout 2>/dev/null || true

# 3. RGB: unload facer, remove DKMS, restore acer_wmi
rm -f /etc/modprobe.d/facer.conf /etc/modules-load.d/facer.conf
if command -v dkms >/dev/null && dkms status facer/"$FACER_VER" 2>/dev/null | grep -q facer; then
  dkms remove -m facer -v "$FACER_VER" --all 2>/dev/null || true
  log "removed facer DKMS module"
fi
rm -rf "/usr/src/facer-$FACER_VER"
rmmod facer 2>/dev/null || true
modprobe acer_wmi 2>/dev/null || true
log "restored stock acer_wmi"

# 4. battery: remove persistence (leave the module/package unless --purge)
rm -f /etc/modprobe.d/acer-wmi-battery.conf /etc/modules-load.d/acer-wmi-battery.conf
log "removed battery persistence config"
if [ "$PURGE" -eq 1 ]; then
  dnf -y remove akmod-acer-wmi-battery 2>/dev/null || true
  dnf -y copr disable asan/acer-modules 2>/dev/null || true
  log "purged akmod-acer-wmi-battery + copr"
fi

# 5. binaries
rm -f /usr/local/bin/nitroctl /usr/local/bin/nitro-rgb-fx /usr/local/bin/nitro-control-gui
log "removed CLI/engine/GUI binaries"

# 6. desktop integration
rm -f /usr/share/applications/nitro-control.desktop
for s in 256 128 64 48; do rm -f "/usr/share/icons/hicolor/${s}x${s}/apps/nitro-control.png"; done
update-desktop-database /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
u="$(target_user)"; home="$(getent passwd "$u" | cut -d: -f6)"
[ -n "$home" ] && rm -f "$home/.config/autostart/nitro-control.desktop"
log "removed app launcher, icons, autostart"

# 7. config + group
if [ "$KEEP_CONFIG" -eq 0 ]; then
  rm -rf /etc/nitro-control
  [ -n "$home" ] && rm -rf "$home/.config/nitro-control"
  log "removed config"
fi
if [ "$PURGE" -eq 1 ]; then
  groupdel "$GROUP" 2>/dev/null || true
  dnf -y remove python3-pyside6 2>/dev/null || true
  log "purged group + pyside6"
fi

log "uninstall complete. A reboot is recommended to fully reset EC/module state."
echo "Done. If the battery limit was on, it will reset to stock behaviour after reboot."
