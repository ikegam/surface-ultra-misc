# speaker-tuning: Dolby tuning as a PipeWire filter

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

Optional, on top of `speaker-amp`. The Windows Dolby driver has a tuning for this machine too
(`SOUNDWIRE_SDCAFUNCTION_10_MAN_025D_FUNC_1320_SUBSYS_308E10EC.xml`). Its speaker EQ (`audio-optimizer`) is
disabled, so on its own it changes little; what remains is a bass enhancer and a limiter. `install.sh` converts it
with [speaker-tuning-to-easyeffects](https://github.com/antoinecellerier/speaker-tuning-to-easyeffects) (MIT,
fetched at a pinned commit, not vendored) into a PipeWire filter-chain on the built-in speakers, without the volume
leveler (it pulls everything down to -26 LUFS). The XML is read from your Windows partition (mounted read-only
with `udisksctl` for a moment if it isn't, then cached) and nothing derived from it leaves the machine.

```
cd speaker-tuning
./install.sh        # needs: sudo pacman -S lsp-plugins-lv2 calf
./uninstall.sh
```

The PipeWire restart is followed by a restart of the desktop portals, otherwise screen sharing breaks.

The converted chain boosts by +4 dB (`volmax`) into a limiter whose automatic level regulation (ALR) then pulls
everything, vocals included, up and down with the mix; Windows' Dolby limits per band instead. `install.sh`
therefore drops the boost (speaker-amp's amp gain of 85 makes up for it in the analog domain) and ALR, leaving the
limiter as a plain brickwall, and runs the bass enhancer at 2 instead of 3.98. Windows has the bass enhancer off,
but without it this chassis loses its body.

**Playback starting late.** When the speakers have been idle, PipeWire closes them and the amps power down; waking
the link, both amps and their DSP takes about 2 s, so the first sound comes late. This is the default and is left
that way here: speaker-amp checks both DSPs at every playback start, and letting the speakers suspend saves ~0.8 W
at idle. If the delay bothers you, `./no-suspend.sh on` keeps the speakers open (a WirePlumber rule,
`wireplumber/51-speaker-no-suspend.conf`); `./no-suspend.sh off` undoes it.
