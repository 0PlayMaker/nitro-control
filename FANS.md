# Fan & thermal control on the Acer Nitro AN517-41 — why it's not shipped (yet)

**Status: intentionally NOT enabled.** This document exists so the door stays open.
If you have this laptop and want to help make fan control real, start here.

Battery limit and RGB are solved and shipped. Fan control is deliberately left out
because on *this specific machine* every available method is either impossible,
fragile, or dangerous. This is not laziness — it's a safety decision. Below is
exactly what we found, why each path is risky, and what a good solution would look
like.

---

## What we verified on the real machine (2026-08-04)

Fedora 44, kernel 7.1.4, `Nitro AN517-41`, BIOS V1.08, AMD Ryzen 7 5800H + RTX 3080.

- **No `platform_profile`.** `/sys/firmware/acpi/platform_profile` does **not exist**.
  So the clean, standard Linux knob for "quiet / balanced / performance" thermal
  profiles is simply not exposed by this firmware. `power-profiles-daemon` therefore
  can't drive the fans either.
- **No mainline fan control.** Mainline `acer-wmi` only wires up hwmon PWM fan control
  for **Predator** models (PH16-72, PT14-51). There is no Nitro quirk at all, and none
  for the AMD 2021 chassis specifically.
- **Sensors read fine.** `k10temp` (CPU), `amdgpu` (iGPU), `nvidia-smi` (dGPU), and the
  ACPI thermal zones all report temperatures. **Reading is safe and already used** by
  the GUI dashboard and the `temp`/`cpu` RGB effects. It's *writing* fan speed that's
  the problem.

---

## The three ways to get fan control, and why each is risky here

### 1. Linuwu-Sense (WMI) — conflicts with our RGB, and doesn't list this model

[`0x7375646F/Linuwu-Sense`](https://github.com/0x7375646F/Linuwu-Sense) (and the
`PXDiv/Div-Linuwu-Sense` fork with the DAMX GUI) is the most capable Nitro/Predator
WMI driver. Problems:

- **It REPLACES `acer_wmi`.** So does the `facer` module we use for the RGB keyboard.
  **Two forks of `acer_wmi` cannot both own the WMI interface at once.** Running
  Linuwu-Sense would mean giving up the working RGB, or vice-versa. Pick one owner.
- **AN517-41 is not in its supported list.** DAMX targets 2022-and-newer WMI Nitros.
  You would have to **hand-add a DMI quirk** (`.nitro_sense = 1`, `.four_zone_kb = 1`,
  `.cpu_fans = 1`, `.gpu_fans = 1`) for the `Nitro AN517-41` string and rebuild.
- **Sibling results are mixed and discouraging.** On the AN515-54 it gave temps/RPM and
  manual fan control but `platform_profile` returned an **I/O error**; on the AN515-57
  the `nitro_sense` sysfs directory **never appeared at all**. The project has also
  broken on new kernels before (a `platform_profile_notify` signature change).

**Verdict:** medium-to-high risk, and it costs us the RGB. Not worth it as the default.

### 2. NBFC-Linux (direct EC register writes) — highest risk

[NBFC-Linux](https://github.com/nbfc-linux/nbfc-linux) writes **embedded-controller
registers directly** from a per-model JSON config. There is an `Acer Nitro AN515-45`
config (the AMD chassis sibling), which is the closest starting point.

- **A wrong register write can stop the fans** while the CPU/GPU keep pulling 100+ W.
  That is a genuine hardware-damage / thermal-shutdown path.
- The AN515-45 config is a *sibling*, not this exact board. EC register maps are not
  guaranteed identical across models.
- It does **not** replace `acer_wmi`, so it *could* coexist with our RGB — that's its
  one advantage. But it is the most dangerous option and must never run unattended.

**Verdict:** last resort only, with a human watching `sensors` live and an immediate
`sudo nbfc stop` ready.

### 3. Do nothing — let the firmware manage fans

This is the current shipped behaviour. The EC's built-in fan curve runs the fans.
It's conservative but **safe**, and it's what the machine does under Windows when
NitroSense isn't actively overriding it. For most users this is fine.

---

## Hard safety requirements for ANY fan code (non-negotiable)

If fan control is ever added to this project, the code MUST:

1. **Clamp manual speed to a floor (30%).** In Linuwu-Sense `fan_speed=0` means *auto*
   and `100` means max; the GUI must never be able to quietly park the fans near-off.
2. **Always show a one-click "Back to Auto"** button — no confirmation dialog.
3. **Run a temperature watchdog.** If CPU or GPU exceeds ~90 °C, force auto and notify
   the user. The watchdog must be running *before* any manual value is ever applied.
4. **Revert to auto on GUI exit, crash, and logout** (`ExecStop` in the service).
5. **Never apply a manual fan setting at boot** before the watchdog is alive.
6. Fan state is **not persistent** — a reboot returns control to the EC. Good.

---

## What a *good* solution would look like (contributor roadmap)

In rough order of preference:

1. **Best: mainline `acer-wmi` hwmon support for the Nitro.** The right long-term fix is
   a kernel patch adding a DMI quirk for the AMD Nitro chassis to the mainline
   `acer-wmi` fan/hwmon code (the same mechanism Predators already use). Upstreamed,
   signed-by-distro, no out-of-tree module. This is where energy should go.
2. **Coexistence-first WMI probe.** Before anything, someone with this exact board should
   build Linuwu-Sense with an AN517-41 quirk **in isolation** (RGB temporarily removed)
   and check whether `.../nitro_sense/fan_speed` actually appears and whether
   `platform_profile` throws the I/O error the siblings hit. If the sysfs nodes never
   appear (like the AN515-57), **stop** — this model just can't do it via WMI.
3. **If and only if WMI works**, decide the keyboard-vs-fans ownership question: either
   (a) extend `facer` to also expose fan control (one module owns everything — ideal), or
   (b) accept losing `facer` RGB in favour of Linuwu-Sense's own `four_zone_kb` +
   `battery_limiter` (then Phase 3/4 collapse into Linuwu-Sense). Keep our proven
   `acer-wmi-battery` + `facer` stack as the fallback.
4. **NBFC only as a mapped, tested, watchdog-guarded last resort**, and never as the
   default install path.

## How to safely experiment (if you insist)

```bash
# 1. Watch temps LIVE in one terminal the whole time:
watch -n1 sensors

# 2. In another, try the WMI route in isolation (expect to lose RGB temporarily).
#    Add a DMI quirk for "Nitro AN517-41" to Linuwu-Sense, rebuild, load it,
#    and check whether the control surface even appears:
ls /sys/module/linuwu_sense/drivers/*/**/nitro_sense/ 2>/dev/null
cat /sys/firmware/acpi/platform_profile 2>/dev/null   # watch for I/O error

# 3. If nothing appears, revert immediately:
sudo rmmod linuwu_sense ; sudo modprobe facer      # restore RGB
```

**Keep the fans on auto unless you are actively watching temperatures.** No RGB effect
is worth a cooked GPU.

---

*This file is part of the nitro-control project. If you get fan control working on an
AN517-41, please open a PR updating this document with exactly what you did.*
