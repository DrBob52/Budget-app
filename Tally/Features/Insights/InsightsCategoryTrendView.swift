import SwiftUI
import SwiftData
import Charts
import TallyCore

/// One category's spending across the last six periods, with its limit when budgeted.
struct InsightsCategoryTrendView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var categories: [Category]

    let categoryID: UUID?
    let name: String
    let symbol: String
    let colorHex: String
    /// Last period shown on the chart.
    let period: BudgetPeriod

    private struct Bar: Identifiable {
        let id: Date
        let label: String
        let title: String
        let amount: Decimal
        let isSelected: Bool
    }

    private var limit: Decimal {
        guard let categoryID else { return 0 }
        return categories.first { $0.id == categoryID }?.budgetLimit ?? 0
    }

    private var bars: [Bar] {
        let calculator = settings.periodCalculator
        let entries: [LedgerEntry] = transactions.map(\.ledgerEntry)
        let periods: [BudgetPeriod] = calculator.periods(endingWith: period, count: InsightsData.historyCount)
        var result: [Bar] = []
        for item in periods {
            let totals: [CategoryTotal] = InsightsCalculator.totalsByCategory(entries: entries, in: item)
            let amount: Decimal = totals.first { $0.categoryID == categoryID }?.total ?? 0
            result.append(Bar(
                id: item.start,
                label: InsightsFormat.shortLabel(item, kind: settings.periodKind),
                title: item.title(),
                amount: amount,
                isSelected: item.start == period.start
            ))
        }
        return result
    }

    var body: some View {
        let rows: [Bar] = bars
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(rows)
                InsightsSection("Last \(InsightsData.historyCount) periods") {
                    chart(rows)
                }
                breakdown(rows)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 12)
        }
        .tallyScreen()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private func header(_ rows: [Bar]) -> some View {
        let total: Decimal = rows.reduce(Decimal(0)) { $0 + $1.amount }
        let average: Decimal = rows.isEmpty ? 0 : total / Decimal(rows.count)
        let selected: Decimal = rows.last?.amount ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CategoryIcon(symbol: symbol, colorHex: colorHex, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.titleSerif)
                        .foregroundStyle(Palette.ink)
                    Text(period.title())
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Rule()
            HStack(alignment: .top, spacing: 16) {
                InsightsStat(title: "This period", amount: selected)
                InsightsStat(title: "Average", amount: average)
                if limit > 0 {
                    InsightsStat(title: "Limit", amount: limit)
                }
            }
        }
        .tallyCard()
    }

    // MARK: Chart

    private func chart(_ rows: [Bar]) -> some View {
        let color: Color = Color(hex: colorHex)
        return VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(rows) { row in
                    BarMark(
                        x: .value("Period", row.label),
                        y: .value("Spent", row.amount.doubleValue)
                    )
                    .foregroundStyle(color.opacity(row.isSelected ? 1 : 0.45))
                }
                if limit > 0 {
                    RuleMark(y: .value("Limit", limit.doubleValue))
                        .foregroundStyle(Palette.negative)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Limit \(settings.format(limit, compact: true))")
                                .font(.caption2)
                                .foregroundStyle(Palette.negative)
                        }
                }
            }
            .insightsMoneyAxis(settings)
            .insightsLabelAxis()
            .frame(height: 210)
            .insightsPrivacy(settings.hideAmounts)

            if limit <= 0 && categoryID != nil {
                InsightsNote("This category has no limit. Set one in the Plan tab to see it on the chart.")
            }
        }
    }

    // MARK: Breakdown

    private func breakdown(_ rows: [Bar]) -> some View {
        InsightsSection("By period") {
            VStack(spacing: 0) {
                ForEach(Array(rows.reversed().enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Rule() }
                    HStack {
                        Text(row.title)
                            .font(.body)
                            .foregroundStyle(row.isSelected ? Palette.ink : Palette.inkSecondary)
                        Spacer()
                        MoneyText(amount: row.amount, font: .amountSmall)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }
}
