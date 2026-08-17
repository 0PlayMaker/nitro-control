# Nitro Control

A **NitroSense replacement for Linux** — battery charge limiting, full 4-zone RGB
keyboard control with 35+ effects, and a native Qt tray app — for the **Acer Nitro
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
- ⌨️ **4-zone RGB keyboard** with **35+ software effects**: rainbow, plasma, aurora,
  ocean, fire, candle, comet, meteor, breathe, wave, twinkle, lightning, matrix,
  vaporwave, police, heartbeat, disco, sunrise, and more.
- 🎵 **Sound-reactive** effects — a 4-band **spectrum analyser**, a **bass + VU
  meter**, and a whole-keyboard **pulse** — with live controls for smoothing,
  noise gate, auto-levelling, resting glow, bar direction and meter source.
- 📊 **Live effects** that map CPU load, temperature and battery to the keyboard.
- 🎨 Per-effect custom colours, per-zone colours, brightness, speed, **intensity**,
  and an **idle-timeout** (lights fade out after inactivity, swell back on a
  keypress). Waking is **keyboard-only by default** — the touchpad won't light
  the keyboard up — switchable to keyboard + touchpad.
- 💾 **User presets** — save any tuned look (a modified candle, your own
  sound-reactive setup) by name, re-apply or delete it from the GUI or CLI.
- 🌙 **Firmware backlight blanking disabled.** The Acer EC blanks the keyboard 30 s
  after the last keypress and ignores anything written over WMI — which makes
  *any* Linux idle-timeout setting look broken. A small kernel module turns it off
  so the idle timer here is the one that decides. See [How it works](#how-it-works).
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
- **Backlight blanking**: `nitro_kbd_timeout`, a ~190-line module in
  [`kernel/`](kernel/), also via DKMS. The EC keeps its backlight idle timeout in
  a 48-bit word behind WMI GUID `61EF69EA-…`, laid out as
  `[47:40 timeout secs][39:32 aux][31:0 subcommand]`. It exposes it at
  `/sys/kernel/nitro_kbd/backlight_timeout` (seconds, `0` = off). The setting
  lives in EC RAM and resets to 30 s on every power cycle — which is why toggling
  it in Windows NitroSense does **not** carry over to Linux — so
  `nitroctl boot-apply` re-asserts it at boot and on resume. Writes preserve the
  neighbouring `aux` field rather than blanking the whole word.

---

## Install

```bash
git clone https://github.com/0PlayMaker/nitro-control.git
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
nitroctl status              # temps, battery, wear, capabilities, EC blanking
nitroctl battery on|off      # 80% charge limit
nitroctl kb ec-timeout 0     # firmware backlight blanking off (0-255 s)
nitro-rgb-fx list            # list effects
nitro-rgb-fx candle --color green --amplitude 2   # green, dramatic candle
nitro-rgb-fx zones --zone-colors red,gold,green,blue
nitro-rgb-fx set --wake-source any    # let the touchpad wake the lights too
```

**Sound-reactive** — `sound` (4-band spectrum), `soundbass` (bass + VU meter),
`soundwave` (whole-keyboard pulse):

```bash
nitro-rgb-fx sound --spec-reverse --gate 0.15 --smoothing 0.6
nitro-rgb-fx soundbass --bass-zone 4 --vu-source nobass --bass-gain 1.2
nitro-rgb-fx soundwave --glow 0.1 --adapt 0.5
```

`--gate` ignores room noise, `--smoothing` sets how slowly bars fall back,
`--adapt` is how fast auto-levelling tracks a change in volume, and `--glow`
keeps unlit zones dimly on instead of fully black.

**Presets** — save any tuned look and bring it back:

```bash
nitro-rgb-fx save-preset "movie night"   # snapshot the current settings
nitro-rgb-fx presets                     # list saved presets
nitro-rgb-fx preset "movie night"        # apply one
nitro-rgb-fx del-preset "movie night"
```

In the GUI, **Apply** commits the current look as the one that comes back after a
reboot; **My presets** saves and deletes named looks.

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
- **[Linuwu-Sense](https://github.com/0x7375646F/Linuwu-Sense)** — where the
  backlight-timeout WMI call was documented; `kernel/nitro_kbd_timeout.c` is an
  independent, much smaller implementation, but it would not exist without it.

These modules are fetched at install time, not bundled; they keep their own
licenses. Nitro Control's own code (`nitroctl`, `nitro-rgb-fx`, the GUI, installer)
is released under the **MIT License** — see [LICENSE](LICENSE). The one exception
is `kernel/nitro_kbd_timeout.c`, which is **GPL-2.0** as a Linux kernel module.

Made by **PlayMaker**.
