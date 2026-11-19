# keyboard: Caps Lock lag

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

The built-in keyboard's LED sits behind slow HID-over-I2C writes, and every write made by the `kbd-capslock` LED
trigger to follow the key state delays Caps Lock itself. `73-surface-capslock-led.rules` sets the trigger of the
built-in keyboard's Caps Lock LED to `none`. The LED no longer lights, but the lag is gone.

```
cd keyboard
sudo ./install.sh      # applies at once; no reboot
sudo ./uninstall.sh
```

**Repeated keys through a key remapper.** On this keyboard a key release sometimes arrives very late (hundreds of
ms), only about 15 ms before the next key press (cause under investigation; the handling of GPIO interrupt EINT 139 is
suspected). A raw capture of the keyboard had no press shorter than 20 ms, but keyd's virtual keyboard showed several
3-17 ms presses, which looked like repeated keys. Do remaps such as Caps→Ctrl with Hyprland (`kb_options =
ctrl:nocaps`, key bindings) instead of keyd.
