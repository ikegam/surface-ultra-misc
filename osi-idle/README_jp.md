# osi-idle: Windows と同じ OS-initiated CPU アイドル

(English: [README.md](README.md))

[surface-ultra-misc](../README_jp.md) の一部です。

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
- `s2idle_depth`: s2idle で要求する状態です。動作中に書き換えられ、次のサスペンドから効きます。既定値は 5(Standby-DRIPS)です。ふたを閉じた長時間のサスペンドは、OSI の有無にかかわらず DRIPS の中で同じ BERT 記録(原因 0xa0000004)を残して落ちます。DRIPS そのものが原因かを確かめるために、4(パッケージの電源断)を選べるようにしています。
- `osi=0`: PC モードのまま動かします。ドライバ単体の試験用です。
- `pep=0`: `ELST` と SYSRAM への書き込みを行いません。
