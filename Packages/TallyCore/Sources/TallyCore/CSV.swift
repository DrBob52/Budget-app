import Foundation

public enum CSV {
    /// Picks the delimiter that appears most often in the first line: comma, semicolon or tab.
    public static func detectDelimiter(in text: String) -> Character {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let candidates: [Character] = [",", ";", "\t"]
        return candidates.max { a, b in
            firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count
        } ?? ","
    }

    /// RFC 4180 parsing: quoted fields, escaped quotes ("") and newlines inside quotes.
    /// Blank lines are skipped.
    public static func parse(_ text: String, delimiter: Character? = nil) -> [[String]] {
        let delimiter = delimiter ?? detectDelimiter(in: text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func nextChar() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        func endRow() {
            row.append(field)
            field = ""
            if !(row.count == 1 && row[0].isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while let char = nextChar() {
            if inQuotes {
                if char == "\"" {
                    if let following = nextChar() {
                        if following == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = following
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else if char == "\"" && field.isEmpty {
                inQuotes = true
            } else if char == delimiter {
                row.append(field)
                field = ""
            } else if char == "\n" || char == "\r\n" || char == "\r" {
                endRow()
            } else {
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            endRow()
        }
        return rows
    }

    public static func escape(_ field: String, delimiter: Character = ",") -> String {
        // Check scalars: "\r\n" is a single Character, so Character-based checks miss it.
        let needsQuotes = field.unicodeScalars.contains { scalar in
            scalar == "\"" || scalar == "\n" || scalar == "\r" || delimiter.unicodeScalars.contains(scalar)
        }
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func make(rows: [[String]], delimiter: Character = ",") -> String {
        rows.map { $0.map { escape($0, delimiter: delimiter) }.joined(separator: String(delimiter)) }
            .joined(separator: "\n") + "\n"
    }
}

/// Which columns of a bank export hold which values.
public struct ImportColumnMapping: Equatable, Sendable {
    public var hasHeader: Bool
    public var dateColumn: Int
    public var descriptionColumn: Int
    /// Single signed amount column (negative = money out).
    public var amountColumn: Int?
    /// Separate money-out / money-in columns, used when `amountColumn` is nil.
    public var debitColumn: Int?
    public var creditColumn: Int?
    /// e.g. "yyyy-MM-dd". Nil tries common formats.
    public var dateFormat: String?
    /// "," for most European banks. Nil guesses per value.
    public var decimalSeparator: Character?
    /// Flip signs for banks that export spending as positive numbers.
    public var invertSign: Bool

    public init(
        hasHeader: Bool = true,
        dateColumn: Int = 0,
        descriptionColumn: Int = 1,
        amountColumn: Int? = 2,
        debitColumn: Int? = nil,
        creditColumn: Int? = nil,
        dateFormat: String? = nil,
        decimalSeparator: Character? = nil,
        invertSign: Bool = false
    ) {
        self.hasHeader = hasHeader
        self.dateColumn = dateColumn
        self.descriptionColumn = descriptionColumn
        self.amountColumn = amountColumn
        self.debitColumn = debitColumn
        self.creditColumn = creditColumn
        self.dateFormat = dateFormat
        self.decimalSeparator = decimalSeparator
        self.invertSign = invertSign
    }
}

public struct ImportedRow: Hashable, Identifiable, Sendable {
    public var date: Date
    public var description: String
    /// Signed: negative = expense, positive = income.
    public var amount: Decimal
    /// Stable key used to skip rows that were already imported.
    public var fingerprint: String
    public var id: String { fingerprint }

    public init(date: Date, description: String, amount: Decimal) {
        self.date = date
        self.description = description
        self.amount = amount
        self.fingerprint = ImportedRow.fingerprint(date: date, description: description, amount: amount)
    }

    public static func fingerprint(date: Date, description: String, amount: Decimal) -> String {
        let day = ISO8601DateFormatter.dayOnly.string(from: date)
        let text = description.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(day)|\(amount)|\(text)"
    }
}

public struct ImportResult: Sendable {
    public var rows: [ImportedRow]
    /// 0-based indexes of source rows that couldn't be read.
    public var failedRows: [Int]
}

extension ISO8601DateFormatter {
    static let dayOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        return formatter
    }()
}

public enum StatementImporter {
    public static let commonDateFormats = [
        "yyyy-MM-dd", "yyyy/MM/dd", "dd/MM/yyyy", "MM/dd/yyyy", "dd.MM.yyyy",
        "d/M/yyyy", "M/d/yyyy", "dd-MM-yyyy", "yyyyMMdd", "yyyy-MM-dd HH:mm:ss", "MM/dd/yy", "dd/MM/yy"
    ]

    /// Guesses a mapping from header names (English and Swedish) and column contents.
    public static func suggestMapping(for rows: [[String]]) -> ImportColumnMapping {
        var mapping = ImportColumnMapping()
        guard let first = rows.first else { return mapping }
        let header = first.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let looksLikeHeader = parseDate(first.first ?? "", format: nil) == nil

        func find(_ keys: [String], rejecting rejected: [String] = []) -> Int? {
            header.firstIndex { name in
                keys.contains { name.contains($0) } && !rejected.contains { name.contains($0) }
            }
        }

        mapping.hasHeader = looksLikeHeader
        if looksLikeHeader {
            mapping.dateColumn = find(["date", "datum", "posted", "booking"]) ?? 0
            mapping.descriptionColumn = find(["description", "text", "payee", "merchant", "name", "memo", "beskrivning", "mottagare", "details"]) ?? 1
            if let debit = find(["debit", "withdrawal", "money out", "paid out", "uttag"], rejecting: ["date"]),
               let credit = find(["credit", "deposit", "money in", "paid in", "insättning"], rejecting: ["date"]) {
                mapping.amountColumn = nil
                mapping.debitColumn = debit
                mapping.creditColumn = credit
            } else {
                mapping.amountColumn = find(["amount", "belopp", "value", "sum"], rejecting: ["date", "datum", "balance", "saldo"]) ?? min(2, max(first.count - 1, 0))
            }
        } else {
            mapping.dateColumn = 0
            let sample = first
            mapping.amountColumn = sample.indices.last { parseAmount(sample[$0], decimalSeparator: nil) != nil && $0 != 0 }
            mapping.descriptionColumn = sample.indices.first { $0 != mapping.dateColumn && $0 != mapping.amountColumn } ?? 1
        }

        let dataRows = mapping.hasHeader ? Array(rows.dropFirst()) : rows
        let dateSamples = dataRows.prefix(20).compactMap { $0[safe: mapping.dateColumn] }
        mapping.dateFormat = commonDateFormats.first { format in
            !dateSamples.isEmpty && dateSamples.allSatisfy { parseDate($0, format: format) != nil }
        }
        return mapping
    }

    public static func importRows(_ rows: [[String]], mapping: ImportColumnMapping) -> ImportResult {
        var imported: [ImportedRow] = []
        var failed: [Int] = []
        for (index, row) in rows.enumerated() {
            if index == 0 && mapping.hasHeader { continue }
            guard let dateText = row[safe: mapping.dateColumn],
                  let date = parseDate(dateText, format: mapping.dateFormat) else {
                failed.append(index)
                continue
            }
            let description = row[safe: mapping.descriptionColumn]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            var amount: Decimal?
            if let column = mapping.amountColumn {
                amount = row[safe: column].flatMap { parseAmount($0, decimalSeparator: mapping.decimalSeparator) }
            } else {
                let debit = mapping.debitColumn.flatMap { row[safe: $0] }.flatMap { parseAmount($0, decimalSeparator: mapping.decimalSeparator) }
                let credit = mapping.creditColumn.flatMap { row[safe: $0] }.flatMap { parseAmount($0, decimalSeparator: mapping.decimalSeparator) }
                if debit != nil || credit != nil {
                    amount = (credit?.magnitudeValue ?? 0) - (debit?.magnitudeValue ?? 0)
                }
            }
            guard var value = amount, value != 0 else {
                failed.append(index)
                continue
            }
            if mapping.invertSign { value = -value }
            imported.append(ImportedRow(date: date, description: description, amount: value))
        }
        return ImportResult(rows: imported, failedRows: failed)
    }

    /// Reads "1,234.56", "1 234,56", "-45,00 kr", "(12.00)", "$5". Returns nil for blanks.
    public static func parseAmount(_ text: String, decimalSeparator: Character?) -> Decimal? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") {
            negative = true
            s = String(s.dropFirst().dropLast())
        }
        s = s.replacingOccurrences(of: "\u{2212}", with: "-") // unicode minus
        if s.contains("-") { negative.toggle() }
        s = String(s.filter { $0.isNumber || $0 == "." || $0 == "," })
        guard !s.isEmpty, s.contains(where: \.isNumber) else { return nil }

        let separator: Character
        if let decimalSeparator {
            separator = decimalSeparator
        } else {
            // The last "." or "," followed by 1-2 digits is the decimal separator.
            let lastDot = s.lastIndex(of: ".")
            let lastComma = s.lastIndex(of: ",")
            switch (lastDot, lastComma) {
            case let (dot?, comma?):
                separator = dot > comma ? "." : ","
            case let (dot?, nil):
                separator = looksLikeGrouping(s, separator: ".", last: dot) ? "," : "."
            case let (nil, comma?):
                separator = looksLikeGrouping(s, separator: ",", last: comma) ? "." : ","
            case (nil, nil):
                separator = "."
            }
        }
        let grouping: Character = separator == "." ? "," : "."
        s = String(s.filter { $0 != grouping })
        if separator == "," {
            s = s.replacingOccurrences(of: ",", with: ".")
        }
        guard var value = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        if negative { value = -value }
        return value
    }

    /// With only one kind of separator present, it groups thousands when it appears more than
    /// once, or once with exactly three digits after it and a non-zero whole part ("1.234").
    /// "0.123" and "12.5" are decimals.
    static func looksLikeGrouping(_ s: String, separator: Character, last: String.Index) -> Bool {
        if s.filter({ $0 == separator }).count > 1 { return true }
        let digitsAfter = s.distance(from: last, to: s.endIndex) - 1
        let whole = s[..<last]
        let wholeIsZero = whole.isEmpty || whole.allSatisfy { $0 == "0" }
        return digitsAfter == 3 && !wholeIsZero
    }

    public static func parseDate(_ text: String, format: String?) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formats = format.map { [$0] } ?? commonDateFormats
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.isLenient = false
        for candidate in formats {
            formatter.dateFormat = candidate
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    /// Extracts transactions from an OFX/QFX statement (SGML or XML flavour).
    public static func parseOFX(_ text: String) -> [ImportedRow] {
        var rows: [ImportedRow] = []
        let blocks = text.components(separatedBy: "<STMTTRN>").dropFirst()
        for block in blocks {
            let body = block.components(separatedBy: "</STMTTRN>").first ?? block
            guard let amountText = tagValue("TRNAMT", in: body),
                  let amount = parseAmount(amountText, decimalSeparator: "."),
                  let dateText = tagValue("DTPOSTED", in: body),
                  let date = parseOFXDate(dateText) else { continue }
            let name = tagValue("NAME", in: body) ?? tagValue("MEMO", in: body) ?? ""
            rows.append(ImportedRow(date: date, description: name, amount: amount))
        }
        return rows
    }

    static func tagValue(_ tag: String, in body: String) -> String? {
        guard let range = body.range(of: "<\(tag)>") else { return nil }
        let rest = body[range.upperBound...]
        let end = rest.firstIndex { $0 == "<" || $0 == "\n" || $0 == "\r" } ?? rest.endIndex
        let value = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func parseOFXDate(_ text: String) -> Date? {
        let digits = String(text.prefix(8))
        return parseDate(digits, format: "yyyyMMdd")
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
