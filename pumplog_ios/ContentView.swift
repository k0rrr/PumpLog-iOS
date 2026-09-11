import SwiftData
import SwiftUI
import UIKit

private enum Phase1Route: Hashable {
    case muscleSelection
    case workoutSetup([Phase1MuscleGroup])
    case workout(UUID)
    case result(UUID)
}

// MARK: - Root navigation
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Phase1Workout.startedAt, order: .reverse) private var workouts: [Phase1Workout]
    @State private var path: [Phase1Route] = []
    @State private var selectedTab = 0
    @State private var seedError: String?

    private var activeWorkout: Phase1Workout? { workouts.first(where: { $0.status == .active }) }
    private var latestCompletedWorkout: Phase1Workout? {
        workouts.first(where: { $0.status == .completed && $0.workoutExercises.contains { $0.sets.contains { $0.completedAt != nil } } })
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            homeNavigation
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            Phase1HistoryTab()
                .tabItem { Label("History", systemImage: "calendar") }.tag(1)
            Phase1BodyTab()
                .tabItem { Label("Body", systemImage: "figure.stand") }.tag(2)
            Phase1SettingsTab()
                .tabItem { Label("Setting", systemImage: "gearshape") }.tag(3)
        }
        .task {
            do {
                try Phase1DataMigrationService.migrateLegacyDataIfNeeded(in: modelContext)
                try Phase1SeedService.seedIfNeeded(in: modelContext)
            }
            catch { seedError = "種目の初期設定に失敗しました。" }
        }
        .alert("エラー", isPresented: Binding(get: { seedError != nil }, set: { if !$0 { seedError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(seedError ?? "") }
        .preferredColorScheme(.dark)
        .tint(Phase1DesignTokens.orange)
        .onChange(of: selectedTab) { _, newValue in
            // Returning to Home shows the resume CTA instead of keeping a stale
            // Workout destination on the Home navigation stack.
            if newValue == 0, !path.isEmpty { path.removeAll() }
        }
    }

    private var homeNavigation: some View {
        NavigationStack(path: $path) {
            Phase1HomeView(activeWorkout: activeWorkout, latestCompletedWorkout: latestCompletedWorkout,
                           onStart: { if let activeWorkout { path.append(.workout(activeWorkout.id)) } else { path.append(.muscleSelection) } },
                           onResume: { path.append(.workout($0.id)) },
                           onStartTemplate: { startTemplate($0) })
            .navigationDestination(for: Phase1Route.self) { route in
                switch route {
                case .muscleSelection:
                    Phase1MuscleSelectionView { path.append(.workoutSetup($0)) }
                case .workoutSetup(let groups):
                    Phase1WorkoutSetupView(groups: groups) { path.append(.workout($0.id)) }
                case .workout(let id):
                    Phase1WorkoutView(workoutID: id, onBack: { returnToWorkoutSetup(for: id) }) { resultID in
                        if let resultID { path.append(.result(resultID)) } else { path.removeAll() }
                    }
                    .navigationBarBackButtonHidden(true)
                case .result(let id):
                    Phase1ResultView(workoutID: id) { path.removeAll() }
                }
            }
        }
    }

    private func returnToWorkoutSetup(for workoutID: UUID) {
        guard let workout = workouts.first(where: { $0.id == workoutID }) else {
            path.removeAll()
            return
        }
        let groups = Phase1MuscleGroup.allCases.filter { group in
            workout.workoutExercises.contains { $0.exercise?.muscleGroup == group }
        }
        path = groups.isEmpty ? [.muscleSelection] : [.workoutSetup(groups)]
    }

    private func startTemplate(_ exerciseIDs: [UUID]) {
        if let activeWorkout {
            path.append(.workout(activeWorkout.id))
            return
        }
        let allExercises = (try? modelContext.fetch(FetchDescriptor<Phase1Exercise>())) ?? []
        let exercises = exerciseIDs.compactMap { id in allExercises.first { $0.id == id && !$0.isArchived } }
        guard !exercises.isEmpty else { return }
        let workout = Phase1Workout()
        modelContext.insert(workout)
        for (index, exercise) in exercises.enumerated() {
            let entry = Phase1WorkoutExercise(orderIndex: index, workout: workout, exercise: exercise)
            modelContext.insert(entry)
            workout.workoutExercises.append(entry)
        }
        workout.selectedWorkoutExerciseID = workout.workoutExercises.first?.id
        do {
            try modelContext.save()
            path.append(.workout(workout.id))
        } catch {
            modelContext.delete(workout)
        }
    }
}

// MARK: - History
private struct Phase1HistoryTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Phase1Workout> { $0.statusRaw == "completed" }, sort: \Phase1Workout.startedAt, order: .reverse) private var workouts: [Phase1Workout]
    @State private var displayedMonth = Date()
    @State private var selectedDay: Date?
    @State private var searchText = ""
    @State private var pendingDeleteID: UUID?
    @State private var errorMessage: String?
    private var visibleWorkouts: [Phase1Workout] {
        let calendar = Calendar.current
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return workouts.filter { workout in
            guard calendar.isDate(workout.startedAt, equalTo: displayedMonth, toGranularity: .month),
                  workout.workoutExercises.contains(where: { $0.sets.contains { $0.completedAt != nil } }) else { return false }
            if let selectedDay, !calendar.isDate(workout.startedAt, inSameDayAs: selectedDay) { return false }
            guard !query.isEmpty else { return true }
            return workout.workoutExercises.contains { entry in
                let exercise = entry.exercise
                return exercise?.name.localizedCaseInsensitiveContains(query) == true
                    || phase1DisplayExerciseName(exercise).localizedCaseInsensitiveContains(query)
                    || exercise?.muscleGroup.title.localizedCaseInsensitiveContains(query) == true
            }
        }
    }
    var body: some View {
        NavigationStack {
            ZStack {
                Phase1DesignTokens.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        Phase1TabHeader(title: "History")
                        Phase1SearchField(text: $searchText, prompt: "種目名・部位で検索")
                            .padding(.bottom, 8)
                        HStack {
                            Button {
                                displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                                selectedDay = nil
                            } label: { Image(systemName: "chevron.left").font(.caption.weight(.bold)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                                .accessibilityLabel("前の月")
                            Spacer()
                            Text(phase1MonthTitle(displayedMonth)).font(.headline)
                            Spacer()
                            Button {
                                displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                                selectedDay = nil
                            } label: { Image(systemName: "chevron.right").font(.caption.weight(.bold)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                                .accessibilityLabel("次の月")
                        }
                        .padding(.top, 18).padding(.bottom, 12)
                        calendarView
                            .padding(12)
                            .background(Phase1DesignTokens.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.bottom, 18)
                        ForEach(visibleWorkouts) { workout in
                            NavigationLink(destination: Phase1WorkoutDetailView(workoutID: workout.id)) {
                                HStack(spacing: 12) {
                                    Text(workoutMuscleSummary(workout)).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(workoutDurationText(workout)).foregroundStyle(.secondary).monospacedDigit()
                                }
                                .frame(maxWidth: .infinity, minHeight: 49, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("削除", role: .destructive) { pendingDeleteID = workout.id }
                                    .accessibilityLabel("この履歴を削除")
                            }
                            Divider().overlay(Phase1DesignTokens.divider)
                        }
                        if visibleWorkouts.isEmpty {
                            Text("まだ記録がありません").foregroundStyle(Phase1DesignTokens.secondary).padding(.top, 50)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                }
            }
        }
        .navigationBarHidden(true)
        .confirmationDialog("この履歴を削除しますか？", isPresented: Binding(get: { pendingDeleteID != nil }, set: { if !$0 { pendingDeleteID = nil } }), titleVisibility: .visible) {
            Button("削除する", role: .destructive) { deleteWorkout(id: pendingDeleteID) }
            Button("キャンセル", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("記録したセットもすべて削除されます。")
        }
        .alert("履歴を削除できませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func deleteWorkout(id: UUID?) {
        guard let id, let workout = workouts.first(where: { $0.id == id }) else { pendingDeleteID = nil; return }
        modelContext.delete(workout)
        do {
            try modelContext.save()
            pendingDeleteID = nil
        } catch {
            // Keep the list and the model consistent if SwiftData rejects the
            // deletion. Re-inserting the object restores the pending history.
            modelContext.insert(workout)
            errorMessage = "保存状態を確認してから、もう一度お試しください。"
            pendingDeleteID = nil
        }
    }
    private func workoutMuscleSummary(_ workout: Phase1Workout) -> String {
        workout.workoutExercises.first(where: { $0.sets.contains { $0.completedAt != nil } })?.exercise?.muscleGroup.title ?? ""
    }
    private func workoutDurationText(_ workout: Phase1Workout) -> String {
        guard let end = workout.endedAt else { return "—" }
        return "\(max(1, Int(end.timeIntervalSince(workout.startedAt) / 60)))min"
    }

    private var calendarView: some View {
        let calendar = Calendar.current
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let firstWeekday = max(1, calendar.firstWeekday) - 1
        let weekdayTitles = (0..<7).map { symbols[($0 + firstWeekday) % 7] }
        return VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(weekdayTitles.indices, id: \.self) { index in
                    Text(weekdayTitles[index])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(index == 0 ? Phase1DesignTokens.orange : Phase1DesignTokens.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } == true
                        let hasWorkout = hasCompletedWorkout(on: date)
                        Button { selectedDay = isSelected ? nil : date } label: {
                            VStack(spacing: 3) {
                                Text("\(calendar.component(.day, from: date))")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(isSelected ? .white : .primary)
                                Circle()
                                    .fill(hasWorkout ? Phase1DesignTokens.orange : .clear)
                                    .frame(width: 5, height: 5)
                            }
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(isSelected ? Phase1DesignTokens.orange : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(calendar.component(.day, from: date))日")
                        .accessibilityValue(hasWorkout ? "記録あり" : "記録なし")
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
    }

    private var calendarDays: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let weekday = calendar.dateComponents([.weekday], from: interval.start).weekday,
              let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let dates = Array(repeating: Optional<Date>.none, count: leading)
            + dayRange.map { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }
        let trailing = (7 - dates.count % 7) % 7
        return dates + Array(repeating: Optional<Date>.none, count: trailing)
    }

    private func hasCompletedWorkout(on date: Date) -> Bool {
        let calendar = Calendar.current
        return workouts.contains { workout in
            calendar.isDate(workout.startedAt, inSameDayAs: date)
                && workout.workoutExercises.contains { $0.sets.contains { $0.completedAt != nil } }
        }
    }
}

// MARK: - History detail and growth
private struct Phase1WorkoutDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let workoutID: UUID
    @State private var editingSet: Phase1WorkoutSet?
    @State private var showingDateEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var refreshToken = UUID()

    private var workout: Phase1Workout? {
        (try? modelContext.fetch(FetchDescriptor<Phase1Workout>()))?.first { $0.id == workoutID }
    }

    var body: some View {
        ZStack {
            Phase1DesignTokens.background.ignoresSafeArea()
            ScrollView {
                if let workout {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            Phase1IconButton("chevron.left", label: "戻る") { dismiss() }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(shortDateWithWeekday(workout.startedAt)).font(.title3.bold())
                                Text("\(workoutMuscleSummary(workout)) — \(workoutDurationText(workout))")
                                    .font(.subheadline).foregroundStyle(Phase1DesignTokens.secondary)
                            }
                            Spacer()
                            Menu {
                                Button("日付を編集", systemImage: "calendar") { showingDateEditor = true }
                                Button("履歴を削除", systemImage: "trash", role: .destructive) { showingDeleteConfirmation = true }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("履歴の操作")
                        }
                        ForEach(workout.workoutExercises.filter { $0.sets.contains { $0.completedAt != nil } }.sorted { $0.orderIndex < $1.orderIndex }) { entry in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(entry.exercise?.name ?? "種目").font(.headline)
                                let completed = entry.sets.filter { $0.completedAt != nil }.sorted { $0.setNumber < $1.setNumber }
                                let best = completed.max { lhs, rhs in
                                    (lhs.weight ?? 0, lhs.reps) < (rhs.weight ?? 0, rhs.reps)
                                }
                                ForEach(completed) { set in
                                    let isBest = best?.id == set.id
                                    Button { editingSet = set } label: {
                                        HStack {
                                            Text("SET \(set.setNumber)")
                                            Spacer()
                                            Text(set.weight.map { "\(format($0))kg × \(set.reps)" } ?? "\(set.reps)回")
                                                .monospacedDigit()
                                            if isBest { Text("BEST").font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 3).background(Phase1DesignTokens.orange).clipShape(RoundedRectangle(cornerRadius: 4)) }
                                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Phase1DesignTokens.secondary)
                                        }
                                        .foregroundStyle(isBest ? Phase1DesignTokens.orange : .white)
                                        .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .background(isBest ? Phase1DesignTokens.orange.opacity(0.10) : .clear)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button("削除", role: .destructive) { deleteSet(set, from: entry, workout: workout) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 24)
                } else {
                    ContentUnavailableView("記録が見つかりません", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .navigationBarHidden(true)
        .id(refreshToken)
        .sheet(item: $editingSet) { set in
            Phase1SetEditSheet(set: set, exercise: set.workoutExercise?.exercise) { weight, reps in
                updateSet(set, weight: weight, reps: reps)
            } onDelete: {
                if let workout, let entry = set.workoutExercise {
                    deleteSet(set, from: entry, workout: workout)
                }
                editingSet = nil
            }
        }
        .sheet(isPresented: $showingDateEditor) {
            if let workout {
                Phase1HistoryDateEditSheet(initialDate: workout.startedAt) { date in
                    updateWorkoutDate(workout, date: date)
                }
            }
        }
        .confirmationDialog("この履歴を削除しますか？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("削除する", role: .destructive) { deleteWorkout() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("記録したセットもすべて削除されます。")
        }
        .alert("履歴を更新できませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func updateSet(_ set: Phase1WorkoutSet, weight: Double?, reps: Int) {
        guard let exercise = set.workoutExercise?.exercise,
              (Phase1Defaults.minReps...Phase1Defaults.maxReps).contains(reps) else {
            errorMessage = "入力値を確認してください。"
            return
        }
        let previousWeight = set.weight
        let previousReps = set.reps
        let previousUpdatedAt = set.updatedAt
        set.weight = exercise.recordType == .weightAndReps ? normalize(weight ?? 0, step: exercise.weightStep) : nil
        set.reps = reps
        set.updatedAt = .now
        do {
            try modelContext.save()
            editingSet = nil
            refreshToken = UUID()
        } catch {
            set.weight = previousWeight
            set.reps = previousReps
            set.updatedAt = previousUpdatedAt
            errorMessage = "入力値を保存できませんでした。"
        }
    }

    private func deleteSet(_ set: Phase1WorkoutSet, from entry: Phase1WorkoutExercise, workout: Phase1Workout) {
        let previousSets = entry.sets
        let previousNumbers = Dictionary(uniqueKeysWithValues: previousSets.map { ($0.id, $0.setNumber) })
        modelContext.delete(set)
        entry.sets.removeAll { $0.id == set.id }
        for (index, item) in entry.sets.sorted(by: { $0.setNumber < $1.setNumber }).enumerated() { item.setNumber = index + 1 }
        if workout.restingAfterSetID == set.id {
            workout.restingAfterSetID = nil
            workout.restEndAt = nil
        }
        workout.updatedAt = .now
        do {
            try modelContext.save()
            refreshToken = UUID()
        } catch {
            modelContext.insert(set)
            set.workoutExercise = entry
            entry.sets = previousSets
            for item in previousSets {
                if let number = previousNumbers[item.id] { item.setNumber = number }
            }
            errorMessage = "セットを削除できませんでした。"
        }
    }

    private func deleteWorkout() {
        guard let workout else { return }
        modelContext.delete(workout)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.insert(workout)
            errorMessage = "履歴を削除できませんでした。"
        }
    }

    private func updateWorkoutDate(_ workout: Phase1Workout, date: Date) {
        let previousStart = workout.startedAt
        let previousEnd = workout.endedAt
        let updatedStart = datePreservingTime(date, from: previousStart)
        let duration = previousEnd?.timeIntervalSince(previousStart)
        workout.startedAt = updatedStart
        if let duration, duration >= 0 { workout.endedAt = updatedStart.addingTimeInterval(duration) }
        workout.updatedAt = .now
        do {
            try modelContext.save()
            showingDateEditor = false
            refreshToken = UUID()
        } catch {
            workout.startedAt = previousStart
            workout.endedAt = previousEnd
            errorMessage = "日付を保存できませんでした。"
        }
    }

    private func normalize(_ value: Double, step: Double) -> Double {
        let increment = max(0.1, step)
        return min(Phase1Defaults.maxWeight, max(Phase1Defaults.minWeight, (value / increment).rounded() * increment))
    }

    private func datePreservingTime(_ date: Date, from original: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let time = calendar.dateComponents([.hour, .minute, .second], from: original)
        var components = DateComponents()
        components.year = day.year; components.month = day.month; components.day = day.day
        components.hour = time.hour; components.minute = time.minute; components.second = time.second
        return calendar.date(from: components) ?? date
    }

    private func format(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }
    private func workoutMuscleSummary(_ workout: Phase1Workout) -> String {
        workout.workoutExercises.first(where: { $0.sets.contains { $0.completedAt != nil } })?.exercise?.muscleGroup.title ?? ""
    }
    private func workoutDurationText(_ workout: Phase1Workout) -> String {
        guard let end = workout.endedAt else { return "—" }
        return "\(max(1, Int(end.timeIntervalSince(workout.startedAt) / 60)))min"
    }
}

private struct Phase1HistoryDateEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initialDate: Date
    let onSave: (Date) -> Void
    @State private var selectedDate: Date

    init(initialDate: Date, onSave: @escaping (Date) -> Void) {
        self.initialDate = initialDate
        self.onSave = onSave
        _selectedDate = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("日付", selection: $selectedDate, displayedComponents: .date)
            }
            .navigationTitle("日付を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { onSave(selectedDate) } }
            }
        }
    }
}

private struct Phase1GrowthTab: View {
    @Query(filter: #Predicate<Phase1Workout> { $0.statusRaw == "completed" }, sort: \Phase1Workout.startedAt, order: .reverse) private var workouts: [Phase1Workout]
    private var volume: Double { workouts.flatMap { $0.workoutExercises }.flatMap { $0.sets }.compactMap { set in set.weight.map { $0 * Double(set.reps) } }.reduce(0, +) }
    var body: some View {
        NavigationStack {
            List { Section("累計") { LabeledContent("トレーニング回数", value: "\(workouts.count)回"); LabeledContent("総負荷量", value: "\(format(volume))kg") }; Section("自己ベスト") { Text("記録を重ねると種目ごとのPRが表示されます。").foregroundStyle(.secondary) } }
                .navigationTitle("成長")
        }
    }
    private func format(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }
}

// MARK: - Exercise and settings tabs
private struct Phase1ExerciseTab: View {
    @Query(filter: #Predicate<Phase1Exercise> { !$0.isArchived }, sort: \Phase1Exercise.name) private var exercises: [Phase1Exercise]
    var body: some View {
        NavigationStack {
            ZStack {
                Phase1DesignTokens.background.ignoresSafeArea()
                List(exercises) { exercise in
                    HStack { VStack(alignment: .leading, spacing: 4) { Text(exercise.name); Text(exercise.muscleGroup.title).font(.caption).foregroundStyle(Phase1DesignTokens.secondary) }; Spacer(); Text(exercise.recordType == .repsOnly ? "回数" : "kg＋回数").font(.caption).foregroundStyle(Phase1DesignTokens.secondary) }
                        .listRowBackground(Phase1DesignTokens.background)
                }.scrollContentBackground(.hidden)
            }
            .navigationTitle("メニュー")
            .toolbarBackground(Phase1DesignTokens.background, for: .navigationBar)
        }
    }
}

private struct Phase1SettingsTab: View {
    @AppStorage("phase1RestHapticsEnabled") private var restHapticsEnabled = true
    @AppStorage("phase1KeepScreenAwake") private var keepScreenAwake = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Phase1TabHeader(title: "Setting")
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                Form {
                    Section("トレーニング") {
                        Toggle("休憩終了時に振動", isOn: $restHapticsEnabled)
                        Toggle("トレーニング中は画面をスリープさせない", isOn: $keepScreenAwake)
                    }
                    Section("今後の設定") {
                        Text("初期休憩時間・重量単位は今後追加予定です")
                            .foregroundStyle(.secondary)
                    }
                    Section("アカウント") {
                        Text("アカウント設定は準備中です")
                            .foregroundStyle(.secondary)
                    }
                    Section("データ") {
                        Text("バックアップ・データ削除は今後追加予定です")
                            .foregroundStyle(.secondary)
                    }
                    Section("アプリ") {
                        LabeledContent("アプリ名", value: "PumpLog")
                        LabeledContent("バージョン", value: "Phase 1")
                    }
                    Section("3D人体モデル") {
                        Text("Body Anatomy 3D Viewer / Z-Anatomy")
                        Text("解剖学的な筋肉モデルを使用し、トレーニングで負荷がかかった部位をハイライトします。モデルはアプリ内で表示用に加工しています。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Link("モデルの出典とCC BY-SA 4.0ライセンス", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                            .font(.footnote)
                        Text("Body Anatomy 3D Viewer（hpfrei）およびZ-Anatomy contributorsに帰属します。Three.js（MIT）とDraco（Apache License 2.0）の notices はアプリに同梱しています。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Phase1DesignTokens.background)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Home and templates
@MainActor
final class Phase1HomeViewModel: ObservableObject {
    let activeWorkout: Phase1Workout?
    init(activeWorkout: Phase1Workout?) { self.activeWorkout = activeWorkout }
    var activeSummary: String? {
        guard let activeWorkout else { return nil }
        let count = activeWorkout.workoutExercises.reduce(0) { $0 + $1.sets.filter { $0.completedAt != nil }.count }
        let performed = activeWorkout.workoutExercises.filter { $0.sets.contains { $0.completedAt != nil } }.count
        return "\(performed)種目・\(count)セット記録済み"
    }
}

private struct Phase1TrainingTemplate: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var exerciseIDs: [UUID]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, exerciseIDs: [UUID], createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.exerciseIDs = exerciseIDs
        self.createdAt = createdAt
    }
}

private struct Phase1HomeView: View {
    @Query(filter: #Predicate<Phase1Exercise> { !$0.isArchived }, sort: \Phase1Exercise.name) private var exercises: [Phase1Exercise]
    @Query(filter: #Predicate<Phase1Workout> { $0.statusRaw == "completed" }, sort: \Phase1Workout.startedAt, order: .reverse) private var completedWorkouts: [Phase1Workout]
    @AppStorage("phase1TrainingTemplates") private var templateData = ""
    @State private var showingTemplateEditor = false
    @State private var templateToDelete: Phase1TrainingTemplate?
    let activeWorkout: Phase1Workout?
    let onStart: () -> Void
    let onResume: (Phase1Workout) -> Void
    let onStartTemplate: ([UUID]) -> Void
    let latestCompletedWorkout: Phase1Workout?

    init(activeWorkout: Phase1Workout?, latestCompletedWorkout: Phase1Workout?, onStart: @escaping () -> Void, onResume: @escaping (Phase1Workout) -> Void, onStartTemplate: @escaping ([UUID]) -> Void) {
        self.activeWorkout = activeWorkout
        self.onStart = onStart; self.onResume = onResume
        self.onStartTemplate = onStartTemplate
        self.latestCompletedWorkout = latestCompletedWorkout
    }

    var body: some View {
        ZStack {
            Phase1DesignTokens.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Phase1TabHeader(title: "PumpLog")
                if !templates.isEmpty {
                    Text("保存したメニュー").font(.subheadline).foregroundStyle(Phase1DesignTokens.secondary)
                    ForEach(templates) { template in
                        HStack(spacing: 0) {
                            Button { onStartTemplate(template.exerciseIDs) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(template.name).font(.headline)
                                        Text("\(template.exerciseIDs.count)種目").font(.caption).foregroundStyle(Phase1DesignTokens.secondary)
                                    }
                                    Spacer()
                                    Text("開始").font(.subheadline.weight(.semibold)).foregroundStyle(Phase1DesignTokens.orange)
                                }
                                .padding(.leading, 16)
                                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                        .background(Phase1DesignTokens.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("削除", role: .destructive) { templateToDelete = template }
                                .accessibilityLabel("\(template.name)を削除")
                        }
                        .contextMenu {
                            Button("削除", role: .destructive) { templateToDelete = template }
                        }
                    }
                }
                Text("最近の記録").font(.subheadline).foregroundStyle(Phase1DesignTokens.secondary)
                if !completedWorkouts.isEmpty {
                    ForEach(Array(completedWorkouts.prefix(3))) { workout in
                        recentWorkoutRow(workout)
                    }
                } else if let latestCompletedWorkout {
                    recentWorkoutRow(latestCompletedWorkout)
                } else {
                    Text("まだ記録がありません").foregroundStyle(Phase1DesignTokens.secondary)
                }
                }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 20)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 10) {
            VStack(spacing: 10) {
                Phase1SecondaryButton("メニューを作成") { showingTemplateEditor = true }
                    .accessibilityLabel("トレーニングメニューを作成")

                if let activeWorkout {
                    Phase1PrimaryButton("トレーニングに戻る", accessibilityIdentifier: "resumeWorkoutButton") {
                        onResume(activeWorkout)
                    }
                } else {
                    Phase1PrimaryButton("トレーニングを開始", accessibilityIdentifier: "startWorkoutButton", action: onStart)
                }
            }
            .background(Phase1DesignTokens.background)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingTemplateEditor) {
            Phase1TemplateEditorSheet { name, exerciseIDs in
                addTemplate(name: name, exerciseIDs: exerciseIDs)
            }
        }
        .confirmationDialog("このメニューを削除しますか？", isPresented: Binding(get: { templateToDelete != nil }, set: { if !$0 { templateToDelete = nil } }), titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                if let templateToDelete { deleteTemplate(templateToDelete) }
            }
            Button("キャンセル", role: .cancel) { templateToDelete = nil }
        }
    }

    private var templates: [Phase1TrainingTemplate] {
        guard let data = templateData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Phase1TrainingTemplate].self, from: data) else { return [] }
        return decoded
    }

    private func addTemplate(name: String, exerciseIDs: [UUID]) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !exerciseIDs.isEmpty else { return }
        var updated = templates
        updated.append(Phase1TrainingTemplate(name: cleanName, exerciseIDs: exerciseIDs))
        saveTemplates(updated)
    }

    private func deleteTemplate(_ template: Phase1TrainingTemplate) {
        saveTemplates(templates.filter { $0.id != template.id })
        templateToDelete = nil
    }

    private func saveTemplates(_ templates: [Phase1TrainingTemplate]) {
        guard let data = try? JSONEncoder().encode(templates),
              let encoded = String(data: data, encoding: .utf8) else { return }
        templateData = encoded
    }

    private func recentWorkoutRow(_ workout: Phase1Workout) -> some View {
        NavigationLink(destination: Phase1WorkoutDetailView(workoutID: workout.id)) {
            HStack {
                let performed = workout.workoutExercises.filter { $0.sets.contains { $0.completedAt != nil } }
                Text("\(shortDateWithWeekday(workout.startedAt))  \(performed.first?.exercise?.muscleGroup.title ?? "")")
                Spacer()
                Text("\(workoutDuration(workout))min").foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(Phase1DesignTokens.divider).frame(height: 0.5) }
        }
        .buttonStyle(.plain)
    }

    private func workoutDuration(_ workout: Phase1Workout) -> Int {
        guard let endedAt = workout.endedAt else { return 0 }
        return max(1, Int(endedAt.timeIntervalSince(workout.startedAt) / 60))
    }

    private func activeSummary(for workout: Phase1Workout) -> String {
        let setCount = workout.workoutExercises.reduce(0) { $0 + $1.sets.filter { $0.completedAt != nil }.count }
        let exerciseCount = workout.workoutExercises.filter { $0.sets.contains { $0.completedAt != nil } }.count
        return "\(exerciseCount)種目・\(setCount)セット記録済み"
    }
}

// MARK: - Template editor
private struct Phase1TemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Phase1Exercise> { !$0.isArchived }, sort: \Phase1Exercise.name) private var exercises: [Phase1Exercise]
    let onSave: (String, [UUID]) -> Void
    @State private var name = ""
    @State private var selectedIDs: Set<UUID> = []
    @State private var showingCreateExercise = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("メニュー名") {
                    TextField("例：胸の日", text: $name)
                }
                Section("種目") {
                    Button("種目を追加") { showingCreateExercise = true }
                    ForEach(exercises) { exercise in
                        let isSelected = selectedIDs.contains(exercise.id)
                        Button {
                            if isSelected { selectedIDs.remove(exercise.id) }
                            else { selectedIDs.insert(exercise.id) }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(exercise.name)
                                    Text(exercise.muscleGroup.title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isSelected { Image(systemName: "checkmark").foregroundStyle(Phase1DesignTokens.orange) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if exercises.isEmpty {
                        Text("登録されている種目がありません").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("メニューを作成")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(name, exercises.filter { selectedIDs.contains($0.id) }.map(\.id))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedIDs.isEmpty)
                }
            }
            .sheet(isPresented: $showingCreateExercise) {
                Phase1CreateExerciseView(defaultGroup: .chest) { name, group, recordType, weightStep in
                    createExercise(name: name, group: group, recordType: recordType, weightStep: weightStep)
                }
            }
            .alert("種目を追加できませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func createExercise(name: String, group: Phase1MuscleGroup, recordType: Phase1RecordType, weightStep: Double) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              !exercises.contains(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame && $0.muscleGroup == group && $0.recordType == recordType }) else {
            errorMessage = "同じ部位・記録方法の種目がすでにあります。"
            return
        }
        let exercise = Phase1Exercise(name: cleanName, muscleGroup: group, recordType: recordType, weightStep: weightStep)
        modelContext.insert(exercise)
        do {
            try modelContext.save()
            selectedIDs.insert(exercise.id)
            showingCreateExercise = false
        } catch {
            modelContext.delete(exercise)
            errorMessage = "種目を保存できませんでした。"
        }
    }
}

@MainActor
// MARK: - Muscle selection
final class Phase1MuscleSelectionViewModel: ObservableObject {
    @Published var selected: Set<Phase1MuscleGroup> = []
    func toggle(_ group: Phase1MuscleGroup) {
        if selected.contains(group) { selected.remove(group) } else { selected.insert(group) }
    }
    func toggle(_ groups: [Phase1MuscleGroup]) {
        // Treat each row as an independent toggle. This lets users combine
        // Chest + Back (or any other parts) without the last tap replacing
        // their previous choices.
        let isSelected = groups.allSatisfy { selected.contains($0) }
        if isSelected { groups.forEach { selected.remove($0) } }
        else { groups.forEach { selected.insert($0) } }
    }
}

private struct Phase1MuscleSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = Phase1MuscleSelectionViewModel()
    @AppStorage("phase1HiddenMuscleGroups") private var hiddenMuscleGroups = ""
    @AppStorage("phase1CustomBodyParts") private var customBodyPartsData = ""
    @State private var showingGroupEditor = false
    let onNext: ([Phase1MuscleGroup]) -> Void

    var body: some View {
        ZStack {
            Phase1DesignTokens.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Phase1IconButton("chevron.left", label: "戻る") { dismiss() }
                    Text("部位を選択").font(.title3.bold())
                    Spacer()
                    Button("編集") { showingGroupEditor = true }
                        .font(.subheadline.weight(.semibold))
                    .accessibilityLabel("部位を追加・削除")
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(displayOptions.enumerated()), id: \.offset) { _, option in
                            let selected = option.groups.allSatisfy { viewModel.selected.contains($0) }
                            Button { viewModel.toggle(option.groups) } label: {
                                HStack(spacing: 8) {
                                    Text(option.title).font(.body.weight(selected ? .semibold : .regular))
                                    Text(option.english).font(.subheadline).foregroundStyle(selected ? Phase1DesignTokens.orange.opacity(0.9) : Phase1DesignTokens.secondary)
                                    Spacer()
                                    if selected { Image(systemName: "checkmark").font(.subheadline.weight(.bold)).foregroundStyle(Phase1DesignTokens.orange) }
                                }
                                .padding(.horizontal, 16).frame(height: 56)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(selected ? Phase1DesignTokens.orange.opacity(0.10) : .clear)
                                .overlay(alignment: .leading) { Rectangle().fill(selected ? Phase1DesignTokens.orange : .clear).frame(width: 3) }
                                .overlay(alignment: .bottom) { Rectangle().fill(selected ? Phase1DesignTokens.orange : Phase1DesignTokens.divider).frame(height: selected ? 1 : 0.5) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(selected ? "選択中" : "未選択")
                        }
                    }
                    .padding(.horizontal, 20)
                }
                Spacer(minLength: 8)
                Phase1PrimaryButton("次へ", accessibilityIdentifier: "nextMuscleButton") {
                    onNext(Phase1MuscleGroup.allCases.filter { viewModel.selected.contains($0) })
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .accessibilityLabel("次へ")
                .disabled(viewModel.selected.isEmpty)
                .opacity(viewModel.selected.isEmpty ? 0.45 : 1)
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showingGroupEditor) {
            Phase1MuscleGroupEditorSheet(hiddenGroups: hiddenGroupSet, customBodyParts: customBodyParts) { group, isVisible in
                setGroupVisibility(group, isVisible: isVisible)
            } onAdd: { name, baseGroup in
                addCustomBodyPart(name: name, baseGroup: baseGroup)
            } onDeleteCustom: { part in
                deleteCustomBodyPart(part)
            }
        }
    }

    private var displayOptions: [(title: String, english: String, groups: [Phase1MuscleGroup])] {
        [
            ("胸", "Chest", [.chest]),
            ("背中", "Back", [.back]),
            ("脚", "Legs", [.legs]),
            ("肩", "Shoulders", [.shoulders]),
            ("腕", "Arms", [.biceps, .triceps]),
            ("腹筋", "Abs", [.abs])
        ]
        .filter { $0.groups.allSatisfy { !hiddenGroupSet.contains($0) } }
        + customBodyParts
            .filter { !hiddenGroupSet.contains($0.baseGroup) }
            .map { (title: $0.name, english: $0.baseGroup.englishTitle, groups: [$0.baseGroup]) }
    }

    private var hiddenGroupSet: Set<Phase1MuscleGroup> {
        Set(hiddenMuscleGroups.split(separator: ",").compactMap { Phase1MuscleGroup(rawValue: String($0)) })
    }

    private var customBodyParts: [Phase1CustomBodyPart] {
        guard let data = customBodyPartsData.data(using: .utf8),
              let parts = try? JSONDecoder().decode([Phase1CustomBodyPart].self, from: data) else { return [] }
        return parts
    }

    private func setGroupVisibility(_ group: Phase1MuscleGroup, isVisible: Bool) {
        var groups = hiddenGroupSet
        if isVisible { groups.remove(group) } else {
            groups.insert(group)
            viewModel.selected.remove(group)
        }
        hiddenMuscleGroups = groups.map(\.rawValue).sorted().joined(separator: ",")
    }

    private func addCustomBodyPart(name: String, baseGroup: Phase1MuscleGroup) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let builtInNames = Set([
            "胸", "背中", "脚", "肩", "腕", "腹筋",
            "Chest", "Back", "Legs", "Shoulders", "Arms", "Abs"
        ])
        guard !cleanName.isEmpty,
              !builtInNames.contains(cleanName),
              !customBodyParts.contains(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) else { return }
        var parts = customBodyParts
        parts.append(Phase1CustomBodyPart(name: cleanName, baseGroup: baseGroup))
        if let data = try? JSONEncoder().encode(parts), let string = String(data: data, encoding: .utf8) { customBodyPartsData = string }
    }

    private func deleteCustomBodyPart(_ part: Phase1CustomBodyPart) {
        let parts = customBodyParts.filter { $0.id != part.id }
        if let data = try? JSONEncoder().encode(parts), let string = String(data: data, encoding: .utf8) { customBodyPartsData = string }
    }
}

// MARK: - Body-part editing
private struct Phase1CustomBodyPart: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let baseGroup: Phase1MuscleGroup

    init(id: UUID = UUID(), name: String, baseGroup: Phase1MuscleGroup) {
        self.id = id; self.name = name; self.baseGroup = baseGroup
    }
}

private struct Phase1MuscleGroupEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let hiddenGroups: Set<Phase1MuscleGroup>
    let customBodyParts: [Phase1CustomBodyPart]
    let onToggle: (Phase1MuscleGroup, Bool) -> Void
    let onAdd: (String, Phase1MuscleGroup) -> Void
    let onDeleteCustom: (Phase1CustomBodyPart) -> Void
    @State private var showingAddSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section("部位") {
                    ForEach(Phase1MuscleGroup.allCases) { group in
                        let isVisible = !hiddenGroups.contains(group)
                        HStack {
                            Text(group.title)
                            Spacer()
                            Button(isVisible ? "削除" : "追加") { onToggle(group, !isVisible) }
                                .buttonStyle(.bordered)
                                .tint(isVisible ? .red : Phase1DesignTokens.orange)
                        }
                        .frame(minHeight: 44)
                    }
                }
                if !customBodyParts.isEmpty {
                    Section("追加した部位") {
                        ForEach(customBodyParts) { part in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(part.name)
                                    Text("種目の基準: \(part.baseGroup.title)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("削除", role: .destructive) { onDeleteCustom(part) }
                                    .buttonStyle(.bordered)
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
                Section {
                    Button("部位を追加") { showingAddSheet = true }
                }
            }
            .navigationTitle("部位を追加・削除")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
            .sheet(isPresented: $showingAddSheet) {
                Phase1AddBodyPartSheet { name, baseGroup in
                    onAdd(name, baseGroup)
                    showingAddSheet = false
                }
            }
        }
    }
}

private struct Phase1AddBodyPartSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (String, Phase1MuscleGroup) -> Void
    @State private var name = ""
    @State private var baseGroup: Phase1MuscleGroup = .chest

    var body: some View {
        NavigationStack {
            Form {
                Section("部位名") { TextField("例：プッシュ", text: $name) }
                Section("種目の基準") {
                    Picker("基準となる部位", selection: $baseGroup) {
                        ForEach(Phase1MuscleGroup.allCases) { group in Text(group.title).tag(group) }
                    }
                }
            }
            .navigationTitle("部位を追加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") { onAdd(name, baseGroup); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private extension Phase1MuscleGroup {
    var englishTitle: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .legs: return "Legs"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .abs: return "Abs"
        }
    }
}

@MainActor
// MARK: - Workout setup
final class Phase1WorkoutSetupViewModel: ObservableObject {
    let groups: [Phase1MuscleGroup]
    private(set) var context: ModelContext?
    @Published var exercises: [Phase1Exercise] = []
    @Published var selectedIDs: [UUID] = []
    @Published var errorMessage: String?

    init(groups: [Phase1MuscleGroup]) { self.groups = groups }
    func load(context: ModelContext) {
        self.context = context
        exercises = ((try? context.fetch(FetchDescriptor<Phase1Exercise>())) ?? [])
            .filter { !$0.isArchived && groups.contains($0.muscleGroup) }.sorted { $0.name < $1.name }
        if selectedIDs.isEmpty { selectedIDs = exercises.map(\.id) }
    }
    func toggle(_ id: UUID) {
        if let index = selectedIDs.firstIndex(of: id) { selectedIDs.remove(at: index) } else { selectedIDs.append(id) }
    }
    func removeExercise(_ id: UUID) {
        selectedIDs.removeAll { $0 == id }
        exercises.removeAll { $0.id == id }
    }
    var availableExercises: [Phase1Exercise] { exercises.filter { !selectedIDs.contains($0.id) } }
    func previousSummary(for exercise: Phase1Exercise) -> String {
        guard let context else { return "前回記録なし" }
        let value = Phase1PreviousRecordService.value(for: exercise, setNumber: 1, before: Date(), in: context)
        guard value.isAvailable else { return "前回記録なし" }
        let weight = exercise.recordType == .weightAndReps ? "\(format(value.weight ?? 0))kg × " : ""
        return "前回 \(weight)\(value.reps)回"
    }

    func createExercise(name: String, group: Phase1MuscleGroup, recordType: Phase1RecordType, weightStep: Double) -> Phase1Exercise? {
        guard let context else { return nil }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              !exercises.contains(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame && $0.muscleGroup == group && $0.recordType == recordType }) else {
            errorMessage = "同じ部位・記録方法の種目がすでにあります。"; return nil
        }
        let exercise = Phase1Exercise(name: cleanName, muscleGroup: group, recordType: recordType, weightStep: weightStep)
        context.insert(exercise)
        do {
            try context.save()
            exercises.append(exercise)
            exercises.sort { $0.name < $1.name }
            selectedIDs.append(exercise.id)
            return exercise
        } catch {
            errorMessage = "種目を保存できませんでした。"; return nil
        }
    }
    func move(from source: IndexSet, to destination: Int) { selectedIDs.move(fromOffsets: source, toOffset: destination) }
    func isSelected(_ id: UUID) -> Bool { selectedIDs.contains(id) }
    func start() -> Phase1Workout? {
        guard let context, !selectedIDs.isEmpty else { return nil }
        // A fast double-tap (or returning from another screen while an active
        // workout already exists) must not create a second active workout.
        if let existing = (try? context.fetch(FetchDescriptor<Phase1Workout>()))?.first(where: { $0.status == .active }) {
            return existing
        }
        let workout = Phase1Workout(); context.insert(workout)
        for (index, id) in selectedIDs.enumerated() {
            guard let exercise = exercises.first(where: { $0.id == id }) else { continue }
            let entry = Phase1WorkoutExercise(orderIndex: index, workout: workout, exercise: exercise)
            context.insert(entry)
            if !workout.workoutExercises.contains(where: { $0.id == entry.id }) { workout.workoutExercises.append(entry) }
        }
        workout.selectedWorkoutExerciseID = workout.workoutExercises.sorted { $0.orderIndex < $1.orderIndex }.first?.id
        do { try context.save(); return workout }
        catch { errorMessage = "トレーニングを開始できませんでした。"; return nil }
    }
    private func format(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }
}

private struct Phase1WorkoutSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: Phase1WorkoutSetupViewModel
    @State private var showingCreateExercise = false
    let onStart: (Phase1Workout) -> Void

    init(groups: [Phase1MuscleGroup], onStart: @escaping (Phase1Workout) -> Void) {
        self.onStart = onStart
        _viewModel = StateObject(wrappedValue: Phase1WorkoutSetupViewModel(groups: groups))
    }

    var body: some View {
        ZStack {
            Phase1DesignTokens.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Phase1IconButton("chevron.left", label: "戻る") { dismiss() }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("今日のトレーニング").font(.title3.bold())
                        Text(groupSummary).font(.subheadline).foregroundStyle(Phase1DesignTokens.secondary)
                    }
                    Spacer()
                    Phase1IconButton("plus", label: "種目を追加") { showingCreateExercise = true }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 18)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(viewModel.exercises) { exercise in
                            let selected = viewModel.isSelected(exercise.id)
                            Button { viewModel.toggle(exercise.id) } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack {
                                            Text(displayName(for: exercise)).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                                            Spacer()
                                        }
                                        Label(viewModel.previousSummary(for: exercise), systemImage: "clock.arrow.circlepath")
                                            .font(.caption).foregroundStyle(Phase1DesignTokens.secondary)
                                    }
                                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Phase1DesignTokens.orange) }
                                }
                                .padding(.horizontal, 16).frame(height: 76)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(RoundedRectangle(cornerRadius: 14))
                                .background(Phase1DesignTokens.card).clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Phase1DesignTokens.orange.opacity(0.65) : .clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("今回から削除", role: .destructive) { viewModel.removeExercise(exercise.id) }
                            }
                        }
                        if viewModel.exercises.isEmpty { Text("種目を1つ以上選択してください").foregroundStyle(Phase1DesignTokens.secondary).padding(.top, 40) }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)
                }
                Phase1PrimaryButton("次へ", accessibilityIdentifier: "nextExerciseButton") {
                    if let workout = viewModel.start() { onStart(workout) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .accessibilityLabel("次へ")
                .disabled(viewModel.selectedIDs.isEmpty)
                .opacity(viewModel.selectedIDs.isEmpty ? 0.45 : 1)
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { viewModel.load(context: modelContext) }
        .sheet(isPresented: $showingCreateExercise) {
            Phase1CreateExerciseView(defaultGroup: viewModel.groups.first ?? .chest) { name, group, type, step in
                if viewModel.createExercise(name: name, group: group, recordType: type, weightStep: step) != nil { showingCreateExercise = false }
            }
        }
        .alert("エラー", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(viewModel.errorMessage ?? "") }
    }

    private var groupSummary: String {
        viewModel.groups.map {
            switch $0 {
            case .triceps: return "三頭"
            case .biceps: return "二頭"
            default: return $0.title
            }
        }.joined(separator: "・")
    }
    private func displayName(for exercise: Phase1Exercise) -> String {
        switch exercise.seedKey {
        case "bench_press": return "Bench Press"
        case "incline_dumbbell_press": return "Incline DB Press"
        case "cable_fly": return "Cable Fly"
        case "push_down": return "Triceps Pushdown"
        default: return exercise.name
        }
    }
}

