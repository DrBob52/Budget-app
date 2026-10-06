import SwiftUI
import TallyCore

struct WatchCategoriesView: View {
    @EnvironmentObject private var model: WatchSessionModel

    private var snapshot: BudgetSnapshot { model.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if snapshot.categories.isEmpty {
                    Text("No budgeted categories yet. Set limits in the Plan tab on your iPhone.")
                        .font(.system(size: 13))
                        .foregroundStyle(WatchPalette.inkSecondary)
                } else {
                    ForEach(snapshot.categories) { line in
                        WatchCategoryRow(line: line, currencyCode: snapshot.currencyCode)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Categories")
    }
}

struct WatchCategoryRow: View {
    let line: BudgetSnapshot.CategoryLine
    let currencyCode: String

    private func money(_ value: Decimal) -> String {
        MoneyFormat.string(value, currencyCode: currencyCode, compact: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: line.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(watchHex: line.colorHex))
                Text(line.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WatchPalette.ink)
                    .lineLimit(1)
                Spacer(minLength: 2)
            }
            WatchBar(progress: line.progress)
            Text("\(money(line.spent)) of \(money(line.available))")
                .font(WatchFonts.serif(12, weight: .regular))
                .foregroundStyle(line.progress > 1 ? WatchPalette.negative : WatchPalette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
