import SwiftUI
import WidgetKit
import TallyCore

struct LeftToSpendWidget: Widget {
    let kind = "TallyLeftToSpend"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetBudgetProvider()) { entry in
            WidgetLeftToSpendView(entry: entry)
        }
        .configurationDisplayName("Left to spend")
        .description("What remains of this period's budget, and what you can spend each day.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct WidgetLeftToSpendView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetBudgetEntry

    private var text: WidgetBudgetText { WidgetBudgetText(snapshot: entry.snapshot) }

    var body: some View {
        content
            .widgetURL(URL(string: "tally://tab/budget"))
            .containerBackground(for: .widget) {
                WidgetPalette.paper
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium:
            WidgetMediumLeftView(text: text)
        case .accessoryCircular:
            WidgetCircularLeftView(text: text)
        case .accessoryRectangular:
            WidgetRectangularLeftView(text: text)
        case .accessoryInline:
            WidgetInlineLeftView(text: text)
        default:
            WidgetSmallLeftView(text: text)
        }
    }
}

// MARK: - Home Screen

struct WidgetSmallLeftView: View {
    let text: WidgetBudgetText

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LEFT TO SPEND")
                .font(WidgetFonts.label(9))
                .tracking(0.8)
                .foregroundStyle(WidgetPalette.inkSecondary)
            Text(text.left)
                .font(WidgetFonts.serif(32))
                .foregroundStyle(text.leftColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            WidgetBar(progress: text.progress)
            Text(text.allowanceLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WidgetPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text(text.snapshot.periodTitle)
                .font(.system(size: 11))
                .foregroundStyle(WidgetPalette.inkSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WidgetMediumLeftView: View {
    let text: WidgetBudgetText

    private var topLines: [BudgetSnapshot.CategoryLine] {
        Array(text.snapshot.categories.prefix(3))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            WidgetSmallLeftView(text: text)
                .frame(maxWidth: .infinity)
            Rectangle()
                .fill(WidgetPalette.rule)
                .frame(width: 1)
            categoriesColumn
                .frame(maxWidth: .infinity)
        }
    }

    private var categoriesColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("TOP CATEGORIES")
                .font(WidgetFonts.label(9))
                .tracking(0.8)
                .foregroundStyle(WidgetPalette.inkSecondary)
            if topLines.isEmpty {
                Text("Set budgets in the Plan tab to see categories here.")
                    .font(.system(size: 12))
                    .foregroundStyle(WidgetPalette.inkSecondary)
            } else {
                ForEach(topLines) { line in
                    WidgetCategoryRow(line: line, text: text)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WidgetCategoryRow: View {
    let line: BudgetSnapshot.CategoryLine
    let text: WidgetBudgetText

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(line.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(text.money(line.spent))
                    .font(WidgetFonts.serif(12, weight: .medium))
                    .foregroundStyle(line.progress > 1 ? WidgetPalette.negative : WidgetPalette.inkSecondary)
                    .lineLimit(1)
            }
            WidgetBar(progress: line.progress, height: 3)
        }
    }
}

// MARK: - Lock Screen

struct WidgetCircularLeftView: View {
    let text: WidgetBudgetText

    private var gaugeValue: Double {
        min(max(text.progress, 0), 1)
    }

    var body: some View {
        Gauge(value: gaugeValue) {
            Text("Left")
        } currentValueLabel: {
            Text(text.left)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

struct WidgetRectangularLeftView: View {
    let text: WidgetBudgetText

    private var barValue: Double {
        min(max(text.progress, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Left to spend")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text.left)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            ProgressView(value: barValue)
            Text(text.daysLeft)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WidgetInlineLeftView: View {
    let text: WidgetBudgetText

    var body: some View {
        Text("\(text.left) left, \(text.daysLeft)")
    }
}
