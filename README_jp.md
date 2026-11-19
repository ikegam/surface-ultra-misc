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
| [`als/`](als/) | 照度センサーのドライバ | 独立 |
| [`thermal/`](thermal/) | SoC 電力・表面温度の制御(CPU と GPU の制限、2 つのプロファイル)、Tj の安全網 | 独立。teo さんのファン制御デーモンを補うもので、`ssam-helper` が登録する SSAM 温度センサーを読む |
| [`ssam-helper/`](ssam-helper/) | 標準 SSAM + 補助モジュール | **teo さんが discussion で示した方式**を独自に実装したもの |
| [`backlight/`](backlight/) | 自動輝度 | **teo さんの `n1x-edp-backlight` へのパッチ**(スクリプト本体はここには入れていない) |
| [`power-button/`](power-button/) | 電源ボタンのドライバ | 独立したドライバ。phantom の「音量下げ」(浮いた `MSHW0040` のピン)の原因は teo さんが見つけたもの |
| [`suspend/`](suspend/) | ふたを閉じたときの誤復帰の防止、復帰直後にキーが効かない問題 | ふた閉じのフックは **teo さんが discussion で示した方式**を独自に実装し、タッチパッドと電源ボタンを足したもの。NVIDIA の部分は独立 |
| [`sapd-lps0/`](sapd-lps0/) | サスペンド前後に Surface 固有の Modern Standby 通知を送る(試験中) | 独立 |
| [`osi-idle/`](osi-idle/) | Windows と同じ PSCI OS-initiated モードで CPU アイドルと s2idle を動かす(試験中) | 独立 |
| [`sleep-debug/`](sleep-debug/) | サスペンドの診断:最後の PM 段階を UEFI 変数に残す、起動時のレポート、サスペンドごとのログ | 独立 |
| [`keyboard/`](keyboard/) | Caps Lock の遅れ、キー再マップでの連打 | 独立 |
| [`wifi-powersave/`](wifi-powersave/) | バッテリー時だけ Wi-Fi の省電力 | 独立 |
| [`audio-jack/`](audio-jack/) | ヘッドホンジャックの検出 | 独立(上流の Realtek ドライバ) |
| [`speaker-amp/`](speaker-amp/) | スピーカー: Windows のアンプ DSP ファームとチューニングで鳴らす | 独立。teo さんの音声環境(UCM プロファイル、`n1x-sdw-settle`)と組み合わせて動く |
| [`speaker-tuning/`](speaker-tuning/) | スピーカー: Windows の Dolby チューニングを PipeWire フィルタに(任意) | 独立 |
| [`gpu-power/`](gpu-power/) | NVIDIA の電力管理(nvidia-powerd、RATED_TDP)の調査メモと診断ツール | 独立 |

## 削除したもの

- `usb4/`(2026-11-12): linux-omarchy はドックの PCIe トンネルがある間だけトンネル用ルートポートを起こしておく
  (パッチ `1105`、7.3-3 にすでに入っている)ので、3 つのポートを常に起こしておく udev ルールは不要になりました。
- `power-button/install.sh` の `soc_button_array` ブラックリスト(2026-11-12): カーネル自身が `MSHW0040` を飛ばします。

入れていた場合: `sudo rm -f /etc/udev/rules.d/75-n1x-usb4-tunnel-pm.rules /etc/modprobe.d/n1x-no-soc-button-array.conf`

## ライセンス

GPL-2.0(LICENSE を参照)。`als/` の spi-hid のソースは linux-omarchy が取り込んでいる spi-hid パッチ群(Microsoft、
Google、Semihalf ほか)から取ったもので、変更点は各ファイルの先頭に書いてあります。
`audio-jack/` の rt721-sdca のソースは Realtek のもの(GPL-2.0-only)で、Linux v7.4-rc1 から無改変でコピーしています。
