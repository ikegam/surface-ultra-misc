# power-button: 電源ボタン

(English: [README.md](README.md))

[surface-ultra-misc](../README_jp.md) の一部です。

電源ボタンを使えるようにします。短く押すと `KEY_POWER` が送られ、Omarchy の電源メニューが開きます。

ボタンは ACPI の `MSHW0040`(`\_SB.MSBT`)の向こうにあります。x86 の Surface では `soc_button_array` がこれを gpio-keys
にします。upstream の 7.3 は `soc_button_array` を x86 だけでビルドし、linux-omarchy は arm64 でもビルドしますが、この機種の
`MSHW0040` は飛ばします(omacom/omarchy-pkgs#2166)。そのため、この機種では電源ボタンにドライバがありません。`_CRS` には
`\_SB.GIO0` の GPIO が 3 本あり、46 番が電源(復帰の要因として指定されているのはこれだけ)、残りが 40・41 番です。
この機種には音量ボタンがなく、teo-casares さんが見つけたとおり 40・41 番は浮いていて「音量下げ」を押しっぱなしと報告
します。`n1x-power-button` は `MSHW0040` に対応し、46 番だけを使って 40・41 番には触りません。そのため
`modprobe.blacklist=gpio_keys` は起動オプションに残したままで構いません。読み込んだ時点の値を「離している」とみなします。
サスペンド中に押すと復帰しますが、キーは送らないので、復帰後に電源メニューは開きません。

```
cd power-button
sudo ./install.sh      # DKMS に入れてすぐ読み込む。次回からは起動時に自動。再起動不要
sudo ./uninstall.sh
```

ボタンでサスペンドから復帰できます(ふたを開けた状態で確認)。ふたを閉じてサスペンドする場合は、キーボードやタッチパッドと
同じように、ボタンの wakeup(`/sys/bus/platform/devices/MSHW0040:00/power/wakeup`)も止めてください。止めないと、
カバンの中で押されて起きてしまいます。[`suspend/`](../suspend/) のフックがこれを行います。
