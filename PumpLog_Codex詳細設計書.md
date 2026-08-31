# PumpLog Codex向け詳細設計書

| 項目 | 内容 |
|---|---|
| 文書版 | 1.0 |
| 対象 | iOSアプリ Phase 1（Workout Core MVP） |
| UI | SwiftUI |
| 永続化 | SwiftData |
| 設計 | Feature単位 + MVVM + 小さなService |
| 基準OS | iOS 17以上（SwiftData利用） |
| 対応端末 | iPhone、縦向きを優先 |

> 本書は、Codexが追加のプロダクト判断を極力行わずにPhase 1を一括実装できることを目的とする。本文で「必須」とした仕様を優先し、「推奨デフォルト」は定数・設定値として交換可能に実装する。「未確定」はPhase 1完了を妨げない。

---

## 1. プロダクト定義

### 1.1 コンセプト

**記録を最小限に。前回の自分を超える。**

PumpLogは、筋力トレーニング中の入力操作を減らし、現在の種目・セットに対応する前回値を自動提示して、成長をその場で確認できるiOSアプリである。

### 1.2 解決する課題

- セットごとに重量と回数を最初から入力する手間
- 前回の同種目・同セット記録を探す手間
- 休憩タイマーを別操作で開始する手間
- ジムの混雑時に固定された種目順を強制される不便
- トレーニング直後に成長を把握しづらい問題

### 1.3 UX原則

1. 前回値を初期値にし、変更部分だけを入力させる。
2. セット保存と休憩開始を1操作にまとめる。
3. Workout中は記録に不要な情報とBottom Tabを表示しない。
4. 今日選んだ種目は任意の順番で実施できる。
5. 欠損データを `0` と表現しない。
6. 保存は画面遷移より先に行い、強制終了から復元できるようにする。
7. 医学的根拠のない「回復率」は表示しない。

---

## 2. スコープ

### 2.1 Phase 1で必須

- Home
- Active Workoutがある場合の復帰導線
- 複数部位選択
- 登録済み種目の複数選択、追加、削除、並び替え
- 初期種目マスターのSeed
- Workout作成
- 任意順での種目切り替え
- 重量＋回数、および回数のみの記録
- 前回の同セット記録の表示と入力初期値への反映
- セット完了、追加、編集、削除
- 種目完了
- Rest Timer（バックグラウンド・再起動復元対応）
- Workout終了、Result、保存
- 最小限のPR判定
- Empty State、エラー表示、アクセシビリティ
- Unit Testおよび主要フローのUI Test

### 2.2 Phase 1では作らない

- Menuテンプレートの作成・編集
- Historyタブと詳細履歴UI（データはPhase 1から保存する）
- Body、人体図、部位別経過時間UI
- グラフ、Training Load、消費カロリー
- 通知、HealthKit、クラウド同期、アカウント
- 3D、高度なアニメーション、派手な演出
- lb切り替え、距離・時間種目

### 2.3 後続フェーズ

| Phase | 内容 |
|---|---|
| 2 | Menu、種目管理、Archive、Menuから開始 |
| 3 | History、Workout詳細、種目履歴 |
| 4 | Body（Front/Backの2D）、最終実施からの経過時間 |
| 5 | 詳細PR、進捗グラフ、演出、通知、UI Polish |

---

## 3. 技術方針

### 3.1 必須方針

- SwiftUI App lifecycleを使用する。
- SwiftDataの `ModelContainer` をアプリルートに注入する。
- Viewは表示とイベント転送、ViewModelは画面状態とユースケース調停を担当する。
- SwiftDataの検索・PR・前回値取得はServiceに分離し、Viewから直接複雑なQueryを実行しない。
- 日時は `Date` で保存し、経過時間は保存せず都度計算する。
- enumは `String, Codable, CaseIterable` とし、SwiftDataにはraw valueまたはCodable値として保存する。
- 金額ではない重量の丸め誤差をUIへ露出させない。表示とstep整列用に `WeightValue` ヘルパーを設けるか、0.5kg単位の整数化を採用する。
- Phase 1ではローカル・単一ユーザーのみ。

### 3.2 依存関係

```text
View
  ↓ user action / rendered state
ViewModel
  ├─ ModelContext
  ├─ PreviousRecordService
  ├─ PRService
  └─ WorkoutRecoveryService
          ↓
       SwiftData
```

View同士、ViewModel同士を直接参照させない。画面間で必要な識別子またはRouteを渡す。

---

## 4. 画面一覧と遷移

