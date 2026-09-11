import Foundation
import SwiftData

@MainActor
enum Phase1DataMigrationService {
    private static let completedKey = "pumplog.phase1.migration.v1"

    static func migrateLegacyDataIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) throws {
        guard !defaults.bool(forKey: completedKey) else { return }
        let current = try context.fetch(FetchDescriptor<Phase1Exercise>())
        var exercisesByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        if current.isEmpty, let data = defaults.data(forKey: "exercises.v2"), let legacyExercises = try? JSONDecoder().decode([Exercise].self, from: data) {
            for legacy in legacyExercises {
                let mapped = Phase1Exercise(id: legacy.id, name: legacy.name, muscleGroup: mapGroup(legacy.muscleGroup))
                context.insert(mapped); exercisesByID[mapped.id] = mapped
            }
        }

        if let data = defaults.data(forKey: "records"), let records = try? JSONDecoder().decode([WorkoutRecord].self, from: data) {
            let grouped = Dictionary(grouping: records) { $0.sessionID ?? $0.id }
            for group in grouped.values {
                guard let first = group.min(by: { $0.date < $1.date }) else { continue }
                let workout = Phase1Workout(startedAt: first.date, status: .completed)
                workout.endedAt = first.date
                context.insert(workout)
                for (index, record) in group.sorted(by: { $0.date < $1.date }).enumerated() {
                    guard let legacyID = record.exerciseID,
                          let exercise = exercisesByID[legacyID] ?? exercisesByID.values.first(where: { $0.name == record.exerciseName }) else { continue }
                    let entry = Phase1WorkoutExercise(orderIndex: index, workout: workout, exercise: exercise)
                    context.insert(entry); workout.workoutExercises.append(entry)
                    for (setIndex, legacySet) in record.sets.enumerated() where legacySet.reps > 0 {
                        let set = Phase1WorkoutSet(setNumber: setIndex + 1, weight: exercise.recordType == .weightAndReps ? legacySet.weight : nil, reps: min(100, max(1, legacySet.reps)), completedAt: record.date, workoutExercise: entry)
                        context.insert(set); entry.sets.append(set)
                    }
                }
            }
        }
        try context.save()
        defaults.set(true, forKey: completedKey)
    }

    private static func mapGroup(_ group: MuscleGroup) -> Phase1MuscleGroup {
        switch group {
        case .chest: .chest
        case .back: .back
        case .shoulders: .shoulders
        case .arms: .biceps
        case .legs: .legs
        case .core: .abs
        case .fullBody: .chest
        }
    }
}
