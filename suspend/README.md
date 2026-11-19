# suspend: sleep and resume

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

**Wakeups with the lid closed.** Keys pressed in a bag wake the machine from s2idle through the I2C keyboard
(`MSHW0794`) interrupt (reported by teo-casares in the discussion, who handles it with a system-sleep hook).
`surface-ultra-lid-wakeup` is an independent implementation of the same approach. Besides the keyboard, it also turns
off wakeup for the touchpad (`MSHW0734`) and the power button (`MSHW0040`, [`power-button/`](../power-button/)), only while the lid is
closed, and turns it back on at resume. With the lid open, keys and the button still wake the machine.

**Keys dead for 10-30 s right after resume.** `nvidia-sleep.sh`, run by `nvidia-suspend.service` and
`nvidia-resume.service`, switches to VT 63 (`chvt 63`) before suspend and back after resume. Each time, Hyprland
disables and re-enables the seat and adds every input device again (`Disabling seat` / `Enabling seat` in
hyprland.log), and the lock screen gets no keys until that is done. The keyboard and I2C are fine. When the driver
runs with `NVreg_UseKernelSuspendNotifiers=1`, VRAM is saved from the kernel suspend notifiers, so the two services
are not needed. With them masked, keys work right after resume. (The lock screen's password field may still need one
click for focus; that is a separate, unsolved problem.) `NVreg_EnableS0ixPowerManagement=1` (to bring the display
back after s2idle; see teo-casares' discussion) is assumed.

```
cd suspend
sudo ./install.sh                       # hook only; applies from the next suspend
sudo ./install.sh --mask-nvidia-sleep   # also mask nvidia-suspend/resume (checks the driver settings first)
sudo ./uninstall.sh
```
