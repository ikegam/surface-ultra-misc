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
| `thermal/` | SoC 電力・表面温度の制御(CPU と GPU の制限、2 つのプロファイル)、Tj の安全網 | 独立。teo さんのファン制御デーモンを補うもので、`ssam-helper` が登録する SSAM 温度センサーを読む |
| `ssam-helper/` | 標準 SSAM + 補助モジュール | **teo さんが discussion で示した方式**を独自に実装したもの |
| `backlight/` | 自動輝度 | **teo さんの `n1x-edp-backlight` へのパッチ**(スクリプト本体はここには入れていない) |
| `power-button/` | 電源ボタンのドライバ | 独立したドライバ。phantom の「音量下げ」(浮いた `MSHW0040` のピン)の原因は teo さんが見つけたもの |
| `suspend/` | ふたを閉じたときの誤復帰の防止、復帰直後にキーが効かない問題 | ふた閉じのフックは **teo さんが discussion で示した方式**を独自に実装し、タッチパッドと電源ボタンを足したもの。NVIDIA の部分は独立 |
| `sapd-lps0/` | サスペンド前後に Surface 固有の Modern Standby 通知を送る(試験中) | 独立 |
| `osi-idle/` | Windows と同じ PSCI OS-initiated モードで CPU アイドルと s2idle を動かす(試験中) | 独立 |
| `keyboard/` | Caps Lock の遅れ、キー再マップでの連打 | 独立 |
| `audio-jack/` | ヘッドホンジャックの検出 | 独立(上流の Realtek ドライバ) |
| `speaker-amp/` | スピーカー: Windows のアンプ DSP ファームとチューニングで鳴らす | 独立。teo さんの音声環境(UCM プロファイル、`n1x-sdw-settle`)と組み合わせて動く |
| `speaker-tuning/` | スピーカー: Windows の Dolby チューニングを PipeWire フィルタに(任意) | 独立 |
| `gpu-power/` | NVIDIA の電力管理(nvidia-powerd、RATED_TDP)の調査メモと診断ツール | 独立 |

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

`als/scp-peek.py`(root、読むだけ)は、SCP が受けたリセットの合図の回数と、SCP ファームウェアのログの末尾を表示します。
デバイスが出ないときの調査用です。

## thermal: 電力と表面温度の制御

Linux の既定では何も制御されていません。ACPI の温度ゾーンにはトリップ点が 1 つも無く、CPU に負荷をかけ続けると SoC は
64〜68 W を出し、Tj はファームウェア側の約 98 ℃ に張り付きます。Windows の熱ポリシー(MPTF)は、本体表面の温度
(SAM センサー VTS1)を 45 ℃ に保つよう SoC の持続電力上限を下げます(標準モードで AC 55 W、バッテリー 42.5 W)。
ここでは Linux にある手段で同じことをします。既定のプロファイルは Windows より多めに許し(80 W、表面 52 ℃)、
`standard` プロファイルが Windows の値です。

- **`n1x-thermald`**(systemd サービス、python3 の標準ライブラリのみ):2 秒ごとに SoC の平均電力を予算と比べ、制限の
  段を上り下りします。CPU を先に、GPU を最後に絞ります(この機械の主な用途はローカル LLM を GPU で動かすことなので)。
  CPU の `scaling_max_freq` を各クラスタの最大の 100 / 80 / 60 / 40 %、続いて GPU の最大クロック(`nvidia-smi -lgc`)を
  2400 / 2100 / 1800 / 1400 / 1000 MHz にします。GPU は常に 2400 MHz に制限します。LLM のデコードで測ると速度は落ちず、
  2515 MHz のブーストより約 15 W 減ります(1800 MHz でデコード -5 %・-6 W、1400 MHz で -11 %・-10 W)。表面温度の PI 制御
  (VTS1 = `surface_thermal` の temp9、二次 = temp12)が予算を下げます。
