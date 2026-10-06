import SwiftUI
import WidgetKit

struct WidgetQuickAddEntry: TimelineEntry {
    let date: Date
}

struct WidgetQuickAddProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetQuickAddEntry {
        WidgetQuickAddEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetQuickAddEntry) -> Void) {
        completion(WidgetQuickAddEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetQuickAddEntry>) -> Void) {
        completion(Timeline(entries: [WidgetQuickAddEntry(date: Date())], policy: .never))
    }
}

struct QuickAddWidget: Widget {
    let kind = "TallyQuickAdd"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetQuickAddProvider()) { entry in
            WidgetQuickAddView(entry: entry)
        }
        .configurationDisplayName("Quick add")
        .description("Jump straight to logging an expense or income.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WidgetQuickAddView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetQuickAddEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                WidgetPalette.paper
            }
    }

    @ViewBuilder
    private var content: some View {
        if family == .systemMedium {
            WidgetQuickAddMedium()
        } else {
            WidgetQuickAddSmall()
                .widgetURL(URL(string: "tally://add"))
        }
    }
}

struct WidgetQuickAddSmall: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(WidgetPalette.accent)
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(WidgetPalette.paper)
            }
            .frame(width: 56, height: 56)
            Text("Log expense")
                .font(WidgetFonts.serif(17))
                .foregroundStyle(WidgetPalette.ink)
            Text("Takes a few seconds")
                .font(.system(size: 11))
                .foregroundStyle(WidgetPalette.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct WidgetQuickAddMedium: View {
    var body: some View {
        HStack(spacing: 12) {
            if let expenseURL = URL(string: "tally://add") {
                Link(destination: expenseURL) {
                    WidgetQuickAddTile(symbol: "minus", title: "Expense", subtitle: "Money out", tint: WidgetPalette.negative)
                }
            }
            if let incomeURL = URL(string: "tally://add?kind=income") {
                Link(destination: incomeURL) {
                    WidgetQuickAddTile(symbol: "plus", title: "Income", subtitle: "Money in", tint: WidgetPalette.accent)
                }
            }
        }
    }
}

struct WidgetQuickAddTile: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Circle().fill(tint)
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(WidgetPalette.paper)
            }
            .frame(width: 40, height: 40)
            Spacer(minLength: 0)
            Text(title)
                .font(WidgetFonts.serif(18))
                .foregroundStyle(WidgetPalette.ink)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(WidgetPalette.inkSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WidgetPalette.rule, lineWidth: 1)
        )
    }
}
