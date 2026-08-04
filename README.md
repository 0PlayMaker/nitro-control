# Nitro Control

A **NitroSense replacement for Linux** — battery charge limiting, full 4-zone RGB
keyboard control with 30+ effects, and a native Qt tray app — for the **Acer Nitro
AN517-41** (and close siblings) on Fedora / KDE Plasma.

Acer's control software is Windows-only. If you run Linux you lose the battery
health limit (which silently resets), the RGB keyboard, and the rest. Nitro Control
brings the important parts back, natively, and makes the battery limit **survive
reboots, suspend and kernel updates** — the thing that actually matters.

> Made by **PlayMaker**.

---

## Features

- 🔋 **Battery charge limit (80%)** that persists across cold boots, suspend/resume
  and kernel updates (re-asserted automatically — never silently resets again).
- ⌨️ **4-zone RGB keyboard** with **30+ software effects**: rainbow, plasma, aurora,
  ocean, fire, candle, comet, meteor, breathe, wave, twinkle, lightning, matrix,
  vaporwave, police, heartbeat, disco, sunrise, and more.
- 🎵 **Sound-reactive** effects (VU bar + pulse) that react to system audio.
- 📊 **Live effects** that map CPU load, temperature and battery to the keyboard.
- 🎨 Per-effect custom colours, brightness, speed, **intensity**, and an
  **idle-timeout** (lights off after inactivity, wake on keypress).
- 🖥️ A **capability-driven Qt GUI** with a **system-tray** icon, live dashboard
  (CPU/GPU temps, battery, wear), and one-click controls — hides features your
  machine doesn't support instead of showing dead buttons.
- 🛠️ A scriptable CLI: `nitroctl` (hardware control) and `nitro-rgb-fx` (effects).
- 🔒 No-password daily use (a `nitro` group owns the sysfs writes); no running the
  GUI as root.

Fan control is **intentionally not shipped** — see **[FANS.md](FANS.md)** for why,
and a safe roadmap for contributors.

---

## Supported hardware

| | |
|---|---|
| Model | **Acer Nitro AN517-41** (confirmed). Close siblings AN517-42 / AN515-45/55 may work with `--force`. |
| OS | Fedora (tested on 44), KDE Plasma |
| Secure Boot | Off, **or** on with an enrolled akmods MOK key (the installer guides you) |

Verified on: AN517-41, BIOS V1.08, Fedora 44, kernel 7.1.x, Ryzen 7 5800H + RTX 3080.

## How it works

- **Battery**: the [`acer-wmi-battery`](https://github.com/frederik-h/acer-wmi-battery)
  WMI driver (via the [`asan/acer-modules`](https://copr.fedorainfracloud.org/coprs/asan/acer-modules/)
  Copr as an akmod, so it rebuilds on kernel updates). A module option + systemd
  boot/resume unit re-assert the limit from `/etc/nitro-control/config.json`.
- **RGB**: the [`facer`](https://github.com/JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module)
  kernel module (installed via DKMS), driven by a small persistent daemon that
  renders effects frame-by-frame over `/dev/acer-gkbbl-static-0`.

---

## Install

```bash
git clone https://github.com/PlayMaker/nitro-control.git
cd nitro-control
sudo ./install.sh          # battery + RGB + GUI (default)
```

Then **log out and back in** once (so your user joins the `nitro` and `input`
groups). Launch **Nitro Control** from your app menu, or run `nitro-control-gui`.

### Options

```
sudo ./install.sh --check          # dry run: show what it would do
sudo ./install.sh --battery-only   # just the battery limit
sudo ./install.sh --with-rgb       # add RGB
sudo ./install.sh --gui            # add the GUI + tray + launcher
sudo ./install.sh --all            # everything (battery+RGB+GUI)
sudo ./install.sh --force          # run on a close sibling model
```

The installer is **idempotent** (safe to re-run), logs to
`/var/log/nitro-control-install.log`, detects Secure Boot, and prints a summary
plus the exact rollback command.

## Usage

**GUI** — tray icon → dashboard, battery toggle, keyboard effects.

**CLI:**
```bash
nitroctl status              # temps, battery, wear, capabilities
nitroctl battery on|off      # 80% charge limit
nitro-rgb-fx list            # list effects
nitro-rgb-fx candle --color green --amplitude 2   # green, dramatic candle
nitro-rgb-fx sound           # react to system audio
```

## Uninstall

```bash
sudo ./uninstall.sh              # remove everything, restore stock acer_wmi
sudo ./uninstall.sh --purge      # also remove packages + the nitro group
```

---

## Credits & licensing

Nitro Control is glue + a GUI + effects on top of two community kernel modules —
huge thanks to their authors:

- **facer** — 4-zone RGB — by [JafarAkhondali](https://github.com/JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module) (GPL-2.0)
- **acer-wmi-battery** — charge limit — by [frederik-h](https://github.com/frederik-h/acer-wmi-battery) (GPL-2.0)
- **asan/acer-modules** Copr — packaging of the battery akmod

These modules are fetched at install time, not bundled; they keep their own
licenses. Nitro Control's own code (`nitroctl`, `nitro-rgb-fx`, the GUI, installer)
is released under the **MIT License** — see [LICENSE](LICENSE).

Made by **PlayMaker**.