- **プロファイル**(`/etc/n1x-thermald.conf`、変更はすぐ反映。`sudo n1x-thermald --profile 名前` で書き換え):

  | プロファイル | 予算 AC / バッテリー | 表面 | 二次 | HOT | サスペンド | 電源断 |
  |---|---|---|---|---|---|---|
  | `performance`(既定) | 80 / 80 W | 52 ℃ | 58 ℃ | 61 ℃ | 63 ℃ | 65 ℃ |
  | `standard`(Windows の「推奨」) | 55 / 42.5 W | 45 ℃ | 51 ℃ | 55.5 ℃ | 57 ℃ | 59 ℃ |

  HOT(二次の表面温度、または電池 RTS5 = temp5 が 62 ℃ 以上)では CPU を最低周波数、GPU を 1000 MHz に固定します。
  「サスペンド」の温度が 3 回続くとサスペンド、電池 64 ℃ 以上か「電源断」の温度で電源を切ります。電池の値は Windows と
  同じで、両プロファイル共通です。SSAM のセンサーが無いときは電力予算だけで動きます。
- **Tj の安全網**:SoC の Tj を見る追加の ACPI 温度ゾーン `\_TZ.NXTJ`(`n1x-thermal.asl`)。100 ℃ で 20 個の CPU すべてを
  減速し、105 ℃ で電源を切ります。`n1x-thermal-ssdt.service` が起動時に `acpi_configfs` で読み込みます。

ACPI の「温度ゾーン」のうち 2 つは温度ではありません。`\_TZ.PSOC`(thermal_zone2)と `\_TZ.PSYS`(thermal_zone1)は
SoC とシステムの平均電力を mW で返すので、「2005 ℃」のような値に見えます。`n1x-thermald` は PSOC を電力の帰還に使います。

19 スレッドの負荷での実測(Windows の値):SoC 電力 65 W → 52 W、Tj 98 ℃ → 94 ℃。負荷が終わると段階的に全速へ戻ります。

