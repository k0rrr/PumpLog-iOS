# PumpLog コード構成

## レイヤー

- `ContentView.swift`: ルート遷移と、まだ分離していない既存画面群
- `Phase1BodyTab.swift`: Body Status画面と期間別の負荷集計
- `Phase1UIFoundation.swift`: 共通カラー、表示名、日付フォーマット
- `Body3DView.swift`: WKWebViewと3Dモデルの橋渡し
- `Phase1Models.swift`: SwiftDataのモデルと列挙型
- `Phase1Services.swift`: 初期データ、保存、前回記録などのサービス
- `*ViewModel`: 画面の状態と操作（Workout、セット編集、結果など）

## 変更時の目安

1. 画面固有のUIと状態は対象画面のファイルに置く
2. 複数画面で使う表示ルールは `Phase1UIFoundation.swift` に置く
3. SwiftDataの読み書きはViewModelまたはServiceに集約する
4. 3D表示の変更は `Body3DView.swift` と `BodyAnatomyLicensed.bundle` に限定する
5. 新しい画面を追加するときは、`ContentView.swift` に本体を追加せず、画面名のSwiftファイルを作ってルートから呼び出す

## 今後の分離候補

既存挙動を保護するため、`ContentView.swift` に残るHistory、Home、Workout、Resultは、機能変更のタイミングに合わせて順番に独立ファイルへ移す。
