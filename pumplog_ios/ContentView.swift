import SwiftUI

private enum AppTab: Hashable {
    case record
    case history
    case growth
    case body
    case exercises
}

struct ContentView: View {
    @StateObject private var store = AppStore()
    @State private var selectedTab: AppTab = .record

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordView(store: store)
                .tabItem { Label("記録", systemImage: "plus.circle") }
                .tag(AppTab.record)
            HistoryView(store: store)
                .tabItem { Label("履歴", systemImage: "clock") }
                .tag(AppTab.history)
            GrowthView(store: store)
                .tabItem { Label("成長", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.growth)
            MuscleMapView(store: store)
                .tabItem { Label("身体", systemImage: "figure.arms.open") }
                .tag(AppTab.body)
            ExerciseManagementView(store: store)
                .tabItem { Label("種目", systemImage: "list.bullet") }
                .tag(AppTab.exercises)
        }
    }
}

private struct RecordView: View {
    @ObservedObject var store: AppStore
    @State private var weight = ""
    @State private var reps = ""
    @State private var showValidationError = false
    @State private var showingExercisePicker = false
    @State private var showingTemplatePicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("トレーニング") {
                    DatePicker("日時", selection: $store.draft.date)
                    if !store.draft.exercises.isEmpty {
                        Picker("種目", selection: entrySelection) {
                            ForEach(store.draft.exercises) { entry in
                                Text(store.exercise(for: entry)?.name ?? "削除された種目")
                                    .tag(Optional(entry.id))
                            }
                        }
                    }
                    HStack {
                        Button("種目を追加", systemImage: "plus") { showingExercisePicker = true }
                        Spacer()
                        if store.selectedEntry != nil {
                            Button("種目を外す", systemImage: "minus.circle", role: .destructive) {
                                store.removeSelectedExercise()
                            }
                        }
                    }
                }

