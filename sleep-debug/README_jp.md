# sleep-debug: サスペンドの診断

(English: [README.md](README.md))

[surface-ultra-misc](../README_jp.md) の一部です。

s2idle でのリセット(`sapd-lps0` 参照)を調べるための道具です。ジャーナルは `Performing sleep operation` で途切れ、
pstore にも何も残りません。そこから先は RAM の中にしか無く、電源と一緒に消えるためです。機械を動かすのには不要です。

- **`n1x_sleep_trace`**(DKMS モジュール):`suspend_resume` トレースポイントにつなぎ、到達した PM の段階(サスペンド
  開始、`dpm_suspend*`、`machine_suspend`、DRIPS の出入り、`dpm_resume_noirq`、`dpm_complete`)を不揮発の UEFI 変数
  `N1XSleepTrace-e592f01a-...` に書きます。ブロックしないランタイムサービスの経路を使い、1 回のサスペンドで 10 回ほどの
  小さな書き込みです。リセットしても、最後に届いた段階が変数に残ります。
- **`n1x-sleep-collect`**(`n1x-sleep-collect.service`、起動ごとに 1 回):その変数を読み、前回の起動がどう終わったか
  (サスペンド中、正常終了、突然)、ファームの BERT 記録、起動時の RTC の時刻(電源が落ちたおおよその時刻)を調べ、SPM の
  SRAM 2 ページを保存します。起動ごとに 1 ブロックを `/var/log/n1x-sleep-trace.log` に、生データを
  `/var/lib/n1x-sleep-trace/<boot-id>/` に置きます。
- **`n1x-sleep-log`**(systemd-sleep フック):サスペンドの直前に機械の状態(蓋、電池、温度制御、GPU と使用中のアプリ、
  メモリ、カメラ、有効な wakeup 元、サスペンド統計、上位プロセス)を `/var/log/n1x-sleep.log` に書いて sync します。
  復帰後は s2idle の起床回数、増えた IRQ、ハードウェアが眠っていた時間を書きます。バッテリー時は、寝ている間の平均電力も
  `n1x-sleep-trace.log` に残します。

```
=== boot 8702c3ec collected 2026-11-19 23:13:37
previous boot ended abruptly (not in suspend)
trace var: suspend #1 started 2026-11-19 14:13:12, last phase dpm_complete:done [completed] (13 writes, DRIPS in/out 2/2, mono 1066.3s)
BERT: none
```

```
cd sleep-debug
sudo ./install.sh      # DKMS、すぐ読み込む。collector は次の起動から動く
sudo ./uninstall.sh    # UEFI 変数も消す
```

`sudo ./install.sh --panic` は、タスクのハングや CPU のロックアップを panic に変えます。カーネルログの末尾が efi-pstore に
残り、10 秒後に再起動します(`systemd-pstore` が `/var/lib/systemd/pstore` に写します)。`pm_debug_messages` と
`pm_print_times` も有効にします。`uninstall.sh` で戻ります。

`pm-test-loop.sh [freezer|devices|platform] [回数]`(root)は、サスペンドの処理をその `pm_test` の段階まで進めてすぐ戻す
のを繰り返します(既定 30 回)。各回の前に `/var/log/n1x-pmtest.log` に書いて fsync するので、電源が落ちたら最後の行で
どの回で落ちたか分かります。作業は先に保存してください。
