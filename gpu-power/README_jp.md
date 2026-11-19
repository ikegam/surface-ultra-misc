# gpu-power: NVIDIA の電力管理のメモ

(English: [README.md](README.md))

[surface-ultra-misc](../README_jp.md) の一部です。

一部の N1X ノートは AC 接続時に GPU が約 750 MHz に張り付くのに、この機械では張り付かない理由を調べたときのメモです。測ったときのドライバは 620.70.06(オープンなカーネルモジュール)、linux-omarchy 7.3 です。620.70.06 では s2idle が壊れた(`nv_pmops_suspend` が `NV_ERR_NOT_SUPPORTED` を返した)ので、この機械は 615.78.08 に戻しています。`ratedtdp-probe` は 615 でも同じ値を読みます。機械を動かすのにここの物は不要です。

- **SoC の上限はファームウェアがすでにかけています。** CPU と GPU の両方に全負荷をかけると、SoC の平均電力(ACPI `\_TZ.PSOC`)は 80.0 W で落ち着き、GPU が自分でクロックを下げます(2132 → 1976 MHz)。OS 側に残っている仕事は表面温度を抑えることで、それは [`thermal/`](../thermal/) がやっています。
- **nvidia-powerd(Dynamic Boost)はこの機械では役に立ちません。** ファームは NVPCF の `_DSM` にリビジョン 0x300 でしか答えません。620 のデーモンは 3.x の設定を読みますが、ワーカーを作りません("No Worker Running!")。ワーカーの生成は 1.x/2.x の経路にしか無いためです。2.x のデータに見せると(`nvpcf-shim/`)QBoost は動きますが、反応するのはプラットフォームのファームからの NVPCF イベントだけです。GPU の上限の書き込み(非公開の制御 `0x2080e634`)は `NOT_SUPPORTED` で返り、CPU の上限は SBIOS の `_DSM` に送られます。
- **約 750 MHz の下限は RATED_TDP が決めているようです。** `RATED_TDP` の GLOBAL クライアントを FORCE_LIMIT にすると、負荷中の GPU が 2379 MHz / 49.6 W から 741 MHz / 12.5 W に下がり、DEFAULT で元に戻ります。`ctrl2080perf.h` には、最も優先度の高い RM クライアントが「電力コントローラが一つも動いていないとき」FORCE_LIMIT を要求する、とあります。この機械では RM クライアントを含む全クライアントが DEFAULT でした。
- NVPCF 3.0 の初期設定テーブル(サブファンクション 1)は AES で暗号化されています。鍵はドライバのユーザー空間のデーモンに入っているので、テーブルは読めます。鍵や復号ツールはここには置いていません。

## ratedtdp-probe

詳細: [ratedtdp-probe/README.md](ratedtdp-probe/README.md)(英語)。

読み取りだけです。LD_PRELOAD した先のプログラムの RM ハンドルを使って、調停クライアントごとの RATED_TDP の要求を表示します。root は不要です。

```
cd gpu-power/ratedtdp-probe && make
LD_PRELOAD=$PWD/ratedtdp-probe.so nvidia-smi -L
```

## nvpcf-shim(実験)

nvidia-powerd 620 の QBoost ワーカーを N1X で動かす `LD_PRELOAD` シムです。NVPCF 3.x を隠し、2.x の問い合わせに答え、TGP の電力ポリシーを指定し、デーモンが読む x86 の RAPL MSR を模し、AC 状態を `ADP1` から返し、デーモンの制御目標が見えるように RM の制御をすべてログに残します。調査用で、常用するものではありません。`make` でビルドし(対応する open-gpu-kernel-modules の SDK ヘッダが要ります)、ファイル先頭にある `SHIM_*` 変数を付けて `LD_PRELOAD` でデーモンを動かします。
