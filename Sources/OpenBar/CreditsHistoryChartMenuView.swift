import OpenBarCore
import SwiftUI

@MainActor
struct CreditsHistoryChartMenuView: View {
    private struct Point: Identifiable {
        let id: String
        let date: Date
        let creditsUsed: Double

        init(date: Date, creditsUsed: Double) {
            self.date = date
            self.creditsUsed = creditsUsed
            self.id = "\(Int(date.timeIntervalSince1970))-\(creditsUsed)"
        }
    }

    private let breakdown: [OpenAIDashboardDailyBreakdown]
    private let width: CGFloat
    @State private var selectedDayKey: String?

    init(breakdown: [OpenAIDashboardDailyBreakdown], width: CGFloat) {
        self.breakdown = breakdown
        self.width = width
    }

    var body: some View {
        let model = Self.makeModel(from: self.breakdown)
        VStack(alignment: .leading, spacing: 10) {
            if model.points.isEmpty {
                Text(L("No credits history data."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L("No credits history data available."))
            } else {
                DailyBarChart(
                    days: model.selectableDayDates.map { entry in
                        let creditsUsed = model.pointsByDayKey[entry.dayKey]?.creditsUsed ?? 0
                        return DailyBarChart.Day(
                            date: entry.date,
                            segments: [.init(value: creditsUsed, color: Self.barColor)],
                            accessibilityValue: Self.creditsAccessibilityValue(creditsUsed))
                    },
                    axisDates: model.axisDates,
                    peak: Self.peakPoint(model: model).map { (date: $0.date, value: $0.creditsUsed) },
                    selectedIndex: self.selectedDayKey.flatMap { key in
                        model.selectableDayDates.firstIndex { $0.dayKey == key }
                    },
                    plotPadding: ChartAxisLabelLayout.dateLabelEdgePadding,
                    onHover: { index in
                        self.selectedDayKey = index.map { model.selectableDayDates[$0].dayKey }
                    })
                    .frame(height: 130)
                    .accessibilityLabel(L("Credits history chart"))
                    .accessibilityValue(
                        model.points.isEmpty
                            ? L("No data")
                            : String(format: L("%d days of credits data"), model.points.count))

                let detail = self.detailLines(model: model)
                VStack(alignment: .leading, spacing: 0) {
                    Text(detail.primary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(height: 16, alignment: .leading)
                    Text(detail.secondary ?? " ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(height: 16, alignment: .leading)
                        .opacity(detail.secondary == nil ? 0 : 1)
                }

                if let total = model.totalCreditsUsed {
                    Text(String(
                        format: L("Total (30d): %@ credits"),
                        total.formatted(.number.precision(.fractionLength(0...2)))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: self.width, maxWidth: .infinity, alignment: .leading)
    }

    private struct Model {
        let points: [Point]
        let breakdownByDayKey: [String: OpenAIDashboardDailyBreakdown]
        let pointsByDayKey: [String: Point]
        let dayDates: [(dayKey: String, date: Date)]
        let selectableDayDates: [(dayKey: String, date: Date)]
        let axisDates: [Date]
        let peakKey: String?
        let totalCreditsUsed: Double?
    }

    private static let barColor = Color(red: 73 / 255, green: 163 / 255, blue: 176 / 255)

    private static func creditsAccessibilityValue(_ creditsUsed: Double) -> String {
        "\(L("Credits used")): \(creditsUsed.formatted(.number.precision(.fractionLength(0...2))))"
    }

    private static func makeModel(from breakdown: [OpenAIDashboardDailyBreakdown]) -> Model {
        let sorted = breakdown.sorted { lhs, rhs in lhs.day < rhs.day }

        var points: [Point] = []
        points.reserveCapacity(sorted.count)

        var breakdownByDayKey: [String: OpenAIDashboardDailyBreakdown] = [:]
        breakdownByDayKey.reserveCapacity(sorted.count)

        var pointsByDayKey: [String: Point] = [:]
        pointsByDayKey.reserveCapacity(sorted.count)

        var dayDates: [(dayKey: String, date: Date)] = []
        dayDates.reserveCapacity(sorted.count)

        var selectableDayDates: [(dayKey: String, date: Date)] = []
        selectableDayDates.reserveCapacity(sorted.count)

        var totalCreditsUsed: Double = 0
        var peak: (key: String, creditsUsed: Double)?

        for day in sorted {
            guard let date = self.dateFromDayKey(day.day) else { continue }
            breakdownByDayKey[day.day] = day
            dayDates.append((dayKey: day.day, date: date))
            totalCreditsUsed += day.totalCreditsUsed
            if day.totalCreditsUsed > 0 {
                let point = Point(date: date, creditsUsed: day.totalCreditsUsed)
                points.append(point)
                pointsByDayKey[day.day] = point
                selectableDayDates.append((dayKey: day.day, date: date))
                if let cur = peak {
                    if day.totalCreditsUsed > cur.creditsUsed { peak = (day.day, day.totalCreditsUsed) }
                } else {
                    peak = (day.day, day.totalCreditsUsed)
                }
            }
        }

        let axisDates: [Date] = {
            guard let first = dayDates.first?.date, let last = dayDates.last?.date else { return [] }
            if Calendar.current.isDate(first, inSameDayAs: last) { return [first] }
            return [first, last]
        }()

        return Model(
            points: points,
            breakdownByDayKey: breakdownByDayKey,
            pointsByDayKey: pointsByDayKey,
            dayDates: dayDates,
            selectableDayDates: selectableDayDates,
            axisDates: axisDates,
            peakKey: peak?.key,
            totalCreditsUsed: totalCreditsUsed > 0 ? totalCreditsUsed : nil)
    }

    private static func dateFromDayKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }

        var comps = DateComponents()
        comps.calendar = Calendar.current
        comps.timeZone = TimeZone.current
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return comps.date
    }

    private static func peakPoint(model: Model) -> Point? {
        guard let key = model.peakKey else { return nil }
        return model.pointsByDayKey[key]
    }

    private func detailLines(model: Model) -> (primary: String, secondary: String?) {
        guard let key = self.selectedDayKey,
              let day = model.breakdownByDayKey[key],
              let date = Self.dateFromDayKey(key)
        else {
            return (L("Hover a bar for details"), nil)
        }

        let dayLabel = date.formatted(.dateTime.month(.abbreviated).day())
        let total = day.totalCreditsUsed.formatted(.number.precision(.fractionLength(0...2)))
        if day.services.isEmpty {
            return (String(format: L("%@: %@ credits"), dayLabel, total), nil)
        }
        if day.services.count <= 1, let first = day.services.first {
            let used = first.creditsUsed.formatted(.number.precision(.fractionLength(0...2)))
            return (String(format: L("%@: %@ credits"), dayLabel, used), first.service)
        }

        let services = day.services
            .sorted { lhs, rhs in
                if lhs.creditsUsed == rhs.creditsUsed { return lhs.service < rhs.service }
                return lhs.creditsUsed > rhs.creditsUsed
            }
            .prefix(3)
            .map { "\($0.service) \($0.creditsUsed.formatted(.number.precision(.fractionLength(0...2))))" }
            .joined(separator: " · ")

        return (String(format: L("%@: %@ credits"), dayLabel, total), services)
    }
}
