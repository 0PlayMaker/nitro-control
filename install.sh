#!/usr/bin/env bash
#
# nitro-control installer — NitroSense replacement for Acer Nitro on Fedora/KDE.
# Reproduces battery charge-limit + 4-zone RGB + the nitroctl CLI and Qt GUI.
#
# Usage:  sudo ./install.sh [flags]
#   --all           battery + RGB + GUI (default if no component flag given)
#   --battery-only  just the battery charge limit (safest, minimal)
#   --with-rgb      include the RGB keyboard
#   --gui           include the Qt GUI + tray + app launcher
#   --with-fans     experimental fan control — NOT supported here (see FANS.md)
#   --check         dry run: print what would happen, change nothing
#   --force         skip the model-match abort (for AN517-42/AN515-55 siblings)
#   --verbose       shell trace
#   -h | --help
#
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
LOG="/var/log/nitro-control-install.log"
EXPECTED_MODEL="Nitro AN517-41"
FACER_REPO="https://github.com/JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module.git"
FACER_VER="0.2"
COPR="asan/acer-modules"
GROUP="nitro"
HEALTH_MODE="/sys/bus/wmi/drivers/acer-wmi-battery/health_mode"

DO_BATTERY=0 DO_RGB=0 DO_GUI=0 DO_FANS=0 CHECK=0 FORCE=0
declare -a INSTALLED=() SKIPPED=() NOTES=()

# ---------- arg parse ----------
comp_flag=0
for a in "$@"; do
  case "$a" in
    --all) DO_BATTERY=1; DO_RGB=1; DO_GUI=1; comp_flag=1 ;;
    --battery-only) DO_BATTERY=1; comp_flag=1 ;;
    --with-rgb) DO_RGB=1; comp_flag=1 ;;
    --gui) DO_GUI=1; comp_flag=1 ;;
    --with-fans) DO_FANS=1; comp_flag=1 ;;
    --check) CHECK=1 ;;
    --force) FORCE=1 ;;
    --verbose) set -x ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -n 20; exit 0 ;;
    *) echo "unknown flag: $a (try --help)"; exit 2 ;;
  esac
done
# Default when no component flag: full install (battery + RGB + GUI).
if [ "$comp_flag" -eq 0 ]; then DO_BATTERY=1; DO_RGB=1; DO_GUI=1; fi

# ---------- helpers ----------
log()  { echo "$(date '+%F %T') $*" | tee -a "$LOG" ; }
info() { log "[*] $*" ; }
warn() { log "[!] $*" ; }
run()  { if [ "$CHECK" -eq 1 ]; then log "[dry-run] $*"; else log "+ $*"; "$@"; fi ; }
add_installed() { INSTALLED+=("$1"); }
add_skipped()   { SKIPPED+=("$1"); }

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This installer must run as root:  sudo $0 $*"; exit 1
  fi
}

target_user() { echo "${SUDO_USER:-$(logname 2>/dev/null || echo root)}"; }

# ---------- preflight ----------
need_root "$@"
: > /dev/null  # ensure we can write log dir
touch "$LOG" 2>/dev/null || { echo "cannot write $LOG"; exit 1; }
info "nitro-control install starting (battery=$DO_BATTERY rgb=$DO_RGB gui=$DO_GUI fans=$DO_FANS check=$CHECK)"

MODEL="$(dmidecode -s system-product-name 2>/dev/null || echo unknown)"
info "detected model: $MODEL"
if [ "$MODEL" != "$EXPECTED_MODEL" ]; then
  if [ "$FORCE" -eq 1 ]; then
    warn "model '$MODEL' != '$EXPECTED_MODEL' but --force given; continuing"
    NOTES+=("Ran on '$MODEL' via --force; verify RGB/battery actually bind.")
  else
    warn "model '$MODEL' does not match '$EXPECTED_MODEL'. Aborting."
    warn "If this is a close sibling (AN517-42 / AN515-55), re-run with --force."
    exit 3
  fi
fi

