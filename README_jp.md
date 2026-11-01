# surface-ultra-misc

(English: [README.md](README.md))

Microsoft Surface Laptop Ultra(NVIDIA N1X SoC、arm64)を Linux で使うための小物集です。
カメラは別リポジトリ [surface-ultra-camera](https://github.com/ikegam/surface-ultra-camera) にあります。

非公式のもので、Microsoft・NVIDIA・MediaTek とは関係ありません。Omarchy(linux-omarchy 7.3)で確認しています。

## クレジット

teo-casares さんによる、この機種で Omarchy を動かす取り組みの上に成り立っています。
[Gist](https://gist.github.com/teo-casares/8b64949638e1952602a7f435bb34d5b8)(カーネルパッチ、DKMS モジュール、
サービス)と [omacom/omarchy discussion #15885](https://github.com/omacom/omarchy/discussions/15885) を先に見てください。
以下はその環境を前提にしています。

| ディレクトリ | 内容 | teo-casares さんの成果との関係 |
|---|---|---|
| `als/` | 照度センサーのドライバ | 独立 |
| `thermal/` | SoC 電力・表面温度の制御、Tj の安全網 | 独立。teo さんのファン制御デーモンを補うもので、`ssam-helper` が登録する SSAM 温度センサーを読む |
| `ssam-helper/` | 標準 SSAM + 補助モジュール | **teo さんが discussion で示した方式**を独自に実装したもの |
| `backlight/` | 自動輝度 | **teo さんの `n1x-edp-backlight` へのパッチ**(スクリプト本体はここには入れていない) |

## als: 照度センサー

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
そのままでは動かないので、本体と ACPI 部分を 1 つのモジュール `n1x-spi-hid` として外部ビルドし、次の 3 点を直しています。

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

本体はシンボルを公開せず、トレースの名前も変えてあるので、標準の `spi-hid` を置き換えたり衝突したりしません。

```
cd als
sudo ./install.sh     # DKMS に入れてすぐ読み込む。次回からは起動時に自動。再起動不要
sudo ./uninstall.sh
```

`als/scp-peek.py`(root、読むだけ)は、SCP が受けたリセットの合図の回数と、SCP ファームウェアのログの末尾を表示します。
デバイスが出ないときの調査用です。

## thermal: 電力と表面温度の制御

Linux の既定では何も制御されていません。ACPI の温度ゾーンにはトリップ点が 1 つも無く、CPU に負荷をかけ続けると SoC は
64〜68 W を出し、Tj はファームウェア側の約 98 ℃ に張り付きます。Windows の熱ポリシー(MPTF)は、本体表面の温度
(SAM センサー VTS1)を 45 ℃ に保つよう SoC の持続電力上限を下げます(標準モードで AC 55 W、バッテリー 42.5 W)。
ここでは Linux にある手段で同じことをします。

- **`n1x-thermald`**(systemd サービス、python3 の標準ライブラリのみ):2 秒ごとに SoC の平均電力を予算と比べ、全 CPU の
  `scaling_max_freq` を 5 % 刻みで動かします(下限 40 %)。表面温度の PI 制御(VTS1 = `surface_thermal` の temp9、目標
  45 ℃。VTS5 = temp12、目標 51 ℃)が予算を下げます。非常時は、二次の表面温度 55.5 ℃ 以上か電池(RTS5 = temp5)62 ℃
  以上で CPU を最低周波数に固定し、57 ℃ / 64 ℃ で電源を切ります。値は Windows と同じです。SSAM のセンサーが無いときは
  電力予算だけで動きます。
- **Tj の安全網**:SoC の Tj を見る追加の ACPI 温度ゾーン `\_TZ.NXTJ`(`n1x-thermal.asl`)。100 ℃ で 20 個の CPU すべてを
  減速し、105 ℃ で電源を切ります。`n1x-thermal-ssdt.service` が起動時に `acpi_configfs` で読み込みます。

ACPI の「温度ゾーン」のうち 2 つは温度ではありません。`\_TZ.PSOC`(thermal_zone2)と `\_TZ.PSYS`(thermal_zone1)は
SoC とシステムの平均電力を mW で返すので、「2005 ℃」のような値に見えます。`n1x-thermald` は PSOC を電力の帰還に使います。

19 スレッドの負荷での実測:SoC 電力 65 W → 52 W、Tj 98 ℃ → 94 ℃。負荷が終わると段階的に全速へ戻ります。

```
cd thermal
sudo ./install.sh          # 周波数の上限が実際に効くかの自己テスト付き
./n1x-thermald --dry-run   # 判断だけ表示(一般ユーザーで可)
cat /run/n1x-thermald/status.json
```

ファンは EC(または teo-casares さんのファン制御デーモン)に任せ、`n1x-thermald` は触りません。

## ssam-helper: 改変モジュールを使わない標準 SSAM

カーネル内モジュールの改変版はカーネル更新で壊れます。teo-casares さんが discussion で示したとおり、標準モジュールに
小さな補助を 2 つ足せば動くので、何も置き換えない新しいモジュールとして実装しました。

- `n1x_ssam_uartclk`:`surface_aggregator` がポートを開く前に、SAM の UART(NVDA0240)に本当のクロック 52 MHz を設定
  します。`mtk8250_set_termios()` が 42.9 MHz を超えると誤る小数分周(32 ビットの桁あふれ)も直します。
- `n1x_ssam_clients`:MSHW0733 用のプラットフォームハブで、バッテリー、AC、SSAM の温度センサー 11 個(`surface_temp`、
  hwmon `surface_thermal`、tempN = SAM のインスタンス N)、ファン回転数(`surface_fan`)を登録します。`profile=1` で
  プラットフォームプロファイルも登録します(実験的。この EC はプロファイル 0 を返します)。

```
cd ssam-helper
sudo ./install.sh      # 入っている surface-n1x-ssam/1.0 をその場で置き換え。再起動不要
sudo ./rollback.sh     # surface-n1x-ssam/1.0 に戻す
```

## backlight: 自動輝度

`backlight/n1x-edp-backlight-auto.patch` は、teo-casares さんの `n1x-edp-backlight` に自動輝度を足すパッチです
(スクリプトは teo さんの Gist から取ってください。手順はパッチの先頭にあります)。`als` を使ってこの機種用の Windows の
lux → nits 曲線に追従します。輝度キーで調整した分は曲線へのオフセットとして保存され、再起動後も残ります。
`echo 0 > /var/lib/n1x-edp-backlight/auto` で自動輝度を止められます。

## ライセンス

GPL-2.0(LICENSE を参照)。`als/` の spi-hid のソースは linux-omarchy が取り込んでいる spi-hid パッチ群(Microsoft、
Google、Semihalf ほか)から取ったもので、変更点は各ファイルの先頭に書いてあります。
