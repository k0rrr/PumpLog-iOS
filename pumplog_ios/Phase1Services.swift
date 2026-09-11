import Foundation
import SwiftData

enum Phase1SeedService {
    struct Seed {
        let key: String
        let name: String
        let group: Phase1MuscleGroup
        let type: Phase1RecordType
        let step: Double
        let rest: Int
    }

    static let seeds: [Seed] = [
        .init(key: "bench_press", name: "ベンチプレス", group: .chest, type: .weightAndReps, step: 2.5, rest: 120),
        .init(key: "incline_dumbbell_press", name: "インクラインダンベルプレス", group: .chest, type: .weightAndReps, step: 1, rest: 90),
        .init(key: "cable_fly", name: "ケーブルフライ", group: .chest, type: .weightAndReps, step: 2.5, rest: 60),
        .init(key: "lat_pulldown", name: "ラットプルダウン", group: .back, type: .weightAndReps, step: 2.5, rest: 90),
        .init(key: "seated_row", name: "シーテッドロー", group: .back, type: .weightAndReps, step: 2.5, rest: 90),
        .init(key: "shoulder_press", name: "ショルダープレス", group: .shoulders, type: .weightAndReps, step: 2.5, rest: 90),
        .init(key: "side_raise", name: "サイドレイズ", group: .shoulders, type: .weightAndReps, step: 1, rest: 60),
        .init(key: "dumbbell_curl", name: "ダンベルカール", group: .biceps, type: .weightAndReps, step: 1, rest: 60),
        .init(key: "push_down", name: "プッシュダウン", group: .triceps, type: .weightAndReps, step: 2.5, rest: 60),
        .init(key: "squat", name: "スクワット", group: .legs, type: .weightAndReps, step: 2.5, rest: 150),
        .init(key: "leg_press", name: "レッグプレス", group: .legs, type: .weightAndReps, step: 5, rest: 120),
        .init(key: "crunch", name: "クランチ", group: .abs, type: .repsOnly, step: 1, rest: 60)
    ]

    @MainActor
    static func seedIfNeeded(in context: ModelContext) throws {
        var existing = try context.fetch(FetchDescriptor<Phase1Exercise>())
        // Keep historical relationships intact: duplicate exercises are archived,
        // never physically deleted. Prefer the record with the most history.
        var winners: [String: Phase1Exercise] = [:]
        for exercise in existing {
            let key = canonicalKey(name: exercise.name, group: exercise.muscleGroupRaw, type: exercise.recordTypeRaw)
            if let current = winners[key] {
                let currentScore = current.workoutExercises.count + (current.isArchived ? 0 : 1)
                let candidateScore = exercise.workoutExercises.count + (exercise.isArchived ? 0 : 1)
                if candidateScore > currentScore {
                    current.isArchived = true
                    winners[key] = exercise
                } else {
                    exercise.isArchived = true
                }
            } else {
                winners[key] = exercise
            }
        }
        existing = Array(winners.values)
        let existingKeys = Set(existing.compactMap(\.seedKey))
        let existingCanonicalKeys = Set(existing.map { canonicalKey(name: $0.name, group: $0.muscleGroupRaw, type: $0.recordTypeRaw) })
        for seed in seeds where !existingKeys.contains(seed.key) {
            let canonical = canonicalKey(name: seed.name, group: seed.group.rawValue, type: seed.type.rawValue)
            guard !existingCanonicalKeys.contains(canonical) else { continue }
            context.insert(Phase1Exercise(
                name: seed.name,
                muscleGroup: seed.group,
                recordType: seed.type,
                weightStep: seed.step,
                restDuration: seed.rest,
                seedKey: seed.key
            ))
        }
        try context.save()
    }

    private static func canonicalKey(name: String, group: String, type: String) -> String {
        "\(name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased())|\(group)|\(type)"
    }
}

struct Phase1PreviousValue {
    let weight: Double?
    let reps: Int
    let display: String
    let isAvailable: Bool
}

