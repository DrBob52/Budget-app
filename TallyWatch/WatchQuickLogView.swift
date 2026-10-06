import SwiftUI
import WatchKit
import TallyCore

/// Quick-log flow: amount keypad, then category, then confirm.
struct WatchQuickLogView: View {
    enum Step {
        case keypad
        case category
        case confirm
        case done
    }

    @EnvironmentObject private var model: WatchSessionModel

    @State private var step: Step = .keypad
    @State private var amountText: String = ""
    @State private var category: BudgetSnapshot.QuickCategory?

    private var currencyCode: String { model.snapshot.currencyCode }

    private var amount: Decimal {
        var text = amountText
        if text.hasSuffix(".") { text.removeLast() }
        return Decimal(string: text) ?? 0
    }

    var body: some View {
        Group {
            switch step {
            case .keypad:
                WatchKeypadView(
                    text: $amountText,
                    currencyCode: currencyCode,
                    canContinue: amount > 0,
                    onNext: { step = .category }
                )
            case .category:
                WatchCategoryPickerView(
                    categories: model.snapshot.quickCategories,
                    onBack: { step = .keypad },
                    onPick: { picked in
                        category = picked
                        step = .confirm
                    }
                )
            case .confirm:
                WatchConfirmView(
                    amount: amount,
                    currencyCode: currencyCode,
                    category: category,
                    onBack: { step = .category },
                    onConfirm: save
                )
            case .done:
                WatchDoneView(onFinish: reset)
            }
        }
        .navigationTitle("Log")
    }

    private func save() {
        model.logExpense(amount: amount, categoryID: category?.id, title: "")
        WKInterfaceDevice.current().play(.success)
        step = .done
    }

    private func reset() {
        amountText = ""
        category = nil
        step = .keypad
    }
}

// MARK: - Keypad

struct WatchKeypadView: View {
    @Binding var text: String
    let currencyCode: String
    let canContinue: Bool
    let onNext: () -> Void

    private var fractionDigits: Int { MoneyFormat.fractionDigits(for: currencyCode) }

    private var display: String {
        let symbol = MoneyFormat.symbol(for: currencyCode)
        return symbol + (text.isEmpty ? "0" : text)
    }

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        [".", "0", "delete"]
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(display)
                    .font(WatchFonts.serif(30))
                    .foregroundStyle(text.isEmpty ? WatchPalette.inkSecondary : WatchPalette.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                ForEach(0..<rows.count, id: \.self) { index in
                    HStack(spacing: 6) {
                        ForEach(rows[index], id: \.self) { key in
                            keyButton(key)
                        }
                    }
                }
                Button(action: onNext) {
                    Text("Next")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WatchPalette.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(canContinue ? WatchPalette.accent : WatchPalette.sunken)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canContinue)
                .padding(.top, 4)
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        Button {
            press(key)
        } label: {
            Group {
                if key == "delete" {
                    Image(systemName: "delete.left")
                        .font(.system(size: 15, weight: .medium))
                } else {
                    Text(key)
                        .font(WatchFonts.serif(20, weight: .medium))
                }
            }
            .foregroundStyle(WatchPalette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WatchPalette.surface)
            )
        }
        .buttonStyle(.plain)
        .opacity(key == "." && fractionDigits == 0 ? 0.3 : 1)
        .disabled(key == "." && fractionDigits == 0)
    }

    private func press(_ key: String) {
        switch key {
        case "delete":
            if !text.isEmpty { text.removeLast() }
        case ".":
            guard fractionDigits > 0, !text.contains(".") else { return }
            text = text.isEmpty ? "0." : text + "."
        default:
            appendDigit(key)
        }
    }

    private func appendDigit(_ digit: String) {
        guard text.count < 9 else { return }
        if let dot = text.firstIndex(of: ".") {
            let fraction = text.distance(from: dot, to: text.endIndex) - 1
            guard fraction < fractionDigits else { return }
            text += digit
        } else if text == "0" {
            text = digit
        } else {
            text += digit
        }
    }
}

// MARK: - Category

struct WatchCategoryPickerView: View {
    let categories: [BudgetSnapshot.QuickCategory]
    let onBack: () -> Void
    let onPick: (BudgetSnapshot.QuickCategory?) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Amount")
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(WatchPalette.inkSecondary)
                }
                .buttonStyle(.plain)

                Text("Pick a category")
                    .font(WatchFonts.serif(16))
                    .foregroundStyle(WatchPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(categories) { item in
                    Button {
                        onPick(item)
                    } label: {
                        WatchPickRow(symbol: item.symbol, name: item.name, tint: Color(watchHex: item.colorHex))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    onPick(nil)
                } label: {
                    WatchPickRow(symbol: "tag", name: "No category", tint: WatchPalette.inkSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
        }
    }
}

struct WatchPickRow: View {
    let symbol: String
    let name: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(WatchPalette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WatchPalette.surface)
        )
    }
}

// MARK: - Confirm and done

struct WatchConfirmView: View {
    let amount: Decimal
    let currencyCode: String
    let category: BudgetSnapshot.QuickCategory?
    let onBack: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(MoneyFormat.string(amount, currencyCode: currencyCode))
                    .font(WatchFonts.serif(30))
                    .foregroundStyle(WatchPalette.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(category?.name ?? "No category")
                    .font(.system(size: 14))
                    .foregroundStyle(WatchPalette.inkSecondary)
                Rectangle().fill(WatchPalette.rule).frame(height: 1)
                Button(action: onConfirm) {
                    Text("Log expense")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WatchPalette.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(WatchPalette.accent)
                        )
                }
                .buttonStyle(.plain)
                Button(action: onBack) {
                    Text("Change category")
                        .font(.system(size: 13))
                        .foregroundStyle(WatchPalette.inkSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
        }
    }
}

struct WatchDoneView: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(WatchPalette.accent)
            Text("Logged")
                .font(WatchFonts.serif(18))
                .foregroundStyle(WatchPalette.ink)
            Text("Sent to your iPhone")
                .font(.system(size: 12))
                .foregroundStyle(WatchPalette.inkSecondary)
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            onFinish()
        }
    }
}
