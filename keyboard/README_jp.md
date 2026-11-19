# keyboard: Caps Lock の遅れ

(English: [README.md](README.md))

[surface-ultra-misc](../README_jp.md) の一部です。

内蔵キーボードの LED は HID over I2C の遅い書き込みの向こうにあり、LED のトリガー `kbd-capslock` がキー状態に連動して
書き込むたびに Caps Lock の処理自体が遅れます。`73-surface-capslock-led.rules` は内蔵キーボードの Caps Lock LED の
トリガーを `none` にします。LED は点かなくなりますが、遅れはなくなります。

```
cd keyboard
sudo ./install.sh      # すぐ効く。再起動不要
sudo ./uninstall.sh
```

**キー再マップを挟むと連打になる。** この機種のキーボードは、キーを離した報告がまれに大きく遅れ(数百 ms)、次のキーを
押した報告の約 15 ms 前にようやく届きます(原因は調査中。GPIO の割り込み EINT 139 の扱いを疑っています)。キーボードの生の入力を記録すると
20 ms 未満の押下は 1 回もありませんでしたが、keyd を通した仮想キーボードでは 3〜17 ms の押下が何回も出ていて、連打に
見えていました。Caps→Ctrl などは keyd を使わず、Hyprland の `kb_options = ctrl:nocaps` やキー割り当てで行うのが安全です。
