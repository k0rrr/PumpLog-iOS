import Combine
import SwiftUI

enum HistoryPeriod: String, CaseIterable, Identifiable {
    case all = "全期間"
    case last7Days = "過去7日"
    case last30Days = "過去30日"
    case last90Days = "過去90日"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .all: nil
        case .last7Days: 7
        case .last30Days: 30
        case .last90Days: 90
        }
    }
}

enum ProgressMetric: String, CaseIterable, Identifiable {
    case maxWeight = "最大重量"
    case estimatedOneRepMax = "推定1RM"
    case volume = "総負荷量"

    var id: String { rawValue }
    var unit: String { "kg" }

    func value(for point: ExerciseProgressPoint) -> Double {
        switch self {
        case .maxWeight: point.maxWeight
        case .estimatedOneRepMax: point.estimatedOneRepMax
        case .volume: point.totalVolume
        }
    }
}

@MainActor
final class RecordViewModel: ObservableObject {
    let store: AppStore

    @Published var weight = ""
    @Published var reps = ""
    @Published var showValidationError = false
    @Published var showingExercisePicker = false
    @Published var showingTemplatePicker = false

    private var storeCancellable: AnyCancellable?

    init(store: AppStore) {
        self.store = store
        storeCancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var draft: WorkoutDraft { store.draft }
    var exercises: [Exercise] { store.exercises }
    var selectedEntryIndex: Int? { store.selectedEntryIndex }
    var selectedEntry: SessionExerciseDraft? { store.selectedEntry }
    var personalBestMessage: String? { store.personalBestMessage }
    var hasPreviousWorkout: Bool { store.hasPreviousWorkout }

    var dateBinding: Binding<Date> {
        Binding(get: { self.store.draft.date }, set: { self.store.draft.date = $0 })
    }

    var restDurationBinding: Binding<Int> {
        Binding(get: { self.store.draft.restDuration }, set: { self.store.draft.restDuration = $0 })
    }

    func noteBinding(for entryIndex: Int) -> Binding<String> {
        Binding(
            get: { self.store.draft.exercises[entryIndex].note },
            set: { self.store.draft.exercises[entryIndex].note = $0 }
        )
    }

    func setBinding(entryIndex: Int, setIndex: Int) -> Binding<WorkoutSet> {
        Binding(
            get: { self.store.draft.exercises[entryIndex].sets[setIndex] },
            set: { self.store.draft.exercises[entryIndex].sets[setIndex] = $0 }
        )
    }

    func exercise(for entry: SessionExerciseDraft) -> Exercise? {
        store.exercise(for: entry)
    }

    func selectWorkoutEntry(_ entryID: UUID) {
        store.selectWorkoutEntry(entryID)
    }

    func removeSelectedExercise() {
        store.removeSelectedExercise()
    }

    func removeSet(entryIndex: Int, setIndex: Int) {
        guard store.draft.exercises.indices.contains(entryIndex),
              store.draft.exercises[entryIndex].sets.indices.contains(setIndex) else { return }
        store.draft.exercises[entryIndex].sets.remove(at: setIndex)
    }

    func duplicateSet(at index: Int) {
        store.duplicateSet(at: index)
    }

    func duplicateLastSet() {
        store.duplicateLastSet()
    }

    func startRestTimer() {
        store.startRestTimer(seconds: store.draft.restDuration)
    }

    func addRestTime(_ seconds: Int) {
        store.addRestTime(seconds)
    }

    func stopRestTimer() {
        store.stopRestTimer()
    }

    func addExercise(_ exerciseID: UUID) {
        store.addExerciseToWorkout(exerciseID)
    }

    func applyTemplate(_ template: WorkoutTemplate) {
        store.applyTemplate(template)
    }

    func repeatPreviousWorkout() {
        store.repeatPreviousWorkout()
    }

    func openExercisePicker() {
        showingExercisePicker = true
    }

    func addSet() {
        guard let parsedWeight = Double(weight.replacingOccurrences(of: ",", with: ".")),
              let parsedReps = Int(reps), parsedWeight >= 0, parsedReps > 0 else {
            showValidationError = true
            return
        }
        store.appendSet(weight: parsedWeight, reps: parsedReps)
        weight = ""
        reps = ""
    }

    func completeWorkout() -> Bool {
        guard store.finishWorkout() else {
            showValidationError = true
            return false
        }
        weight = ""
        reps = ""
        showValidationError = false
        showingExercisePicker = false
        showingTemplatePicker = false
        return true
    }

    func clearPersonalBestMessage() {
        store.personalBestMessage = nil
    }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    let store: AppStore

    @Published var editingRecord: WorkoutRecord?
    @Published var recordPendingDeletion: WorkoutRecord?
    @Published var selectedDate = Date()
    @Published var displayedMonth = Date()
    @Published var searchText = ""
    @Published var selectedMuscleGroup: MuscleGroup?
    @Published var period: HistoryPeriod = .all

    private let calendar = Calendar.current
    private var storeCancellable: AnyCancellable?

    init(store: AppStore) {
        self.store = store
        storeCancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var hasActiveFilter: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedMuscleGroup != nil
            || period != .all
    }

    var selectedRecords: [WorkoutRecord] {
        store.records
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.date > $1.date }
    }