                if let entryIndex = store.selectedEntryIndex {
                    Section("セットを追加") {
                        HStack {
                            TextField("重量 (kg)", text: $weight).keyboardType(.decimalPad)
                            TextField("回数", text: $reps).keyboardType(.numberPad)
                            Button("追加", action: addSet).buttonStyle(.borderedProminent)
                        }
                        if store.draft.exercises[entryIndex].sets.isEmpty {
                            Text("重量と回数を入力してセットを追加してください")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !store.draft.exercises[entryIndex].sets.isEmpty {
                        Section("セット") {
                            ForEach(Array(store.draft.exercises[entryIndex].sets.indices), id: \.self) { index in
                                SetEditorRow(
                                    number: index + 1,
                                    set: $store.draft.exercises[entryIndex].sets[index],
                                    onDuplicate: { store.duplicateSet(at: index) },
                                    onDelete: { store.draft.exercises[entryIndex].sets.remove(at: index) },
                                    onCompletionChange: { store.setCompletion(at: index, isCompleted: $0) }
                                )
                            }
                            Button("最後と同じセットを追加", systemImage: "plus.square.on.square") {
                                store.duplicateLastSet()
                            }
                        }
                    }

                    Section("種目メモ") {
                        TextField(
                            "フォームや体調など",
                            text: $store.draft.exercises[entryIndex].note,
                            axis: .vertical
                        )
                        .lineLimit(2...5)
                    }
                }

                Section {
                    Button("トレーニングを完了") {
                        showValidationError = !store.finishWorkout()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(store.draft.exercises.isEmpty)
                }
            }
            .navigationTitle("PumpLog")
            .safeAreaInset(edge: .bottom) {
                if store.draft.restEndsAt != nil {
                    RestTimerBanner(store: store)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("テンプレートから開始", systemImage: "list.clipboard") {
                            showingTemplatePicker = true
                        }
                        Button("前回のメニューを複製", systemImage: "arrow.clockwise") {
                            store.repeatPreviousWorkout()
                        }
                        .disabled(!store.hasPreviousWorkout)
                    } label: {
                        Label("メニュー", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                WorkoutExercisePicker(store: store)
            }
            .sheet(isPresented: $showingTemplatePicker) {
                TemplatePickerView(store: store)
            }
            .alert("保存できません", isPresented: $showValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("すべての種目に1回以上の有効なセットを入力してください。")
            }
            .alert("自己ベスト更新！", isPresented: personalBestAlert) {
                Button("OK") { store.personalBestMessage = nil }
            } message: {
                Text(store.personalBestMessage ?? "")
            }
            .overlay {
                if store.exercises.isEmpty {
                    ContentUnavailableView(
                        "種目がありません",
                        systemImage: "dumbbell",
                        description: Text("「種目」タブで種目を追加してください。")
                    )
                } else if store.draft.exercises.isEmpty {
                    ContentUnavailableView {
                        Label("種目を追加してください", systemImage: "dumbbell")
                    } description: {
                        Text("種目またはテンプレートを選んでトレーニングを始めます。")
                    } actions: {
                        Button("種目を追加") { showingExercisePicker = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var entrySelection: Binding<UUID?> {
        Binding(
            get: { store.draft.selectedEntryID },
            set: { newValue in
                guard let newValue else { return }
                store.selectWorkoutEntry(newValue)
            }
        )
    }

    private var personalBestAlert: Binding<Bool> {
        Binding(
            get: { store.personalBestMessage != nil },
            set: { if !$0 { store.personalBestMessage = nil } }
        )
    }

    private func addSet() {
        guard let parsedWeight = Double(weight.replacingOccurrences(of: ",", with: ".")),
              let parsedReps = Int(reps), parsedWeight >= 0, parsedReps > 0 else {
            showValidationError = true
            return
        }
        store.appendSet(weight: parsedWeight, reps: parsedReps)
        weight = ""
        reps = ""
    }
}

private struct SetEditorRow: View {
    let number: Int
    @Binding var set: WorkoutSet
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    var onCompletionChange: ((Bool) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    let newValue = !set.isCompleted
                    set.isCompleted = newValue
                    onCompletionChange?(newValue)
                } label: {
                    Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(set.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)
                Text("Set \(number)").font(.headline)
                Spacer()
                Menu {
                    Button("複製", systemImage: "plus.square.on.square", action: onDuplicate)
                    Button("削除", systemImage: "trash", role: .destructive, action: onDelete)
                } label: { Image(systemName: "ellipsis.circle") }
            }
            HStack {
                TextField("重量", value: $set.weight, format: .number)
                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                Text("kg ×")
                TextField("回数", value: $set.reps, format: .number)
                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                Text("回")
            }
            Picker("種類", selection: $set.kind) {
                ForEach(SetKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
            }
            .pickerStyle(.segmented)
        }
        .opacity(set.isCompleted ? 0.65 : 1)
    }
}

private struct RestTimerBanner: View {
    @ObservedObject var store: AppStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int((store.draft.restEndsAt ?? context.date).timeIntervalSince(context.date)))
            HStack(spacing: 16) {
                Image(systemName: "timer")
                VStack(alignment: .leading) {
                    Text("休憩タイマー").font(.caption)
                    Text(durationText(remaining)).font(.title3.monospacedDigit().bold())
                }
                Spacer()
                Button("+30秒") { store.addRestTime(30) }
                Button("終了") { store.stopRestTimer() }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
    }

    private func durationText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct WorkoutExercisePicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AppStore

    var body: some View {
        NavigationStack {
            List(store.exercises) { exercise in
                Button {
                    store.addExerciseToWorkout(exercise.id)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(exercise.name)
                            Text(exercise.muscleGroup.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.draft.exercises.contains(where: { $0.exerciseID == exercise.id }) {
                            Image(systemName: "checkmark").foregroundStyle(.green)
                        }
                    }
                }
            }
            .navigationTitle("種目を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

private struct TemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AppStore

    var body: some View {
        NavigationStack {
            List(store.templates) { template in
                Button {
                    store.applyTemplate(template)
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        Text(template.name)
                        Text("\(template.exerciseIDs.count)種目")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if store.templates.isEmpty {
                    ContentUnavailableView(
                        "テンプレートがありません",
                        systemImage: "list.clipboard",
                        description: Text("「種目」タブで作成できます。")
                    )
                }
            }
            .navigationTitle("テンプレート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

private struct HistoryView: View {
    @ObservedObject var store: AppStore
    @State private var editingRecord: WorkoutRecord?
    @State private var recordPendingDeletion: WorkoutRecord?
    @State private var selectedDate = Date()
    @State private var displayedMonth = Date()

    private var selectedRecords: [WorkoutRecord] {
        store.records
            .filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WorkoutCalendarView(
                        records: store.records,
                        selectedDate: $selectedDate,
                        displayedMonth: $displayedMonth
                    )
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))

                    Text(selectedDate.formatted(date: .long, time: .omitted))
                        .font(.title3.bold())

                    if selectedRecords.isEmpty {
                        Text("この日の記録はありません")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 100)
                            .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        ForEach(selectedRecords) { record in
                            HStack(alignment: .top, spacing: 12) {
                                Button { editingRecord = record } label: {
                                    RecordSummary(record: record)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Menu {
                                    Button("編集", systemImage: "pencil") {
                                        editingRecord = record
                                    }
                                    Button("削除", systemImage: "trash", role: .destructive) {
                                        recordPendingDeletion = record
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.title3)
                                        .padding(.top, 4)
                                }
                            }
                            .padding()
                            .background(.background, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("履歴")
            .onAppear {
                if let latest = store.records.max(by: { $0.date < $1.date }),
                   !store.records.contains(where: { Calendar.current.isDateInToday($0.date) }) {
                    selectedDate = latest.date
                    displayedMonth = latest.date
                }
            }
            .sheet(item: $editingRecord) { record in
                RecordEditView(record: record) { store.updateRecord($0) }
            }
            .alert("記録を削除しますか？", isPresented: deletionAlert) {
                Button("キャンセル", role: .cancel) { recordPendingDeletion = nil }
                Button("削除", role: .destructive) {
                    if let recordPendingDeletion { store.deleteRecord(recordPendingDeletion) }
                    recordPendingDeletion = nil
                }
            }
        }
    }

    private var deletionAlert: Binding<Bool> {
        Binding(
            get: { recordPendingDeletion != nil },
            set: { if !$0 { recordPendingDeletion = nil } }
        )
    }
}

private struct RecordSummary: View {
    let record: WorkoutRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(record.exerciseName).font(.headline)
                Spacer()
                Text(record.date, style: .time).foregroundStyle(.secondary)
            }
            ForEach(Array(record.sets.enumerated()), id: \.element.id) { index, set in
                Text("Set \(index + 1)  \(set.weight.formatted()) kg × \(set.reps) 回")
                    .font(.subheadline)
            }
            if !record.note.isEmpty {
                Text(record.note).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RecordEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var record: WorkoutRecord
    let onSave: (WorkoutRecord) -> Void

    init(record: WorkoutRecord, onSave: @escaping (WorkoutRecord) -> Void) {
        _record = State(initialValue: record)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("記録") {
                    Text(record.exerciseName)
                    DatePicker("日時", selection: $record.date)
                }
                Section("セット") {
                    ForEach(Array(record.sets.indices), id: \.self) { index in
                        SetEditorRow(
                            number: index + 1,
                            set: $record.sets[index],
                            onDuplicate: {
                                let set = record.sets[index]
                                record.sets.insert(
                                    WorkoutSet(weight: set.weight, reps: set.reps, kind: set.kind),
                                    at: index + 1
                                )
                            },
                            onDelete: { record.sets.remove(at: index) }
                        )
                    }
                    Button("セットを追加", systemImage: "plus") {
                        record.sets.append(WorkoutSet(weight: 0, reps: 1))
                    }
                }
                Section("メモ") {
                    TextField("メモ", text: $record.note, axis: .vertical)
                }
            }
            .navigationTitle("記録を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(record); dismiss() }
                        .disabled(record.sets.isEmpty || record.sets.contains { $0.weight < 0 || $0.reps <= 0 })
                }
            }
        }
    }
}

private struct ExerciseManagementView: View {
    @ObservedObject var store: AppStore
    @State private var editingExercise: Exercise?
    @State private var showingNewExercise = false
    @State private var showingNewTemplate = false

    var body: some View {
        NavigationStack {
            List {
                Section("種目") {
                    ForEach(store.exercises) { exercise in
                        Button { editingExercise = exercise } label: {
                            VStack(alignment: .leading) {
                                Text(exercise.name).foregroundStyle(.primary)
                                Text([exercise.targetMuscles.map(\.rawValue).joined(separator: "・"), exercise.equipment]
                                    .filter { !$0.isEmpty }.joined(separator: "・"))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    .onDelete(perform: store.deleteExercises)
                    .onMove(perform: store.moveExercises)
                }

                Section("テンプレート") {
                    ForEach(store.templates) { template in
                        VStack(alignment: .leading) {
                            Text(template.name)
                            Text(template.exerciseIDs.compactMap { id in
                                store.exercises.first { $0.id == id }?.name
                            }.joined(separator: "・"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: store.deleteTemplates)

                    Button("テンプレートを追加", systemImage: "plus") {
                        showingNewTemplate = true
                    }
                }
            }
            .navigationTitle("種目")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("追加", systemImage: "plus") { showingNewExercise = true }
                }
            }
            .sheet(isPresented: $showingNewExercise) {
                ExerciseEditView(title: "種目を追加") { name, group, equipment, targets in
                    store.addExercise(
                        name: name,
                        muscleGroup: group,
                        equipment: equipment,
                        targetMuscles: targets
                    )
                }
            }
            .sheet(isPresented: $showingNewTemplate) {
                TemplateEditView(store: store)
            }
            .sheet(item: $editingExercise) { exercise in
                ExerciseEditView(title: "種目を編集", exercise: exercise) { name, group, equipment, targets in
                    store.updateExercise(Exercise(
                        id: exercise.id,
                        name: name,
                        muscleGroup: group,
                        equipment: equipment,
                        targetMuscles: targets
                    ))
                }
            }
        }
    }
}

private struct TemplateEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AppStore
    @State private var name = ""
    @State private var selectedIDs: Set<UUID> = []
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("テンプレート名") {
                    TextField("例：Push Day", text: $name)
                }
                Section("種目") {
                    ForEach(store.exercises) { exercise in
                        Button {
                            if selectedIDs.contains(exercise.id) { selectedIDs.remove(exercise.id) }
                            else { selectedIDs.insert(exercise.id) }
                        } label: {
                            HStack {
                                Text(exercise.name).foregroundStyle(.primary)
                                Spacer()
                                if selectedIDs.contains(exercise.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("テンプレートを作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let orderedIDs = store.exercises.map(\.id).filter { selectedIDs.contains($0) }
                        if store.addTemplate(name: name, exerciseIDs: orderedIDs) { dismiss() }
                        else { showError = true }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedIDs.isEmpty)
                }
            }
            .alert("保存できません", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("同じ名前のテンプレートがすでにあります。")
            }
        }
    }
}

private struct ExerciseEditView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State private var name: String
    @State private var muscleGroup: MuscleGroup
    @State private var equipment: String
    @State private var targetMuscles: Set<MuscleRegion>
    @State private var showDuplicateError = false
    let onSave: (String, MuscleGroup, String, [MuscleRegion]) -> Bool

    init(
        title: String,
        exercise: Exercise? = nil,
        onSave: @escaping (String, MuscleGroup, String, [MuscleRegion]) -> Bool
    ) {
        let initialGroup = exercise?.muscleGroup ?? .fullBody
        self.title = title
        _name = State(initialValue: exercise?.name ?? "")
        _muscleGroup = State(initialValue: initialGroup)
        _equipment = State(initialValue: exercise?.equipment ?? "")
        _targetMuscles = State(initialValue: Set(exercise?.targetMuscles ?? initialGroup.defaultRegions))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本情報") {
                    TextField("種目名", text: $name)
                    Picker("分類", selection: $muscleGroup) {
                        ForEach(MuscleGroup.allCases) { group in Text(group.rawValue).tag(group) }
                    }
                    TextField("器具（任意）", text: $equipment)
                }

                Section {
                    Text("実際に負荷がかかる筋肉を複数選択できます。身体マップには選択したすべての筋肉が反映されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(MuscleGroup.allCases.filter { $0 != .fullBody }) { group in
                    Section(group.rawValue) {
                        ForEach(MuscleRegion.allCases.filter { $0.muscleGroup == group }) { region in
                            Button { toggle(region) } label: {
                                HStack {
                                    Text(region.rawValue).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: targetMuscles.contains(region)
                                          ? "checkmark.circle.fill"
                                          : "circle")
                                        .foregroundStyle(targetMuscles.contains(region) ? .red : .secondary)
                                }
                            }
                        }
                    }
                }
            }
            .onChange(of: muscleGroup) { _, newGroup in
                targetMuscles = Set(newGroup.defaultRegions)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let orderedTargets = MuscleRegion.allCases.filter { targetMuscles.contains($0) }
                        if onSave(name, muscleGroup, equipment, orderedTargets) { dismiss() }
                        else { showDuplicateError = true }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || targetMuscles.isEmpty)
                }
            }
            .alert("保存できません", isPresented: $showDuplicateError) {
                Button("OK", role: .cancel) {}
            } message: { Text("同じ名前の種目がすでにあります。") }
        }
    }

    private func toggle(_ region: MuscleRegion) {
        if targetMuscles.contains(region) { targetMuscles.remove(region) }
        else { targetMuscles.insert(region) }
    }
}