```text
起動
 └─ RootView
     ├─ active Workoutあり → Homeに「トレーニングに戻る」
     └─ active Workoutなし → Home

Home
 └─ トレーニング開始
     └─ MuscleSelection
         └─ 次へ
             └─ WorkoutSetup（今日のトレーニング）
                 └─ トレーニング開始
                     └─ Workout Mode
                         ├─ WorkoutExerciseList ↔ WorkoutEntry
                         ├─ Set Complete → Rest（同一Workout画面内の状態）
                         └─ Workout終了 → 確認 → Result → Home
```

### 4.1 Navigation要件

- Setupまでは `NavigationStack` を使う。
- Workout開始後は全画面のWorkout Modeに切り替え、Bottom Tabを表示しない。
- Workout中の通常の戻るジェスチャーでSetupへ戻れないようにする。
- Workout終了は明示ボタンと確認ダイアログを通す。
- Resultの「完了」でNavigationをHomeのルートへ戻す。

---

## 5. 画面仕様

### 5.1 HomeView

目的: 直近状況を理解し、最短でWorkoutを開始または再開する。

表示優先順位:

1. Active Workoutがあれば「トレーニングに戻る」カードとPrimary CTA
2. なければ「トレーニング開始」Primary CTA
3. 最新のcompleted Workout概要（存在する場合）
4. 初回Empty State

最新Workout概要は日付、実施部位、最大3種目と各種目の代表セットを表示する。Phase 1では詳細タップ先を作らず、無効なリンクを置かない。

Acceptance Criteria:

- 履歴0件で `0kg × 0` を表示せず、「まだ記録がありません」を表示する。
- active Workoutが1件ある場合、新規開始より復帰を優先する。
- active Workoutがある状態で新規Workoutを同時作成できない。

### 5.2 MuscleSelectionView

- 候補: 胸、背中、肩、二頭、三頭、脚、腹。
- 複数選択可、初期選択なし。
- 1つ以上選択するまで「次へ」をdisabledにする。
- 各部位は44×44pt以上のタップ領域を持つ。
- 選択状態は色に加えてcheckmarkまたは枠線でも示す。
- Phase 1では「最後に鍛えた日」の表示は任意。表示する場合はcompleted Workoutだけを対象にする。

### 5.3 WorkoutSetupView

- タイトル: 「今日のトレーニング」
- 選択された部位のExerciseだけを候補として表示する。
- Archive済みExerciseは候補に出さない。
- 同一Exerciseの重複追加は禁止する。
- 種目の複数選択、削除、Dragによる並び替えを可能にする。
- 1種目以上で「トレーニング開始」を有効にする。
- 開始時にWorkoutとWorkoutExerciseを一括作成・保存してからWorkout Modeへ遷移する。
- WorkoutExerciseの `orderIndex` は画面順の0始まり連番。

Empty State: 選択部位にExerciseがなければ「この部位の種目がありません」を表示する。Phase 1はSeedを含めるため通常は発生しないが、クラッシュさせない。

### 5.4 WorkoutExerciseListView

- 今日の全種目を並び順に表示する。
- 各行に種目名、完了セット数、完了状態を表示する。
- 完了・進行中・未着手を色だけでなくアイコンと文言で区別する。
- 任意の未完了または完了済み種目へ移動可能。完了済みも記録確認・編集のため開ける。
- 一覧から種目を追加する機能はPhase 1では任意。実装する場合も重複は禁止し、直後に保存する。
- Workout終了ボタンを表示する。

### 5.5 WorkoutView（入力状態）

表示:

- 種目名
- 現在の `SET n`
- 前回の同セット記録、または「前回記録はありません」
- WeightPicker（`weightAndReps` のみ）
- RepsPicker
- Primary CTA「セット完了」
- Secondary CTA「種目を完了」
- 完了済みセット一覧（編集・削除入口）
- 種目一覧への入口

入力範囲:

- 重量: 0〜500kg、Exerciseの `weightStep` ごと
- 回数: 1〜100回
- `repsOnly` は重量UIを表示せず `weight = nil`
- Pickerの初期値は「7. 前回記録と初期値」の規則に従う。

セット進行:

- 初回はSET 1だけを提示する。
- 「セット完了」で記録を作り、休憩状態へ移る。
- 休憩後のPrimary動作は「次のセット」でSET n+1を提示する。
- ユーザーがこれ以上行わない場合は「種目を完了」を押す。
- 固定3セットは前提にしない。

### 5.6 Rest状態

Restは別の永続画面モデルではなく、Active Workout内のUI状態としてWorkout画面に表示する。