// MARK: - Exercise creation
private struct Phase1CreateExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    let defaultGroup: Phase1MuscleGroup
    let onCreate: (String, Phase1MuscleGroup, Phase1RecordType, Double) -> Void
    @State private var name = ""
    @State private var group: Phase1MuscleGroup
    @State private var recordType: Phase1RecordType = .weightAndReps
    @State private var weightStep = 2.5

    init(defaultGroup: Phase1MuscleGroup, onCreate: @escaping (String, Phase1MuscleGroup, Phase1RecordType, Double) -> Void) {
        self.defaultGroup = defaultGroup; self.onCreate = onCreate
        _group = State(initialValue: defaultGroup)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("種目") { TextField("種目名", text: $name) }
                Section("部位") { Picker("部位", selection: $group) { ForEach(Phase1MuscleGroup.allCases) { Text($0.title).tag($0) } } }
                Section("記録方法") { Picker("記録方法", selection: $recordType) { ForEach(Phase1RecordType.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented) }
                if recordType == .weightAndReps {
                    Section("重量刻み") { Picker("重量刻み", selection: $weightStep) { ForEach([0.5, 1.0, 2.5, 5.0], id: \.self) { value in Text(String(format: "%.1f kg", value)).tag(value) } } }
                }
                Section { Button("種目を追加") { onCreate(name, group, recordType, weightStep) }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .navigationTitle("新しい種目を作成")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } } }
        }
    }
}

