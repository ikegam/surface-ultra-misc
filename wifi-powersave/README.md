# wifi-powersave: Wi-Fi power save on battery

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

Omarchy turns Wi-Fi power save off for good (NetworkManager `wifi.powersave=2`). On battery, turning it on saves
~0.4 W at idle here (MT7925). `surface-wifi-powersave` sets it on when `ADP1` is offline and off on AC; a udev rule
runs it when AC is plugged or unplugged, and a NetworkManager dispatcher script runs it again after a connection
comes up (NetworkManager resets the setting then).

```
cd wifi-powersave
sudo ./install.sh      # applies at once; needs iw
sudo ./uninstall.sh    # back to off
```
