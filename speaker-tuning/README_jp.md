# speaker-tuning: Dolby チューニングを PipeWire フィルタに

(English: [README.md](README.md))

[surface-ultra-misc](../README_jp.md) の一部です。

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