- SET COMPLETEした値と、PR/前回差分を表示する。
- `mm:ss` の残り時間を表示する。
- 「次のセット」「種目一覧」「休憩をスキップ」を提供する。
- 0になっても自動遷移しない。0:00で停止し、ユーザー操作を待つ。
- Appがbackgroundでも絶対時刻 `restEndAt` との差分で再計算する。
- タイマーを秒数のデクリメント結果として永続化しない。
- 通知はPhase 1対象外。

### 5.7 セット編集・削除

- 完了済みセット行のタップまたはContext Menuから編集Sheetを開く。
- 編集可能項目は重量（対象種目のみ）と回数。
- 保存時に `updatedAt` を更新し、即座にSwiftDataへ保存する。
- 編集後はPRとResult集計を再計算する。PRフラグを固定保存しない。
- 削除は確認後に実行する。
- 削除後、同じWorkoutExercise内のsetNumberを1から連番へ詰め直し、一度の保存として処理する。
- 現在表示中のsetNumberは `sets.count + 1` から再計算する。
- 削除したセットが休憩の起点なら `restEndAt` と `restingAfterSetID` をclearする。

### 5.8 種目完了

- 1セット以上保存済みの場合に実行できる。
- 0セットで押した場合は確認なしに完了させず、「1セット以上記録してください」を示す。
- 実行時に `isCompleted = true`、`completedAt = now` として即保存する。
- 完了後も再度開いて編集できる。新しいセットを追加した場合は `isCompleted = false` に戻す。
- 全種目完了時はWorkout終了を提案するが、自動終了はしない。

### 5.9 Workout終了確認

確認ダイアログ:

- 1セット以上ある場合: 「トレーニングを終了しますか？」
- 未完了種目がある場合: 「未完了の種目があります。記録済みセットを保存して終了しますか？」
- 0セットの場合: 「記録がありません。このトレーニングを破棄しますか？」

動作:

- 1セット以上: statusをcompleted、endedAtをnow、休憩状態をclearして保存後Resultへ。
- 0セット: Workoutと子要素を削除しHomeへ。空のcompleted Workoutを残さない。
- 「キャンセル」は状態を変更しない。

### 5.10 ResultView

表示:

- 完了アイコン
- 実施部位（実際に1セット以上記録したExerciseから重複除去）
- 開始〜終了の所要時間
- 種目ごとのセット一覧
- 前回差分
- 今回達成したWeight PR / Rep PR数
- 「完了」CTA

初回種目は「初回記録」とし、PR数には含めない。全セットを表示できるようScrollViewを使用する。

---

## 6. データモデル

### 6.1 enum

```swift
enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest, back, shoulders, biceps, triceps, legs, abs
}

enum RecordType: String, Codable, CaseIterable {
    case weightAndReps
    case repsOnly
}

enum WorkoutStatus: String, Codable {
    case active
    case completed
}
```

表示名はenumのrawValueにせずLocalization層またはcomputed propertyで日本語化する。

### 6.2 Exercise（SwiftData `@Model`）

| Property | Type | 制約・意味 |
|---|---|---|
| id | UUID | unique |
| name | String | trim後1〜50文字 |
| muscleGroupRaw | String | MuscleGroup raw value |
| recordTypeRaw | String | RecordType raw value |
| weightStep | Double | `weightAndReps`で0より大きい |
| restDurationSeconds | Int | 0〜600 |
| isArchived | Bool | default false |
| seedKey | String? | Seed重複防止用、unique相当 |
| createdAt | Date | 作成日時 |
| updatedAt | Date | 更新日時 |

Exerciseは過去記録との参照を保持するため物理削除せず、将来UIではArchiveする。

### 6.3 Workout（SwiftData `@Model`）

| Property | Type | 制約・意味 |
|---|---|---|
| id | UUID | unique |
| startedAt | Date | 作成時刻 |
| endedAt | Date? | completed時のみ必須 |
| statusRaw | String | active/completed |
| restEndAt | Date? | Rest復元用絶対時刻 |
| restingAfterSetID | UUID? | Rest起点セット |
| selectedWorkoutExerciseID | UUID? | 復帰時に開く種目 |
| createdAt | Date | 作成日時 |
| updatedAt | Date | 状態変更日時 |
| workoutExercises | [WorkoutExercise] | cascade delete、UIではorderIndexでsort |

Workoutに選択部位は重複保存しない。実施部位は1セット以上記録されたWorkoutExerciseのExerciseから導出する。

### 6.4 WorkoutExercise（SwiftData `@Model`）

