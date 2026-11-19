# gpu-power: NVIDIA power management notes

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

Notes from looking into why some N1X laptops hold the GPU at ~750 MHz on AC while this one does not. Measured
with driver 620.70.06 (open kernel modules), linux-omarchy 7.3. This machine is back on 615.78.08 because 620.70.06
broke s2idle (`nv_pmops_suspend` returned `NV_ERR_NOT_SUPPORTED`); `ratedtdp-probe` reads the same on 615. Nothing
here is needed to run the machine.

- **The firmware already caps the SoC.** With the CPU and GPU both under full load, the averaged SoC power (ACPI
  `\_TZ.PSOC`) settles at 80.0 W and the GPU lowers its own clock (2132 → 1976 MHz). What the OS still has to do
  is keep the skin temperature down, which [`thermal/`](../thermal/) does.
- **nvidia-powerd (Dynamic Boost) does not help here.** The firmware answers the NVPCF `_DSM` only at revision
  0x300. The 620 daemon reads the 3.x config but creates no worker ("No Worker Running!"); its worker factory
  creates workers only on the 1.x/2.x path. Made to see 2.x data (`nvpcf-shim/`), QBoost runs, but it reacts only
  to NVPCF events from the platform firmware, its GPU limit write (private control `0x2080e634`) is answered
  `NOT_SUPPORTED`, and its CPU limit goes to an SBIOS `_DSM`.
- **RATED_TDP is what sets the ~750 MHz floor, as far as I can tell.** Setting `RATED_TDP` client GLOBAL to
  FORCE_LIMIT drops the GPU under load from 2379 MHz / 49.6 W to 741 MHz / 12.5 W, and DEFAULT restores it.
  `ctrl2080perf.h` says the RM client, which has the highest priority, asks for FORCE_LIMIT "when no power
  controllers are active". On this machine every client, the RM client included, reads DEFAULT.
- The NVPCF 3.0 init table (subfunction 1) is AES-encrypted. The key ships inside the driver's user-space
  daemon, so the table can be read; neither the key nor a decryptor is published here.

## ratedtdp-probe

Details: [ratedtdp-probe/README.md](ratedtdp-probe/README.md).

Read-only. Prints the RATED_TDP request of each arbitration client, using the RM handles of the program it is
preloaded into. No root needed.

```
cd gpu-power/ratedtdp-probe && make
LD_PRELOAD=$PWD/ratedtdp-probe.so nvidia-smi -L
```

```
RATED_TDP RM      rc=0 status=0 action=0 DEFAULT vpstate=0
RATED_TDP WAR     rc=0 status=0 action=0 DEFAULT vpstate=0
RATED_TDP GLOBAL  rc=0 status=0 action=0 DEFAULT vpstate=0
...
```

## nvpcf-shim (experiment)

An `LD_PRELOAD` shim that lets nvidia-powerd 620 start its QBoost worker on N1X: it hides NVPCF 3.x, answers the
2.x queries, names a TGP power policy, emulates the x86 RAPL MSRs the daemon reads, reports the AC state from
`ADP1`, and logs every RM control so the daemon's control targets can be seen. It is for study, not for daily use.
Build with `make` (it needs the SDK headers of the matching open-gpu-kernel-modules), then run the daemon with
`LD_PRELOAD` and the `SHIM_*` variables described at the top of the file.
