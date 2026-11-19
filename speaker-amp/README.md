# speaker-amp: Windows amp DSP firmware and tuning

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

The speakers sound flat and thin on Linux compared with Windows. The two RT1320 amplifiers have a DSP, and on
Windows the Realtek driver loads it with firmware and a Surface-specific tuning (EQ, speaker protection, the
left/right voicing). Linux runs the amps without it. The kernel's `rt1320-sdw` driver can load both
(`realtek/rt1320/rt1320_<vendor>_<product>_<sku>.dat` and `rt1320_RAE_...dat`), but no such files exist for
this machine, and Microsoft/Realtek don't ship them for Linux.

This directory builds them **from your own Windows install** and changes the driver so they load by themselves:

- `extract.py` reads `RTKDAT_10EC.dat` from the Realtek SDCA driver package in the mounted Windows partition. That
  file is a password-protected ZIP, obfuscated with a byte-chained XOR; the key and the password are found in your
  copy of `RtkSdcaXu.sys`. For this machine (SUBSYS `0x308E10EC`) the driver uses the `Nocturne_A` set:
  four DSP code images, two DSP parameter blocks, and one RAE tuning per amp (`FWFiles_20` for SoundWire unique
  ID 0, `FWFiles_22` for ID 2). **No Realtek or Microsoft data is in this repository**, and the generated files stay
  in `/usr/lib/firmware/updates/realtek/rt1320/`.
- `module/` is `rt1320-sdw` from Linux v7.3 with `surface-rt1320.patch` (DKMS, `BUILD_EXCLUSIVE_KERNEL` `^7\.3\.`):
  - starts the DSP the way Realtek's Windows driver does for this machine (found by static analysis of
    `RtkSdcaXu.sys`): hold the amp, fully reset the DSP (back to ROM, clock and core resets pulsed; skipped on a
    freshly powered amp, `0xd613` = 0), download the
    code, send the AFX parameter blocks with their header last, run, wait for the `0x3fc2bfc4` handshake, then the
    post-start setup. The stock Linux sequence starts the DSP only if it was left in a clean state; the amps keep
    power across reboots and even power-off, so after a SoC crash in s2idle it never came up again;
  - keeps mixer writes away from the amps while that runs: UCM enabling the speakers when PipeWire starts made the
    start fail;
  - loads the DSP firmware and the RAE tuning 10 s after the card is up (after the boot-time `n1x-sdw-settle` bus
    reset; the `alsactl` restore of `DSP FW Update` goes through the same delayed path), one amp at a time, and
    again after resume (upstream only reloads the firmware, so the tuning was lost);
  - a per-amp RAE file (`..._<unique id>.dat`), since left and right differ;
  - trusts a DSP that reports itself running only if its mailbox is idle, and keeps it bypassed (stock sound) if it
    does not start, logging the DSP registers.
  - sends a 2-channel microphone capture on DP8 only. Stock code always adds DP8 + DP10 (4 channels), but the bus
    reserves room for 2: DP10 then overlaps the speaker data when the microphone starts first (a call), giving a
    data bus clash, crackle and one amp dropping out. The host only ever read DP8, so the mic sound is unchanged.
  - never re-inits a live DSP, as on Windows: the DSP is stalled before the init preset (module load, reload) and at
    remove. Keeps the amp function in PS0 from the DSP download through the RAE load, waits for PDE23 up to the
    ACPI maximum (8 s) there and skips the load if it doesn't get there, then gives PDE23 back to what DAPM last
    asked for (stock code always ended in PS3). Note: with `0xc081` bit 2 clear (idle in PS3, fresh amp) `0xf01e`
    and DSP RAM read back `0xdeadbeef`; that alone is not a broken DSP.
  - checks at every playback start that both DSPs run (the registers go to the log as `dsp at playback:`). After a
    long runtime suspend one amp's DSP was sometimes not running, and the stereo image moved to the other side. If
    it is not running, the driver sends a uevent (`RT1320_DSP=lost`), and the udev rule `61-surface-ultra-amp.rules`
    power-cycles the amps through the sleep hook below (at most once per 10 min).
  - module option `silence_detect` (-1 = preset, on; 0 = off; 1 = on; applies at once). With the amps' silence
    detection on, after ~15 s of digital silence one amp came back ~2.5 s after the other. `install.sh` sets
    `silence_detect=0` in `/etc/modprobe.d/n1x-rt1320-silence.conf`.
- `surface-ultra-amp-sleep` (systemd-sleep hook, installed to `/usr/lib/systemd/system-sleep/`) powers the amps
  off for s2idle, as Windows does with `CNT0._PS3`. Linux never runs it, so the amps stayed powered through sleep
  and the DSP could come back broken. Before sleep it stops PipeWire, unbinds the card, unloads the amp driver and
  holds the amp LDO enables (GPIO 47/74) low. After resume it powers the amps up, rebuilds the card, waits until
  both amps run the DSP firmware, then starts PipeWire and restarts the desktop portals. The speakers are silent
  for ~20-25 s after resume.
- With the playback-start check, the speaker no-suspend rule ([`speaker-tuning/no-suspend.sh`](../speaker-tuning/no-suspend.sh)) is no longer needed:
  the speakers may suspend again, which saves ~0.8 W at idle.
- `amp-power-cycle.sh` (rescue, normally not needed) power-cycles both amps through their LDO enables, as ACPI
  `CNT0._PS3`/`_PS0` do on Windows (GPIO 74 = amp 1, GPIO 47 = amp 2); Linux never calls those. Use it when the
  speakers crackle or drop out after a bus error: a module reload alone leaves the amps in that state. Module
  options can follow (e.g. `auto_dspfw=0`).
- `speaker-amp-gain` also sets the amps' channel routing as Windows does (left amp `L,L`, right amp `R,R`; the
  driver default `L,R` on both collapses the stereo image to the middle).
- `speaker-amp-gain`: their UCM profile caps the amp gain at 75 (-9 dB) because no speaker protection was loaded.
  `install.sh` adds one `exec` line to that profile (backup kept) which raises it to 85 (-1.5 dB) only while both
  amps run the DSP firmware.

```
cd speaker-amp
sudo ./install.sh            # firmware + DKMS driver + sleep hook, then rebuilds the sound card
sudo ./install.sh --no-reload  # same, takes effect at the next boot
./status.sh                  # DSP FW / tuning / gain of both amps
sudo ./uninstall.sh
```

The Windows partition doesn't need to be mounted: `install.sh` mounts it read-only for the extraction and
unmounts it again (or pass a Windows directory). The firmware only has to be extracted once; later runs keep it
if no Windows install is found. The very first load after
`install.sh` can fail if the amps were used with an earlier attempt; a reboot fixes that.