| Property | Type | 制約・意味 |
|---|---|---|
| id | UUID | unique |
| orderIndex | Int | 0始まり連番 |
| isCompleted | Bool | default false |
| completedAt | Date? | 種目完了日時 |
| workout | Workout? | inverse relationship |
| exercise | Exercise? | delete rule nullify/deny相当、履歴保護 |
| sets | [WorkoutSet] | cascade delete、setNumberでsort |

同一Workout内で同一Exerciseは1件のみ。開始前のViewModelと保存前validationの双方で防ぐ。

### 6.5 WorkoutSet（SwiftData `@Model`）

| Property | Type | 制約・意味 |
|---|---|---|
| id | UUID | unique |
| setNumber | Int | 1以上、同一WorkoutExerciseで連番 |
| weight | Double? | repsOnlyではnil |
| reps | Int | 1〜100 |
| completedAt | Date | セット完了時刻 |
| updatedAt | Date | 編集時刻 |
| workoutExercise | WorkoutExercise? | inverse relationship |

PRや前回差分は派生値であり保存しない。元データ編集後の不整合を防ぐためである。

### 6.6 Relationshipと削除規則

```text
Exercise 1 ── * WorkoutExercise * ── 1 Workout
                             |
                             1
                             |
                             *
                         WorkoutSet
```

- Workout削除 → WorkoutExerciseとWorkoutSetをcascade delete。
- WorkoutExercise削除 → WorkoutSetをcascade delete。
- Exerciseは使用履歴がある限り削除しない。Archiveで候補から隠す。
- optional relationshipになり得るSwiftDataの制約を考慮し、Service境界でnilを除外しUIに安全なDTOを返す。

---

## 7. 前回記録と入力初期値

### 7.1 「前回Workout」の定義

対象Exerciseについて、現在Workoutの `startedAt` より前に終了した `status == completed` のWorkoutを `endedAt` 降順に検索し、該当Exerciseで1セット以上存在する最新1件を前回Workoutとする。active、空セット、現在Workoutは除外する。

### 7.2 同セット記録

現在がSET nなら、前回Workout内の同Exerciseの `setNumber == n` を返す。

### 7.3 フォールバック

1. 前回Workoutの同セット番号
2. 前回Workoutの最後のセット
3. 現在Workoutの直前セット
4. Exercise既定値

Exercise既定値:

- `weightAndReps`: 20kg（weightStepへ整列）、8 reps
- `repsOnly`: 8 reps

この値は `AppDefaults` に集約し、後から変更可能にする。UIには「前回記録」としてフォールバック値を表示せず、実データがない場合は「前回記録はありません」と表示する。

### 7.4 表示形式

- 整数重量: `80kg × 8`
- 小数重量: `77.5kg × 8`
- repsOnly: `12回`
- Localeに依存しない小数誤差を避け、不要な `.0` を表示しない。

---

## 8. PR判定

### 8.1 比較対象

- 同一Exerciseの過去のcompleted Workoutに属するセットだけ。
- 現在セット、active Workoutの他セット、編集前の自分自身は除外する。
- 過去データ0件はPRではなく「初回記録」。

### 8.2 Weight PR

`recordType == weightAndReps` かつ今回重量が過去最大重量より大きい場合。

```text
current.weight > max(historical.weight)
```

### 8.3 Rep PR

- weightAndReps: 今回と同じ重量の過去セットにおける最大repsを超えた場合。
- repsOnly: 過去全セットの最大repsを超えた場合。

Doubleの同重量比較は表示単位へ正規化した値で行い、直接の浮動小数点完全一致に依存しない。

### 8.4 同時達成・同値

- Weight PRとRep PRは同時成立可。
- 過去最大と同値はPRではない。
- 重量増・回数減はWeight PRのみになり得る。
- 編集・削除後はその時点の全データから再計算する。

### 8.5 前回差分

PRとは別に同セットの前回値との差を表示する。例: `+2.5kg / -2回`。比較対象がなければ表示しない。

---

## 9. 状態遷移

### 9.1 Workout

```text
notCreated
  └─ startWorkout() / save → active
       ├─ resume → active
       ├─ finish（1セット以上）/ save → completed
       └─ discard（0セット）/ delete → notCreated
```

アプリ内にactive Workoutは最大1件とする。既存activeが複数見つかった場合、最新startedAtを復元候補とし、古いものは自動削除せずエラーを記録して安全にHomeへ案内する。

### 9.2 WorkoutExercise

```text
notStarted（0 set, isCompleted=false）
  └─ completeSet → inProgress
       ├─ completeSet → inProgress
       └─ completeExercise → completed
              └─ add/edit after completion → inProgress
```

