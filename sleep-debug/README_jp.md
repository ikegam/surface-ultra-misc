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
  s2idle の中で SoC を起こしているものを特定するための行も書きます(AC 接続時のスリープで、0.5 秒ごとに起きて
  すぐ眠り直すことがあります)。`s2idle-entries` は CPU ごとの s2idle 突入回数です。長いスリープでは journal が
  カーネルメッセージを取りこぼすので、こちらが本当の回数です。`wakeup-src-delta` はイベント数が増えた wakeup 元、
  `irq-all` は増えた IRQ すべてと、それが入った CPU です。回数とほぼ同じだけ増えた項目がトリガーです。

**トレーサは無効の状態で入ります**(`/etc/modprobe.d/n1x-sleep-trace.conf`: `options n1x_sleep_trace enable=0`)。
作者の機械でも 2026-11-21 から無効です。1 回のサスペンドで不揮発の UEFI 変数に 10 回ほど書き、そのうち数回は DRIPS の
直前、割り込み禁止の `tick_freeze()` の中で書きます。ちょうどその区間で電源が落ちうる機械では、ファームの変数領域(起動
エントリ、Secure Boot の鍵)を壊すおそれがあります。調べたい段階のタイミングも変えてしまいます。有効にするのは、短い
試験のときだけにしてください: `echo Y | sudo tee /sys/module/n1x_sleep_trace/parameters/enable`。collector と
スリープログのフックは UEFI 変数に書かないので、有効のままです。

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