enum Phase1FinishAction {
    case completed(UUID)
    case discarded
    case failed
}

@MainActor
// MARK: - Workout
final class Phase1WorkoutViewModel: ObservableObject {
    private(set) var context: ModelContext?
    let workoutID: UUID
    private let now: () -> Date
    @Published var selectedEntryID: UUID?
    @Published var weightText = ""
    @Published var repsText = ""
    @Published var selectedWeight = Phase1Defaults.defaultWeight
    @Published var selectedReps = Phase1Defaults.defaultReps
    @Published var errorMessage: String?
    @Published var editingSet: Phase1WorkoutSet?

    init(workoutID: UUID, now: @escaping () -> Date = Date.init) {
        self.workoutID = workoutID
        self.now = now
        self.context = nil
        self.selectedEntryID = nil
    }

    func configure(context: ModelContext) {
        self.context = context
        let current = (try? context.fetch(FetchDescriptor<Phase1Workout>()))?.first(where: { $0.id == workoutID })
        if selectedEntryID == nil { selectedEntryID = current?.selectedWorkoutExerciseID ?? current?.workoutExercises.sorted { $0.orderIndex < $1.orderIndex }.first?.id }
        objectWillChange.send()
    }

    var workout: Phase1Workout? { guard let context else { return nil }; return (try? context.fetch(FetchDescriptor<Phase1Workout>()))?.first(where: { $0.id == workoutID }) }
    var entries: [Phase1WorkoutExercise] { workout?.workoutExercises.sorted { $0.orderIndex < $1.orderIndex } ?? [] }
    var selectedEntry: Phase1WorkoutExercise? { entries.first(where: { $0.id == selectedEntryID }) ?? entries.first }
    var selectedExercise: Phase1Exercise? { selectedEntry?.exercise }
    var selectedEntryIndex: Int {
        guard let selectedEntry else { return 0 }
        return entries.firstIndex(where: { $0.id == selectedEntry.id }) ?? 0
    }
    var completedSetCount: Int { selectedEntry?.sets.filter { $0.completedAt != nil }.count ?? 0 }
    var currentSetNumber: Int { completedSetCount + 1 }
    var weightOptions: [Double] {
        guard let exercise = selectedExercise else { return stride(from: 0, through: 500, by: 2.5).map { $0 } }
        return stride(from: Phase1Defaults.minWeight, through: Phase1Defaults.maxWeight, by: max(0.1, exercise.weightStep)).map { $0 }
    }
    var repsOptions: [Int] { Array(Phase1Defaults.minReps...Phase1Defaults.maxReps) }
    var historicalPreviousValue: Phase1PreviousValue? {
        guard let selectedExercise, let workout, let context else { return nil }
        return Phase1PreviousRecordService.value(for: selectedExercise, setNumber: currentSetNumber, before: workout.startedAt, in: context)
    }
    var inputValue: Phase1PreviousValue? {
        guard let selectedExercise else { return nil }
        let historical = historicalPreviousValue
        if historical?.isAvailable == true { return historical }
        if let currentSet = selectedEntry?.sets.last(where: { $0.completedAt != nil }) {
            let weightText = selectedExercise.recordType == .weightAndReps ? "\(format(currentSet.weight ?? 0))kg × " : ""
            return Phase1PreviousValue(weight: selectedExercise.recordType == .weightAndReps ? currentSet.weight : nil, reps: currentSet.reps, display: "このトレーニングの前セット：\(weightText)\(currentSet.reps)回", isAvailable: true)
        }
        return historical
    }
    var previousDisplay: String {
        if historicalPreviousValue?.isAvailable == true {
            return historicalPreviousValue?.display ?? ""
        }
        guard let selectedExercise else { return "前回記録なし" }
        let initial = selectedExercise.recordType == .weightAndReps
            ? "初期値：\(format(selectedWeight))kg × \(selectedReps)回"
            : "初期値：\(selectedReps)回"
        return "前回記録なし  ·  \(initial.replacingOccurrences(of: "初期値：", with: "初期値 "))"
    }
    var remainingRest: TimeInterval? {
        guard let workout else { return nil }
        return Phase1WorkoutRecoveryService.remainingRest(for: workout)
    }