### 9.3 Workout画面

```text
entry
 └─ completeSet/save → rest
      ├─ nextSet → entry(set + 1)
      ├─ skip → entry(set + 1)
      └─ exerciseList → list（restEndAtは維持）
```

別種目へ移動した場合、既存Rest TimerはWorkout全体で1つだけ維持する。別セット完了時は新しい `restEndAt` で上書きする。

---

## 10. 保存タイミングと整合性

| イベント | 保存内容 | 失敗時 |
|---|---|---|
| Workout開始 | Workout + WorkoutExercise一式 | 遷移せずエラー表示 |
| セット完了 | WorkoutSet、選択種目ID、restEndAt | Restへ遷移せず入力維持 |
| セット編集 | weight/reps/updatedAt | Sheetを閉じず再試行可能 |
| セット削除 | delete + setNumber再採番 | UIを確定更新しない |
| 種目完了 | isCompleted/completedAt | 完了表示へ変えない |
| 種目切替 | selectedWorkoutExerciseID | 切替は可能、復元位置のみ影響 |
| 休憩開始/終了 | restEndAt/restingAfterSetID | Timer表示を安全に解除 |
| Workout終了 | status/endedAt/rest clear | Resultへ遷移しない |
| 空Workout破棄 | Workout cascade delete | Homeへ遷移しない |

`ModelContext.save()` は上記のユーザー確定操作ごとに明示実行する。保存完了前に成功Hapticや完了画面を表示しない。多重タップ防止のため保存中は該当CTAをdisabledにする。

---

## 11. Active Workout復元

- 起動時またはHome表示時にactive Workoutを検索する。
- Homeに「トレーニングに戻る」を表示する。
- 復帰先は `selectedWorkoutExerciseID`、なければ最初の未完了種目、全て完了なら先頭種目。
- `restEndAt > now` ならRest状態を復元し残秒を再計算する。
- `restEndAt <= now` なら0:00状態を表示するか休憩状態をclearし、次セットへ進める。実装は前者で統一する。
- Relationship欠損、Exercise欠損など破損データは一覧から除外し、操作可能なデータがなければ破棄確認を提示する。
- アプリ終了時イベントだけに保存を依存しない。

---

## 12. Seedデータ

初回起動時のみ `seedKey` で冪等投入する。アプリ再起動・アップデートで重複させない。

最低例:

| 部位 | Exercise | Type | Step | Rest |
|---|---|---|---:|---:|
| 胸 | Bench Press | weightAndReps | 2.5kg | 90秒 |
| 胸 | Incline Dumbbell Press | weightAndReps | 2.0kg | 90秒 |
| 胸 | Cable Fly | weightAndReps | 2.5kg | 60秒 |
| 背中 | Lat Pulldown | weightAndReps | 2.5kg | 90秒 |
| 背中 | Seated Row | weightAndReps | 2.5kg | 90秒 |
| 肩 | Shoulder Press | weightAndReps | 2.0kg | 90秒 |
| 肩 | Side Raise | weightAndReps | 1.0kg | 60秒 |
| 二頭 | Dumbbell Curl | weightAndReps | 1.0kg | 60秒 |
| 三頭 | Push Down | weightAndReps | 2.5kg | 60秒 |
| 脚 | Squat | weightAndReps | 2.5kg | 120秒 |
| 脚 | Leg Press | weightAndReps | 5.0kg | 120秒 |
| 腹 | Crunch | repsOnly | 0 | 60秒 |

表記揺れを避けるため、表示名の日本語化をする場合は全件同じ言語へ揃える。Phase 1では上表の英語名を正とする。

---

## 13. UIデザイン仕様

### 13.1 Design Tokens

| Token | 値 |
|---|---|
| Background | `#0B0B0C` |
| Surface | `#171719` |
| Elevated | `#202023` |
| Primary Text | `#F5F5F7` |
| Secondary Text | `#8E8E93` |
| Accent | `#5E5CE6` |
| Positive | systemGreen |
| Warning | systemOrange |
| Destructive | systemRed |
| Grid | 8pt |
| Screen horizontal padding | 16〜20pt |
| Card radius | 16pt |
| Primary CTA height | 約56pt |
| Minimum tap target | 44×44pt |
| Animation | 150〜300ms |

### 13.2 Typographyと操作

- SF Pro相当のsystem fontを使う。
- 重量・回数・Timerは `monospacedDigit()`。
- Pickerの選択値は40〜48pt相当を目安にする。
- Primary CTAは画面下部の片手で届きやすい位置に置く。
- iOS標準 `Picker`、`NavigationStack`、`confirmationDialog`、Sheetを優先する。
- Reduce Motion有効時はscaleなどの不要な動きを無効化する。

