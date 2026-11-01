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
| `power-button/` | 電源ボタンのドライバ | 独立したドライバ。phantom の「音量下げ」(浮いた `MSHW0040` のピン)の原因は teo さんが見つけたもの |
| `usb4/` | USB4 のトンネル用ポートを止めない設定 | **teo さんが discussion で示した方式**を独自に実装したもの |

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
  効果が確認できなかったので、既定では無効です。標準の `surface_platform_profile` と同じ要求(TMP cid 0x03 に 1〜4、
  FAN cid 0x0e に 1〜4)を直接送ると、EC はどの値も受け付けます(status 0)が、TMP の読み返しは 0 のままでした。
  同じ CPU 負荷(8 スレッド、約 45〜53 W)で FAN 1・2・4 を比べても、ファンの回り方は同じでした。表面温度約 41 ℃ で
  回り始め、44 ℃ で約 3000 rpm になります。表面温度 45 ℃ を超えた範囲で効く可能性は残りますが、`thermal/` が
  表面温度をそれより下に抑えるので、ファンは EC に任せています。

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

## power-button: 電源ボタン

電源ボタンを使えるようにします。短く押すと `KEY_POWER` が送られ、Omarchy の電源メニューが開きます。

ボタンは ACPI の `MSHW0040`(`\_SB.MSBT`)の向こうにあります。x86 の Surface では `soc_button_array` がこれを gpio-keys
にしますが、`soc_button_array` は x86 専用なので、この機種では電源ボタンにドライバがありません。`_CRS` には
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

ボタンでのサスペンドからの復帰はまだ試していません。

## usb4: ドック

USB4 / Thunderbolt のドックを使うには、USB4 のトンネル用ルートポート 3 つ(`10de:22cf`)を省電力で止めないようにする
必要があります(teo-casares さんが Thunderbolt ドックで確認)。`usb4/75-n1x-usb4-tunnel-pm.rules` がこれらに
`power/control=on` を設定します。teo さんの設定のもう一方の `power_wrap_drv.usb4_release=0` は、linux-omarchy 7.3 では
N1X の既定値になっています。ドックを挿したままだとサスペンドに失敗した例があるそうなので、サスペンド前にはドックを
抜いてください。

```
cd usb4
sudo ./install.sh      # すぐ効く。再起動不要
sudo ./uninstall.sh
```

ここではドックでの確認はしていません。

## ライセンス

GPL-2.0(LICENSE を参照)。`als/` の spi-hid のソースは linux-omarchy が取り込んでいる spi-hid パッチ群(Microsoft、
Google、Semihalf ほか)から取ったもので、変更点は各ファイルの先頭に書いてあります。
