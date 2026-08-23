import SwiftUI

private enum BodySide: String, CaseIterable, Identifiable {
    case front = "正面"
    case back = "背面"

    var id: String { rawValue }
}

struct MuscleMapView: View {
    @ObservedObject var store: AppStore
    @State private var selectedDate = Date()
    @State private var side: BodySide = .front
    @State private var didSelectInitialDate = false

    private let calendar = Calendar.current

    private var snapshot: MuscleLoadSnapshot {
        MuscleLoadAnalytics.snapshot(
            on: selectedDate,
            records: store.records,
            exercises: store.exercises
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    dateCard

                    Picker("表示", selection: $side) {
                        ForEach(BodySide.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 14) {
                        MuscleFigure(side: side, snapshot: snapshot)
                            .frame(height: 390)

                        HStack(spacing: 18) {
                            intensityKey(opacity: 0.25, text: "軽い")
                            intensityKey(opacity: 0.55, text: "中")
                            intensityKey(opacity: 0.9, text: "高い")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 18))

                    summaryCard
                    muscleBreakdown
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("身体")
            .onAppear(perform: selectUsefulInitialDate)
        }
    }

    private var dateCard: some View {
        HStack {
            Button("前日", systemImage: "chevron.left") { moveDate(-1) }
                .labelStyle(.iconOnly)
            Spacer()
            DatePicker(
                "表示日",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "ja_JP"))
            Spacer()
            Button("翌日", systemImage: "chevron.right") { moveDate(1) }
                .labelStyle(.iconOnly)
                .disabled(calendar.isDateInToday(selectedDate))
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var summaryCard: some View {
        HStack(spacing: 12) {
            summaryItem(
                title: "種目",
                value: "\(snapshot.workoutCount)",
                icon: "dumbbell.fill"
            )
            Divider().frame(height: 42)
            summaryItem(
                title: "総負荷量",
                value: "\(snapshot.totalVolume.formatted(.number.notation(.compactName))) kg",
                icon: "sum"
            )
            Divider().frame(height: 42)
            summaryItem(
                title: "部位",
                value: "\(snapshot.activeGroups.count)",
                icon: "figure.arms.open"
            )
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var muscleBreakdown: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("部位別の負荷").font(.title3.bold())

            if snapshot.activeGroups.isEmpty {
                ContentUnavailableView(
                    "この日の記録はありません",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("記録を保存すると、鍛えた部位が赤く表示されます。")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ForEach(MuscleGroup.mapGroups) { group in
                    let intensity = snapshot.intensity(for: group)
                    HStack(spacing: 12) {
                        Circle()
                            .fill(regionColor(intensity: intensity))
                            .frame(width: 13, height: 13)
                        Text(group.rawValue)
                            .frame(width: 42, alignment: .leading)
                        ProgressView(value: intensity)
                            .tint(.red)
                        Text(snapshot.load(for: group).formatted(.number.precision(.fractionLength(0))))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                Text("数値は重量・回数・セット数から計算した負荷スコアです。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func summaryItem(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func intensityKey(opacity: Double, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Color.red.opacity(opacity)).frame(width: 10, height: 10)
            Text(text)
        }
    }

    private func regionColor(intensity: Double) -> Color {
        intensity == 0
            ? Color(uiColor: .tertiarySystemFill)
            : Color.red.opacity(0.2 + intensity * 0.75)
    }

    private func moveDate(_ amount: Int) {
        guard let nextDate = calendar.date(byAdding: .day, value: amount, to: selectedDate),
              nextDate <= Date() else { return }
        selectedDate = nextDate
    }

    private func selectUsefulInitialDate() {
        guard !didSelectInitialDate else { return }
        didSelectInitialDate = true
        guard !store.records.contains(where: { calendar.isDateInToday($0.date) }),
              let latest = store.records.max(by: { $0.date < $1.date }) else { return }
        selectedDate = latest.date
    }
}

private struct MuscleFigure: View {
    let side: BodySide
    let snapshot: MuscleLoadSnapshot

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 210, size.height / 370)
            let xOffset = (size.width - 210 * scale) / 2
            let yOffset = (size.height - 370 * scale) / 2

            context.translateBy(x: xOffset, y: yOffset)
            context.scaleBy(x: scale, y: scale)

            drawEllipse(CGRect(x: 82, y: 4, width: 46, height: 49), group: nil, in: &context)
            drawRoundedRect(CGRect(x: 92, y: 48, width: 26, height: 24), radius: 8, group: torsoGroup, in: &context)

            drawShoulders(in: &context)
            drawTorso(in: &context)
            drawArms(in: &context)
            drawLegs(in: &context)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("筋肉負荷マップ・\(side.rawValue)")
        .accessibilityValue(accessibilitySummary)
    }

    private var torsoGroup: MuscleGroup { side == .front ? .chest : .back }

    private var accessibilitySummary: String {
        let active = snapshot.activeGroups.map(\.rawValue).joined(separator: "、")
        return active.isEmpty ? "負荷の記録なし" : "負荷のある部位：\(active)"
    }

    private func drawShoulders(in context: inout GraphicsContext) {
        drawEllipse(CGRect(x: 52, y: 63, width: 43, height: 34), group: .shoulders, in: &context)
        drawEllipse(CGRect(x: 115, y: 63, width: 43, height: 34), group: .shoulders, in: &context)
    }

    private func drawTorso(in context: inout GraphicsContext) {
        if side == .front {
            drawPath(points: [(76, 69), (105, 64), (105, 132), (67, 125)], group: .chest, in: &context)
            drawPath(points: [(105, 64), (134, 69), (143, 125), (105, 132)], group: .chest, in: &context)
            drawPath(points: [(67, 125), (105, 132), (105, 206), (78, 194)], group: .core, in: &context)
            drawPath(points: [(105, 132), (143, 125), (132, 194), (105, 206)], group: .core, in: &context)
        } else {
            drawPath(
                points: [(76, 69), (105, 64), (134, 69), (143, 125), (132, 194), (105, 206), (78, 194), (67, 125)],
                group: .back,
                in: &context
            )
        }
    }

    private func drawArms(in context: inout GraphicsContext) {
        drawPath(points: [(57, 78), (77, 89), (58, 159), (40, 154)], group: .arms, in: &context)
        drawPath(points: [(153, 78), (133, 89), (152, 159), (170, 154)], group: .arms, in: &context)
        drawPath(points: [(40, 151), (58, 158), (45, 230), (29, 226)], group: .arms, in: &context)
        drawPath(points: [(170, 151), (152, 158), (165, 230), (181, 226)], group: .arms, in: &context)
    }

    private func drawLegs(in context: inout GraphicsContext) {
        drawPath(points: [(78, 193), (104, 203), (98, 283), (68, 283)], group: .legs, in: &context)
        drawPath(points: [(106, 203), (132, 193), (142, 283), (112, 283)], group: .legs, in: &context)
        drawPath(points: [(68, 280), (98, 280), (92, 354), (70, 354)], group: .legs, in: &context)
        drawPath(points: [(112, 280), (142, 280), (140, 354), (118, 354)], group: .legs, in: &context)
    }

    private func drawEllipse(
        _ rect: CGRect,
        group: MuscleGroup?,
        in context: inout GraphicsContext
    ) {
        draw(Path(ellipseIn: rect), group: group, in: &context)
    }

    private func drawRoundedRect(
        _ rect: CGRect,
        radius: CGFloat,
        group: MuscleGroup?,
        in context: inout GraphicsContext
    ) {
        draw(Path(roundedRect: rect, cornerRadius: radius), group: group, in: &context)
    }

    private func drawPath(
        points: [(CGFloat, CGFloat)],
        group: MuscleGroup,
        in context: inout GraphicsContext
    ) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.0, y: point.1))
        }
        path.closeSubpath()
        draw(path, group: group, in: &context)
    }

    private func draw(
        _ path: Path,
        group: MuscleGroup?,
        in context: inout GraphicsContext
    ) {
        let intensity = group.map(snapshot.intensity(for:)) ?? 0
        let fill = intensity == 0
            ? Color(uiColor: .tertiarySystemFill)
            : Color.red.opacity(0.2 + intensity * 0.75)
        context.fill(path, with: .color(fill))
        context.stroke(path, with: .color(.secondary.opacity(0.45)), lineWidth: 1.2)
    }
}
