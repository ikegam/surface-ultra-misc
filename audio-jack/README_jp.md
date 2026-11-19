# audio-jack: ヘッドホンジャックの検出

(English: [README.md](README.md))

[surface-ultra-misc](../README_jp.md) の一部です。

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
