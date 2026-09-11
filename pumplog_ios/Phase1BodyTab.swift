import SwiftData
import SwiftUI

private enum Phase1BodyPeriod: String, CaseIterable, Identifiable {
    case today, week, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今日"
        case .week: "今週"
        case .month: "今月"
        }
    }
}

struct Phase1BodyTab: View {
    @Query(filter: #Predicate<Phase1Workout> { $0.statusRaw == "completed" }, sort: \Phase1Workout.startedAt, order: .reverse) private var workouts: [Phase1Workout]
    @State private var selectedPeriod: Phase1BodyPeriod = .today

    private var periodCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2 // 月曜日始まり
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    private var periodInterval: DateInterval? {
        periodCalendar.dateInterval(of: calendarComponent, for: Date())
    }

    private var calendarComponent: Calendar.Component {
        switch selectedPeriod {
        case .today: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    private var groupSetCounts: [Phase1MuscleGroup: Int] {
        guard let periodInterval else { return [:] }
        var counts: [Phase1MuscleGroup: Int] = [:]
        for workout in workouts {
            for entry in workout.workoutExercises {
                guard let group = entry.exercise?.muscleGroup else { continue }
                let completedSets = entry.sets.reduce(into: 0) { result, set in
                    guard let completedAt = set.completedAt, periodInterval.contains(completedAt) else { return }
                    result += 1
                }
                if completedSets > 0 { counts[group, default: 0] += completedSets }
            }
        }
        return counts
    }

    private var activeGroups: Set<Phase1MuscleGroup> { Set(groupSetCounts.keys) }

    private var periodDescription: String {
        switch selectedPeriod {
        case .today: "今日のトレーニング負荷"
        case .week: "今週のトレーニング負荷"
        case .month: "今月のトレーニング負荷"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Phase1DesignTokens.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Phase1TabHeader(title: "Body Status")
                            Text(activeGroups.isEmpty ? "トレーニングを記録すると、負荷部位が表示されます" : periodDescription)
                                .font(.subheadline)
                                .foregroundStyle(Phase1DesignTokens.secondary)
                        }
                        Picker("表示期間", selection: $selectedPeriod) {
                            ForEach(Phase1BodyPeriod.allCases) { period in
                                Text(period.title).tag(period)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("負荷を表示する期間")

                        Phase1Body3DView(activeGroups: activeGroups)
                            .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("負荷の表示")
                                .font(.headline)
                            HStack(spacing: 8) {
                                Circle().fill(Color(red: 1, green: 0.25, blue: 0.12)).frame(width: 12, height: 12)
                                Text(activeGroups.isEmpty ? "記録なし" : periodDescription)
                                    .font(.subheadline)
                                    .foregroundStyle(Phase1DesignTokens.secondary)
                            }
                            if groupSetCounts.isEmpty {
                                Text("この期間の記録はありません")
                                    .font(.subheadline.weight(.medium))
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(groupSetCounts.keys.sorted { $0.title < $1.title }, id: \.self) { group in
                                        HStack {
                                            Text(group.title)
                                            Spacer()
                                            Text("\(groupSetCounts[group] ?? 0)セット")
                                                .foregroundStyle(Phase1DesignTokens.secondary)
                                                .monospacedDigit()
                                        }
                                        .font(.subheadline.weight(.medium))
                                    }
                                }
                            }
                            Text("モデルはドラッグで回転、ピンチで拡大できます。")
                                .font(.footnote)
                                .foregroundStyle(Phase1DesignTokens.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Phase1DesignTokens.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