### 13.3 Haptic

- Set Complete保存成功: medium
- PR成立: success（mediumと二重発火させずsuccessを優先）
- destructive確認: warning
- Pickerの値変更Hapticは発火過多になり得るためPhase 1では任意。

### 13.4 Accessibility

- Dynamic TypeでCTAや重要値が欠けない。必要なら縦積みに変える。
- VoiceOver label例: 「重量 80キログラム」「回数 8回」「セット1を完了」。
- 選択、完了、PRは色だけに依存しない。
- コントラストを確保する。
- VoiceOverの読み順を画面の意味順にする。

---

## 14. フォルダ構成

```text
PumpLog/
├── App/
│   ├── PumpLogApp.swift
│   ├── RootView.swift
│   ├── AppRoute.swift
│   └── AppDefaults.swift
├── Models/
│   ├── Exercise.swift
│   ├── Workout.swift
│   ├── WorkoutExercise.swift
│   ├── WorkoutSet.swift
│   ├── MuscleGroup.swift
│   ├── RecordType.swift
│   └── WorkoutStatus.swift
├── Features/
│   ├── Home/
│   │   ├── HomeView.swift
│   │   └── HomeViewModel.swift
│   ├── WorkoutSetup/
│   │   ├── MuscleSelectionView.swift
│   │   ├── WorkoutSetupView.swift
│   │   └── WorkoutSetupViewModel.swift
│   ├── Workout/
│   │   ├── WorkoutView.swift
│   │   ├── WorkoutViewModel.swift
│   │   ├── WorkoutExerciseListView.swift
│   │   ├── RestContentView.swift
│   │   └── SetEditorView.swift
│   └── Result/
│       ├── WorkoutResultView.swift
│       └── WorkoutResultViewModel.swift
├── Components/
│   ├── PrimaryButton.swift
│   ├── WeightPicker.swift
│   ├── RepsPicker.swift
│   ├── PreviousRecordView.swift
│   └── WorkoutSetRow.swift
├── Services/
│   ├── ExerciseSeedService.swift
│   ├── PreviousRecordService.swift
│   ├── PRService.swift
│   └── WorkoutRecoveryService.swift
├── DesignSystem/
│   ├── PumpLogColors.swift
│   └── PumpLogSpacing.swift
└── Resources/
    ├── Assets.xcassets
    └── Localizable.xcstrings

PumpLogTests/
├── PreviousRecordServiceTests.swift
├── PRServiceTests.swift
├── WorkoutViewModelTests.swift
├── WorkoutRecoveryServiceTests.swift
└── TestModelContainerFactory.swift

PumpLogUITests/
└── WorkoutFlowUITests.swift
```

ファイル数を増やすためだけの抽象化は禁止する。Repository protocolはテストで必要になった時点で追加する。

---

## 15. 命名・実装規則

- 型: UpperCamelCase、property/function: lowerCamelCase。
- Viewは `...View`、ViewModelは `...ViewModel`、Serviceは `...Service`。
- Boolは `is/has/can/should` で始める。
- UIイベント関数は動詞で始める: `startWorkout()`, `completeSet()`, `finishWorkout()`。
- 永続Modelの配列順に依存せず、必ず `orderIndex` / `setNumber` でsortする。
- UI表示文字列をModelの永続raw valueにしない。
- force unwrap、`try!`、無視した `try? modelContext.save()` を本番コードで使わない。
- `Date.now` をロジック内に直書きせず、テスト可能なClock/now closureを注入できる形にする。
- ViewModelを `@MainActor` にする。
- 1ファイル1主要型を基本にする。
- Magic numberは `AppDefaults` またはDesign Tokenに集約する。

---

## 16. エッジケース

