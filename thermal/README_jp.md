# thermal: 電力と表面温度の制御

(English: [README.md](README.md))

[surface-ultra-misc](../README_jp.md) の一部です。

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
