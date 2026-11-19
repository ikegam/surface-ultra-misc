# als: ambient light sensor

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

Exposes the ambient light sensor as the IIO device `als`:

```
$ cat /sys/bus/iio/devices/iio:device0/name
als
$ cat /sys/bus/iio/devices/iio:device0/in_illuminance_raw    # units of 0.01 lux
36180
```

Chromaticity (x, y) is reported too. Color temperature stays 0 (the sensor hub firmware does not fill it in).

**How it works.** The sensor (ams TCS3430) sits behind a sensor hub that runs as firmware on the SoC's SCP
coprocessor. The SCP acts as an SPI slave on SPI3 and is an ACPI HID-over-SPI device: `\_SB.SENH`
(`MSFW1111`, `_CID PNP0C51`). The kernel's HID-over-SPI driver (the spi-hid series that linux-omarchy carries;
`CONFIG_SPI_HID_ACPI` is not enabled there) does not work as is, so core and ACPI glue are built out of tree
as one module, `n1x-spi-hid`, with four fixes:

1. **The reset was never sent.** `spi-hid-acpi` calls `device_reset(&adev->dev)`, but the `struct device`
   inside an `acpi_device` has no ACPI handle, so `_RST` never runs (and the error is ignored). `_RST` is now
   evaluated directly. On this machine it rings a doorbell to the sensor hub firmware.
2. **The interrupt line has no GPIO.** The `GpioInt` is pin 190, an EINT-only line: `pinctrl-mt8901` only has
   GPIOs 0-181, so the ACPI IRQ lookup fails, and `mtk-eint` would refuse `request_irq()` because it locks the
   matching GPIO. The module takes over EINT 190's flow handler and forwards it to an irq_sim interrupt
   (a reset response that arrives while the interrupt is disabled is kept by genirq and resent).
3. **A one-shot read of an input report returned the feature report.** `spi_hid_ll_raw_request()` always sends
   GET_FEATURE, so `hid-sensor-hub`'s sync read parsed settings as the illuminance. Input-report requests now
   fail, and `hid-sensor-hub` takes the next periodic report (every 750 ms).
4. **Sometimes silent after resume.** After some s2idle resumes the sensor hub sends nothing at all, not even
   the reset response, and every later report is dropped ("HID not ready"): the illuminance stays 0 and
   automatic brightness stops until the driver is rebound. If no interrupt arrives within 3 s of resume, the
   driver now resets the sensor hub again (up to 3 times) and logs `sensor hub silent after resume`.

The core exports no symbols and uses its own trace system name, so it neither replaces nor collides with the
stock `spi-hid`.

```
cd als
sudo ./install.sh     # DKMS, loaded right away and at every boot; no reboot
sudo ./uninstall.sh
```

`scp-peek.py` (root, read-only) prints how many reset doorbells the SCP has taken and the tail of the SCP
firmware log; useful when the device does not appear.
