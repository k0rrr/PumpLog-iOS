import Foundation

struct MuscleLoadSnapshot {
    let date: Date
    let loads: [MuscleGroup: Double]
    let totalVolume: Double
    let workoutCount: Int

    var activeGroups: [MuscleGroup] {
        MuscleGroup.mapGroups.filter { load(for: $0) > 0 }
    }

    func load(for group: MuscleGroup) -> Double {
        loads[group, default: 0]
    }

    func intensity(for group: MuscleGroup) -> Double {
        guard load(for: group) > 0 else { return 0 }
        return min(1, sqrt(load(for: group) / 3_000))
    }
}

extension MuscleGroup {
    static let mapGroups: [MuscleGroup] = [.chest, .back, .shoulders, .arms, .legs, .core]
}

enum MuscleLoadAnalytics {
    static func snapshot(
        on date: Date,
        records: [WorkoutRecord],
        exercises: [Exercise],
        calendar: Calendar = .current
    ) -> MuscleLoadSnapshot {
        let dailyRecords = records.filter { calendar.isDate($0.date, inSameDayAs: date) }
        let exercisesByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        var loads: [MuscleGroup: Double] = [:]

        for record in dailyRecords {
            let group = record.exerciseID.flatMap { exercisesByID[$0]?.muscleGroup }
                ?? exercises.first(where: { $0.name == record.exerciseName })?.muscleGroup
                ?? .fullBody
            let load = trainingLoad(for: record)
            let targetGroups = group == .fullBody ? MuscleGroup.mapGroups : [group]
            for target in targetGroups {
                loads[target, default: 0] += load
            }
        }

        return MuscleLoadSnapshot(
            date: date,
            loads: loads,
            totalVolume: dailyRecords.reduce(0) { $0 + $1.totalVolume },
            workoutCount: dailyRecords.count
        )
    }

    private static func trainingLoad(for record: WorkoutRecord) -> Double {
        record.analyticsSets.reduce(0) { result, set in
            // 自重種目もマップに反映できるよう、重量0kgには小さな基準負荷を持たせる。
            result + max(set.weight, 10) * Double(set.reps)
        }
    }
}