    var filteredRecords: [WorkoutRecord] {
        store.records.filter(matchesFilters).sorted { $0.date > $1.date }
    }

    var displayRecords: [WorkoutRecord] {
        hasActiveFilter ? filteredRecords : selectedRecords
    }

    var calendarRecords: [WorkoutRecord] {
        hasActiveFilter ? filteredRecords : store.records
    }

    var deletionAlert: Binding<Bool> {
        Binding(
            get: { self.recordPendingDeletion != nil },
            set: { if !$0 { self.recordPendingDeletion = nil } }
        )
    }

    func selectInitialDateIfNeeded() {
        guard let latest = store.records.max(by: { $0.date < $1.date }),
              !store.records.contains(where: { calendar.isDateInToday($0.date) }) else { return }
        selectedDate = latest.date
        displayedMonth = latest.date
    }

    func resetFilters() {
        searchText = ""
        selectedMuscleGroup = nil
        period = .all
    }

    func updateRecord(_ record: WorkoutRecord) {
        store.updateRecord(record)
    }

    func deletePendingRecord() {
        if let recordPendingDeletion {
            store.deleteRecord(recordPendingDeletion)
        }
        recordPendingDeletion = nil
    }

    func muscleGroup(for record: WorkoutRecord) -> MuscleGroup {
        if let exerciseID = record.exerciseID,
           let exercise = store.exercises.first(where: { $0.id == exerciseID }) {
            return exercise.muscleGroup
        }
        return store.exercises.first(where: { $0.name == record.exerciseName })?.muscleGroup ?? .fullBody
    }

    private func matchesFilters(_ record: WorkoutRecord) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let matchesText = record.exerciseName.localizedCaseInsensitiveContains(query)
                || record.note.localizedCaseInsensitiveContains(query)
            guard matchesText else { return false }
        }

        if let selectedMuscleGroup,
           muscleGroup(for: record) != selectedMuscleGroup {
            return false
        }

        if let days = period.days,
           let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date())),
           record.date < startDate {
            return false
        }
        return true
    }
}

@MainActor
final class GrowthViewModel: ObservableObject {
    let store: AppStore

    @Published var selectedExerciseID: UUID?
    @Published var metric: ProgressMetric = .maxWeight
    private var storeCancellable: AnyCancellable?

    init(store: AppStore) {
        self.store = store
        storeCancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var selectedExercise: Exercise? {
        store.exercises.first { $0.id == selectedExerciseID }
    }

    var exerciseRecords: [WorkoutRecord] {
        guard let selectedExerciseID else { return [] }
        return WorkoutAnalytics.records(for: selectedExerciseID, in: store.records)
    }

    var summary: PersonalBestSummary {
        guard let selectedExerciseID else { return .empty }
        return WorkoutAnalytics.summary(for: selectedExerciseID, in: store.records)
    }

    func selectInitialExerciseIfNeeded() {
        guard selectedExerciseID == nil else { return }
        selectedExerciseID = store.exercises.first(where: { exercise in
            store.records.contains { $0.exerciseID == exercise.id }
        })?.id ?? store.exercises.first?.id
    }
}

@MainActor
final class MuscleMapViewModel: ObservableObject {
    let store: AppStore

