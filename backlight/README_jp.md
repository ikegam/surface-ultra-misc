# backlight: 自動輝度

(English: [README.md](README.md))

[surface-ultra-misc](../README_jp.md) の一部です。

`n1x-edp-backlight-auto.patch` は、teo-casares さんの `n1x-edp-backlight` に自動輝度を足すパッチです
(スクリプトは teo さんの Gist から取ってください。手順はパッチの先頭にあります)。`als` を使ってこの機種用の Windows の
lux → nits 曲線に追従します。輝度キーで調整した分は曲線へのオフセットとして保存され、再起動後も残ります。
`echo 0 > /var/lib/n1x-edp-backlight/auto` で自動輝度を止められます。起動時や、s2idle でパネルが明るさを失ったあとに
明るさを戻すときは、一気に変えずに約 0.3 秒かけて変えます(ファームウェアはパネルを別の明るさにしておくので、起動と
復帰のたびに明るさの変化が目に見えていました)。
