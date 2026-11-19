# thermal: power and skin temperature control

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

Linux does nothing here by default: none of the ACPI thermal zones has a trip point, and under a sustained CPU
load the SoC draws 64-68 W with Tj pinned at the firmware's ~98 C. On Windows the thermal policy (MPTF) keeps
the *skin* temperature (SAM sensor VTS1) at 45 C by lowering the SoC's sustained power limit: 55 W on AC,
42.5 W on battery in the default mode. This directory does the same with the knobs Linux has; its default
profile allows more than Windows (80 W, skin 52 C), the `standard` profile uses Windows' numbers.

- **`n1x-thermald`** (systemd service, python3 standard library only): every 2 s it compares the averaged SoC
  power with a budget and walks a ladder of limits, CPU first and GPU last (the GPU running local LLMs is what
  this machine is used for): CPU `scaling_max_freq` 100 / 80 / 60 / 40 % of each cluster's maximum, then the GPU
  max clock (`nvidia-smi -lgc`) 2400 / 2100 / 1800 / 1400 / 1000 MHz. The GPU is always capped at 2400 MHz:
  measured with an LLM decode, that costs no speed and saves ~15 W against the 2515 MHz boost (1800 MHz: -5 %
  decode, -6 W; 1400 MHz: -11 %, -10 W). A PI loop on the skin temperature (VTS1 = `surface_thermal` temp9;
  secondary = temp12) lowers the budget.
- **Profiles** (`/etc/n1x-thermald.conf`, re-read live; `sudo n1x-thermald --profile NAME` writes it):

  | profile | budget AC / DC | skin | secondary | HOT | suspend | power off |
  |---|---|---|---|---|---|---|
  | `performance` (default) | 80 / 80 W | 52 C | 58 C | 61 C | 63 C | 65 C |
  | `standard` (Windows "recommended") | 55 / 42.5 W | 45 C | 51 C | 55.5 C | 57 C | 59 C |

  HOT (secondary skin, or battery RTS5 = temp5 >= 62 C) pins the CPUs to their minimum and the GPU to 1000 MHz;
  "suspend" suspends after three samples; battery >= 64 C or "power off" powers off. The battery limits are
  Windows' and the same in both profiles. Without the SSAM sensors it runs on the power budget alone.
- **Tj safety net**: an extra ACPI thermal zone `\_TZ.NXTJ` (`n1x-thermal.asl`) on the SoC Tj, passive at
  100 C on all 20 CPUs, critical at 105 C. `n1x-thermal-ssdt.service` loads it through `acpi_configfs` at boot.

Two of the ACPI "thermal zones" are not temperatures: `\_TZ.PSOC` (thermal_zone2) and `\_TZ.PSYS`
(thermal_zone1) report averaged SoC and system power in mW, which is why they read "2005 C" and similar.
`n1x-thermald` uses PSOC as its power feedback.

Measured with a 19-thread load (Windows' numbers): SoC power 65 W -> 52 W, Tj 98 C -> 94 C, and back to full speed in steps once
the load stops.

```
cd thermal
sudo ./install.sh          # includes a selftest that the frequency cap really slows a CPU
./n1x-thermald --dry-run   # print decisions only, any user
cat /run/n1x-thermald/status.json
sudo n1x-thermald --profile standard   # Windows values; no restart needed
```

The fan is left to the EC (or to teo-casares' fan daemon); `n1x-thermald` does not touch it.
