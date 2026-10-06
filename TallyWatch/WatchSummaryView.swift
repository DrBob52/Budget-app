import SwiftUI
import TallyCore

struct WatchSummaryView: View {
    @EnvironmentObject private var model: WatchSessionModel

    private var snapshot: BudgetSnapshot { model.snapshot }

    private func money(_ value: Decimal) -> String {
        MoneyFormat.string(value, currencyCode: snapshot.currencyCode, compact: true)
    }

    private var leftColor: Color {
        snapshot.leftToSpend < 0 ? WatchPalette.negative : WatchPalette.ink
    }

    private var daysText: String {
        let days = snapshot.daysRemaining
        if days <= 0 { return "Period ended" }
        return days == 1 ? "1 day left" : "\(days) days left"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ring
                details
                if !model.hasRealData {
                    Text("Sample figures. Open Tally on your iPhone to sync.")
                        .font(.system(size: 11))
                        .foregroundStyle(WatchPalette.inkSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(snapshot.periodTitle)
    }

    private var ring: some View {
        ZStack {
            WatchRing(progress: snapshot.progress, lineWidth: 9)
            VStack(spacing: 0) {
                Text(money(snapshot.leftToSpend))
                    .font(WatchFonts.serif(28))
                    .foregroundStyle(leftColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("left to spend")
                    .font(.system(size: 11))
                    .foregroundStyle(WatchPalette.inkSecondary)
            }
            .padding(.horizontal, 18)
        }
        .frame(width: 130, height: 130)
        .padding(.top, 4)
    }

    private var details: some View {
        VStack(spacing: 6) {
            Rectangle().fill(WatchPalette.rule).frame(height: 1)
            WatchDetailRow(title: "Per day", value: perDayText)
            Rectangle().fill(WatchPalette.rule).frame(height: 1)
            WatchDetailRow(title: "Remaining", value: daysText)
            Rectangle().fill(WatchPalette.rule).frame(height: 1)
            WatchDetailRow(title: "Spent", value: money(snapshot.spent))
        }
    }

    private var perDayText: String {
        if let allowance = snapshot.dailyAllowance, snapshot.daysRemaining > 0 {
            return money(allowance)
        }
        return "None"
    }
}

struct WatchDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(WatchPalette.inkSecondary)
            Spacer(minLength: 4)
            Text(value)
                .font(WatchFonts.serif(15, weight: .medium))
                .foregroundStyle(WatchPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