    @Published var selectedDate = Date()
    private var didSelectInitialDate = false
    private var storeCancellable: AnyCancellable?
    private let calendar = Calendar.current

    init(store: AppStore) {
        self.store = store
        storeCancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var snapshot: MuscleLoadSnapshot {
        MuscleLoadAnalytics.snapshot(on: selectedDate, records: store.records, exercises: store.exercises)
    }

    func moveDate(_ amount: Int) {
        guard let nextDate = calendar.date(byAdding: .day, value: amount, to: selectedDate),
              nextDate <= Date() else { return }
        selectedDate = nextDate
    }

    func selectUsefulInitialDate() {
        guard !didSelectInitialDate else { return }
        didSelectInitialDate = true
        guard !store.records.contains(where: { calendar.isDateInToday($0.date) }),
              let latest = store.records.max(by: { $0.date < $1.date }) else { return }
        selectedDate = latest.date
    }
}

@MainActor
final class ExerciseManagementViewModel: ObservableObject {
    let store: AppStore

    @Published var editingExercise: Exercise?
    @Published var showingNewExercise = false
    @Published var showingNewTemplate = false
    private var storeCancellable: AnyCancellable?

    init(store: AppStore) {
        self.store = store
        storeCancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var exercises: [Exercise] { store.exercises }
    var templates: [WorkoutTemplate] { store.templates }

    func deleteExercises(at offsets: IndexSet) { store.deleteExercises(at: offsets) }
    func moveExercises(from source: IndexSet, to destination: Int) { store.moveExercises(from: source, to: destination) }
    func deleteTemplates(at offsets: IndexSet) { store.deleteTemplates(at: offsets) }

    func addExercise(name: String, group: MuscleGroup, equipment: String, targets: [MuscleRegion]) -> Bool {
        store.addExercise(name: name, muscleGroup: group, equipment: equipment, targetMuscles: targets)
    }

    func updateExercise(_ exercise: Exercise) -> Bool {
        store.updateExercise(exercise)
    }
}

@MainActor
final class WorkoutExercisePickerViewModel: ObservableObject {
    let store: AppStore
    private var storeCancellable: AnyCancellable?

    init(store: AppStore) {
        self.store = store
        storeCancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var exercises: [Exercise] { store.exercises }

    func isSelected(_ exerciseID: UUID) -> Bool {
        store.draft.exercises.contains { $0.exerciseID == exerciseID }
    }

    func addExercise(_ exerciseID: UUID) {
        store.addExerciseToWorkout(exerciseID)
    }

    func createExercise(name: String, group: MuscleGroup, equipment: String, targets: [MuscleRegion]) -> Bool {
        store.addExercise(name: name, muscleGroup: group, equipment: equipment, targetMuscles: targets)
    }
}

@MainActor
final class TemplatePickerViewModel: ObservableObject {
    let store: AppStore
    private var storeCancellable: AnyCancellable?

    init(store: AppStore) {
        self.store = store
        storeCancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var templates: [WorkoutTemplate] { store.templates }
    var exercises: [Exercise] { store.exercises }

    func apply(_ template: WorkoutTemplate) {
        store.applyTemplate(template)
    }

    func exerciseNames(for template: WorkoutTemplate) -> String {
        template.exerciseIDs.compactMap { id in
            exercises.first { $0.id == id }?.name
        }.joined(separator: "・")
    }
}

@MainActor
final class TemplateEditViewModel: ObservableObject {
    let store: AppStore
    @Published var name = ""
    @Published var selectedIDs: Set<UUID> = []
    @Published var showError = false
    private var storeCancellable: AnyCancellable?

    init(store: AppStore) {
        self.store = store
        storeCancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var exercises: [Exercise] { store.exercises }

    func toggle(_ exerciseID: UUID) {
        if selectedIDs.contains(exerciseID) { selectedIDs.remove(exerciseID) }
        else { selectedIDs.insert(exerciseID) }
    }

    func save() -> Bool {
        let orderedIDs = exercises.map(\.id).filter { selectedIDs.contains($0) }
        let didSave = store.addTemplate(name: name, exerciseIDs: orderedIDs)
        showError = !didSave
        return didSave
    }
}
