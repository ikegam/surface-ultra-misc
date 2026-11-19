# ssam-helper: 改変モジュールを使わない標準 SSAM

(English: [README.md](README.md))

[surface-ultra-misc](../README_jp.md) の一部です。

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
  回り始め、44 ℃ で約 3000 rpm になります。表面温度 45 ℃ を超えた範囲で効く可能性は残りますが、[`thermal/`](../thermal/) が
  表面温度をそれより下に抑えるので、ファンは EC に任せています。

```
cd ssam-helper
sudo ./install.sh      # 入っている surface-n1x-ssam/1.0 をその場で置き換え。再起動不要
sudo ./rollback.sh     # surface-n1x-ssam/1.0 に戻す
```
