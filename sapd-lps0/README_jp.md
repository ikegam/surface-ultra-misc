# sapd-lps0: Surface の Modern Standby 通知

(English: [README.md](README.md))

[surface-ultra-misc](../README_jp.md) の一部です。

**試験中で、効果はまだ評価中です。** この機械では、ふたを閉じた s2idle の 7〜10 回に 1 回ほどが復帰しませんでした。
journal は `PM: suspend entry (s2idle)` で終わり、pstore にも記録が残らないまま SoC が自分でリセットします。その次の起動は
NVIDIA の GSP 初期化(`GspStatusQueueInit ... NV_ERR_TIMEOUT`)で止まって画面が出ず、電源ボタンをもう一度長押しすると
普通に起動します。

ファームウェアには、Microsoft の Modern Standby `_DSM`(`11e00d56-ce64-47ce-837b-1f898f9aa461`)を持つ LPS0 デバイス
(`_CID PNP0D80`)が 2 つあります。

- `\_SB.PEPD`(`NVDA6210`): NVIDIA のプラットフォーム拡張。linux-omarchy の power_wrap(NVIDIA のふた復帰パッチ、
  NV-Kernels #656)がすでに呼んでいます(カーネルログの `LPS0 EC sleep notifications enabled`)。
- `\_SB.SAPD`(`MSHW0299`): Surface だけのもの。Linux では誰も呼びません。function 7(スリープ開始)で GPIO 136 を Low に
  し、3/4/8/9 で High に戻します。このピンを触る ACPI メソッドはほかにありません。Windows ではスリープ中ずっと Low、
  Linux では High のままです。

`n1x_sapd_lps0` は `MSHW0299` にバインドし、Windows と同じ順序の通知をデバイスの noirq フェーズで送ります(入るときに
3, 7, 5、出るときに 6, 9, 8, 4)。失敗はログに残すだけで、サスペンドは止めません。リセットが止まるかはまだ確かめられて
おらず、ふた閉じ数十回分で試験中です。スリープの深さは変わりません(サスペンドごとに DRIPS 1 回)。

```
cd sapd-lps0
sudo ./install.sh                                   # DKMS。すぐロードされ、再起動不要
cat /sys/bus/platform/devices/MSHW0299:00/stats     # functions=0x3f8 entries=N failures=0 enable=1
echo 0 | sudo tee /sys/module/n1x_sapd_lps0/parameters/enable   # A/B 比較用に送信を止める
sudo ./uninstall.sh
```

サスペンドのたびに `entry notifications sent (#N)` / `exit notifications sent` がログに出ます(モジュールパラメータ `verbose`)。