    func select(_ entryID: UUID) {
        guard let context, entries.contains(where: { $0.id == entryID }), let workout else { return }
        let previousEntryID = selectedEntryID
        selectedEntryID = entryID
        workout.selectedWorkoutExerciseID = entryID
        workout.updatedAt = now()
        do {
            try context.save()
            loadDefaults()
        } catch {
            // Do not leave the UI pointing at an exercise whose selection was
            // not persisted. This keeps the picker, menu and saved workout in
            // sync when a save fails.
            selectedEntryID = previousEntryID
            errorMessage = "種目の切り替えを保存できませんでした。"
        }
    }

    func loadDefaults() {
        guard let exercise = selectedExercise else { return }
        // A newly selected exercise may not have a previous record yet. In
        // that case reset to the app defaults instead of leaking the values
        // from the exercise that was previously on screen.
        let value = inputValue
        selectedWeight = normalize(value?.weight ?? Phase1Defaults.defaultWeight, step: exercise.weightStep)
        selectedReps = min(Phase1Defaults.maxReps, max(Phase1Defaults.minReps, value?.reps ?? Phase1Defaults.defaultReps))
        if exercise.recordType == .weightAndReps { weightText = format(selectedWeight) } else { weightText = "" }
        repsText = String(selectedReps)
    }

