# backlight: automatic brightness

(日本語: [README_jp.md](README_jp.md))

Part of [surface-ultra-misc](../README.md).

`n1x-edp-backlight-auto.patch` adds automatic brightness to teo-casares' `n1x-edp-backlight` (get the
script from their Gist; the patch header has the commands). It follows Windows' lux -> nits curve for this
machine using `als`; a brightness key press is kept as an offset on top of the curve and saved across restarts;
`echo 0 > /var/lib/n1x-edp-backlight/auto` turns it off. When the level is put back at start-up or after the
panel lost it in s2idle, it fades there over about 0.3 s instead of jumping (the firmware leaves the panel at
another level, so the change was visible at every boot and resume).
