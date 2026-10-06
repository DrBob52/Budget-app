import Foundation
import TallyCore

/// Turns the ledger into a CSV file the user can share.
enum ExportService {
    static let header: [String] = [
        "Date", "Type", "Title", "Category", "Account", "To account",
        "Amount", "Currency", "Note", "Paid by"
    ]

    /// CSV text for the given transactions, oldest first.
    static func csv(transactions: [Transaction], settings: AppSettings) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let currency = settings.currencyCode
        let digits = MoneyFormat.fractionDigits(for: currency)
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = Locale(identifier: "en_US_POSIX")
        numberFormatter.numberStyle = .decimal
        numberFormatter.usesGroupingSeparator = false
        numberFormatter.minimumFractionDigits = digits
        numberFormatter.maximumFractionDigits = digits

        var rows: [[String]] = [header]
        let sorted = transactions.sorted { $0.date < $1.date }
        for transaction in sorted {
            let amountText = numberFormatter.string(from: transaction.amount as NSDecimalNumber) ?? "\(transaction.amount)"
            rows.append([
                dayFormatter.string(from: transaction.date),
                transaction.kind.displayName,
                transaction.title,
                transaction.category?.name ?? "",
                transaction.account?.name ?? "",
                transaction.toAccount?.name ?? "",
                amountText,
                currency,
                transaction.note,
                transaction.paidBy?.name ?? ""
            ])
        }
        return CSV.make(rows: rows)
    }

    /// "tally-transactions-2026-10-06.csv"
    static func fileName(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return "tally-transactions-\(formatter.string(from: date)).csv"
    }

    /// Writes the CSV to a temporary file and returns its URL, or nil if writing fails.
    static func writeCSV(transactions: [Transaction], settings: AppSettings) -> URL? {
        let text = csv(transactions: transactions, settings: settings)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName())
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