# Secure Boot gate (only matters when we build out-of-tree modules)
SB="$(mokutil --sb-state 2>/dev/null | tr -d '\n' || echo unknown)"
info "secure boot: $SB"
if echo "$SB" | grep -qi enabled && { [ "$DO_BATTERY" -eq 1 ] || [ "$DO_RGB" -eq 1 ]; }; then
  if ! mokutil --list-enrolled 2>/dev/null | grep -qi akmods; then
    warn "Secure Boot is ENABLED and no akmods MOK is enrolled."
    warn "Out-of-tree modules will fail to load until you enroll a signing key:"
    warn "  sudo dnf install -y akmods kmodtool mokutil openssl kernel-devel gcc make dkms"
    warn "  sudo kmodgenca -a && sudo mokutil --import /etc/pki/akmods/certs/public_key.der"
    warn "  reboot -> MOK Manager -> Enroll MOK, then re-run this installer."
    [ "$CHECK" -eq 1 ] || exit 4
  fi
fi

# ---------- core (always) : group, config, CLI, engine, units, udev ----------
install_core() {
  info "== core =="
  if getent group "$GROUP" >/dev/null; then add_skipped "group $GROUP"; else
    run groupadd "$GROUP"; add_installed "group $GROUP"; fi
  local u; u="$(target_user)"
  if id -nG "$u" 2>/dev/null | grep -qw "$GROUP"; then add_skipped "user $u in $GROUP"; else
    run usermod -aG "$GROUP" "$u"; add_installed "added $u to $GROUP"
    NOTES+=("Log out/in (or reboot) so '$u' picks up the '$GROUP' group.")
  fi
  # 'input' group lets the RGB idle-timeout detect keypresses (wake-on-key).
  if id -nG "$u" 2>/dev/null | grep -qw input; then add_skipped "user $u in input"; else
    run usermod -aG input "$u"; add_installed "added $u to input (RGB idle timeout)"
  fi

  run install -m 0755 "$REPO/bin/nitroctl"           /usr/local/bin/nitroctl
  run install -m 0755 "$REPO/bin/nitro-rgb-fx"       /usr/local/bin/nitro-rgb-fx
  add_installed "nitroctl + nitro-rgb-fx -> /usr/local/bin"

  run mkdir -p /etc/nitro-control
  if [ -f /etc/nitro-control/config.json ]; then add_skipped "config.json (kept existing)"; else
    run install -m 0664 "$REPO/config/config.json" /etc/nitro-control/config.json
    add_installed "/etc/nitro-control/config.json"; fi

  run install -m 0644 "$REPO/systemd/nitro-control.service" /etc/systemd/system/nitro-control.service
  run install -m 0755 "$REPO/systemd/nitro-control-sleep.sh" /usr/lib/systemd/system-sleep/nitro-control
  run install -m 0644 "$REPO/udev/99-nitro-control.rules" /etc/udev/rules.d/99-nitro-control.rules
  run systemctl daemon-reload
  run udevadm control --reload
  add_installed "systemd unit + sleep hook + udev rule"
}

# ---------- battery ----------
install_battery() {
  info "== battery =="
  if [ -e /sys/class/power_supply/BAT*/charge_control_end_threshold ] 2>/dev/null; then
    NOTES+=("Kernel already exposes charge_control_end_threshold — native support present; module may be optional.")
  fi
  if [ ! -e "$HEALTH_MODE" ] && ! rpm -q akmod-acer-wmi-battery >/dev/null 2>&1; then
    run dnf -y copr enable "$COPR"
    run dnf -y install akmod-acer-wmi-battery
    run akmods --kernels "$(uname -r)" --force
    add_installed "akmod-acer-wmi-battery (Copr $COPR)"
  else
    add_skipped "acer-wmi-battery (already present)"
  fi
  run bash -c "echo 'options acer-wmi-battery enable_health_mode=1' > /etc/modprobe.d/acer-wmi-battery.conf"
  run bash -c "echo 'acer-wmi-battery' > /etc/modules-load.d/acer-wmi-battery.conf"
  [ "$CHECK" -eq 1 ] || modprobe acer-wmi-battery 2>/dev/null || true
  add_installed "battery persistence (modprobe.d + modules-load.d)"
}

