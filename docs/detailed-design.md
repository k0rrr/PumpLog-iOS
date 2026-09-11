# PumpLog 詳細設計書

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 文書名 | PumpLog 詳細設計書 |
| 版 | 0.1 |
| 作成日 | 2026-08-29 |
| 対象 | フェーズ1ローカル保存版 |
| 開発方式 | SwiftUI / Swift |

## 2. システム構成

```text
ContentView
  ├─ RecordView             記録・テンプレート適用
  ├─ HistoryView            履歴・検索・編集
  ├─ GrowthView             成長分析
  ├─ MuscleMapView          部位負荷表示
  └─ ExerciseManagementView 種目・テンプレート管理

AppStore (@MainActor ObservableObject)
  ├─ exercises              種目マスタ
  ├─ records                保存済み履歴
  ├─ draft                  記録中の下書き
  ├─ templates              メニューテンプレート
  └─ personalBestMessage    自己ベスト通知

Persistence
  └─ UserDefaults（Codable JSON）
```

`ContentView`が`AppStore`を`@StateObject`として所有する。子画面へは`@ObservedObject`で共有し、記録・履歴・分析が同じ状態を参照する。

### 2.1 MVVMの責務

| 層 | 実装 | 責務 |
|---|---|---|
| Model / Store | `Models.swift`, `AppStore.swift` | データ定義、永続化、共有データの整合性 |
| ViewModel | `ViewModels.swift` | 画面状態、入力値、表示用変換、画面操作の窓口 |
| View | `ContentView.swift`, `ProgressView.swift`, `MuscleMapView.swift` | レイアウト、バインディング、画面遷移、入力フォーカス |

画面は`AppStore`のメソッドを直接呼び出さず、原則として対応するViewModelの操作メソッドを呼び出す。ViewModelは`AppStore.objectWillChange`を購読し、共有データの変更を自身のViewへ転送する。

対応するViewModelは次のとおり。

- `RecordViewModel`
- `HistoryViewModel`
- `GrowthViewModel`
- `MuscleMapViewModel`
- `ExerciseManagementViewModel`
- `WorkoutExercisePickerViewModel`
- `TemplatePickerViewModel`
- `TemplateEditViewModel`

## 3. モデル設計

### 3.1 列挙型

#### MuscleGroup

大分類は次の7種類とする。

```text
胸 / 背中 / 肩 / 腕 / 脚 / 腹 / 全身
```

#### MuscleRegion

身体マップと将来のアバター部位IDとして使用する。

```text
胸上部, 胸下部,
僧帽筋, 広背筋, 脊柱起立筋,
肩前部, 肩側部, 肩後部,
上腕二頭筋, 上腕三頭筋, 前腕,
腹直筋, 腹斜筋,
大腿四頭筋, ハムストリング, 臀筋, ふくらはぎ
```

#### SetKind

```text
warmup = ウォームアップ
working = 通常
```

### 3.2 エンティティ

#### Exercise

| 属性 | 型 | 必須 | 説明 |
|---|---|---:|---|
| id | UUID | ○ | 種目の安定識別子 |
| name | String | ○ | 種目名。重複不可 |
| muscleGroup | MuscleGroup | ○ | 大分類 |
| equipment | String |  | 使用器具 |
| targetMuscles | [MuscleRegion] | ○ | 対象詳細部位 |

対象部位未指定時は大分類の既定部位を設定する。標準3種目（ベンチプレス、スクワット、デッドリフト）には推奨部位を設定する。

#### WorkoutSet

| 属性 | 型 | 必須 | 説明 |
|---|---|---:|---|
| id | UUID | ○ | セット識別子 |
| weight | Double | ○ | 重量kg。0以上 |
| reps | Int | ○ | 回数。1以上 |
| kind | SetKind | ○ | ウォームアップまたは通常 |
| isCompleted | Bool | ○ | セット完了管理用。既定false |

#### SessionExerciseDraft

記録中の1種目分の下書き。

| 属性 | 型 | 説明 |
|---|---|---|
| id | UUID | 下書き内の種目エントリ識別子 |
| exerciseID | UUID | Exerciseへの参照 |
| sets | [WorkoutSet] | 入力済みセット |
| note | String | 種目メモ |

#### WorkoutDraft

```text
id: UUID
date: Date
exercises: [SessionExerciseDraft]
selectedEntryID: UUID?
restEndsAt: Date?
restDuration: Int（既定90秒）
```

`selectedEntryID`は種目タブの選択状態を示す。`restEndsAt`がnilでなければ休憩タイマー実行中とする。

#### WorkoutRecord

完了後に保存する種目単位の履歴。

| 属性 | 型 | 説明 |
|---|---|---|
| id | UUID | 履歴識別子 |
| exerciseID | UUID? | 種目参照。旧データ互換のためoptional |
| exerciseName | String | 保存時点の表示名 |
| date | Date | トレーニング日。表示は日付のみ |
| sets | [WorkoutSet] | 完了時点のセット |
| note | String | 種目メモ |
| sessionID | UUID? | 同一トレーニングを束ねるID |

