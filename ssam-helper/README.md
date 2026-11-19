# ssam-helper: stock SSAM without patched modules

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

Patched copies of in-tree SSAM modules break on kernel updates. As teo-casares described in the discussion,
the stock modules work with two small helpers, implemented here as new modules that shadow nothing:

- `n1x_ssam_uartclk`: sets the real 52 MHz clock of the SAM UART (NVDA0240) before `surface_aggregator` opens
  it, and corrects the fractional divider that `mtk8250_set_termios()` gets wrong above 42.9 MHz (32-bit overflow).
- `n1x_ssam_clients`: a platform hub for MSHW0733 that registers battery, AC, the 11 SSAM temperature sensors
  (`surface_temp`, hwmon `surface_thermal`, tempN = SAM instance N) and fan speed (`surface_fan`).
  `profile=1` also registers the platform profile device (experimental: this EC reads back profile 0).
  It is off by default because it made no measurable difference. Sending the same requests as the stock
  `surface_platform_profile` directly (TMP cid 0x03 values 1–4, FAN cid 0x0e values 1–4), the EC accepted every
  value (status 0), but the TMP read back stayed 0. Under the same 8-thread CPU load (about 45–53 W), FAN 1, 2 and 4
  gave the same fan curve: the fan starts at about 41 °C skin and reaches about 3000 rpm at 44 °C. An effect above
  45 °C skin is not ruled out, but [`thermal/`](../thermal/) keeps the skin below that, so the fan is left to the EC.

```
cd ssam-helper
sudo ./install.sh      # replaces an installed surface-n1x-ssam/1.0 live; no reboot
sudo ./rollback.sh     # back to surface-n1x-ssam/1.0
```