| ケース | 期待動作 |
|---|---|
| 前回記録なし | Empty文言、既定入力値、PR扱いしない |
| 前回SET 3なし | 前回Workoutの最終セットを入力値へ使用、前回表示は「SET 3なし」 |
| repsOnly | weight nil、重量UI・Weight PRなし |
| 0kg | weightAndRepsでは許可可だが、初期仕様では範囲内。表示は0kg。データ欠損とは区別 |
| CTA連打 | 1セットだけ作成、保存中disabled |
| Picker範囲外の過去値 | 範囲へclampしstepへ正規化。元の履歴は変更しない |
| セット途中で種目変更 | 未保存Picker値は破棄。確定済みセットだけ保持 |
| Rest中に別種目へ移動 | Timer継続、起点を保持 |
| Rest中にアプリ終了 | restEndAtから復元 |
| 端末時刻変更 | wall-clock依存のため残秒が変化し得る。0〜restDurationへclamp |
| active Workout存在中の開始 | 新規作成せず復帰を案内 |
| Workout 0セット終了 | 確認後破棄、履歴を残さない |
| 未完了種目あり終了 | 記録済みセットを保持してcompleted |
| セット削除 | 再採番、PR/Result再計算 |
| ExerciseがArchive | 過去Workout表示は維持、新規候補から除外 |
| Relationship破損 | 該当行を安全に除外し、クラッシュしない |
| 保存失敗 | 成功画面へ進まず再試行可能なエラー |
| Dynamic Type最大 | 横並びが破綻せずScroll可能 |

---

## 17. テスト観点

### 17.1 Unit Test（必須）

PreviousRecordService:

- completedのみを対象にする。
- 最新の対象Workoutを選ぶ。
- 同セット、最後のセット、現在Workout直前セット、既定値の順でfallbackする。
- 同名でもIDが異なるExerciseを混同しない。
- 削除後の再採番でも正しく取得する。

PRService:

- 重量が過去最大超過でWeight PR。
- 同重量のreps超過でRep PR。
- repsOnlyのreps超過。
- 同値はPRではない。
- 初回はPRではない。
- active Workoutを過去比較に含めない。
- 小数重量を正規化して比較する。
- 編集・削除後に結果が変わる。

WorkoutViewModel:

- completeSetが1レコードだけ作る。
- 入力validation失敗時は保存しない。
- 保存成功時だけRestへ移る。
- delete後にsetNumberを詰める。
- completion後の追加でisCompletedをfalseへ戻す。
- finish時にstatus/endedAt/rest状態を正しく更新する。
- 0セットWorkoutを破棄する。

Recovery:

- selected Exerciseへ復帰する。
- future/pastのrestEndAtを正しく扱う。
- active 0件、1件、複数件、破損relationshipでクラッシュしない。

### 17.2 UI Test（主要Happy Path必須）

1. 初回起動 → 胸選択 → Bench Press追加 → Workout開始。
2. 初回値でSET 1完了 → Rest → 次セット → 種目完了。
3. Workout終了 → Result → Home。
4. 2回目Workoutで前回SET 1が表示・初期入力される。
5. SETを編集・削除し、番号とResultが更新される。
6. Active Workoutを残して再起動し、「トレーニングに戻る」から復帰する。
7. repsOnlyで重量UIが出ない。

### 17.3 Manual QA

- 実機でPicker、片手操作、Haptic、background復帰を確認する。
- VoiceOver、最大Dynamic Type、Reduce Motion、Dark Modeを確認する。
- 100セット程度の履歴でも入力画面に目立つ遅延がないことを確認する。
- 端末言語・12/24時間表示に依存せず壊れないことを確認する。

---

## 18. Codex向け実装順

各Stepの完了時にBuildと関連Testを実行し、失敗を次Stepへ持ち越さない。

1. Xcode projectの現状確認、Deployment Target、Test Target確認。
2. enum、SwiftData Model、Relationship、in-memory Test container。
3. App rootのModelContainerとSeedの冪等投入。
4. PreviousRecordServiceとPRServiceをテストファーストで実装。
5. Root/HomeとActive Workout検索。
6. MuscleSelectionとWorkoutSetup。
7. Workout作成と保存後の全画面遷移。
8. Workout入力、Picker、completeSet、Rest。
9. 種目一覧、自由な切替、種目完了。
10. セット編集・削除・再採番。
11. Workout終了、Result、空Workout破棄。
12. Active WorkoutとRest復元。
13. エラー処理、多重タップ防止、Accessibility。
14. Unit/UI Test拡充、実機QA、警告解消。

実装中に仕様とXcode/SwiftData制約が衝突した場合は、データ消失を避ける選択を優先し、変更理由と影響をREADMEまたは実装報告へ記録する。

---

## 19. Phase 1 Definition of Done / Acceptance Criteria

以下をすべて満たしたときPhase 1完了とする。

