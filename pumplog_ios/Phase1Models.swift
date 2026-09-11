import Foundation
import SwiftData

enum Phase1MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest, back, shoulders, biceps, triceps, legs, abs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chest: "胸"
        case .back: "背中"
        case .shoulders: "肩"
        case .biceps: "上腕二頭筋"
        case .triceps: "上腕三頭筋"
        case .legs: "脚"
        case .abs: "腹筋"
        }
    }

    var symbol: String {
        switch self {
        case .chest: "figure.strengthtraining.traditional"
        case .back: "figure.rower"
        case .shoulders: "figure.arms.open"
        case .biceps, .triceps: "figure.strengthtraining.functional"
        case .legs: "figure.run"
        case .abs: "figure.core.training"
        }
    }
}

enum Phase1RecordType: String, Codable, CaseIterable, Identifiable {
    case weightAndReps, repsOnly
    var id: String { rawValue }
    var title: String { self == .weightAndReps ? "重量＋回数" : "回数のみ" }
}

enum Phase1WorkoutStatus: String, Codable {
    case active, completed
}

enum Phase1Defaults {
    static let defaultWeight = 20.0
    static let defaultReps = 8
    static let minWeight = 0.0
    static let maxWeight = 500.0
    static let minReps = 1
    static let maxReps = 100
    static let defaultRest = 90
}

@Model
final class Phase1Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var muscleGroupRaw: String
    var recordTypeRaw: String
    var weightStep: Double
    var restDuration: Int
    var isArchived: Bool
    var seedKey: String?
    var createdAt: Date
    var updatedAt: Date
    @Relationship(inverse: \Phase1WorkoutExercise.exercise) var workoutExercises: [Phase1WorkoutExercise] = []

    init(
        id: UUID = UUID(),
        name: String,
        muscleGroup: Phase1MuscleGroup,
        recordType: Phase1RecordType = .weightAndReps,
        weightStep: Double = 2.5,
        restDuration: Int = Phase1Defaults.defaultRest,
        isArchived: Bool = false,
        seedKey: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.muscleGroupRaw = muscleGroup.rawValue
        self.recordTypeRaw = recordType.rawValue
        self.weightStep = max(0.1, weightStep)
        self.restDuration = min(max(0, restDuration), 600)
        self.isArchived = isArchived
        self.seedKey = seedKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var muscleGroup: Phase1MuscleGroup { Phase1MuscleGroup(rawValue: muscleGroupRaw) ?? .chest }
    var recordType: Phase1RecordType { Phase1RecordType(rawValue: recordTypeRaw) ?? .weightAndReps }
}

@Model
final class Phase1Workout {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var statusRaw: String
    var restEndAt: Date?
    var restingAfterSetID: UUID?
    var selectedWorkoutExerciseID: UUID?
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Phase1WorkoutExercise.workout) var workoutExercises: [Phase1WorkoutExercise] = []

    init(id: UUID = UUID(), startedAt: Date = .now, status: Phase1WorkoutStatus = .active) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
        self.statusRaw = status.rawValue
        self.restEndAt = nil
        self.restingAfterSetID = nil
        self.selectedWorkoutExerciseID = nil
        self.createdAt = startedAt
        self.updatedAt = startedAt
    }

    var status: Phase1WorkoutStatus {
        get { Phase1WorkoutStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class Phase1WorkoutExercise {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var isCompleted: Bool
    var completedAt: Date?
    var workout: Phase1Workout?
    var exercise: Phase1Exercise?
    @Relationship(deleteRule: .cascade, inverse: \Phase1WorkoutSet.workoutExercise) var sets: [Phase1WorkoutSet] = []

    init(id: UUID = UUID(), orderIndex: Int, workout: Phase1Workout, exercise: Phase1Exercise) {
        self.id = id
        self.orderIndex = orderIndex
        self.isCompleted = false
        self.completedAt = nil
        self.workout = workout
        self.exercise = exercise
    }
}

@Model
final class Phase1WorkoutSet {
    @Attribute(.unique) var id: UUID
    var setNumber: Int
    var weight: Double?
    var reps: Int
    var completedAt: Date?
    var updatedAt: Date
    var workoutExercise: Phase1WorkoutExercise?

    init(
        id: UUID = UUID(),
        setNumber: Int,
        weight: Double?,
        reps: Int,
        completedAt: Date? = .now,
        updatedAt: Date = .now,
        workoutExercise: Phase1WorkoutExercise? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.completedAt = completedAt
        self.updatedAt = updatedAt
        self.workoutExercise = workoutExercise
    }
}