    func completeSet() {
        guard let context, let entry = selectedEntry, let exercise = entry.exercise, let workout else { return }
        // SET COMPLETE is the primary CTA, so it is easy to tap twice. Once a
        // set starts its rest period, ignore repeated taps until the rest is
        // skipped or expires.
        if let restEndAt = workout.restEndAt, restEndAt > now() { return }
        let reps = selectedReps
        guard (Phase1Defaults.minReps...Phase1Defaults.maxReps).contains(reps) else { errorMessage = "回数は1〜100で入力してください。"; return }
        var weight: Double?
        if exercise.recordType == .weightAndReps {
            guard selectedWeight >= Phase1Defaults.minWeight, selectedWeight <= Phase1Defaults.maxWeight else { errorMessage = "重量は0〜500kgで入力してください。"; return }
            weight = normalize(selectedWeight, step: exercise.weightStep)
        }
        let previousRestEndAt = workout.restEndAt
        let previousRestingSetID = workout.restingAfterSetID
        let previousCompletionState = entry.isCompleted
        let previousCompletedAt = entry.completedAt
        let set = Phase1WorkoutSet(setNumber: currentSetNumber, weight: weight, reps: reps, completedAt: now(), updatedAt: now(), workoutExercise: entry)
        context.insert(set); if !entry.sets.contains(where: { $0.id == set.id }) { entry.sets.append(set) }; entry.isCompleted = false; entry.completedAt = nil
        workout.restingAfterSetID = set.id; workout.restEndAt = now().addingTimeInterval(TimeInterval(exercise.restDuration)); workout.updatedAt = now()
        do {
            try context.save()

            // Keep the value the user just entered while the rest timer is
            // shown. Calling loadDefaults() here can immediately replace it
            // with the previous workout's value for the next set number
            // (for example, changing 20kg to 21kg would appear to revert to
            // 20kg after SET COMPLETE). The next set should start from the
            // completed set's value; selecting another exercise still calls
            // loadDefaults() and applies its historical defaults as usual.
            if exercise.recordType == .weightAndReps, let weight {
                selectedWeight = weight
                weightText = format(weight)
            }
            selectedReps = reps
            repsText = String(reps)
            objectWillChange.send()
        }
        catch {
            context.delete(set)
            entry.sets.removeAll { $0.id == set.id }
            entry.isCompleted = previousCompletionState
            entry.completedAt = previousCompletedAt
            workout.restEndAt = previousRestEndAt
            workout.restingAfterSetID = previousRestingSetID
            errorMessage = "セットを保存できませんでした。入力を確認して再試行してください。"
        }
    }