@MainActor
enum Phase1PreviousRecordService {
    static func value(for exercise: Phase1Exercise, setNumber: Int, before date: Date, in context: ModelContext) -> Phase1PreviousValue {
        let workouts = (try? context.fetch(FetchDescriptor<Phase1Workout>())) ?? []
        let candidates = workouts
            .filter { $0.status == .completed && $0.startedAt < date }
            .sorted { $0.startedAt > $1.startedAt }
        for workout in candidates {
            guard let entry = workout.workoutExercises.first(where: { $0.exercise?.id == exercise.id }) else { continue }
            let sets = entry.sets.filter { $0.completedAt != nil }.sorted { $0.setNumber < $1.setNumber }
            guard !sets.isEmpty else { continue }
            if let same = sets.first(where: { $0.setNumber == setNumber }) {
                return makeValue(same, exercise: exercise, label: "前回SET \(setNumber)")
            }
            let last = sets.last!
            return makeValue(last, exercise: exercise, label: "前回SET \(setNumber)なし")
        }
        return Phase1PreviousValue(
            weight: exercise.recordType == .weightAndReps ? Phase1Defaults.defaultWeight : nil,
            reps: Phase1Defaults.defaultReps,
            display: "前回記録はありません",
            isAvailable: false
        )
    }

    private static func makeValue(_ set: Phase1WorkoutSet, exercise: Phase1Exercise, label: String) -> Phase1PreviousValue {
        let weightText = exercise.recordType == .weightAndReps ? "\(format(set.weight ?? 0))kg × " : ""
        return Phase1PreviousValue(weight: exercise.recordType == .weightAndReps ? set.weight : nil, reps: set.reps, display: "\(label)：\(weightText)\(set.reps)回", isAvailable: true)
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct Phase1PRResult {
    let weightPR: Bool
    let repsPR: Bool

    var count: Int { (weightPR ? 1 : 0) + (repsPR ? 1 : 0) }
}

@MainActor
enum Phase1PRService {
    static func result(for set: Phase1WorkoutSet, exercise: Phase1Exercise, workout: Phase1Workout, in context: ModelContext) -> Phase1PRResult {
        let workouts = (try? context.fetch(FetchDescriptor<Phase1Workout>())) ?? []
        let history = workouts
            .filter { $0.status == .completed && $0.id != workout.id && $0.startedAt < workout.startedAt }
            .flatMap { $0.workoutExercises }
            .filter { $0.exercise?.id == exercise.id }
            .flatMap(\.sets)
            .filter { $0.completedAt != nil }
        guard !history.isEmpty else { return Phase1PRResult(weightPR: false, repsPR: false) }
        let normalized = { (value: Double) in (value * 10).rounded() / 10 }
        let weightPR: Bool
        let repsPR: Bool
        if exercise.recordType == .repsOnly {
            weightPR = false
            repsPR = set.reps > (history.map(\.reps).max() ?? 0)
        } else {
            let currentWeight = normalized(set.weight ?? 0)
            weightPR = currentWeight > (history.compactMap(\.weight).map(normalized).max() ?? -Double.infinity)
            let sameWeight = history.filter { normalized($0.weight ?? 0) == currentWeight }
            repsPR = !sameWeight.isEmpty && set.reps > (sameWeight.map(\.reps).max() ?? 0)
        }
        return Phase1PRResult(weightPR: weightPR, repsPR: repsPR)
    }
}

@MainActor
enum Phase1WorkoutRecoveryService {
    static func activeWorkout(in context: ModelContext) throws -> Phase1Workout? {
        let workouts = try context.fetch(FetchDescriptor<Phase1Workout>())
        return workouts.filter { $0.status == .active }.sorted { $0.startedAt > $1.startedAt }.first
    }

    static func remainingRest(for workout: Phase1Workout, now: Date = .now) -> TimeInterval? {
        guard let restEndAt = workout.restEndAt else { return nil }
        return min(600, max(0, restEndAt.timeIntervalSince(now)))
    }
}
