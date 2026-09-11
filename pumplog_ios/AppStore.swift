import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var exercises: [Exercise] = [] { didSet { saveExercises() } }
    @Published var records: [WorkoutRecord] = [] { didSet { saveRecords() } }
    @Published var draft = WorkoutDraft() { didSet { saveDraft() } }
    @Published var templates: [WorkoutTemplate] = [] { didSet { saveTemplates() } }
    @Published var personalBestMessage: String?

    private let defaults: UserDefaults
    private var isLoading = true

    private enum Key {
        static let exercisesV2 = "exercises.v2"
        static let records = "records"
        static let draft = "workout.draft"
        static let templates = "workout.templates"
        static let legacyExercises = "exercises"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        isLoading = false
        saveExercises()
        saveRecords()
        saveDraft()
    }

    var selectedEntryIndex: Int? {
        draft.exercises.firstIndex { $0.id == draft.selectedEntryID }
    }

    var selectedEntry: SessionExerciseDraft? {
        guard let index = selectedEntryIndex else { return nil }
        return draft.exercises[index]
    }

    var selectedExercise: Exercise? {
        guard let exerciseID = selectedEntry?.exerciseID else { return nil }
        return exercises.first { $0.id == exerciseID }
    }

    var hasPreviousWorkout: Bool { !records.isEmpty }

    func exercise(for entry: SessionExerciseDraft) -> Exercise? {
        exercises.first { $0.id == entry.exerciseID }
    }

    func addExercise(
        name: String,
        muscleGroup: MuscleGroup,
        equipment: String,
        targetMuscles: [MuscleRegion]
    ) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !containsExercise(named: cleanName) else { return false }
        exercises.append(Exercise(
            name: cleanName,
            muscleGroup: muscleGroup,
            equipment: equipment,
            targetMuscles: targetMuscles
        ))
        return true
    }

    func updateExercise(_ exercise: Exercise) -> Bool {
        let cleanName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return false }
        guard !exercises.contains(where: {
            $0.id != exercise.id && $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame
        }) else { return false }
        guard let index = exercises.firstIndex(where: { $0.id == exercise.id }) else { return false }
        var updated = exercise
        updated.name = cleanName
        exercises[index] = updated
        return true
    }

    func deleteExercises(at offsets: IndexSet) {
        let deletedIDs = offsets.map { exercises[$0].id }
        exercises.remove(atOffsets: offsets)
        draft.exercises.removeAll { deletedIDs.contains($0.exerciseID) }
        normalizeSelection()
        templates = templates.map { template in
            var updated = template
            updated.exerciseIDs.removeAll { deletedIDs.contains($0) }
            return updated
        }
    }

    func moveExercises(from source: IndexSet, to destination: Int) {
        exercises.move(fromOffsets: source, toOffset: destination)
    }

    @discardableResult
    func addExerciseToWorkout(_ exerciseID: UUID) -> Bool {
        guard exercises.contains(where: { $0.id == exerciseID }) else { return false }
        if let existing = draft.exercises.first(where: { $0.exerciseID == exerciseID }) {
            draft.selectedEntryID = existing.id
            return false
        }
        let previousSets = latestRecord(for: exerciseID)?.sets.map {
            WorkoutSet(weight: $0.weight, reps: $0.reps, kind: $0.kind)
        } ?? []
        let entry = SessionExerciseDraft(exerciseID: exerciseID, sets: previousSets)
        draft.exercises.append(entry)
        draft.selectedEntryID = entry.id
        return true
    }

    func selectWorkoutEntry(_ entryID: UUID) {
        guard draft.exercises.contains(where: { $0.id == entryID }) else { return }
        draft.selectedEntryID = entryID
    }

    func removeSelectedExercise() {
        guard let entryID = draft.selectedEntryID else { return }
        draft.exercises.removeAll { $0.id == entryID }
        normalizeSelection()
    }

    func appendSet(weight: Double, reps: Int, kind: SetKind = .working) {
        guard let index = selectedEntryIndex else { return }
        draft.exercises[index].sets.append(WorkoutSet(weight: weight, reps: reps, kind: kind))
    }

    func duplicateSet(at index: Int) {
        guard let entryIndex = selectedEntryIndex,
              draft.exercises[entryIndex].sets.indices.contains(index) else { return }
        let set = draft.exercises[entryIndex].sets[index]
        draft.exercises[entryIndex].sets.insert(
            WorkoutSet(weight: set.weight, reps: set.reps, kind: set.kind), at: index + 1
        )
    }

    func duplicateLastSet() {
        guard let entryIndex = selectedEntryIndex,
              let set = draft.exercises[entryIndex].sets.last else { return }
        draft.exercises[entryIndex].sets.append(
            WorkoutSet(weight: set.weight, reps: set.reps, kind: set.kind)
        )
    }

    func setCompletion(at index: Int, isCompleted: Bool) {
        guard let entryIndex = selectedEntryIndex,
              draft.exercises[entryIndex].sets.indices.contains(index) else { return }
        draft.exercises[entryIndex].sets[index].isCompleted = isCompleted
        if isCompleted { startRestTimer(seconds: draft.restDuration) }
    }

    func startRestTimer(seconds: Int) {
        draft.restDuration = seconds
        draft.restEndsAt = Date().addingTimeInterval(TimeInterval(seconds))
    }

    func addRestTime(_ seconds: Int) {
        let base = max(draft.restEndsAt ?? Date(), Date())
        draft.restEndsAt = base.addingTimeInterval(TimeInterval(seconds))
    }

    func stopRestTimer() { draft.restEndsAt = nil }

    func finishWorkout() -> Bool {
        guard !draft.exercises.isEmpty,
              draft.exercises.allSatisfy({
                  !$0.sets.isEmpty && $0.sets.allSatisfy { $0.weight >= 0 && $0.reps > 0 }
              }) else { return false }
        let sessionID = draft.id
        let newRecords = draft.exercises.compactMap { entry -> WorkoutRecord? in
            guard let exercise = exercises.first(where: { $0.id == entry.exerciseID }) else { return nil }
            return WorkoutRecord(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                date: draft.date,
                sets: entry.sets,
                note: entry.note.trimmingCharacters(in: .whitespacesAndNewlines),
                sessionID: sessionID
            )
        }
        guard newRecords.count == draft.exercises.count else { return false }
        let achievements = WorkoutAnalytics.personalBestMessages(
            for: newRecords,
            comparedWith: records
        )
        records.append(contentsOf: newRecords)
        personalBestMessage = achievements.isEmpty ? nil : achievements.joined(separator: "\n")
        draft = WorkoutDraft()
        return true
    }

    func updateRecord(_ record: WorkoutRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
    }

    func deleteRecord(_ record: WorkoutRecord) { records.removeAll { $0.id == record.id } }

    func latestRecord(for exerciseID: UUID) -> WorkoutRecord? {
        records.filter { $0.exerciseID == exerciseID }.max { $0.date < $1.date }
    }

    func addTemplate(name: String, exerciseIDs: [UUID]) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !exerciseIDs.isEmpty,
              !templates.contains(where: { $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame })
        else { return false }
        templates.append(WorkoutTemplate(name: cleanName, exerciseIDs: exerciseIDs))
        return true
    }

    func deleteTemplates(at offsets: IndexSet) { templates.remove(atOffsets: offsets) }

    func applyTemplate(_ template: WorkoutTemplate) {
        draft = WorkoutDraft()
        for exerciseID in template.exerciseIDs { addExerciseToWorkout(exerciseID) }
        draft.selectedEntryID = draft.exercises.first?.id
        draft.date = Date()
    }

    func repeatPreviousWorkout() {
        guard let latest = records.max(by: { $0.date < $1.date }) else { return }
        let previousRecords: [WorkoutRecord]
        if let sessionID = latest.sessionID {
            previousRecords = records
                .filter { $0.sessionID == sessionID }
                .sorted { $0.date < $1.date }
        } else {
            previousRecords = [latest]
        }

        draft = WorkoutDraft()
        for record in previousRecords {
            guard let exerciseID = record.exerciseID,
                  exercises.contains(where: { $0.id == exerciseID }) else { continue }
            let sets = record.sets.map {
                WorkoutSet(weight: $0.weight, reps: $0.reps, kind: $0.kind)
            }
            let entry = SessionExerciseDraft(exerciseID: exerciseID, sets: sets, note: record.note)
            draft.exercises.append(entry)
            if draft.selectedEntryID == nil { draft.selectedEntryID = entry.id }
        }
        draft.date = Date()
    }

    private func normalizeSelection() {
        if !draft.exercises.contains(where: { $0.id == draft.selectedEntryID }) {
            draft.selectedEntryID = draft.exercises.first?.id
        }
    }

    private func containsExercise(named name: String) -> Bool {
        exercises.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private func load() {
        loadExercises()
        loadRecords()
        loadDraft()
        if let data = defaults.data(forKey: Key.templates),
           let decoded = try? JSONDecoder().decode([WorkoutTemplate].self, from: data) {
            templates = decoded
        }
        draft.exercises.removeAll { entry in
            !exercises.contains { $0.id == entry.exerciseID }
        }
        normalizeSelection()
    }

    private func loadExercises() {
        if let data = defaults.data(forKey: Key.exercisesV2),
           let decoded = try? JSONDecoder().decode([Exercise].self, from: data) {
            exercises = decoded
        } else {
            let names = defaults.stringArray(forKey: Key.legacyExercises)
                ?? ["ベンチプレス", "スクワット", "デッドリフト"]
            exercises = names.reduce(into: []) { result, name in
                guard !result.contains(where: { $0.name == name }) else { return }
                result.append(Exercise(name: name, muscleGroup: defaultGroup(for: name)))
            }
        }
    }

    private func loadRecords() {
        guard let data = defaults.data(forKey: Key.records),
              let decoded = try? JSONDecoder().decode([WorkoutRecord].self, from: data) else { return }
        records = decoded.map { record in
            var migrated = record
            if migrated.exerciseID == nil {
                migrated.exerciseID = exercises.first { $0.name == migrated.exerciseName }?.id
            }
            return migrated
        }
    }

    private func loadDraft() {
        guard let data = defaults.data(forKey: Key.draft) else { return }
        if let decoded = try? JSONDecoder().decode(WorkoutDraft.self, from: data) {
            draft = decoded
        } else if let legacy = try? JSONDecoder().decode(LegacyWorkoutDraft.self, from: data),
                  let exerciseID = legacy.exerciseID {
            let entry = SessionExerciseDraft(exerciseID: exerciseID, sets: legacy.sets, note: legacy.note)
            draft = WorkoutDraft(date: legacy.date, exercises: [entry], selectedEntryID: entry.id)
        }
    }

    private func defaultGroup(for name: String) -> MuscleGroup {
        switch name {
        case "ベンチプレス": .chest
        case "スクワット": .legs
        case "デッドリフト": .back
        default: .fullBody
        }
    }

    private func saveExercises() { save(exercises, key: Key.exercisesV2) }
    private func saveRecords() { save(records, key: Key.records) }
    private func saveDraft() { save(draft, key: Key.draft) }
    private func saveTemplates() { save(templates, key: Key.templates) }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard !isLoading, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