    func completeExercise() {
        guard let context, let entry = selectedEntry, !entry.sets.filter({ $0.completedAt != nil }).isEmpty else { errorMessage = "先に1セット以上記録してください。"; return }
        entry.isCompleted = true; entry.completedAt = now()
        do { try context.save(); objectWillChange.send() } catch { errorMessage = "種目の完了を保存できませんでした。" }
    }

    func editSet(id: UUID, weight: Double?, reps: Int) {
        guard let context, let set = selectedEntry?.sets.first(where: { $0.id == id }), let exercise = selectedExercise,
              (Phase1Defaults.minReps...Phase1Defaults.maxReps).contains(reps) else { errorMessage = "入力値を確認してください。"; return }
        let previousWeight = set.weight
        let previousReps = set.reps
        let previousUpdatedAt = set.updatedAt
        set.weight = exercise.recordType == .weightAndReps ? normalize(weight ?? 0, step: exercise.weightStep) : nil
        set.reps = reps; set.updatedAt = now()
        do {
            try context.save()
            editingSet = nil
            objectWillChange.send()
        } catch {
            set.weight = previousWeight
            set.reps = previousReps
            set.updatedAt = previousUpdatedAt
            errorMessage = "セットを更新できませんでした。"
        }
    }

    func deleteSet(_ set: Phase1WorkoutSet) {
        guard let context, let entry = selectedEntry, let workout else { return }
        guard entry.sets.contains(where: { $0.id == set.id }) else { return }
        let previousSets = entry.sets
        let previousNumbers = Dictionary(uniqueKeysWithValues: previousSets.map { ($0.id, $0.setNumber) })
        let previousRestEndAt = workout.restEndAt
        let previousRestingSetID = workout.restingAfterSetID
        context.delete(set); entry.sets.removeAll { $0.id == set.id }
        for (index, item) in entry.sets.sorted(by: { $0.setNumber < $1.setNumber }).enumerated() { item.setNumber = index + 1 }
        if workout.restingAfterSetID == set.id { workout.restingAfterSetID = nil; workout.restEndAt = nil }
        workout.updatedAt = now()
        do {
            try context.save()
            editingSet = nil
            objectWillChange.send()
            loadDefaults()
        } catch {
            // Restore the in-memory relationship and numbering if persistence
            // fails, so the visible workout is never left partially deleted.
            context.insert(set)
            set.workoutExercise = entry
            entry.sets = previousSets
            for item in previousSets {
                if let number = previousNumbers[item.id] { item.setNumber = number }
            }
            workout.restEndAt = previousRestEndAt
            workout.restingAfterSetID = previousRestingSetID
            errorMessage = "セットを削除できませんでした。"
        }
    }

    func addRestTime(_ seconds: Int) {
        guard let context, let workout else { return }
        let current = max(workout.restEndAt ?? now(), now())
        let adjusted = current.addingTimeInterval(TimeInterval(seconds))
        if adjusted <= now() {
            workout.restEndAt = nil
            workout.restingAfterSetID = nil
        } else {
            workout.restEndAt = min(adjusted, now().addingTimeInterval(600))
        }
        do { try context.save(); objectWillChange.send() } catch { errorMessage = "休憩時間を保存できませんでした。" }
    }

