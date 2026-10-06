import SwiftUI
import Charts
import TallyCore

// MARK: - Summary

struct InsightsSummaryCard: View {
    @Environment(AppSettings.self) private var settings
    let data: InsightsData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                InsightsStat(title: "Income", amount: data.current.income)
                InsightsStat(title: "Spending", amount: data.current.expenses)
            }
            Rule()
            HStack(alignment: .top, spacing: 16) {
                InsightsStat(title: "Net", amount: data.current.net, showsSign: true, colored: true)
                savingsStat
            }
            if let note = comparison {
                Rule()
                Text(note.text)
                    .font(.subheadline)
                    .foregroundStyle(note.color)
            }
        }
        .tallyCard()
    }

    private var savingsStat: some View {
        let rate: Double? = InsightsCalculator.savingsRate(income: data.current.income, expenses: data.current.expenses)
        return VStack(alignment: .leading, spacing: 4) {
            Overline("Savings rate")
            Text(rate.map { InsightsFormat.percent($0) } ?? "\u{2014}")
                .font(.display(22))
                .foregroundStyle(savingsColor(rate))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func savingsColor(_ rate: Double?) -> Color {
        guard let rate else { return Palette.inkTertiary }
        if rate > 0 { return Palette.positive }
        if rate < 0 { return Palette.negative }
        return Palette.ink
    }

    private var comparison: (text: String, color: Color)? {
        let before: Decimal = data.previous.expenses
        let now: Decimal = data.current.expenses
        guard before > 0 else { return nil }
        let change: Double = ((now - before) / before).doubleValue
        let percent: Int = Int((abs(change) * 100).rounded())
        if percent == 0 {
            return ("Spending is level with last period", Palette.inkSecondary)
        }
        if change < 0 {
            return ("\(percent)% less than last period", Palette.positive)
        }
        return ("\(percent)% more than last period", Palette.negative)
    }
}

// MARK: - Spending by category

struct InsightsCategoryCard: View {
    @Environment(AppSettings.self) private var settings
    let data: InsightsData

    var body: some View {
        InsightsSection("Spending by category") {
            if data.slices.isEmpty {
                InsightsNote("No spending recorded in this period.")
            } else {
                donut
                legend
            }
        }
    }

    private var donut: some View {
        Chart(data.slices) { slice in
            SectorMark(
                angle: .value("Amount", slice.amount.doubleValue),
                innerRadius: .ratio(0.62),
                angularInset: 1
            )
            .foregroundStyle(Color(hex: slice.colorHex))
        }
        .chartLegend(.hidden)
        .frame(height: 210)
        .insightsPrivacy(settings.hideAmounts)
        .overlay { centerLabel }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spending by category")
        .accessibilityValue(settings.format(data.current.expenses))
    }

    private var centerLabel: some View {
        VStack(spacing: 2) {
            Overline("Spent")
            MoneyText(amount: data.current.expenses, compact: true, font: .display(24))
        }
        .allowsHitTesting(false)
    }

    private var legend: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.slices.enumerated()), id: \.element.id) { index, slice in
                if index > 0 { Rule() }
                NavigationLink {
                    InsightsCategoryTrendView(
                        categoryID: slice.categoryID,
                        name: slice.name,
                        symbol: slice.symbol,
                        colorHex: slice.colorHex,
                        period: data.period
                    )
                } label: {
                    InsightsLegendRow(slice: slice)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct InsightsLegendRow: View {
    let slice: InsightsSlice

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(symbol: slice.symbol, colorHex: slice.colorHex, size: 32)
            Text(slice.name)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                MoneyText(amount: slice.amount, font: .amountSmall)
                Text(InsightsFormat.percent(slice.share))
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.inkTertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Top payees

struct InsightsPayeesCard: View {
    let data: InsightsData

    var body: some View {
        InsightsSection("Top payees") {
            if data.payees.isEmpty {
                InsightsNote("Payees appear here once your expenses have titles.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(data.payees.enumerated()), id: \.element.id) { index, payee in
                        if index > 0 { Rule() }
                        InsightsPayeeRow(payee: payee)
                    }
                }
            }
        }
    }
}

struct InsightsPayeeRow: View {
    let payee: PayeeTotal

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(payee.title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(payee.count == 1 ? "1 purchase" : "\(payee.count) purchases")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 8)
            MoneyText(amount: payee.total, font: .amountSmall)
        }
        .padding(.vertical, 10)
    }
}
