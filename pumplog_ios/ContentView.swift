import SwiftUI

struct ContentView: View {
    @StateObject private var store = AppStore()

    var body: some View {
        TabView {
            RecordView(store: store)
                .tabItem { Label("記録", systemImage: "plus.circle") }
            HistoryView(store: store)
                .tabItem { Label("履歴", systemImage: "clock") }
            ExerciseManagementView(store: store)
                .tabItem { Label("種目", systemImage: "list.bullet") }
        }
    }
}

private struct RecordView: View {
    @ObservedObject var store: AppStore
    @State private var weight = ""
    @State private var reps = ""
    @State private var showValidationError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("トレーニング") {
                    Picker("種目", selection: exerciseSelection) {
                        ForEach(store.exercises) { exercise in
                            Text(exercise.name).tag(Optional(exercise.id))
                        }
                    }
                    DatePicker("日時", selection: $store.draft.date)
                }

                Section("セットを追加") {
                    HStack {
                        TextField("重量 (kg)", text: $weight).keyboardType(.decimalPad)
                        TextField("回数", text: $reps).keyboardType(.numberPad)
                        Button("追加", action: addSet).buttonStyle(.borderedProminent)
                    }
                    if store.draft.sets.isEmpty {
                        Text("重量と回数を入力してセットを追加してください")
                            .foregroundStyle(.secondary)
                    }
                }

                if !store.draft.sets.isEmpty {
                    Section("セット") {
                        ForEach(Array(store.draft.sets.indices), id: \.self) { index in
                            SetEditorRow(
                                number: index + 1,
                                set: $store.draft.sets[index],
                                onDuplicate: { store.duplicateSet(at: index) },
                                onDelete: { store.draft.sets.remove(at: index) }
                            )
                        }
                        Button("最後と同じセットを追加", systemImage: "plus.square.on.square") {
                            store.duplicateLastSet()
                        }
                    }
                }

                Section("メモ") {
                    TextField("フォームや体調など", text: $store.draft.note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button("記録を保存") {
                        showValidationError = !store.saveDraftAsRecord()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(store.exercises.isEmpty)
                }
            }
            .navigationTitle("PumpLog")
            .alert("保存できません", isPresented: $showValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("種目を選び、1回以上の有効なセットを入力してください。")
            }
            .overlay {
                if store.exercises.isEmpty {
                    ContentUnavailableView(
                        "種目がありません",
                        systemImage: "dumbbell",
                        description: Text("「種目」タブで種目を追加してください。")
                    )
                }
            }
        }
    }

    private var exerciseSelection: Binding<UUID?> {
        Binding(
            get: { store.draft.exerciseID },
            set: { newValue in
                guard let newValue else { return }
                store.selectExercise(newValue)
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
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
    }
}

private struct HistoryView: View {
    @ObservedObject var store: AppStore
    @State private var editingRecord: WorkoutRecord?
    @State private var recordPendingDeletion: WorkoutRecord?

    private var groupedRecords: [(date: Date, records: [WorkoutRecord])] {
        Dictionary(grouping: store.records) { Calendar.current.startOfDay(for: $0.date) }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedRecords, id: \.date) { group in
                    Section(group.date.formatted(date: .long, time: .omitted)) {
                        ForEach(group.records) { record in
                            Button { editingRecord = record } label: { RecordSummary(record: record) }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("削除", systemImage: "trash", role: .destructive) {
                                        recordPendingDeletion = record
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("履歴")
            .overlay {
                if store.records.isEmpty {
                    ContentUnavailableView("記録がありません", systemImage: "clock")
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

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.exercises) { exercise in
                    Button { editingExercise = exercise } label: {
                        VStack(alignment: .leading) {
                            Text(exercise.name).foregroundStyle(.primary)
                            Text([exercise.muscleGroup.rawValue, exercise.equipment]
                                .filter { !$0.isEmpty }.joined(separator: "・"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: store.deleteExercises)
                .onMove(perform: store.moveExercises)
            }
            .navigationTitle("種目")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("追加", systemImage: "plus") { showingNewExercise = true }
                }
            }
            .sheet(isPresented: $showingNewExercise) {
                ExerciseEditView(title: "種目を追加") { name, group, equipment in
                    store.addExercise(name: name, muscleGroup: group, equipment: equipment)
                }
            }
            .sheet(item: $editingExercise) { exercise in
                ExerciseEditView(title: "種目を編集", exercise: exercise) { name, group, equipment in
                    store.updateExercise(Exercise(
                        id: exercise.id, name: name, muscleGroup: group, equipment: equipment
                    ))
                }
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
    @State private var showDuplicateError = false
    let onSave: (String, MuscleGroup, String) -> Bool

    init(title: String, exercise: Exercise? = nil, onSave: @escaping (String, MuscleGroup, String) -> Bool) {
        self.title = title
        _name = State(initialValue: exercise?.name ?? "")
        _muscleGroup = State(initialValue: exercise?.muscleGroup ?? .fullBody)
        _equipment = State(initialValue: exercise?.equipment ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("種目名", text: $name)
                Picker("部位", selection: $muscleGroup) {
                    ForEach(MuscleGroup.allCases) { group in Text(group.rawValue).tag(group) }
                }
                TextField("器具（任意）", text: $equipment)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if onSave(name, muscleGroup, equipment) { dismiss() }
                        else { showDuplicateError = true }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("保存できません", isPresented: $showDuplicateError) {
                Button("OK", role: .cancel) {}
            } message: { Text("同じ名前の種目がすでにあります。") }
        }
    }
}
