import Foundation

/// Shared identifiers used by the app, the widget extension and the watch app.
public enum AppGroup {
    public static let identifier = "group.com.tallybudget.shared"
}

public extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, mode)
        return result
    }

    /// The smallest money unit for a given number of fraction digits (0.01 for 2).
    static func unit(scale: Int) -> Decimal {
        Decimal(sign: .plus, exponent: -scale, significand: 1)
    }

    var isNegative: Bool { self < 0 }

    var magnitudeValue: Decimal { self < 0 ? -self : self }
}

public enum MoneyFormat {
    /// Formats an amount in the given ISO 4217 currency.
    /// - Parameters:
    ///   - showsSign: prefix positive values with "+".
    ///   - compact: drop the fraction digits (used for chart axes and hero numbers).
    public static func string(
        _ amount: Decimal,
        currencyCode: String,
        locale: Locale = .current,
        showsSign: Bool = false,
        compact: Bool = false
    ) -> String {
        var style = Decimal.FormatStyle.Currency(code: currencyCode, locale: locale)
        if compact {
            style = style.precision(.fractionLength(0))
        }
        if showsSign {
            style = style.sign(strategy: .always(showZero: false))
        }
        return amount.formatted(style)
    }

    /// Number of fraction digits the currency normally uses (JPY = 0, USD = 2).
    public static func fractionDigits(for currencyCode: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.maximumFractionDigits
    }

    /// Currency symbol for display next to input fields.
    public static func symbol(for currencyCode: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode
        return formatter.currencySymbol ?? currencyCode
    }
}

public struct CurrencyInfo: Identifiable, Hashable, Sendable {
    public let code: String
    public let name: String
    public var id: String { code }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

public enum CurrencyCatalog {
    public static var all: [CurrencyInfo] {
        let locale = Locale.current
        return Locale.commonISOCurrencyCodes
            .map { CurrencyInfo(code: $0, name: locale.localizedString(forCurrencyCode: $0) ?? $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static var defaultCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    public static func name(for code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }
}