    func setRestDuration(seconds: Int) {
        guard let context, let workout else { return }
        let clampedSeconds = min(600, max(0, seconds))
        if clampedSeconds == 0 {
            workout.restEndAt = nil
            workout.restingAfterSetID = nil
        } else {
            // Use the current time as the base so an expired timer can be
            // restarted from the duration editor.
            workout.restEndAt = now().addingTimeInterval(TimeInterval(clampedSeconds))
        }
        do { try context.save(); objectWillChange.send() } catch { errorMessage = "休憩時間を保存できませんでした。" }
    }

    // Kept for existing callers while the UI now edits minutes and seconds.
    func setRestDuration(minutes: Int) {
        setRestDuration(seconds: minutes * 60)
    }

    func skipRest() {
        // Defer the overlay removal until the current tap has finished. If the
        // state is cleared synchronously, the same touch-up event can fall
        // through to the Workout screen's destructive end button.
        DispatchQueue.main.async { [weak self] in
            guard let self, let context = self.context, let workout = self.workout else { return }
            workout.restEndAt = nil
            workout.restingAfterSetID = nil
            do { try context.save(); self.objectWillChange.send() }
            catch { self.errorMessage = "休憩状態を更新できませんでした。" }
        }
    }

    func finish() -> Phase1FinishAction {
        guard let context, let workout else { return .failed }
        let total = workout.workoutExercises.reduce(0) { $0 + $1.sets.filter { $0.completedAt != nil }.count }
        if total == 0 {
            context.delete(workout)
            do { try context.save(); return .discarded } catch { errorMessage = "トレーニングを破棄できませんでした。"; return .failed }
        }
        workout.status = .completed; workout.endedAt = now(); workout.restEndAt = nil; workout.restingAfterSetID = nil; workout.updatedAt = now()
        do { try context.save(); return .completed(workout.id) } catch { errorMessage = "完了を保存できませんでした。入力は保持されています。"; return .failed }
    }

    private func normalize(_ value: Double, step: Double) -> Double { min(Phase1Defaults.maxWeight, max(Phase1Defaults.minWeight, (value / max(0.1, step)).rounded() * max(0.1, step))) }
    func formatWeight(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }
    private func format(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }
}

private struct Phase1WorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: Phase1WorkoutViewModel
    @AppStorage("phase1KeepScreenAwake") private var keepScreenAwake = false
    @State private var showingFinishConfirmation = false
    let onBack: () -> Void
    let onFinish: (UUID?) -> Void

    init(workoutID: UUID, onBack: @escaping () -> Void = {}, onFinish: @escaping (UUID?) -> Void) {
        self.onBack = onBack
        self.onFinish = onFinish
        _viewModel = StateObject(wrappedValue: Phase1WorkoutViewModel(workoutID: workoutID))
    }

    var body: some View {
        ZStack {
            Phase1DesignTokens.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    entryContent
                        .padding(16)
                        .padding(.bottom, 18)
                }
                finishButton
            }
            if viewModel.workout?.restEndAt != nil {
                Phase1RestOverlay(viewModel: viewModel)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .onAppear {
            viewModel.configure(context: modelContext)
            viewModel.loadDefaults()
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        }
        .onChange(of: keepScreenAwake) { _, value in
            UIApplication.shared.isIdleTimerDisabled = value
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .confirmationDialog("トレーニングを終了しますか？", isPresented: $showingFinishConfirmation, titleVisibility: .visible) {
            Button("終了する", role: .destructive) { finishWorkout() }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("記録済みのセットは保存されます。") }
        .alert("入力エラー", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(viewModel.errorMessage ?? "") }
        .sheet(item: $viewModel.editingSet) { set in
            Phase1SetEditSheet(set: set, exercise: viewModel.selectedExercise) { weight, reps in
                viewModel.editSet(id: set.id, weight: weight, reps: reps)
            } onDelete: {
                viewModel.deleteSet(set)
            }
        }
    }

    @ViewBuilder private var entryContent: some View {
        if let entry = viewModel.selectedEntry, let exercise = entry.exercise {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Phase1IconButton("chevron.left", label: "種目選択に戻る") { onBack() }
                    Text("Workout").font(.headline.weight(.semibold)).foregroundStyle(.white)
                    Spacer()
                    Text("種目 \(viewModel.selectedEntryIndex + 1) / \(viewModel.entries.count)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Menu {
                        ForEach(viewModel.entries) { item in
                            Button {
                                viewModel.select(item.id)
                            } label: {
                                if item.id == entry.id {
                                    Label(phase1DisplayExerciseName(item.exercise), systemImage: "checkmark")
                                } else {
                                    Text(phase1DisplayExerciseName(item.exercise))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(phase1DisplayExerciseName(exercise)).font(.title2.bold()).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.8)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(Color.white.opacity(0.9))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    Spacer()
                }
                HStack {
                    Text("SET \(viewModel.currentSetNumber)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.previousDisplay)
                        .font(.caption)
                        .foregroundStyle(viewModel.historicalPreviousValue?.isAvailable == true ? Color.secondary : Color.orange)
                        .multilineTextAlignment(.trailing)
                }
                HStack(alignment: .top, spacing: 14) {
                    if exercise.recordType == .weightAndReps {
                        VStack(spacing: 3) {
                            Text("重量 (kg)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Picker("重量", selection: $viewModel.selectedWeight) {
                                ForEach(viewModel.weightOptions, id: \.self) { value in Text(format(value)).monospacedDigit().tag(value) }
                            }
                            .pickerStyle(.wheel).frame(height: 160).clipped()
                        }
                        .frame(maxWidth: .infinity).frame(height: 182)
                        .background(Phase1DesignTokens.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    VStack(spacing: 3) {
                        Text("回数").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Picker("回数", selection: $viewModel.selectedReps) {
                            ForEach(viewModel.repsOptions, id: \.self) { value in Text("\(value)").monospacedDigit().tag(value) }
                        }
                        .pickerStyle(.wheel).frame(height: 160).clipped()
                    }
                    .frame(maxWidth: .infinity).frame(height: 182)
                    .background(Phase1DesignTokens.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button { viewModel.completeSet() } label: {
                    Label("SET COMPLETE", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity).frame(height: 52)
                }
                .foregroundStyle(.white)
                .background(Phase1DesignTokens.orangeGradient)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("completeSetButton")
                .accessibilityLabel("セットを完了")
                .accessibilityHint("入力した重量と回数を保存して休憩タイマーを開始します")
                if let latest = entry.sets.filter({ $0.completedAt != nil }).max(by: { $0.setNumber < $1.setNumber }),
                   let workout = viewModel.workout,
                   let context = viewModel.context {
                    let result = Phase1PRService.result(for: latest, exercise: exercise, workout: workout, in: context)
                    if result.count > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                            Text(result.weightPR
                                 ? "自己ベスト +\(viewModel.formatWeight(latest.weight ?? 0))kg"
                                 : "自己ベスト +1回")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("自己ベスト更新")
                    }
                }
                Text("記録済みセット").font(.headline)
                ForEach(entry.sets.filter { $0.completedAt != nil }.sorted { $0.setNumber < $1.setNumber }) { set in
                    Button { viewModel.editingSet = set } label: {
                        HStack {
                            Text("SET \(set.setNumber)").font(.headline)
                            Spacer()
                            Text(exercise.recordType == .weightAndReps ? "\(format(set.weight ?? 0))kg × \(set.reps)回" : "\(set.reps)回")
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                        .background(Phase1DesignTokens.card)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).swipeActions { Button("削除", role: .destructive) { viewModel.deleteSet(set) } }
                }
            }
        } else { ContentUnavailableView("種目がありません", systemImage: "dumbbell") }
    }

    private func finishWorkout() {
        switch viewModel.finish() { case .completed(let id): onFinish(id); case .discarded: onFinish(nil); case .failed: break }
    }
    private var finishButton: some View {
        Button { showingFinishConfirmation = true } label: {
            Text("トレーニングを終了")
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .foregroundStyle(Phase1DesignTokens.secondary)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Phase1DesignTokens.secondary.opacity(0.55)))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Phase1DesignTokens.background)
        .accessibilityHint("保存済みのセットを残してトレーニングを終了します")
    }
    private func format(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }
}

// MARK: - Rest and set editing
private struct Phase1RestOverlay: View {
    @ObservedObject var viewModel: Phase1WorkoutViewModel
    @AppStorage("phase1RestHapticsEnabled") private var restHapticsEnabled = true
    @State private var didHaptic = false
    @State private var showingDurationEditor = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let remaining = max(0, (viewModel.workout?.restEndAt ?? context.date).timeIntervalSince(context.date))
            ZStack {
                Phase1DesignTokens.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Text("REST").font(.caption.weight(.bold)).tracking(3)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)

                    ZStack {
                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: restProgress(remaining: remaining))
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.8), value: remaining)
                        VStack(spacing: 4) {
                            Text(String(format: "%02d:%02d", Int(remaining) / 60, Int(remaining) % 60))
                                .font(.system(size: 58, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text("休憩中").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 280, height: 280)
                    .padding(.top, 24)
                    .contentShape(Rectangle())
                    .onTapGesture { showingDurationEditor = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("休憩時間を分単位で編集")

                    HStack(spacing: 12) {
                        Button { viewModel.addRestTime(-30) } label: {
                            Text("-30秒")
                                .frame(maxWidth: .infinity).frame(height: 48)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.8))
                        .accessibilityLabel("休憩を30秒短くする")
                        Button { viewModel.addRestTime(30) } label: {
                            Text("+30秒")
                                .frame(maxWidth: .infinity).frame(height: 48)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.8))
                        .accessibilityLabel("休憩を30秒延長する")
                    }
                    .padding(.top, 18)
                    Spacer(minLength: 24)
                    Phase1PrimaryButton("次のセット", accessibilityIdentifier: "nextSetButton") {
                        viewModel.skipRest()
                    }
                    .accessibilityHint("休憩を終了して次のセットを入力します")
                    if let exercise = viewModel.selectedExercise {
                        Text("Next: SET \(viewModel.currentSetNumber) - \(phase1DisplayExerciseName(exercise))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 12)
                            .padding(.bottom, 18)
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 20)
                .frame(maxWidth: 360)
                .onChange(of: remaining) { _, value in
                    if restHapticsEnabled, value == 0, !didHaptic {
                        didHaptic = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
            }
        }
        .onAppear { didHaptic = false }
        .onChange(of: viewModel.workout?.restEndAt) { _, _ in didHaptic = false }
        .sheet(isPresented: $showingDurationEditor) {
            Phase1RestDurationSheet(currentRemaining: viewModel.remainingRest ?? 0) { seconds in
                viewModel.setRestDuration(seconds: seconds)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("休憩タイマー")
    }

    private func restProgress(remaining: TimeInterval) -> CGFloat {
        let duration = max(1, viewModel.selectedExercise?.restDuration ?? Phase1Defaults.defaultRest)
        return min(1, max(0, CGFloat(remaining) / CGFloat(duration)))
    }
}

private struct Phase1RestDurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Int) -> Void
    @State private var minutes: Int
    @State private var seconds: Int

    init(currentRemaining: TimeInterval, onSave: @escaping (Int) -> Void) {
        self.onSave = onSave
        let totalSeconds = min(600, max(0, Int(currentRemaining.rounded())))
        _minutes = State(initialValue: totalSeconds / 60)
        _seconds = State(initialValue: totalSeconds % 60)
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack(alignment: .center, spacing: 0) {
                    Picker("分", selection: $minutes) {
                        ForEach(0...10, id: \.self) { value in
                            Text("\(value)").monospacedDigit().tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    Text("分").foregroundStyle(.secondary)
                    Picker("秒", selection: $seconds) {
                        ForEach(0...59, id: \.self) { value in
                            Text(String(format: "%02d", value)).monospacedDigit().tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    Text("秒").foregroundStyle(.secondary)
                }
                .frame(height: 180)
                Text("設定範囲：0:00〜10:00")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("休憩時間を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(min(600, minutes * 60 + seconds)); dismiss() }
                }
            }
        }
    }
}

private struct Phase1SetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let set: Phase1WorkoutSet
    let exercise: Phase1Exercise?
    let onSave: (Double?, Int) -> Void
    let onDelete: (() -> Void)?
    @State private var selectedWeight: Double
    @State private var selectedReps: Int
    @State private var showingDeleteConfirmation = false

    init(set: Phase1WorkoutSet, exercise: Phase1Exercise?, onSave: @escaping (Double?, Int) -> Void, onDelete: (() -> Void)? = nil) {
        self.set = set; self.exercise = exercise; self.onSave = onSave; self.onDelete = onDelete
        let step = max(0.1, exercise?.weightStep ?? 2.5)
        let normalizedWeight = min(Phase1Defaults.maxWeight, max(Phase1Defaults.minWeight, ((set.weight ?? Phase1Defaults.defaultWeight) / step).rounded() * step))
        _selectedWeight = State(initialValue: normalizedWeight)
        _selectedReps = State(initialValue: set.reps)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let exercise, exercise.recordType == .weightAndReps {
                    Picker("重量 (kg)", selection: $selectedWeight) {
                        ForEach(stride(from: Phase1Defaults.minWeight, through: Phase1Defaults.maxWeight, by: max(0.1, exercise.weightStep)).map { $0 }, id: \.self) { value in
                            Text(format(value)).monospacedDigit().tag(value)
                        }
                    }.pickerStyle(.wheel).frame(height: 140)
                }
                Picker("回数", selection: $selectedReps) {
                    ForEach(Phase1Defaults.minReps...Phase1Defaults.maxReps, id: \.self) { value in Text("\(value)").monospacedDigit().tag(value) }
                }.pickerStyle(.wheel).frame(height: 140)
            }.navigationTitle("SET \(set.setNumber)を編集")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { onSave(exercise?.recordType == .weightAndReps ? selectedWeight : nil, selectedReps); dismiss() } } }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if onDelete != nil {
                        Button("セットを削除", role: .destructive) { showingDeleteConfirmation = true }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(.bar)
                    }
                }
                .confirmationDialog("SET \(set.setNumber)を削除しますか？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                    Button("削除する", role: .destructive) { onDelete?(); dismiss() }
                    Button("キャンセル", role: .cancel) {}
                }
        }
    }

    private func format(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }
}

