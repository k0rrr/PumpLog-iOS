import Charts
import SwiftUI

private enum ProgressMetric: String, CaseIterable, Identifiable {
    case maxWeight = "最大重量"
    case estimatedOneRepMax = "推定1RM"
    case volume = "総負荷量"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .volume: "kg"
        case .maxWeight, .estimatedOneRepMax: "kg"
        }
    }

    func value(for point: ExerciseProgressPoint) -> Double {
        switch self {
        case .maxWeight: point.maxWeight
        case .estimatedOneRepMax: point.estimatedOneRepMax
        case .volume: point.totalVolume
        }
    }
}

struct GrowthView: View {
    @ObservedObject var store: AppStore
    @State private var selectedExerciseID: UUID?
    @State private var metric: ProgressMetric = .maxWeight

    private var selectedExercise: Exercise? {
        store.exercises.first { $0.id == selectedExerciseID }
    }

    private var exerciseRecords: [WorkoutRecord] {
        guard let selectedExerciseID else { return [] }
        return WorkoutAnalytics.records(for: selectedExerciseID, in: store.records)
    }

    private var summary: PersonalBestSummary {
        guard let selectedExerciseID else { return .empty }
        return WorkoutAnalytics.summary(for: selectedExerciseID, in: store.records)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("種目", selection: $selectedExerciseID) {
                        ForEach(store.exercises) { exercise in
                            Text(exercise.name).tag(Optional(exercise.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if exerciseRecords.isEmpty {
                        ContentUnavailableView(
                            "成長データがありません",
                            systemImage: "chart.xyaxis.line",
                            description: Text("この種目を記録するとグラフが表示されます。")
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        PersonalBestGrid(summary: summary)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("推移").font(.title2.bold())
                            Picker("指標", selection: $metric) {
                                ForEach(ProgressMetric.allCases) { item in
                                    Text(item.rawValue).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)

                            Chart(exerciseRecords.map(\.progressPoint)) { point in
                                LineMark(
                                    x: .value("日付", point.date),
                                    y: .value(metric.rawValue, metric.value(for: point))
                                )
                                .interpolationMethod(.catmullRom)
                                PointMark(
                                    x: .value("日付", point.date),
                                    y: .value(metric.rawValue, metric.value(for: point))
                                )
                            }
                            .chartYAxisLabel(metric.unit)
                            .frame(height: 240)
                        }
                        .padding()
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("種目履歴").font(.title2.bold())
                            ForEach(exerciseRecords.reversed()) { record in
                                NavigationLink {
                                    ProgressRecordDetail(record: record)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(record.date.formatted(date: .abbreviated, time: .omitted))
                                            Text("\(record.sets.count)セット・総負荷量 \(record.totalVolume.formatted()) kg")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("\(record.maxWeight.formatted()) kg")
                                            .font(.headline)
                                    }
                                }
                                Divider()
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("成長")
            .onAppear {
                if selectedExerciseID == nil {
                    selectedExerciseID = store.exercises.first(where: { exercise in
                        store.records.contains { $0.exerciseID == exercise.id }
                    })?.id ?? store.exercises.first?.id
                }
            }
        }
    }
}

private struct PersonalBestGrid: View {
    let summary: PersonalBestSummary

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            MetricCard(title: "最大重量", value: "\(summary.maxWeight.formatted()) kg", icon: "trophy.fill")
            MetricCard(
                title: "推定1RM",
                value: "\(summary.estimatedOneRepMax.formatted(.number.precision(.fractionLength(1)))) kg",
                icon: "bolt.fill"
            )
            MetricCard(title: "最高回数", value: "\(summary.maxReps) 回", icon: "repeat")
            MetricCard(title: "記録回数", value: "\(summary.workoutCount) 回", icon: "calendar")
            MetricCard(
                title: "累計負荷量",
                value: "\(summary.totalVolume.formatted(.number.notation(.compactName))) kg",
                icon: "sum"
            )
            MetricCard(
                title: "平均負荷量",
                value: "\(summary.averageVolume.formatted(.number.notation(.compactName))) kg",
                icon: "chart.bar.fill"
            )
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ProgressRecordDetail: View {
    let record: WorkoutRecord

    var body: some View {
        List {
            Section("記録") {
                LabeledContent("日時", value: record.date.formatted(date: .long, time: .shortened))
                LabeledContent("総負荷量", value: "\(record.totalVolume.formatted()) kg")
                LabeledContent(
                    "推定1RM",
                    value: "\(record.estimatedOneRepMax.formatted(.number.precision(.fractionLength(1)))) kg"
                )
            }
            Section("セット") {
                ForEach(Array(record.sets.enumerated()), id: \.element.id) { index, set in
                    LabeledContent("Set \(index + 1)", value: "\(set.weight.formatted()) kg × \(set.reps) 回")
                }
            }
            if !record.note.isEmpty { Section("メモ") { Text(record.note) } }
        }
        .navigationTitle(record.exerciseName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
