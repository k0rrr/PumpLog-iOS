import Foundation

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest = "胸"
    case back = "背中"
    case shoulders = "肩"
    case arms = "腕"
    case legs = "脚"
    case core = "腹"
    case fullBody = "全身"

    var id: String { rawValue }

    var defaultRegions: [MuscleRegion] {
        switch self {
        case .chest: [.upperChest, .lowerChest]
        case .back: [.trapezius, .lats, .lowerBack]
        case .shoulders: [.frontDeltoids, .sideDeltoids, .rearDeltoids]
        case .arms: [.biceps, .triceps, .forearms]
        case .legs: [.quadriceps, .hamstrings, .glutes, .calves]
        case .core: [.abs, .obliques]
        case .fullBody: MuscleRegion.allCases
        }
    }
}

enum MuscleRegion: String, Codable, CaseIterable, Identifiable, Hashable {
    case upperChest = "胸上部"
    case lowerChest = "胸下部"
    case trapezius = "僧帽筋"
    case lats = "広背筋"
    case lowerBack = "脊柱起立筋"
    case frontDeltoids = "肩前部"
    case sideDeltoids = "肩側部"
    case rearDeltoids = "肩後部"
    case biceps = "上腕二頭筋"
    case triceps = "上腕三頭筋"
    case forearms = "前腕"
    case abs = "腹直筋"
    case obliques = "腹斜筋"
    case quadriceps = "大腿四頭筋"
    case hamstrings = "ハムストリング"
    case glutes = "臀筋"
    case calves = "ふくらはぎ"

    var id: String { rawValue }

    var muscleGroup: MuscleGroup {
        switch self {
        case .upperChest, .lowerChest: .chest
        case .trapezius, .lats, .lowerBack: .back
        case .frontDeltoids, .sideDeltoids, .rearDeltoids: .shoulders
        case .biceps, .triceps, .forearms: .arms
        case .quadriceps, .hamstrings, .glutes, .calves: .legs
        case .abs, .obliques: .core
        }
    }
}

struct Exercise: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var muscleGroup: MuscleGroup
    var equipment: String
    var targetMuscles: [MuscleRegion]

    init(
        id: UUID = UUID(),
        name: String,
        muscleGroup: MuscleGroup = .fullBody,
        equipment: String = "",
        targetMuscles: [MuscleRegion]? = nil
    ) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.targetMuscles = Self.normalizedTargets(
            targetMuscles ?? Self.suggestedTargets(for: name, group: muscleGroup),
            fallback: muscleGroup.defaultRegions
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, muscleGroup, equipment, targetMuscles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        muscleGroup = try container.decodeIfPresent(MuscleGroup.self, forKey: .muscleGroup) ?? .fullBody
        equipment = try container.decodeIfPresent(String.self, forKey: .equipment) ?? ""
        let storedTargets = try container.decodeIfPresent([MuscleRegion].self, forKey: .targetMuscles)
        targetMuscles = Self.normalizedTargets(
            storedTargets ?? Self.suggestedTargets(for: name, group: muscleGroup),
            fallback: muscleGroup.defaultRegions
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(muscleGroup, forKey: .muscleGroup)
        try container.encode(equipment, forKey: .equipment)
        try container.encode(targetMuscles, forKey: .targetMuscles)
    }

    private static func normalizedTargets(
        _ targets: [MuscleRegion],
        fallback: [MuscleRegion]
    ) -> [MuscleRegion] {
        let source = targets.isEmpty ? fallback : targets
        return MuscleRegion.allCases.filter { source.contains($0) }
    }

    private static func suggestedTargets(for name: String, group: MuscleGroup) -> [MuscleRegion] {
        switch name {
        case "ベンチプレス": [.upperChest, .lowerChest, .frontDeltoids, .triceps]
        case "スクワット": [.quadriceps, .hamstrings, .glutes, .abs]
        case "デッドリフト": [.trapezius, .lats, .lowerBack, .forearms, .hamstrings, .glutes]
        default: group.defaultRegions
        }
    }
}

enum SetKind: String, Codable, CaseIterable, Identifiable {
    case warmup = "ウォームアップ"
    case working = "通常"

    var id: String { rawValue }
}

struct WorkoutSet: Identifiable, Codable, Equatable {
    let id: UUID
    var weight: Double
    var reps: Int
    var kind: SetKind
    var isCompleted: Bool

    init(id: UUID = UUID(), weight: Double, reps: Int, kind: SetKind = .working, isCompleted: Bool = false) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.kind = kind
        self.isCompleted = isCompleted
    }

    private enum CodingKeys: String, CodingKey { case id, weight, reps, kind, isCompleted }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(SetKind.self, forKey: .kind) ?? .working
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        if let value = try? container.decode(Double.self, forKey: .weight) {
            weight = value
        } else {
            weight = Double(try container.decode(String.self, forKey: .weight)) ?? 0
        }
        if let value = try? container.decode(Int.self, forKey: .reps) {
            reps = value
        } else {
            reps = Int(try container.decode(String.self, forKey: .reps)) ?? 0
        }
    }
}

struct WorkoutRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var exerciseID: UUID?
    var exerciseName: String
    var date: Date
    var sets: [WorkoutSet]
    var note: String
    var sessionID: UUID?

    init(id: UUID = UUID(), exerciseID: UUID?, exerciseName: String, date: Date = Date(), sets: [WorkoutSet], note: String = "", sessionID: UUID? = nil) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.date = date
        self.sets = sets
        self.note = note
        self.sessionID = sessionID
    }

    private enum CodingKeys: String, CodingKey { case id, exerciseID, exerciseName, name, date, sets, note, sessionID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        exerciseID = try container.decodeIfPresent(UUID.self, forKey: .exerciseID)
        exerciseName = try container.decodeIfPresent(String.self, forKey: .exerciseName)
            ?? container.decode(String.self, forKey: .name)
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        sets = try container.decode([WorkoutSet].self, forKey: .sets)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(exerciseID, forKey: .exerciseID)
        try container.encode(exerciseName, forKey: .exerciseName)
        try container.encode(date, forKey: .date)
        try container.encode(sets, forKey: .sets)
        try container.encode(note, forKey: .note)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
    }
}

struct SessionExerciseDraft: Identifiable, Codable, Equatable {
    let id: UUID
    var exerciseID: UUID
    var sets: [WorkoutSet] = []
    var note = ""

    init(id: UUID = UUID(), exerciseID: UUID, sets: [WorkoutSet] = [], note: String = "") {
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
        self.note = note
    }
}

struct WorkoutDraft: Codable, Equatable {
    var id = UUID()
    var date = Date()
    var exercises: [SessionExerciseDraft] = []
    var selectedEntryID: UUID?
    var restEndsAt: Date?
    var restDuration = 90
}

struct LegacyWorkoutDraft: Codable {
    var exerciseID: UUID?
    var date: Date
    var sets: [WorkoutSet]
    var note: String
}

struct WorkoutTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var exerciseIDs: [UUID]

    init(id: UUID = UUID(), name: String, exerciseIDs: [UUID]) {
        self.id = id
        self.name = name
        self.exerciseIDs = exerciseIDs
    }
}
