# als: 照度センサー

(English: [README.md](README.md))

[surface-ultra-misc](../README_jp.md) の一部です。

照度センサーを IIO デバイス `als` として出します。

```
$ cat /sys/bus/iio/devices/iio:device0/name
als
$ cat /sys/bus/iio/devices/iio:device0/in_illuminance_raw    # 0.01 lux 単位
36180
```

色度(x, y)も読めます。色温度は 0 のままです(センサーハブのファームウェアが埋めていません)。

**仕組み。** センサー(ams TCS3430)は、SoC 内のサブプロセッサ SCP の上で動くセンサーハブの向こうにあります。
SCP は SPI3 のスレーブとして HID over SPI のデバイスになり、ACPI では `\_SB.SENH`(`MSFW1111`、`_CID PNP0C51`)です。
カーネルの HID over SPI ドライバ(linux-omarchy が取り込んでいる spi-hid パッチ群。`CONFIG_SPI_HID_ACPI` は無効)は
そのままでは動かないので、本体と ACPI 部分を 1 つのモジュール `n1x-spi-hid` として外部ビルドし、次の 4 点を直しています。

1. **リセットが送られていなかった。** `spi-hid-acpi` は `device_reset(&adev->dev)` を呼びますが、`acpi_device` の中の
   `struct device` には ACPI ハンドルが無いので `_RST` は実行されません(エラーも無視されます)。`_RST` を直接評価する
   ようにしました。この機種では、`_RST` はセンサーハブのファームウェアへの合図です。
2. **割り込み線に GPIO が無い。** `GpioInt` は 190 番で、GPIO の付かない割り込み専用の線(EINT)です。`pinctrl-mt8901` は
   GPIO 0〜181 しか持たないので ACPI から割り込みを取れず、`mtk-eint` も GPIO をロックしようとして `request_irq()` に
   失敗します。EINT 190 の流れハンドラを自前で受け持ち、irq_sim の割り込みに中継しています(割り込み無効中に来た
   リセット応答は genirq が保持して再送します)。
3. **入力レポートの単発読み出しが設定値を返した。** `spi_hid_ll_raw_request()` は常に GET_FEATURE を送るので、
   `hid-sensor-hub` の同期読み出しが設定値を照度として解釈していました。入力レポートの要求は失敗させ、
   `hid-sensor-hub` が次の定期レポート(750 ms ごと)を使うようにしました。
4. **復帰後に黙ることがある。** s2idle から復帰したとき、センサーハブがリセット応答も含めて何も送ってこないことがあり、
   以後のレポートはすべて捨てられます("HID not ready")。照度は 0 のままになり、ドライバを付け直すまで自動輝度も
   止まります。復帰から 3 秒以内に割り込みが 1 回も来なければ、センサーハブをもう一度リセットし(最大 3 回)、
   ログに `sensor hub silent after resume` と出すようにしました。

本体はシンボルを公開せず、トレースの名前も変えてあるので、標準の `spi-hid` を置き換えたり衝突したりしません。

```
cd als
sudo ./install.sh     # DKMS に入れてすぐ読み込む。次回からは起動時に自動。再起動不要
sudo ./uninstall.sh
```

`scp-peek.py`(root、読むだけ)は、SCP が受けたリセットの合図の回数と、SCP ファームウェアのログの末尾を表示します。
デバイスが出ないときの調査用です。
