import Foundation

struct MuscleLoadSnapshot {
    let date: Date
    let loads: [MuscleRegion: Double]
    let totalVolume: Double
    let workoutCount: Int

    var activeRegions: [MuscleRegion] {
        MuscleRegion.allCases.filter { load(for: $0) > 0 }
    }

    func load(for region: MuscleRegion) -> Double {
        loads[region, default: 0]
    }

    func intensity(for region: MuscleRegion) -> Double {
        guard load(for: region) > 0 else { return 0 }
        return min(1, sqrt(load(for: region) / 3_000))
    }
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
        var loads: [MuscleRegion: Double] = [:]

        for record in dailyRecords {
            let exercise = record.exerciseID.flatMap { exercisesByID[$0] }
                ?? exercises.first(where: { $0.name == record.exerciseName })
            let targetRegions = exercise?.targetMuscles ?? MuscleRegion.allCases
            let load = trainingLoad(for: record)
            for target in targetRegions {
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
