# audio-jack: headphone detection

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

With the rt721-sdca driver in linux-omarchy 7.3, plugging headphones into the 3.5 mm jack is not detected: the
`Headphone Jack` control stays off and PipeWire keeps playing through the speakers. On insertion the RT721 never
raises its jack-detection interrupt (SDCA interrupt 0); only Function_Status (interrupt 3) arrives. Removal is
detected. The rt721-sdca driver from Linux v7.4-rc1 fixes this; it includes Realtek's rework of the jack-detection
setup (`e2eb4873b901` "Adjust blindwrite flow to fix type detection issue") and related changes. This directory
builds that driver unchanged for 7.3 kernels (DKMS `BUILD_EXCLUSIVE_KERNEL` is `^7\.3\.`; 7.4 has it in tree).

```
cd audio-jack
sudo ./install.sh      # DKMS, then rebuilds the sound card at once; no reboot
sudo ./uninstall.sh    # back to the kernel's module
```

`install.sh` stops PipeWire for a few seconds while the card is rebuilt.