```
cd thermal
sudo ./install.sh          # 周波数の上限が実際に効くかの自己テスト付き
./n1x-thermald --dry-run   # 判断だけ表示(一般ユーザーで可)
cat /run/n1x-thermald/status.json
sudo n1x-thermald --profile standard   # Windows の値。再起動は不要
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
`echo 0 > /var/lib/n1x-edp-backlight/auto` で自動輝度を止められます。起動時や、s2idle でパネルが明るさを失ったあとに
明るさを戻すときは、一気に変えずに約 0.3 秒かけて変えます(ファームウェアはパネルを別の明るさにしておくので、起動と
復帰のたびに明るさの変化が目に見えていました)。

## power-button: 電源ボタン

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
カバンの中で押されて起きてしまいます。`suspend/` のフックがこれを行います。

## suspend: サスペンドと復帰

**ふたを閉じたときの誤復帰。** カバンの中でキーが押されると、I2C キーボード(`MSHW0794`)の割り込みで s2idle から起きて
しまいます(teo-casares さんが discussion で報告し、system-sleep のフックで対処しています)。`surface-ultra-lid-wakeup` は
同じ方式を独自に実装したもので、キーボードに加えてタッチパッド(`MSHW0734`)と電源ボタン(`MSHW0040`、`power-button/`)の
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

## sapd-lps0: Surface の Modern Standby 通知

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

## osi-idle: Windows と同じ OS-initiated CPU アイドル

**試験中です。** `sapd-lps0` と同じく、s2idle 中に SoC がリセットされる問題が対象です。記録を見ると、ファームウェアの一番深い状態(Standby-DRIPS)の中で落ちています。

Linux の ACPI LPI アイドルドライバは、PSCI を platform-coordinated(PC)モードのまま使います。各 CPU は一番深い状態を要求し、クラスタや SoC 全体の電源をいつ落とすかはファームウェアが決めます。

Windows の PEP ドライバ `nvpep.sys`(2.27)は、読み込み時に PSCI を **OS-initiated(OSI)モード** に切り替えます。ファームウェアは OSI に対応しています(`PSCI_FEATURES(CPU_SUSPEND)` = 0x1)。OSI モードでは、クラスタやパッケージで最後に眠る CPU だけが、その階層の状態に `_LPI` の LevelID を足して要求します。`nvpep.sys` は、ほかに `\_SB.PEPD.ELST(1)` を呼び、SYSRAM に 2 か所書き込みます(0x130000 = 0x89736C41、0x12FF00 = "OSI")。

`n1x_osi_idle` も同じ手順を踏み、ACPI アイドルドライバを同等のドライバに置き換えます。

- クラスタ(CPU 0-9、10-19)ごとに、最後に眠る CPU を判定します。パッケージ全体も同様です。
- 実際に眠る処理は、カーネル自身の `psci_cpu_suspend_enter()` です。フラグも ACPI ドライバと同じです。
- 普段の待機ではパッケージの電源断までを使います。DRIPS は s2idle のときだけ、最後の CPU が 0x020100F0 + LevelID 0x2000 で要求します。
- 最後の CPU 争いに負けて DENIED が返った CPU は、起き直さずにそのままコアの電源断に入ります。
- 画面がついている間は、ファームウェアがパッケージの要求の大半をクラスタの電源断に格下げします。30 秒でドライバ側の受理は 4,863 回、ファームウェアが数えた本当のパッケージ電源断(PGKLL)は 151 回、クラスタは約 10,500 回でした。デバイスが動いているためのファームウェアの判断で、ドライバの誤りではありません。

**現状**

- 普段の動作は安定しています。クラスタとパッケージの状態に 1 分あたり数千回入り、競合による拒否が少しあるだけです。不正な要求はなく、アイドル時の電力も変わりません。
- s2idle の最初の試験では DRIPS に入って復帰しました。ファームウェアの滞在時間カウンタは、カーネルの記録とミリ秒単位で一致しました。
- リセットがなくなったかどうかは、ふたを閉じるサスペンドを数十回試して判断します。

**注意:** ファームウェアは、OSI から PC モードへの切り替えを受け付けません。モジュールを外すと、次に起動するまで CPU は WFI だけで動きます。

```
cd osi-idle
sudo ./install.sh                         # DKMS。すぐ読み込み、起動時にも読み込む(/etc/modprobe.d に enable=1)
cat /sys/module/n1x_osi_idle/parameters/stats   # CPU_SUSPEND の結果: 電源断して復帰, すぐ復帰, DENIED, INVALID, その他
grep . /sys/module/n1x_osi_idle/parameters/st_*  # 同じものを要求した状態ごとに(WFI, コア, クラスタ, パッケージ SL/LL, DRIPS)
sudo ./drips-count                        # ファームウェアのカウンタ: DRIPS / パッケージ / クラスタの滞在時間(ns)と回数
sudo ./uninstall.sh                       # 削除後に再起動すると ACPI アイドルドライバに戻る
```

**モジュールパラメータ**

- `max_depth`: 普段の待機で使う一番深い状態。既定値は 4 です。1 = コア、2 = クラスタ、3/4 = パッケージ、5 = DRIPS(マシンが固まります)。
- `osi=0`: PC モードのまま動かします。ドライバ単体の試験用です。
- `pep=0`: `ELST` と SYSRAM への書き込みを行いません。

## keyboard: Caps Lock の遅れ

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

## audio-jack: ヘッドホンジャックの検出

linux-omarchy 7.3 の rt721-sdca ドライバでは、3.5mm ジャックにヘッドホンを挿しても検出されません。`Headphone Jack`
は off のままで、PipeWire はスピーカーから鳴らし続けます。挿したとき RT721 はジャック検出の割り込み(SDCA 割り込み
0)を出さず、Function_Status(割り込み 3)だけが来ます。抜いたときは検出されます。Linux v7.4-rc1 の rt721-sdca で
直っています。Realtek によるジャック検出の設定の見直し(`e2eb4873b901` "Adjust blindwrite flow to fix type detection
issue")と関連する修正が入っています。このディレクトリはそのドライバを無改変のまま 7.3 向けにビルドします(DKMS の
`BUILD_EXCLUSIVE_KERNEL` は `^7\.3\.`。7.4 には本体に入っています)。

```
cd audio-jack
sudo ./install.sh      # DKMS に入れて、すぐサウンドカードを組み直す。再起動不要
sudo ./uninstall.sh    # カーネル本体のモジュールに戻す
```

`install.sh` はサウンドカードを組み直す間、PipeWire を数秒止めます。

## speaker-amp: Windows のアンプ DSP ファームとチューニング

Linux だと本体スピーカーの音が Windows より平板で薄い。2 個の RT1320 アンプには DSP があり、Windows では Realtek
ドライバがそこにファームウェアと Surface 専用のチューニング(EQ、スピーカー保護、左右別の音作り)を読み込んでいる。
Linux はそれなしで鳴らしている。カーネルの `rt1320-sdw` には読み込む仕組み
(`realtek/rt1320/rt1320_<vendor>_<product>_<sku>.dat` と `rt1320_RAE_...dat`)があるが、この機種用のファイルは
どこにも配られていない。

このディレクトリは、それを**自分の Windows から**作り、ドライバ側で自動的に読み込ませる。

- `extract.py`: マウントした Windows の Realtek SDCA ドライバから `RTKDAT_10EC.dat` を読む。中身はバイト連鎖 XOR で
  難読化したパスワード付き ZIP で、鍵とパスワードは手元の `RtkSdcaXu.sys` から探す。この機種(SUBSYS
  `0x308E10EC`)では `Nocturne_A` の組(DSP コード 4 本、パラメータ 2 つ、アンプごとの RAE チューニング。
  SoundWire unique ID 0 が `FWFiles_20`、2 が `FWFiles_22`)が使われる。**Realtek・Microsoft のデータはリポジトリに
  入っていない**。生成物は `/usr/lib/firmware/updates/realtek/rt1320/` に置くだけ。
- `module/`: Linux v7.3 の `rt1320-sdw` に `surface-rt1320.patch` を当てたもの(DKMS、7.3 系のみ)。
  - DSP を、Realtek の Windows ドライバ(`RtkSdcaXu.sys` を静的解析して特定)がこの機種でやるのと同じ手順で起動する。
    アンプをホールド → DSP を完全リセット(ROM に戻し、クロックとコアのリセットをかける。電源が入ったばかりの
    アンプ、`0xd613` = 0 のときは省く) → コードを書く → AFX の
    パラメータをヘッダ最後で送る → 起動 → `0x3fc2bfc4` の合図を待つ → 起動後の設定。Linux 標準の手順は、DSP が
    きれいに止まっていたときしか起動できない。アンプは再起動や電源オフでも給電されたままなので、s2idle で SoC が
    クラッシュしたあとは二度と起動しなかった。
  - その間はアンプへのミキサー書き込みを待たせる。PipeWire 起動時に UCM がスピーカーを有効にする書き込みで、起動が
    失敗していた。
  - DSP ファームと RAE は、カード構築の 10 秒後(起動時の `n1x-sdw-settle` のバスリセットのあと。`alsactl` による
    `DSP FW Update` の復元も同じ遅延経路)に 1 台ずつ、復帰後にも読み込む(本家は復帰時にファームしか読み直さず、
    チューニングが消えていた)。
  - 左右で違うので RAE はアンプごとのファイル(`..._<unique id>.dat`)。
  - 「起動済み」と言う DSP は、メールボックスが空いているときだけ信用する。起動しなければバイパス(素の音)のままに
    して、DSP のレジスタをログに出す。
  - 2 チャネルのマイク録音は DP8 だけで送る。本家は常に DP8 + DP10(4 チャネル)を足すが、バスは 2 チャネル分しか
    確保しない。マイクが先に動いていると(通話中)DP10 がスピーカーのデータに重なり、データバス衝突、ぷちぷち音、
    片側のアンプの脱落が起きる。ホストはもともと DP8 しか読んでいないので、マイクの音は変わらない。
  - Windows と同じく、動いている DSP に初期化をかけない。初期設定の前(モジュールの読み込み・再読み込み)と
    remove のときに DSP を止める。DSP の読み込みから RAE の読み込みまでアンプ機能を PS0 に保ち、そこでは PDE23 を
    ACPI の最大値(8 秒)まで待ち、届かなければ読み込みをやめる。終わったら PDE23 を DAPM が最後に求めた状態に戻す
    (本家は必ず PS3 で終わっていた)。なお `0xc081` の bit 2 が 0 のとき(PS3 で待機中、電源投入直後)は `0xf01e` と
    DSP の RAM が `0xdeadbeef` を返す。それだけでは DSP の故障ではない。
  - 再生開始のたびに、両アンプの DSP が動いているか確かめる(レジスタは `dsp at playback:` としてログに出す)。
    長いランタイムサスペンドのあと、片側のアンプの DSP が止まっていて、音がもう片側に寄ることがあった。止まって
    いれば uevent(`RT1320_DSP=lost`)を送り、udev ルール `61-surface-ultra-amp.rules` が下のスリープフックで
    アンプの電源を入れ直す(10 分に 1 回まで)。
  - モジュールオプション `silence_detect`(-1 = プリセットのまま(オン)、0 = オフ、1 = オン。すぐ反映)。アンプの
    無音検出がオンだと、デジタル無音が約 15 秒続いたあと、片方のアンプがもう片方より約 2.5 秒遅れて鳴り出した。
    `install.sh` は `/etc/modprobe.d/n1x-rt1320-silence.conf` で `silence_detect=0` にする。
- `surface-ultra-amp-sleep`(systemd-sleep フック、`/usr/lib/systemd/system-sleep/` に入る)は、Windows が
  `CNT0._PS3` でやるように、s2idle の間アンプの電源を切る。Linux はこれを呼ばないので、アンプはスリープ中も給電
  されたままで、DSP が壊れた状態で戻ることがあった。スリープ前に PipeWire を止め、カードを外し、アンプのドライバを
  外して、アンプの LDO イネーブル(GPIO 47/74)を Low に保つ。復帰後はアンプの電源を入れてカードを作り直し、
  両アンプで DSP ファームが動くのを待ってから PipeWire を起動し、デスクトップのポータルを再起動する。復帰後
  約 20〜25 秒はスピーカーが鳴らない。
- 再生開始時の確認があるので、スピーカーを閉じないルール(`speaker-tuning/no-suspend.sh`)はもう要らない。
  スピーカーはまたサスペンドしてよく、アイドル時に約 0.8 W 減る。
- `amp-power-cycle.sh`(非常用、通常は不要)は、Windows で ACPI の `CNT0._PS3`/`_PS0` がやっているように、LDO の
  イネーブル(GPIO 74 = アンプ 1、GPIO 47 = アンプ 2)で両アンプの電源を入れ直す。Linux はこれを呼ばない。
  バスのエラーの後でスピーカーがぷちぷちしたり途切れたりするときに使う(モジュールの再読み込みだけではアンプの
  状態が戻らない)。後ろにモジュールのオプションを付けられる(例: `auto_dspfw=0`)。
- `speaker-amp-gain` はアンプのチャネル割り当ても Windows と同じにする(左アンプ `L,L`、右アンプ `R,R`。
  ドライバ既定の `L,R` を両方に送ると、音が真ん中に寄る)。
- `speaker-amp-gain`: teo さんの UCM プロファイルは、スピーカー保護がないためアンプ音量を 75(-9 dB)に抑えている。
  `install.sh` はそのプロファイルに `exec` を 1 行足し(バックアップあり)、両アンプで DSP が動いているときだけ
  85(-1.5 dB)に上げる。

```
cd speaker-amp
sudo ./install.sh              # ファーム + DKMS ドライバ + スリープフック、そのあとサウンドカードを作り直す
sudo ./install.sh --no-reload  # 同じ。次の起動から有効
./status.sh                    # 両アンプの DSP ファーム・チューニング・音量
sudo ./uninstall.sh
```

Windows のパーティションはマウントしなくてよい。`install.sh` が抽出のあいだだけ読み取り専用でマウントして外す
(Windows のディレクトリを渡してもよい)。ファームの生成は 1 回だけでよく、Windows が見つからなければ既存のものを使う。以前の試行でアンプを
触っていると、`install.sh` 直後の最初の読み込みが失敗することがある。その場合は再起動で直る。

## speaker-tuning: Dolby チューニングを PipeWire フィルタに

任意で、`speaker-amp` の上に重ねる。Windows の Dolby ドライバにもこの機種用のチューニング
(`SOUNDWIRE_SDCAFUNCTION_10_MAN_025D_FUNC_1320_SUBSYS_308E10EC.xml`)があるが、スピーカー EQ(`audio-optimizer`)が
無効なので、単体ではあまり変わらない。残るのは低音強調とリミッタ。`install.sh` は
[speaker-tuning-to-easyeffects](https://github.com/antoinecellerier/speaker-tuning-to-easyeffects)(MIT、固定コミットを
取得して使い、同梱しない)で、これを本体スピーカー用の PipeWire filter-chain に変換する。音量の自動調整
(-26 LUFS に揃えて小さくなる)は外す。XML は自分の Windows から読み(マウントされていなければ
`udisksctl` で一時的に読み取り専用でマウントし、以後はキャッシュを使う)、変換結果はマシンの外に出さない。

```
cd speaker-tuning
./install.sh        # 事前に: sudo pacman -S lsp-plugins-lv2 calf
./uninstall.sh
```

PipeWire を再起動したあとは、画面共有が壊れないようにデスクトップのポータルも再起動する。

変換結果は +4 dB(`volmax`)持ち上げてリミッタに入れるので、リミッタの自動レベル調整(ALR)がボーカルごと全体の
音量を上下させる(Windows の Dolby は帯域ごとに押さえる)。そこで `install.sh` は持ち上げと ALR をなくし(減った分は
speaker-amp のアンプ音量 85 でアナログ側で補う)、リミッタはクリップ防止の頭打ちだけにして、低音強調を 3.98 から 2 に
弱めている。低音強調は Windows ではオフだが、外すとこの筐体の厚みが消える。

**再生開始の遅れ。** しばらく無音だと PipeWire がスピーカーを閉じ、アンプも省電力に入る。リンクと 2 台のアンプ、
その DSP を起こすのに約 2 秒かかるので、最初の音が遅れる。ここではこれが既定のままで良い。speaker-amp が再生開始の
たびに両方の DSP を確認するし、閉じればアイドル時に約 0.8 W 減る。遅れが気になるなら `./no-suspend.sh on` で
スピーカーを開いたままにできる(WirePlumber のルール `wireplumber/51-speaker-no-suspend.conf`)。`./no-suspend.sh off`
で戻る。

## gpu-power: NVIDIA の電力管理のメモ

一部の N1X ノートは AC 接続時に GPU が約 750 MHz に張り付くのに、この機械では張り付かない理由を調べたときのメモです。測ったときのドライバは 620.70.06(オープンなカーネルモジュール)、linux-omarchy 7.3 です。620.70.06 では s2idle が壊れた(`nv_pmops_suspend` が `NV_ERR_NOT_SUPPORTED` を返した)ので、この機械は 615.78.08 に戻しています。`ratedtdp-probe` は 615 でも同じ値を読みます。機械を動かすのにここの物は不要です。

- **SoC の上限はファームウェアがすでにかけています。** CPU と GPU の両方に全負荷をかけると、SoC の平均電力(ACPI `\_TZ.PSOC`)は 80.0 W で落ち着き、GPU が自分でクロックを下げます(2132 → 1976 MHz)。OS 側に残っている仕事は表面温度を抑えることで、それは `thermal/` がやっています。
- **nvidia-powerd(Dynamic Boost)はこの機械では役に立ちません。** ファームは NVPCF の `_DSM` にリビジョン 0x300 でしか答えません。620 のデーモンは 3.x の設定を読みますが、ワーカーを作りません("No Worker Running!")。ワーカーの生成は 1.x/2.x の経路にしか無いためです。2.x のデータに見せると(`nvpcf-shim/`)QBoost は動きますが、反応するのはプラットフォームのファームからの NVPCF イベントだけです。GPU の上限の書き込み(非公開の制御 `0x2080e634`)は `NOT_SUPPORTED` で返り、CPU の上限は SBIOS の `_DSM` に送られます。
- **約 750 MHz の下限は RATED_TDP が決めているようです。** `RATED_TDP` の GLOBAL クライアントを FORCE_LIMIT にすると、負荷中の GPU が 2379 MHz / 49.6 W から 741 MHz / 12.5 W に下がり、DEFAULT で元に戻ります。`ctrl2080perf.h` には、最も優先度の高い RM クライアントが「電力コントローラが一つも動いていないとき」FORCE_LIMIT を要求する、とあります。この機械では RM クライアントを含む全クライアントが DEFAULT でした。
- NVPCF 3.0 の初期設定テーブル(サブファンクション 1)は AES で暗号化されています。鍵はドライバのユーザー空間のデーモンに入っているので、テーブルは読めます。鍵や復号ツールはここには置いていません。

### ratedtdp-probe

読み取りだけです。LD_PRELOAD した先のプログラムの RM ハンドルを使って、調停クライアントごとの RATED_TDP の要求を表示します。root は不要です。

```
cd gpu-power/ratedtdp-probe && make
LD_PRELOAD=$PWD/ratedtdp-probe.so nvidia-smi -L
```

### nvpcf-shim(実験)

nvidia-powerd 620 の QBoost ワーカーを N1X で動かす `LD_PRELOAD` シムです。NVPCF 3.x を隠し、2.x の問い合わせに答え、TGP の電力ポリシーを指定し、デーモンが読む x86 の RAPL MSR を模し、AC 状態を `ADP1` から返し、デーモンの制御目標が見えるように RM の制御をすべてログに残します。調査用で、常用するものではありません。`make` でビルドし(対応する open-gpu-kernel-modules の SDK ヘッダが要ります)、ファイル先頭にある `SHIM_*` 変数を付けて `LD_PRELOAD` でデーモンを動かします。

## 削除したもの

- `usb4/`(2026-11-12): linux-omarchy はドックの PCIe トンネルがある間だけトンネル用ルートポートを起こしておく
  (パッチ `1105`、7.3-3 にすでに入っている)ので、3 つのポートを常に起こしておく udev ルールは不要になりました。
- `power-button/install.sh` の `soc_button_array` ブラックリスト(2026-11-12): カーネル自身が `MSHW0040` を飛ばします。

入れていた場合: `sudo rm -f /etc/udev/rules.d/75-n1x-usb4-tunnel-pm.rules /etc/modprobe.d/n1x-no-soc-button-array.conf`

## ライセンス

GPL-2.0(LICENSE を参照)。`als/` の spi-hid のソースは linux-omarchy が取り込んでいる spi-hid パッチ群(Microsoft、
Google、Semihalf ほか)から取ったもので、変更点は各ファイルの先頭に書いてあります。
`audio-jack/` の rt721-sdca のソースは Realtek のもの(GPL-2.0-only)で、Linux v7.4-rc1 から無改変でコピーしています。
