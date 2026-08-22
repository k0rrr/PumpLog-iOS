import Foundation

struct ExerciseProgressPoint: Identifiable {
    let id: UUID
    let date: Date
    let maxWeight: Double
    let totalVolume: Double
    let estimatedOneRepMax: Double
}

struct PersonalBestSummary {
    let maxWeight: Double
    let maxReps: Int
    let estimatedOneRepMax: Double
    let totalVolume: Double
    let workoutCount: Int

    var averageVolume: Double {
        workoutCount == 0 ? 0 : totalVolume / Double(workoutCount)
    }

    static let empty = PersonalBestSummary(
        maxWeight: 0,
        maxReps: 0,
        estimatedOneRepMax: 0,
        totalVolume: 0,
        workoutCount: 0
    )
}

extension WorkoutRecord {
    var analyticsSets: [WorkoutSet] {
        let workingSets = sets.filter { $0.kind == .working }
        return workingSets.isEmpty ? sets : workingSets
    }

    var totalVolume: Double {
        analyticsSets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }

    var maxWeight: Double {
        analyticsSets.map(\.weight).max() ?? 0
    }

    var maxReps: Int {
        analyticsSets.map(\.reps).max() ?? 0
    }

    var estimatedOneRepMax: Double {
        analyticsSets.map { set in
            set.weight * (1 + Double(set.reps) / 30)
        }.max() ?? 0
    }

    var progressPoint: ExerciseProgressPoint {
        ExerciseProgressPoint(
            id: id,
            date: date,
            maxWeight: maxWeight,
            totalVolume: totalVolume,
            estimatedOneRepMax: estimatedOneRepMax
        )
    }
}

enum WorkoutAnalytics {
    static func records(for exerciseID: UUID, in records: [WorkoutRecord]) -> [WorkoutRecord] {
        records.filter { $0.exerciseID == exerciseID }.sorted { $0.date < $1.date }
    }

    static func summary(for exerciseID: UUID, in records: [WorkoutRecord]) -> PersonalBestSummary {
        let matching = WorkoutAnalytics.records(for: exerciseID, in: records)
        guard !matching.isEmpty else { return .empty }
        return PersonalBestSummary(
            maxWeight: matching.map(\.maxWeight).max() ?? 0,
            maxReps: matching.map(\.maxReps).max() ?? 0,
            estimatedOneRepMax: matching.map(\.estimatedOneRepMax).max() ?? 0,
            totalVolume: matching.reduce(0) { $0 + $1.totalVolume },
            workoutCount: matching.count
        )
    }

    static func personalBestMessages(
        for newRecords: [WorkoutRecord],
        comparedWith existingRecords: [WorkoutRecord]
    ) -> [String] {
        newRecords.flatMap { record -> [String] in
            guard let exerciseID = record.exerciseID else { return [] }
            let previous = summary(for: exerciseID, in: existingRecords)
            guard previous.workoutCount > 0 else {
                return ["\(record.exerciseName)：最初の記録を保存しました"]
            }

            var achievements: [String] = []
            if record.maxWeight > previous.maxWeight {
                achievements.append("\(record.exerciseName)：最大重量 \(record.maxWeight.formatted()) kg")
            }
            if record.estimatedOneRepMax > previous.estimatedOneRepMax {
                achievements.append("\(record.exerciseName)：推定1RM \(record.estimatedOneRepMax.formatted(.number.precision(.fractionLength(1)))) kg")
            }
            if record.maxReps > previous.maxReps {
                achievements.append("\(record.exerciseName)：最大回数 \(record.maxReps) 回")
            }
            return achievements
        }
    }
}
