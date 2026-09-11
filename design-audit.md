# PumpLog 操作性監査（2026-09-09）

## 実施条件

- iPhone 16 Pro / iOS 18.5 Simulator
- 既存のPumpLogアプリコンテナを確認後、`simctl uninstall`でアプリデータを削除
- 空の初期状態からフローを再実行
- ビルド: `xcodebuild -project pumplog_ios.xcodeproj -scheme pumplog_ios -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO`

## 確認したフロー

1. Home（空状態・4タブ）
2. Home → 部位選択
3. 部位選択 → 今日のトレーニング
4. 種目選択 → Workout
5. Wheel Picker（重量・回数）
6. SET COMPLETE → Rest Timer
7. Restの時間調整（±30秒）と次セット導線
8. トレーニング終了確認
9. Result表示
10. Homeへ戻る導線と履歴保存

## 見つかった問題と対応

### P1: 部位選択で複合部位と単一部位が同時選択される

複合部位（胸・三頭）を選択したとき、重複する「胸」も選択状態に見えていました。選択を単一の部位セットとして扱い、行の選択表示も完全一致に変更しました。

### P1: Workout中にTabBarが残り、誤操作の余地がある

部位選択・Workout設定・Workout・ResultでTabBarを非表示にしました。Homeへ戻った後は通常のTabViewに戻ります。

### P1: 前回記録の表示が二重になる

「前回記録記録なし」のような二重表現が発生し得たため、履歴あり／なしの表示を整理し、「前回記録なし・初期値…」に統一しました。

### P2: Workoutの種目名が保存名（日本語）で表示される

保存データは変更せず、Workout／Restの画面表示だけFigmaと同じ英語名（Bench Press等）に変換しました。

### P2: セット開始時の操作量

重量・回数はWheel Pickerで、前回値がなければ初期値を自動表示。SET COMPLETE後はRest Timerを自動開始し、休憩中は「次のセット」を明示しています。

### P2: 履歴の月送りタイトルが固定される

月送りで一覧は切り替わるのに見出しが現在月のままになる問題を修正し、表示中の月と見出しを同期しました。

## スクリーンショット証跡

- `/private/tmp/pumplog_audit_01b_home.png`
- `/private/tmp/pumplog_audit_08b_setup.png`
- `/private/tmp/pumplog_audit_final_workout.png`
- `/private/tmp/pumplog_audit_final_rest.png`
- `/private/tmp/pumplog_audit_final_result.png`
- `/private/tmp/pumplog_audit_final_clean_home.png`
- `/private/tmp/pumplog_audit_final_history_empty.png`

## 残課題

- Body Statusの筋肉ヒートマップは次フェーズ。
- Rest終了直後は画面状態が切り替わるため、実機では「次のセット」CTAのタップ領域をさらに広げると安心です。
- Simulator座標操作では画面スケールによりCTA位置がずれるため、最終確認は実機またはXCUITestで行うのが望ましいです。
- テスト終了時にSimulatorアプリを再インストールし、作成したテスト記録は削除済みです。

**初回UI監査結果: passed**

---

# 総合QA追補（2026-09-09）

## 1. テストした操作パターン

- 空データでの初回起動、通常起動、4タブ表示
- Home → 部位選択 → 今日のトレーニング → Workout
- 戻る／キャンセル、部位の単一選択・複合選択
- WorkoutのWheel Picker（重量・回数）表示
- SET COMPLETE、Rest Timer、±30秒操作
- SET COMPLETEの短時間連打
- Rest中の「次のセット」操作
- 終了確認ダイアログのキャンセル
- 長い種目名に対するレイアウト保護（コード確認）
- 空入力、0、範囲外値に対する入力制御（Picker・作成フォームのコード確認）
- SwiftDataの保存経路、再起動復元経路（コード確認）
- ダークモード、Dynamic Type、VoiceOverラベル（コード・画面確認）

## 2. 発見した問題（重大度順）

### P1 — Rest解除時のタッチスルー

- 重大度: High
- 対象画面: Rest
- 再現手順: SET COMPLETE → Rest表示 → 「次のセット」をタップ
- 期待される挙動: Restを閉じてWorkoutの次セットへ進む
- 実際の挙動: Rest解除と同じタップが背後の終了ボタンにも伝播し、終了確認が開くことがある
- 原因: `skipRest()`がオーバーレイを同期的に消していた
- 修正方針: 現在のタップイベントが完了した次のメインループでRest状態を解除
- 修正したか / TODOにしたか: 修正済み

### P1 — 主要CTAの連打による二重保存リスク

