# osi-idle: OS-initiated CPU idle like Windows

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

**Experimental, under evaluation.** It targets the same s2idle resets as `sapd-lps0`: the trace shows the SoC dying
inside Standby-DRIPS, the firmware's deepest state.

Linux and Windows reach DRIPS on different firmware paths. Linux's ACPI LPI idle driver keeps PSCI in
platform-coordinated (PC) mode: every CPU asks for the deepest state and the firmware works out when a cluster or the
whole SoC can power down. Windows' PEP driver `nvpep.sys` (2.27) switches PSCI to **OS-initiated (OSI)** mode at load
instead. The firmware advertises OSI (`PSCI_FEATURES(CPU_SUSPEND)` = 0x1) and accepts it. In OSI mode only the last
CPU of a cluster or of the package asks for that domain's state, adding the domain's `_LPI` LevelID. `nvpep.sys` also
calls `\_SB.PEPD.ELST(1)` and writes two SYSRAM words (0x130000 = 0x89736C41, 0x12FF00 = "OSI").

`n1x_osi_idle` does the same steps, then replaces the ACPI idle driver with an equivalent one. That driver tracks
the last idle CPU per cluster (CPUs 0-9, 10-19) and for the package. The idle entry itself is the kernel's own
(`psci_cpu_suspend_enter()` with the same flags as the ACPI driver). At runtime it goes down to package power-down.
Standby-DRIPS is used only from s2idle: the last CPU asks for 0x020100F0 + LevelID 0x2000. A CPU that loses the last-CPU race (DENIED) goes straight to
core power-down instead of waking up.

With the screen on, the firmware turns most package requests into cluster power-down: over 30 s the driver got
4,863 package entries accepted, the firmware counted 151 real package (PGKLL) entries and ~10,500 cluster ones.
That is the firmware's call (devices still active), not a driver error.

Status: runtime idle is stable (cluster and package states entered thousands of times per minute, a few denials from
races, no invalid requests, idle power unchanged). The first s2idle tests reached DRIPS and resumed. The firmware
residency counter matched the kernel's sleep time to the millisecond. Whether the resets are gone needs a few dozen
lid-close suspends.

The firmware refuses to switch from OSI back to PC mode. After an unload the CPUs use only WFI until the next boot.

```
cd osi-idle
sudo ./install.sh                         # DKMS, loads now and at every boot (enable=1 in /etc/modprobe.d)
cat /sys/module/n1x_osi_idle/parameters/stats   # CPU_SUSPEND: powered down, returned, DENIED, INVALID, other
grep . /sys/module/n1x_osi_idle/parameters/st_*  # the same per requested state (WFI, core, cluster, pkg-SL, pkg-LL, DRIPS)
sudo ./drips-count                        # firmware counters: DRIPS / package / cluster residency (ns) and usage
sudo ./uninstall.sh                       # reboot afterwards to get the ACPI idle driver back
```

Module parameters: `max_depth` (runtime, default 4: 1 core, 2 cluster, 3/4 package; 5 = DRIPS hangs the machine),
`osi=0` (keep PC mode, only for testing the driver), `pep=0` (skip `ELST` and the SYSRAM writes).
