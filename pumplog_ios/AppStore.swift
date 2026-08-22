import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var exercises: [Exercise] = [] { didSet { saveExercises() } }
    @Published var records: [WorkoutRecord] = [] { didSet { saveRecords() } }
    @Published var draft = WorkoutDraft() { didSet { saveDraft() } }

    private let defaults: UserDefaults
    private var isLoading = true

    private enum Key {
        static let exercisesV2 = "exercises.v2"
        static let records = "records"
        static let draft = "workout.draft"
        static let legacyExercises = "exercises"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        isLoading = false
        saveExercises()
        saveRecords()
    }

    var selectedExercise: Exercise? { exercises.first { $0.id == draft.exerciseID } }

    func addExercise(name: String, muscleGroup: MuscleGroup, equipment: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !containsExercise(named: cleanName) else { return false }
        exercises.append(Exercise(name: cleanName, muscleGroup: muscleGroup, equipment: equipment))
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
        if let selectedID = draft.exerciseID, deletedIDs.contains(selectedID) {
            draft.exerciseID = exercises.first?.id
            draft.sets = []
        }
    }

    func moveExercises(from source: IndexSet, to destination: Int) {
        exercises.move(fromOffsets: source, toOffset: destination)
    }

    func selectExercise(_ id: UUID) {
        guard draft.exerciseID != id else { return }
        draft.exerciseID = id
        draft.sets = latestRecord(for: id)?.sets.map {
            WorkoutSet(weight: $0.weight, reps: $0.reps, kind: $0.kind)
        } ?? []
    }

    func appendSet(weight: Double, reps: Int, kind: SetKind = .working) {
        draft.sets.append(WorkoutSet(weight: weight, reps: reps, kind: kind))
    }

    func duplicateSet(at index: Int) {
        guard draft.sets.indices.contains(index) else { return }
        let set = draft.sets[index]
        draft.sets.insert(WorkoutSet(weight: set.weight, reps: set.reps, kind: set.kind), at: index + 1)
    }

    func duplicateLastSet() {
        guard let set = draft.sets.last else { return }
        draft.sets.append(WorkoutSet(weight: set.weight, reps: set.reps, kind: set.kind))
    }

    func saveDraftAsRecord() -> Bool {
        guard let exercise = selectedExercise,
              !draft.sets.isEmpty,
              draft.sets.allSatisfy({ $0.weight >= 0 && $0.reps > 0 }) else { return false }
        records.append(WorkoutRecord(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            date: draft.date,
            sets: draft.sets,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        let nextSets = draft.sets.map {
            WorkoutSet(weight: $0.weight, reps: $0.reps, kind: $0.kind)
        }
        draft = WorkoutDraft(exerciseID: exercise.id, sets: nextSets)
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

    private func containsExercise(named name: String) -> Bool {
        exercises.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private func load() {
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
        if let data = defaults.data(forKey: Key.records),
           let decoded = try? JSONDecoder().decode([WorkoutRecord].self, from: data) {
            records = decoded.map { record in
                var migrated = record
                if migrated.exerciseID == nil {
                    migrated.exerciseID = exercises.first { $0.name == migrated.exerciseName }?.id
                }
                return migrated
            }
        }
        if let data = defaults.data(forKey: Key.draft),
           let decoded = try? JSONDecoder().decode(WorkoutDraft.self, from: data) {
            draft = decoded
        }
        if draft.exerciseID == nil || !exercises.contains(where: { $0.id == draft.exerciseID }) {
            draft.exerciseID = exercises.first?.id
        }
        if draft.sets.isEmpty,
           let exerciseID = draft.exerciseID,
           let previous = latestRecord(for: exerciseID) {
            draft.sets = previous.sets.map {
                WorkoutSet(weight: $0.weight, reps: $0.reps, kind: $0.kind)
            }
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

    private func saveExercises() {
        guard !isLoading, let data = try? JSONEncoder().encode(exercises) else { return }
        defaults.set(data, forKey: Key.exercisesV2)
    }

    private func saveRecords() {
        guard !isLoading, let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Key.records)
    }

    private func saveDraft() {
        guard !isLoading, let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: Key.draft)
    }
}
