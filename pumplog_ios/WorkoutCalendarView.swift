import SwiftUI

struct WorkoutCalendarView: View {
    let records: [WorkoutRecord]
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    private var days: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let weekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmptyDays = weekday - calendar.firstWeekday
        let normalizedLeading = leadingEmptyDays >= 0 ? leadingEmptyDays : leadingEmptyDays + 7
        let dates = dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start)
        }
        return Array(repeating: nil, count: normalizedLeading) + dates
    }

    private var workoutDays: Set<Date> {
        Set(records.map { calendar.startOfDay(for: $0.date) })
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("前月", systemImage: "chevron.left") { moveMonth(-1) }
                    .labelStyle(.iconOnly)
                Spacer()
                Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                    .font(.headline)
                Spacer()
                Button("翌月", systemImage: "chevron.right") { moveMonth(1) }
                    .labelStyle(.iconOnly)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.caption.bold())
                        .foregroundStyle(index == 0 ? .red : index == 6 ? .blue : .secondary)
                }

                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayButton(date)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func dayButton(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let hasWorkout = workoutDays.contains(calendar.startOfDay(for: date))
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.body.weight(isSelected ? .bold : .regular))
                    .frame(width: 32, height: 28)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
                Circle()
                    .fill(hasWorkout ? Color.red : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .long, time: .omitted))
        .accessibilityValue(hasWorkout ? "トレーニングあり" : "記録なし")
    }

    private func moveMonth(_ amount: Int) {
        guard let next = calendar.date(byAdding: .month, value: amount, to: displayedMonth) else { return }
        displayedMonth = next
    }
}