# ---------- rgb (facer via DKMS) ----------
install_rgb() {
  info "== rgb keyboard =="
  run install -m 0755 "$REPO/bin/nitro-rgb-fx" /usr/local/bin/nitro-rgb-fx
  if dkms status facer/"$FACER_VER" 2>/dev/null | grep -q installed; then
    add_skipped "facer DKMS module (already installed)"
  else
    local build; build="$(mktemp -d)"
    run git clone --depth 1 "$FACER_REPO" "$build/facer"
    run rm -rf "/usr/src/facer-$FACER_VER"
    run mkdir -p "/usr/src/facer-$FACER_VER"
    run cp -r "$build/facer/Makefile" "$build/facer/src" "/usr/src/facer-$FACER_VER/"
    if [ "$CHECK" -eq 0 ]; then
      cat > "/usr/src/facer-$FACER_VER/dkms.conf" <<EOF
PACKAGE_NAME="facer"
PACKAGE_VERSION="$FACER_VER"
MAKE[0]="make KERNELDIR=/lib/modules/\${kernelver}/build"
CLEAN="make clean"
BUILT_MODULE_NAME[0]="facer"
BUILT_MODULE_LOCATION[0]="src"
DEST_MODULE_LOCATION[0]="/kernel/drivers/acpi"
AUTOINSTALL="yes"
EOF
    fi
    run dkms add -m facer -v "$FACER_VER"
    run dkms build -m facer -v "$FACER_VER"
    run dkms install -m facer -v "$FACER_VER"
    run rm -rf "$build"
    add_installed "facer RGB module (DKMS $FACER_VER)"
  fi
  run bash -c "printf '# facer is a superset fork of acer_wmi (adds RGB)\nblacklist acer_wmi\n' > /etc/modprobe.d/facer.conf"
  run bash -c "echo 'facer' > /etc/modules-load.d/facer.conf"
  if [ "$CHECK" -eq 0 ]; then
    rmmod acer_wmi 2>/dev/null || true
    modprobe facer 2>/dev/null || true
  fi
  add_installed "facer boot wiring (blacklist acer_wmi + modules-load)"
}

# ---------- gui ----------
install_gui() {
  info "== gui =="
  if ! python3 -c "import PySide6" 2>/dev/null; then
    run dnf -y install python3-pyside6
    add_installed "python3-pyside6"
  else
    add_skipped "python3-pyside6 (present)"
  fi
  run install -m 0755 "$REPO/bin/nitro-control-gui" /usr/local/bin/nitro-control-gui
  for s in 256 128 64 48; do
    run install -Dm0644 "$REPO/desktop/icons/nitro-control-$s.png" \
        "/usr/share/icons/hicolor/${s}x${s}/apps/nitro-control.png"
  done
  run install -Dm0644 "$REPO/desktop/nitro-control.desktop" /usr/share/applications/nitro-control.desktop
  [ "$CHECK" -eq 1 ] || update-desktop-database /usr/share/applications 2>/dev/null || true
  [ "$CHECK" -eq 1 ] || gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
  # per-user autostart
  local u home; u="$(target_user)"; home="$(getent passwd "$u" | cut -d: -f6)"
  if [ -n "$home" ] && [ "$CHECK" -eq 0 ]; then
    install -Dm0644 "$REPO/desktop/nitro-control-autostart.desktop" "$home/.config/autostart/nitro-control.desktop"
    chown "$u":"$u" "$home/.config/autostart/nitro-control.desktop"
  fi
  add_installed "GUI + app launcher + icons + autostart"
}

# ---------- fans ----------
handle_fans() {
  warn "Fan control is NOT supported on this model — see FANS.md. Skipping."
  NOTES+=("Fan control intentionally skipped (see FANS.md). No fan code installed.")
}

# ---------- run ----------
install_core
[ "$DO_BATTERY" -eq 1 ] && install_battery || true
[ "$DO_RGB" -eq 1 ] && install_rgb || true
[ "$DO_GUI" -eq 1 ] && install_gui || true
[ "$DO_FANS" -eq 1 ] && handle_fans || true

# Enable boot service + fix perms (after modules are in place)
if [ "$CHECK" -eq 0 ]; then
  systemctl enable --now nitro-control.service 2>/dev/null || true
  nitroctl fix-perms 2>/dev/null || true
fi

# ---------- summary ----------
echo | tee -a "$LOG"
info "================ SUMMARY ================"
info "Installed:"; for i in "${INSTALLED[@]:-}"; do [ -n "$i" ] && info "   + $i"; done
info "Skipped (already present):"; for s in "${SKIPPED[@]:-}"; do [ -n "$s" ] && info "   - $s"; done
if [ "${#NOTES[@]}" -gt 0 ]; then
  info "Notes:"; for n in "${NOTES[@]}"; do info "   ! $n"; done
fi
info "Log: $LOG"
info "Roll back with:  sudo $REPO/uninstall.sh"
if [ "$CHECK" -eq 1 ]; then
  info "(dry run — nothing was changed)"
else
  info "Done. Launch 'Nitro Control' from the menu, or run: nitro-control-gui"
fi