- 重大度: High
- 対象画面: Workout／Workout設定
- 再現手順: SET COMPLETEまたはワークアウト開始を短時間に連打
- 期待される挙動: 1回分だけ保存・1つのActive Workoutだけ作成
- 実際の挙動（修正前）: 連打を明示的に抑止するガードがなかった
- 原因: 保存処理前の状態ガード不足
- 修正方針: Rest中のSET COMPLETEを無視し、既存Active Workoutがあれば新規作成しない
- 修正したか / TODOにしたか: 修正済み

### P2 — 履歴の月送り見出し不整合

- 重大度: Medium
- 対象画面: History
- 再現手順: 月送り矢印をタップ
- 期待される挙動: 一覧と見出しが同じ月になる
- 実際の挙動（修正前）: 一覧だけが切り替わり、見出しが現在月のまま
- 原因: 見出しが`Date()`を直接参照
- 修正方針: `displayedMonth`を見出しにも使用
- 修正したか / TODOにしたか: 修正済み

### P2 — 長い種目名によるレイアウト圧迫

- 重大度: Medium
- 対象画面: 今日のトレーニング／Workout
- 再現手順: 長い日本語・英数字・記号を含む種目名を作成して表示
- 期待される挙動: CTAや数値を押し出さず、読みやすく表示
- 実際の挙動（修正前）: 1行表示前提で横幅を圧迫する可能性
- 原因: 表示テキストの行数・縮小指定不足
- 修正方針: 最大2行＋最小縮小率を指定
- 修正したか / TODOにしたか: 修正済み

## 3. 修正した問題

変更ファイルは[ContentView.swift](/Users/chon/Desktop/pumplog_ios/pumplog_ios/ContentView.swift)のみです。

- `Phase1WorkoutSetupViewModel.start()`にActive Workout重複作成防止を追加
- `Phase1WorkoutViewModel.completeSet()`にRest中の再保存防止を追加
- `skipRest()`の状態解除をメインループへ遅延し、タッチスルーを防止
- Workout／設定画面の長い種目名を2行・縮小表示に対応
- 既存のSwiftDataモデル、保存形式、ナビゲーション構造は維持

## 4. 再テスト結果

- 修正後ビルド: 成功（`** BUILD SUCCEEDED **`）
- 空データ起動: 成功
- Home → 部位選択 → 設定 → Workout: 成功
- Wheel Picker: 成功
- SET COMPLETE連打: Restは1回だけ開始し、二重Rest表示なし
- Restタッチスルー: 修正後は終了確認が開かないことを確認。ただしSimulator座標の不安定により「次セット」遷移自体は追加のXCUITestで確定させる余地あり
- テスト用データ: 最終確認前にSimulatorアプリをアンインストールし削除

## 5. PRODUCT TODO（仕様判断が必要）

- Body Statusの筋肉ヒートマップと負荷集計の仕様
- duration記録（時間）の入力UI・保存モデル
- Active Workoutが存在する状態で新規開始を選んだ場合の扱い
- 種目名の最大文字数、同名種目を別部位で許可するか
- Rest終了時に0秒表示を残すか、自動で通常Workoutへ戻すか
- 破棄・削除確認の文言と確認回数

## 6. UX改善候補

- WorkoutのCTAを画面下部の片手操作範囲に固定
- 前回値・前セット値の表示を1行に整理し、再入力を不要にする
- セット完了直後に次のセット番号を大きく表示
- Pickerの現在値を触覚フィードバックで補助（設定で無効化可能）
- 長い履歴は月単位だけでなく検索・フィルタを追加
- Body/MenuのPlaceholderから実データ状態・空状態へ拡張

## 7. 追加した自動テスト

既存プロジェクトにXCTestターゲットがないため、今回はテストターゲットを新設していません。今回の重要回帰ケースは、次回XCUITest追加時に以下を優先します。

- SET COMPLETE連打が1セットだけ保存される
- Restの次セットタップが終了確認へ伝播しない
- Active Workoutが二重作成されない
- 月送りで見出しと一覧が一致する
- 0／500kg／1／100回の境界値

## 8. 未テスト領域

- 実機での通知・バックグラウンド復帰・ロック画面中のRest Timer
- VoiceOver実走査、Switch Control、完全なキーボード操作
- 文字サイズ最大設定での全画面レイアウト
- 大量のWorkout／Setを投入した長時間スクロール
- CoreSimulatorサービス停止中の復旧（ホスト側障害）
- 修正後のResult → History詳細までの再実行（Simulatorサービス停止により中断）

## 9. 現在のPumpLogの品質評価

Critical未解決: なし。High相当の明確な操作バグは修正済みです。主要Workoutフローは通常利用可能ですが、実機またはXCUITestでRest遷移・再起動復元・大量データを最終確認してからリリース候補とする状態です。

**final result: passed with verification gaps**