1つの`WorkoutDraft`を完了すると、種目エントリごとに1件の`WorkoutRecord`を作成し、全件へ同じ`sessionID`を付与する。

#### WorkoutTemplate

```text
id: UUID
name: String
exerciseIDs: [UUID]
```

`exerciseIDs`の並び順をテンプレート内の種目順とする。

## 4. 状態管理設計

```swift
@Published var exercises: [Exercise]
@Published var records: [WorkoutRecord]
@Published var draft: WorkoutDraft
@Published var templates: [WorkoutTemplate]
@Published var personalBestMessage: String?
```

各状態の変更時に`didSet`から保存処理を呼び出す。`AppStore`は`@MainActor`で実行し、画面からの更新をメインスレッドへ統一する。

### 選択種目

- `selectedEntryIndex`で`selectedEntryID`から配列インデックスを取得する。
- 種目削除後、選択IDが存在しなければ先頭の種目を選択する。
- タブ表示は`SessionExerciseDraft.id`を安定IDとして使用する。

## 5. 画面詳細設計

### 5.1 記録画面（RecordView）

#### 表示構成

1. トレーニング：日付、種目追加、選択中種目を外す
2. 種目ごとに入力：横スクロールタブ、種目番号、種目名、種目数
3. セットを追加：重量、回数、追加ボタン
4. セット：セット番号、重量、回数、種別、複製、削除
5. 休憩タイマー：時間選択、開始、延長、終了
6. 種目メモ
7. トレーニング完了

#### セット追加処理

```text
入力値取得
  ↓
重量をDoubleへ変換（カンマをピリオドへ正規化）
  ↓
回数をIntへ変換
  ↓
重量 >= 0 かつ 回数 > 0 を検証
  ├─ NG: エラー表示、下書き変更なし
  └─ OK: appendSet()
          ↓
       入力欄を空にする
       フォーカス解除・キーボードを閉じる
```

#### 種目追加シート

- `WorkoutExercisePicker`をsheet表示する。
- 種目行をタップした時だけ親の`addExerciseToWorkout(id)`を呼び出す。
- 行タップ後はシートを閉じる。
- 「閉じる」またはスワイプ終了では`draft`を変更しない。
- 「新しい種目」から`ExerciseEditView`を開き、保存後に種目マスタへ追加する。

#### テンプレート適用処理

```text
テンプレート選択
  ↓
draft = WorkoutDraft()
  ↓
exerciseIDs順にaddExerciseToWorkout()
  ↓
先頭エントリをselectedEntryIDへ設定
  ↓
dateを現在日へ設定
  ↓
記録画面へ戻る
```

各種目の追加時、該当種目の最新履歴セットをコピーする。コピーしたセットには新しいセットIDを付与する。

#### 完了処理

```text
トレーニング完了
  ↓
下書き・種目数・セット数を検証
  ↓
重量 >= 0、回数 > 0を検証
  ├─ NG: 保存せずエラー表示
  └─ OK:
       WorkoutRecordを種目ごとに生成
       recordsへ追加
       自己ベストを計算
       draft = WorkoutDraft()
       重量・回数入力を空にする
       フォーカス・シート・タイマーを初期化
```

完了後は`draft.exercises`が空になるため、セット追加フォームとセット一覧は表示しない。

### 5.2 履歴画面（HistoryView）

- 検索条件、期間、部位フィルターを適用した表示配列を作る。
- 通常表示は日付単位にグループ化する。
- 検索時は種目名またはメモに一致する履歴を横断表示する。
- 編集保存は`updateRecord()`、削除は`deleteRecord()`を呼び出す。
- カレンダーの日付は`Calendar.startOfDay`で正規化する。

### 5.3 成長画面（GrowthView）

- 種目を選択する。
- `WorkoutAnalytics.records(for:in:)`で対象履歴を抽出する。
- 日付ごとの重量、回数、総負荷量を集計する。
- `WorkoutAnalytics.summary`から自己ベストを取得する。
- データがない場合は空状態を表示する。

### 5.4 身体画面（MuscleMapView）

- `MuscleLoadAnalytics`で記録を詳細部位へ展開する。
- `Exercise.targetMuscles`を部位ごとの負荷へ配分する。
- 未記録部位と負荷のある部位を区別して表示する。
- 将来のアバター表示に備え、表示名と部位識別子を分離する。

### 5.5 種目画面（ExerciseManagementView）

- 種目一覧を表示する。
- 種目の作成、編集、削除、並べ替えを行う。
- テンプレート一覧にはテンプレート名と種目名一覧を表示する。
- テンプレート作成画面では名前入力と種目複数選択を行う。
- テンプレート削除はスワイプで行う。

## 6. AppStore API設計

### 種目

```text
addExercise(name:muscleGroup:equipment:targetMuscles:) -> Bool
updateExercise(_ exercise:) -> Bool
deleteExercises(at offsets: IndexSet)
moveExercises(from source: IndexSet, to destination: Int)
```

### 記録下書き

