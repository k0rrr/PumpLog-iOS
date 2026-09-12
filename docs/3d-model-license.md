# 3D人体モデルの出典・ライセンス

PumpLogのBody画面では、hpfrei氏の
[Body Anatomy 3D Viewer](https://github.com/hpfrei/body-anatomy-3d-viewer)
に含まれる `body.glb` を使用しています。

このモデルは
[Z-Anatomy](https://github.com/Z-Anatomy/Models-of-human-anatomy)
を基にしています。PumpLogで使用しているモデルのライセンスは、
[Creative Commons Attribution-ShareAlike 4.0 International（CC BY-SA 4.0）](https://creativecommons.org/licenses/by-sa/4.0/deed.ja)
です。

## 使用した素材

- Body Anatomy 3D Viewer: hpfrei
- Anatomy source: Z-Anatomy contributors
- Original model: BodyParts3D / The Database Center for Life Science
- PumpLogで使用したsource revision: `0fc76a927aaf54c6fcc217cabdc3eb4d561130b7`

## PumpLogで行った改変

アプリ内で表示するため、次の加工と連携処理を行っています。

- 骨格メッシュの表示制御
- トレーニングした部位のハイライト表示
- 筋肉グループとPumpLogの部位IDの対応付け
- iOSアプリ内で読み込むための表示処理

改変したモデルもCC BY-SA 4.0の条件で扱います。出典、ライセンス、
改変内容はアプリのSetting画面と、このリポジトリ内のbundle noticesから
確認できます。PumpLogが元の作者や貢献者から承認・推薦されていることを
示すものではありません。

## ライセンス条件

CC BY-SA 4.0では、適切な帰属表示、ライセンスへのリンク、改変内容の表示、
改変物への同一ライセンスの適用が必要です。商用利用を含む共有・改変が認め
られていますが、配布時は必ずライセンス本文と各素材の条件を確認します。

完全な条文は[CC BY-SA 4.0の公式ページ](https://creativecommons.org/licenses/by-sa/4.0/legalcode)
を参照してください。

## 関連ライブラリ

- Three.js runtime and loaders/controls: [MIT License](../pumplog_ios/BodyAnatomyLicensed.bundle/THREE-LICENSE.txt)
- Draco decoder: [Apache License 2.0](../pumplog_ios/BodyAnatomyLicensed.bundle/DRACO-LICENSE.txt)

詳細な帰属情報は
[`ATTRIBUTION.md`](../pumplog_ios/BodyAnatomyLicensed.bundle/ATTRIBUTION.md)、
ライセンス本文は
[`LICENSE-CC-BY-SA-4.0.txt`](../pumplog_ios/BodyAnatomyLicensed.bundle/LICENSE-CC-BY-SA-4.0.txt)
に収録しています。

Z-Anatomyの配布物には、構成や参照元によって別ライセンスの素材が含まれる
場合があります。新しい素材を追加する場合は、元の配布元のライセンスと
必要なクレジットを個別に確認してください。
