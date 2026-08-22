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
}

struct Exercise: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var muscleGroup: MuscleGroup
    var equipment: String

    init(id: UUID = UUID(), name: String, muscleGroup: MuscleGroup = .fullBody, equipment: String = "") {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
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

    init(id: UUID = UUID(), weight: Double, reps: Int, kind: SetKind = .working) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey { case id, weight, reps, kind }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(SetKind.self, forKey: .kind) ?? .working
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

    init(id: UUID = UUID(), exerciseID: UUID?, exerciseName: String, date: Date = Date(), sets: [WorkoutSet], note: String = "") {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.date = date
        self.sets = sets
        self.note = note
    }

    private enum CodingKeys: String, CodingKey { case id, exerciseID, exerciseName, name, date, sets, note }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        exerciseID = try container.decodeIfPresent(UUID.self, forKey: .exerciseID)
        exerciseName = try container.decodeIfPresent(String.self, forKey: .exerciseName)
            ?? container.decode(String.self, forKey: .name)
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        sets = try container.decode([WorkoutSet].self, forKey: .sets)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(exerciseID, forKey: .exerciseID)
        try container.encode(exerciseName, forKey: .exerciseName)
        try container.encode(date, forKey: .date)
        try container.encode(sets, forKey: .sets)
        try container.encode(note, forKey: .note)
    }
}

struct WorkoutDraft: Codable, Equatable {
    var exerciseID: UUID?
    var date = Date()
    var sets: [WorkoutSet] = []
    var note = ""
}