```text
addExerciseToWorkout(_ exerciseID: UUID) -> Bool
selectWorkoutEntry(_ entryID: UUID)
removeSelectedExercise()
appendSet(weight: Double, reps: Int, kind: SetKind)
duplicateSet(at index: Int)
duplicateLastSet()
startRestTimer(seconds: Int)
addRestTime(_ seconds: Int)
stopRestTimer()
finishWorkout() -> Bool
repeatPreviousWorkout()
```

### 履歴・テンプレート

```text
updateRecord(_ record: WorkoutRecord)
deleteRecord(_ record: WorkoutRecord)
latestRecord(for exerciseID: UUID) -> WorkoutRecord?
addTemplate(name: String, exerciseIDs: [UUID]) -> Bool
deleteTemplates(at offsets: IndexSet)
applyTemplate(_ template: WorkoutTemplate)
```

## 7. 永続化設計

### 保存キー

| キー | 内容 |
|---|---|
| `exercises.v2` | `[Exercise]` |
| `records` | `[WorkoutRecord]` |
| `workout.draft` | `WorkoutDraft` |
| `workout.templates` | `[WorkoutTemplate]` |
| `exercises` | 旧形式の種目名配列 |

### 保存方式

- `JSONEncoder`でCodableモデルをDataへ変換する。
- `UserDefaults`へキー単位で保存する。
- 起動時に読み込み、復元不能な場合は既定値で起動する。
- 初回起動時はベンチプレス、スクワット、デッドリフトを用意する。

### 移行・整合性

- `targetMuscles`が旧データにない場合は大分類から補完する。
- `exerciseID`がない旧履歴は種目名からIDを解決する。
- 下書き内の存在しない種目IDは読み込み時に除外する。
- 種目削除時は関連する下書きとテンプレートの参照を更新する。

## 8. 集計設計

### 8.1 総負荷量

```text
セット負荷量 = weight × reps
種目総負荷量 = 対象種目のセット負荷量合計
期間総負荷量 = 対象期間の種目総負荷量合計
```

分析画面の既定値は通常セットのみとし、ウォームアップを含める設定は将来拡張とする。

### 8.2 自己ベスト

- 最大重量
- 最大回数
- 最大セット負荷量
- 1回のトレーニングにおける最大総負荷量

### 8.3 部位負荷

- セット負荷量を対象部位数で均等配分する。
- 同一部位の値を全種目・全履歴から合算する。
- 最大値または期間内相対値で表示強度を正規化する。

## 9. エラー処理

| ケース | 処理 |
|---|---|
| 種目名が空 | 保存せずエラー表示 |
| 種目名が重複 | 保存せず重複メッセージ表示 |
| テンプレート名が空 | 保存ボタン無効化 |
| テンプレート名が重複 | 保存せずエラー表示 |
| セット重量が不正 | 保存せず入力エラー表示 |
| セット回数が0以下 | 保存せず入力エラー表示 |
| セット未入力で完了 | 完了せず必要条件を表示 |
| 参照種目が存在しない | 下書き・テンプレートから除外 |
| JSON復号失敗 | 旧形式を試行し、失敗時は既定値で起動 |

## 10. テスト設計

### 10.1 単体テスト

- 入力値検証、重複追加防止
- 前回値コピー時の新しいセットID
- `finishWorkout`の正常保存、異常入力、空下書き
- 完了時に下書きが空になること
- `applyTemplate`の順序保持と先頭選択
- 種目追加画面を閉じるだけで下書きが変化しないこと
- 種目削除時の下書き・テンプレート参照整理
- 総負荷量、自己ベスト、部位負荷の集計

### 10.2 UIテスト

- 2種目を追加してタブ切替後も各セットが保持されること
- セット追加後にキーボードが閉じること
- 完了後にセット入力フォームとセット一覧が消えること
- テンプレートから開始し、各種目タブを入力できること
- 種目追加画面を開いて閉じても種目数が減らないこと
- 履歴検索、フィルター、編集、削除、カレンダー表示

### 10.3 回帰確認

- 再起動後の種目、履歴、テンプレート、下書き復元
- 旧保存データの読み込み
- タブ移動を繰り返してもクラッシュしないこと
- CoreSimulator上でDebugビルドが成功すること

## 11. 将来の身体アバター設計

### 11.1 方針

現在の`MuscleRegion`をアバター部位の論理IDとして再利用し、UI画像や3Dモデルへ直接依存しない。

### 11.2 データフロー

```text
WorkoutRecord
  ↓
Exercise.targetMuscles
  ↓
MuscleLoadAnalytics
  ↓
[MuscleRegion: load]
  ↓
表示強度へ正規化
  ↓
2D身体マップ / 3Dアバターへ着色
```

### 11.3 表示要件（将来）

- 前面・背面を切り替えられる。
- 部位をタップすると部位名、期間負荷、対象種目を表示する。
- 負荷が高いほど赤く、未記録はグレーで表示する。
- 色だけに依存せず、数値やラベルでも負荷状態を示す。
- 2D画像から3Dモデルへ変更しても集計ロジックを変更しない。
