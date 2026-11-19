# suspend: サスペンドと復帰

(English: [README.md](README.md))

[surface-ultra-misc](../README_jp.md) の一部です。

**ふたを閉じたときの誤復帰。** カバンの中でキーが押されると、I2C キーボード(`MSHW0794`)の割り込みで s2idle から起きて
しまいます(teo-casares さんが discussion で報告し、system-sleep のフックで対処しています)。`surface-ultra-lid-wakeup` は
同じ方式を独自に実装したもので、キーボードに加えてタッチパッド(`MSHW0734`)と電源ボタン(`MSHW0040`、[`power-button/`](../power-button/))の
wakeup も、ふたが閉じているときだけ止め、復帰時に戻します。ふたを開けたままのサスペンドは、従来どおりキーやボタンで
復帰できます。

**復帰直後の 10〜30 秒、キーが効かない。** `nvidia-suspend.service` と `nvidia-resume.service` が実行する
`nvidia-sleep.sh` は、サスペンド前に `chvt 63` で VT を切り替え、復帰後に元の VT へ戻します。Hyprland はそのたびに seat を
無効化・有効化して入力機器をすべて登録し直すので(hyprland.log の `Disabling seat` / `Enabling seat`)、その間はロック画面に
キーが届きません。キーボードや I2C は正常です。ドライバが `NVreg_UseKernelSuspendNotifiers=1` で動いていれば、VRAM の
退避はカーネルのサスペンド通知の中で行われるので、この 2 つのサービスは不要です。マスクすると、復帰直後からキーが効きます
(ロック画面のパスワード欄にフォーカスが入らず、1 回クリックが要ることがあります。これは別の問題で未解決です)。
`NVreg_EnableS0ixPowerManagement=1`(s2idle 復帰後に画面を戻すため。teo さんの discussion を参照)は前提です。

```
cd suspend
sudo ./install.sh                       # フックだけ。次のサスペンドから有効
sudo ./install.sh --mask-nvidia-sleep   # 加えて nvidia-suspend/resume をマスク(ドライバ設定を確認してから)
sudo ./uninstall.sh
```
