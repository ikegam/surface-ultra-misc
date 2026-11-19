# wifi-powersave: バッテリー時だけ Wi-Fi の省電力

(English: [README.md](README.md))

[surface-ultra-misc](../README_jp.md) の一部です。

Omarchy は Wi-Fi の省電力を常に切っています(NetworkManager の `wifi.powersave=2`)。バッテリー時に入れると、この機械
(MT7925)ではアイドル時に約 0.4 W 減ります。`surface-wifi-powersave` は `ADP1` が外れていれば省電力を入れ、AC なら
切ります。AC の抜き差しで udev ルールが、接続が上がったあとで NetworkManager の dispatcher スクリプトが呼びます
(そのとき NetworkManager が設定を戻すため)。

```
cd wifi-powersave
sudo ./install.sh      # すぐ反映。iw が必要
sudo ./uninstall.sh    # 切った状態に戻す
```
