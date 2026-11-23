# sapd-lps0: Surface の Modern Standby 通知

(English: [README.md](README.md))

[surface-ultra-misc](../README_jp.md) の一部です。

**作者の機械では現在オフにしています(2026-11-20)。** リセットは止まりませんでした。また、導入以降、電池でふたを閉じた
長時間のスリープから起きられなくなっています。眠ったまま(約 0.4 W)で、長押ししないと戻りません。AC で入ったスリープは
問題ありません。これが原因かを確かめるため、`enable=0` で読み込んでいます(`/etc/modprobe.d/n1x-sapd-lps0.conf` に
`options n1x_sapd_lps0 enable=0`)。

結果(2026-11-22):オフにしてから、電池でふたを閉じて入ったスリープは 5 回中 5 回、ふたを開けるだけで起きました
(64、176、284、332、339 分。最後は夜間。スリープ中は約 0.7 W)。オンのときは直近 4 回中 4 回起きませんでした。オンの
状態で 243 分後に起きられた日もあり、仕組みは分かっていませんが、作者の機械ではオフのままにします。同じ実験を
したい場合を除き、このモジュールは入れないでください。

訂正(2026-11-23):この 5 回は `suspend/surface-ultra-lid-wakeup` フックも無効(`chmod -x`)にした状態でした。
したがって、この結果だけでは両者を分けられません。フックを有効に戻して最初のふた閉じサスペンド(2026-11-22 12:14、
AC で入眠、このモジュールはオフのまま)は復帰せず、17 時間後には電池が空でした。s2idle の消費では説明できない量です。

再訂正(2026-11-23):フックを再び無効にし、このモジュールもオフのままで、電池でのふた閉じサスペンド(05:53)がまた
復帰しませんでした。つまり、このモジュールでもフックでも失敗は説明できません。6 回続いた成功は、以前からの「7〜10 回に
1 回の失敗」という頻度なら偶然でも起こる範囲です。原因は不明のままです。

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
