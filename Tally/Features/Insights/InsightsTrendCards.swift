import SwiftUI
import Charts
import TallyCore

// MARK: - Income vs spending

struct InsightsIncomeSpendingCard: View {
    @Environment(AppSettings.self) private var settings
    let data: InsightsData

    private static let incomeName = "Income"
    private static let spendingName = "Spending"

    var body: some View {
        InsightsSection("Income vs spending") {
            chart
            legend
        }
    }

    private var chart: some View {
        Chart {
            ForEach(data.history) { totals in
                BarMark(
                    x: .value("Period", data.label(for: totals)),
                    y: .value("Amount", totals.income.doubleValue)
                )
                .foregroundStyle(by: .value("Type", InsightsIncomeSpendingCard.incomeName))
                .position(by: .value("Type", InsightsIncomeSpendingCard.incomeName))

                BarMark(
                    x: .value("Period", data.label(for: totals)),
                    y: .value("Amount", totals.expenses.doubleValue)
                )
                .foregroundStyle(by: .value("Type", InsightsIncomeSpendingCard.spendingName))
                .position(by: .value("Type", InsightsIncomeSpendingCard.spendingName))
            }
            if data.averageSpending > 0 {
                RuleMark(y: .value("Average spending", data.averageSpending.doubleValue))
                    .foregroundStyle(Palette.inkTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartForegroundStyleScale(
            domain: [InsightsIncomeSpendingCard.incomeName, InsightsIncomeSpendingCard.spendingName],
            range: [Palette.accent, Palette.negative]
        )
        .chartLegend(.hidden)
        .insightsMoneyAxis(settings)
        .insightsLabelAxis()
        .frame(height: 200)
        .insightsPrivacy(settings.hideAmounts)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            swatch(Palette.accent, "Income")
            swatch(Palette.negative, "Spending")
            if data.averageSpending > 0 {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Palette.inkTertiary)
                        .frame(width: 14, height: 1.5)
                    Text("Average spending \(settings.format(data.averageSpending, compact: true))")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .hidesAmount(settings.hideAmounts)
                }
            }
        }
    }

    private func swatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
        }
    }
}

// MARK: - Daily pace

struct InsightsPaceCard: View {
    @Environment(AppSettings.self) private var settings
    let data: InsightsData

    private static let spentName = "Spent"
    private static let paceName = "On pace"

    private var showsPace: Bool { data.totalBudget > 0 }

    var body: some View {
        InsightsSection("Daily pace") {
            if data.pacePoints.isEmpty {
                InsightsNote("This period has not started yet.")
            } else {
                verdict
                chart
                caption
            }
        }
    }

    // Positive = spending faster than an even rate.
    private var difference: Decimal? {
        guard let expected = data.expectedToDate else { return nil }
        return data.spentToDate - expected
    }

    private var isAhead: Bool {
        guard let difference else { return false }
        return difference > data.totalBudget * Decimal(string: "0.02")!
    }

    @ViewBuilder
    private var verdict: some View {
        if let difference {
            let size: String = settings.format(difference.magnitudeValue, compact: true)
            let threshold: Decimal = data.totalBudget * Decimal(string: "0.02")!
            if difference > threshold {
                Text("Ahead of pace by \(size). Spending is running faster than your budget allows.")
                    .font(.headlineSerif)
                    .foregroundStyle(Palette.negative)
                    .hidesAmount(settings.hideAmounts)
            } else if difference < -threshold {
                Text("Behind pace by \(size). You are spending slower than an even rate.")
                    .font(.headlineSerif)
                    .foregroundStyle(Palette.positive)
                    .hidesAmount(settings.hideAmounts)
            } else {
                Text("Right on pace.")
                    .font(.headlineSerif)
                    .foregroundStyle(Palette.ink)
            }
        } else {
            InsightsNote("Give your categories limits to compare spending with an even pace.")
        }
    }

    private var chart: some View {
        Chart {
            ForEach(data.pacePoints) { point in
                LineMark(
                    x: .value("Day", point.date),
                    y: .value("Amount", point.cumulative),
                    series: .value("Series", InsightsPaceCard.spentName)
                )
                .foregroundStyle(by: .value("Series", InsightsPaceCard.spentName))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if showsPace {
                LineMark(
                    x: .value("Day", data.period.start),
                    y: .value("Amount", 0.0),
                    series: .value("Series", InsightsPaceCard.paceName)
                )
                .foregroundStyle(by: .value("Series", InsightsPaceCard.paceName))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))

                LineMark(
                    x: .value("Day", data.period.end),
                    y: .value("Amount", data.totalBudget.doubleValue),
                    series: .value("Series", InsightsPaceCard.paceName)
                )
                .foregroundStyle(by: .value("Series", InsightsPaceCard.paceName))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
        .chartForegroundStyleScale(
            domain: [InsightsPaceCard.spentName, InsightsPaceCard.paceName],
            range: [isAhead ? Palette.negative : Palette.accent, Palette.inkTertiary]
        )
        .chartLegend(.hidden)
        .insightsMoneyAxis(settings)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.rule)
                AxisValueLabel(format: Date.FormatStyle().month(.abbreviated).day())
            }
        }
        .frame(height: 190)
        .insightsPrivacy(settings.hideAmounts)
    }

    private var caption: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(isAhead ? Palette.negative : Palette.accent)
                    .frame(width: 14, height: 2)
                Text("Spent so far")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            if showsPace {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Palette.inkTertiary)
                        .frame(width: 14, height: 1.5)
                    Text("Even pace to \(settings.format(data.totalBudget, compact: true))")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .hidesAmount(settings.hideAmounts)
                }
            }
        }
    }
}

// MARK: - Net worth

struct InsightsNetWorthCard: View {
    @Environment(AppSettings.self) private var settings
    let data: InsightsData

    var body: some View {
        InsightsSection("Net worth") {
            headline
            chart
        }
    }

    private var latest: Decimal { data.netWorth.last?.value ?? 0 }

    private var change: Decimal {
        guard let first = data.netWorth.first, let last = data.netWorth.last else { return 0 }
        return last.value - first.value
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            MoneyText(amount: latest, compact: true, font: .display(28))
            Text("\(settings.format(change, showsSign: true, compact: true)) over \(data.netWorth.count) periods")
                .font(.footnote)
                .foregroundStyle(change < 0 ? Palette.negative : Palette.inkSecondary)
                .hidesAmount(settings.hideAmounts)
        }
    }

    private var chart: some View {
        Chart(data.netWorth) { point in
            AreaMark(
                x: .value("Period", point.label),
                y: .value("Net worth", point.value.doubleValue)
            )
            .foregroundStyle(Palette.accent.opacity(0.12))

            LineMark(
                x: .value("Period", point.label),
                y: .value("Net worth", point.value.doubleValue)
            )
            .foregroundStyle(Palette.accent)
            .lineStyle(StrokeStyle(lineWidth: 2))

            PointMark(
                x: .value("Period", point.label),
                y: .value("Net worth", point.value.doubleValue)
            )
            .foregroundStyle(Palette.accent)
            .symbolSize(24)
        }
        .insightsMoneyAxis(settings)
        .insightsLabelAxis()
        .frame(height: 190)
        .insightsPrivacy(settings.hideAmounts)
    }
}