@MainActor
// MARK: - Result
final class Phase1ResultViewModel: ObservableObject {
    private(set) var context: ModelContext?
    let workoutID: UUID
    init(workoutID: UUID) { self.workoutID = workoutID; self.context = nil }
    func configure(context: ModelContext) { self.context = context; objectWillChange.send() }
    var workout: Phase1Workout? { guard let context else { return nil }; return (try? context.fetch(FetchDescriptor<Phase1Workout>()))?.first(where: { $0.id == workoutID }) }
    var performedEntries: [Phase1WorkoutExercise] { workout?.workoutExercises.filter { $0.sets.contains { $0.completedAt != nil } }.sorted { $0.orderIndex < $1.orderIndex } ?? [] }
    var totalSets: Int { performedEntries.reduce(0) { $0 + $1.sets.filter { $0.completedAt != nil }.count } }
    var totalVolume: Double { performedEntries.flatMap(\.sets).filter { $0.completedAt != nil }.compactMap { set in set.weight.map { $0 * Double(set.reps) } }.reduce(0, +) }
    func prs(for entry: Phase1WorkoutExercise) -> Int {
        guard let workout, let exercise = entry.exercise, let context else { return 0 }
        return entry.sets.filter { $0.completedAt != nil }.reduce(0) { $0 + Phase1PRService.result(for: $1, exercise: exercise, workout: workout, in: context).count }
    }
}

private struct Phase1ResultView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: Phase1ResultViewModel
    let onDone: () -> Void

    init(workoutID: UUID, onDone: @escaping () -> Void) {
        self.onDone = onDone
        _viewModel = StateObject(wrappedValue: Phase1ResultViewModel(workoutID: workoutID))
    }

    var body: some View {
        ZStack {
            Phase1DesignTokens.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("トレーニング完了").font(.title3.bold()).frame(maxWidth: .infinity, alignment: .center).padding(.top, 12)
                    if let workout = viewModel.workout {
                        VStack(spacing: 0) {
                            resultLine("", phase1SlashDate(workout.startedAt))
                            resultLine("部位", workoutMuscleSummary(workout))
                            resultLine("時間", workoutDurationText(workout))
                            resultLine("種目数", "\(viewModel.performedEntries.count)")
                            resultLine("総セット数", "\(viewModel.totalSets)")
                        }
                        .padding(16).background(Phase1DesignTokens.card).clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    Text("種目別詳細").font(.subheadline).foregroundStyle(Phase1DesignTokens.secondary)
                    ForEach(viewModel.performedEntries) { entry in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(displayName(for: entry.exercise)).font(.headline)
                                Spacer()
                                Text("\(entry.sets.filter { $0.completedAt != nil }.count) sets").font(.subheadline).foregroundStyle(Phase1DesignTokens.secondary)
                            }
                            if let best = bestSet(for: entry) {
                                Text(best.weight.map { "Best: \(format($0))kg × \(best.reps)" } ?? "Best: \(best.reps)回")
                                    .font(.subheadline).foregroundStyle(Phase1DesignTokens.orange)
                            }
                        }
                        .padding(14).background(Phase1DesignTokens.card).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Spacer(minLength: 50)
                }
                .padding(.horizontal, 20).padding(.bottom, 100)
            }
            VStack {
                Spacer()
                Phase1PrimaryButton("ホームに戻る", accessibilityIdentifier: "resultHomeButton", action: onDone)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { viewModel.configure(context: modelContext) }
    }

    private func format(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }
    @ViewBuilder
    private func resultLine(_ title: String, _ value: String) -> some View {
        if title.isEmpty {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().frame(maxWidth: .infinity, alignment: .center).frame(height: 30)
        } else {
            HStack { Text(title).foregroundStyle(Phase1DesignTokens.secondary); Spacer(); Text(value).fontWeight(.semibold).monospacedDigit() }.frame(height: 26)
        }
    }
    private func workoutMuscleSummary(_ workout: Phase1Workout) -> String {
        workout.workoutExercises.first(where: { $0.sets.contains { $0.completedAt != nil } })?.exercise?.muscleGroup.title ?? ""
    }
    private func workoutDurationText(_ workout: Phase1Workout) -> String {
        guard let end = workout.endedAt else { return "—" }
        return "\(max(1, Int(end.timeIntervalSince(workout.startedAt) / 60)))min"
    }
    private func bestSet(for entry: Phase1WorkoutExercise) -> Phase1WorkoutSet? {
        entry.sets.filter { $0.completedAt != nil }.max { ($0.weight ?? 0, $0.reps) < ($1.weight ?? 0, $1.reps) }
    }
    private func displayName(for exercise: Phase1Exercise?) -> String {
        switch exercise?.seedKey {
        case "bench_press": return "Bench Press"
        case "incline_dumbbell_press": return "Incline DB Press"
        case "cable_fly": return "Cable Fly"
        case "push_down": return "Triceps Pushdown"
        default: return exercise?.name ?? "種目"
        }
    }
}