- [ ] 新規ユーザーが初回起動から種目を選び、1セット以上記録してWorkoutを完了できる。
- [ ] 2回目以降、前回の同Exercise・同setNumberが表示され、入力初期値になる。
- [ ] weightAndRepsとrepsOnlyを記録できる。
- [ ] 種目を任意順に切り替えてもセットが正しいWorkoutExerciseへ保存される。
- [ ] セットの追加・編集・削除後もsetNumberが連番で、ResultとPRが正しい。
- [ ] SET COMPLETEと同時に保存・比較・Rest開始が行われる。
- [ ] アプリを終了・再起動してActive WorkoutとRest状態へ復帰できる。
- [ ] Workout終了時に1セット以上の記録がcompletedとして保存される。
- [ ] 0セットWorkoutは確認後に破棄され、空履歴を残さない。
- [ ] Weight PR、Rep PR、初回記録が仕様どおり区別される。
- [ ] SwiftData保存失敗時に成功扱いせず、入力を失わず再試行できる。
- [ ] active Workoutが同時に複数作られない。
- [ ] Seedが再起動で重複しない。
- [ ] 主要タップ領域が44×44pt以上で、色以外でも状態を識別できる。
- [ ] Unit Testと主要UI Testが通り、Build warningを可能な限り0にする。
- [ ] Phase 1対象外の空Tabや未完成導線を本番UIへ露出しない。

---

## 20. 未確定事項と推奨デフォルト

未確定事項はPhase 1では以下の推奨値で実装し、定数またはModel propertyとして後から変更可能にする。

| 項目 | Phase 1推奨デフォルト | 将来の判断 |
|---|---|---|
| Deployment Target | iOS 17+ | 対象ユーザー分布で見直し |
| テーマ | Dark基準、固定Dark可 | Light完全対応 |
| 重量単位 | kgのみ | lb・単位変換 |
| 重量範囲 | 0〜500kg | Exercise別上限 |
| Reps範囲 | 1〜100 | 時間・距離型追加時に再設計 |
| 初回重量/回数 | 20kg × 8 / repsOnly 8 | Onboardingまたは種目別既定値 |
| Rest初期値 | Exercise別、Seedは60/90/120秒 | ユーザー編集UI |
| Weight Step | Exercise別、標準2.5kg | 種目管理UI |
| Workout中の種目追加 | 任意（後回し可） | ユーザーテスト後に必須化 |
| PR | Weight PR + 同重量Rep PR | e1RM、Volume PR |
| Body色基準 | Phase 1対象外 | 医学的回復ではなく経過時間 |
| 自重への加重/補助重量 | repsOnly | bodyweight + added/assisted weight型 |
| Active複数件 | 最新を案内、他は自動破棄しない | 修復UI/ログ |

### 実装前にプロダクトオーナー確認が望ましい項目

1. アプリ内の種目名を日本語・英語のどちらに統一するか。
2. Phase 1でWorkout中の種目追加を必須にするか。
3. Dark固定でリリースするか、System Appearanceに追従するか。
4. 0kgをweightAndRepsの有効値として許可するか。

回答がない場合は、本書の推奨デフォルトで実装を継続してよい。

---

## 21. Codexへ渡す実装指示テンプレート

```text
添付の「PumpLog Codex向け詳細設計書 v1.0」に従って、Phase 1を実装してください。

まず既存リポジトリ、Xcode project、Deployment Target、既存変更を確認し、ユーザーの既存変更を保持してください。仕様書の実装順に進め、各段階でBuildと関連Testを実行してください。安全な範囲の細部は設計書の推奨デフォルトを使用し、追加確認だけを理由に作業を止めないでください。

完了時は次を報告してください。
- 実装した機能
- 変更した主要ファイル
- 実行したBuild/Testと結果
- 仕様との差分および理由
- 残課題

データ損失、既存仕様との重大な衝突、署名・権限などユーザー判断が必須の問題がある場合だけ、具体的な選択肢と影響を示して確認してください。
```

---

## 付録A: 仕様上の重要な判断

- MenuはWorkoutではなくテンプレート。Phase 1では未実装。
- 選択部位ではなく、実際に1セット以上記録した種目から実施部位を導出する。
- Rest Timerは残秒ではなく終了絶対時刻を保存する。
- 前回値とPRはcompleted Workoutのみで判定する。
- 初回記録はPRに数えない。
- 固定セット数を設けず、1セットずつ追加する。
- 完了済み記録の編集・削除を許可し、派生情報を再計算する。
- Workout中断は自動破棄せずactiveとして復元する。

## 付録B: 非機能要件

- オフラインで全Phase 1機能が動くこと。
- ネットワーク権限を要求しないこと。
- 個人データを外部送信しないこと。
- 主要操作は通常端末で100ms以内に反応を開始し、保存中表示を出すこと。
- 日付・時刻・Locale・Calendarの違いでクラッシュしないこと。
- SwiftData migrationを将来追加できるよう、Model propertyの意味を安易に再利用しないこと。
