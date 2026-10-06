import XCTest
@testable import TallyCore

final class StatementImporterTests: XCTestCase {
    private func amount(_ text: String, separator: Character? = nil) -> Decimal? {
        StatementImporter.parseAmount(text, decimalSeparator: separator)
    }

    // MARK: parseAmount

    func testParseAmount_englishThousandsAndDecimals() {
        XCTAssertEqual(amount("1,234.56"), dec("1234.56"))
        XCTAssertEqual(amount("12,345,678.90"), dec("12345678.90"))
        XCTAssertEqual(amount("0.99"), dec("0.99"))
        XCTAssertEqual(amount("1234.5"), dec("1234.5"))
    }

    func testParseAmount_europeanThousandsAndDecimals() {
        XCTAssertEqual(amount("1.234,56"), dec("1234.56"))
        XCTAssertEqual(amount("1.234.567,89"), dec("1234567.89"))
        XCTAssertEqual(amount("12,50"), dec("12.50"))
        XCTAssertEqual(amount("0,5"), dec("0.5"))
    }

    func testParseAmount_negativeWithCurrencySuffix() {
        XCTAssertEqual(amount("-45,00 kr"), dec("-45.00"))
        XCTAssertEqual(amount("-45.00 USD"), dec("-45.00"))
    }

    func testParseAmount_parenthesesMeanNegative() {
        XCTAssertEqual(amount("(12.00)"), dec("-12.00"))
        XCTAssertEqual(amount("(1,234.50)"), dec("-1234.50"))
        XCTAssertEqual(amount("($5)"), dec("-5"))
    }

    func testParseAmount_currencySymbolsAndSigns() {
        XCTAssertEqual(amount("$5"), dec("5"))
        XCTAssertEqual(amount("-$5.25"), dec("-5.25"))
        XCTAssertEqual(amount("€ 7,50"), dec("7.50"))
        XCTAssertEqual(amount("+10.00"), dec("10.00"))
        XCTAssertEqual(amount("  42  "), dec("42"))
    }

    func testParseAmount_spaceAsThousandsSeparator() {
        XCTAssertEqual(amount("1 234,56"), dec("1234.56"))
        XCTAssertEqual(amount("-1 234,56"), dec("-1234.56"))
        XCTAssertEqual(amount("1\u{00A0}234,56"), dec("1234.56"))
    }

    func testParseAmount_unicodeMinusAndTrailingMinus() {
        XCTAssertEqual(amount("\u{2212}45.00"), dec("-45.00"))
        XCTAssertEqual(amount("45.00-"), dec("-45.00"))
    }

    func testParseAmount_emptyAndNonNumericAreNil() {
        XCTAssertNil(amount(""))
        XCTAssertNil(amount("   "))
        XCTAssertNil(amount("abc"))
        XCTAssertNil(amount("-"))
        XCTAssertNil(amount("kr"))
        XCTAssertNil(amount("."))
        XCTAssertNil(amount(","))
    }

    func testParseAmount_integers() {
        XCTAssertEqual(amount("100"), dec("100"))
        XCTAssertEqual(amount("-7"), dec("-7"))
        XCTAssertEqual(amount("0"), dec("0"))
    }

    func testParseAmount_groupingOnlyThreeDigitGroups() {
        XCTAssertEqual(amount("1,234"), dec("1234"))
        XCTAssertEqual(amount("1.234.567"), dec("1234567"))
        XCTAssertEqual(amount("12,345,678"), dec("12345678"))
    }

    func testParseAmount_explicitDecimalSeparator() {
        XCTAssertEqual(amount("1.234,56", separator: ","), dec("1234.56"))
        XCTAssertEqual(amount("1,234.56", separator: "."), dec("1234.56"))
        XCTAssertEqual(amount("1.234", separator: ","), dec("1234"))
        XCTAssertEqual(amount("1.234", separator: "."), dec("1.234"))
        XCTAssertEqual(amount("12,5", separator: ","), dec("12.5"))
    }

    /// A leading zero can never start a thousands group, so "0.123" is a fraction.
    /// The importer's "one dot followed by three digits means thousands" heuristic reads it as 123.
    func testParseAmount_leadingZeroWithThreeDecimalsIsAFraction() {
        XCTAssertEqual(amount("0.123"), dec("0.123"))
        XCTAssertEqual(amount("0,123"), dec("0.123"))
    }

    // MARK: parseDate

    func testParseDate_explicitFormats() throws {
        let iso = try XCTUnwrap(StatementImporter.parseDate("2024-03-15", format: "yyyy-MM-dd"))
        XCTAssertEqual(localYMD(iso), [2024, 3, 15])
        let dotted = try XCTUnwrap(StatementImporter.parseDate("15.03.2024", format: "dd.MM.yyyy"))
        XCTAssertEqual(localYMD(dotted), [2024, 3, 15])
        let us = try XCTUnwrap(StatementImporter.parseDate("03/15/2024", format: "MM/dd/yyyy"))
        XCTAssertEqual(localYMD(us), [2024, 3, 15])
        let compact = try XCTUnwrap(StatementImporter.parseDate("20240315", format: "yyyyMMdd"))
        XCTAssertEqual(localYMD(compact), [2024, 3, 15])
    }

    func testParseDate_explicitFormatDoesNotFallBackToOthers() {
        XCTAssertNil(StatementImporter.parseDate("2024-03-15", format: "dd.MM.yyyy"))
        XCTAssertNil(StatementImporter.parseDate("15.03.2024", format: "yyyy-MM-dd"))
    }

    func testParseDate_explicitFormatDayFirstVersusMonthFirst() throws {
        let dayFirst = try XCTUnwrap(StatementImporter.parseDate("01/02/2024", format: "dd/MM/yyyy"))
        XCTAssertEqual(localYMD(dayFirst), [2024, 2, 1])
        let monthFirst = try XCTUnwrap(StatementImporter.parseDate("01/02/2024", format: "MM/dd/yyyy"))
        XCTAssertEqual(localYMD(monthFirst), [2024, 1, 2])
    }

    func testParseDate_autoFormats() throws {
        let cases: [(String, [Int])] = [
            ("2024-03-15", [2024, 3, 15]),
            ("2024/03/15", [2024, 3, 15]),
            ("15/03/2024", [2024, 3, 15]),
            ("03/15/2024", [2024, 3, 15]),
            ("15.03.2024", [2024, 3, 15]),
            ("15-03-2024", [2024, 3, 15]),
            ("20240315", [2024, 3, 15]),
            ("2024-03-15 13:45:00", [2024, 3, 15])
        ]
        for (text, expected) in cases {
            let parsed = try XCTUnwrap(StatementImporter.parseDate(text, format: nil), text)
            XCTAssertEqual(localYMD(parsed), expected, text)
        }
    }

    func testParseDate_ambiguousDayMonthPrefersDayFirst() throws {
        // dd/MM/yyyy is listed before MM/dd/yyyy in the common formats.
        let parsed = try XCTUnwrap(StatementImporter.parseDate("01/02/2024", format: nil))
        XCTAssertEqual(localYMD(parsed), [2024, 2, 1])
    }

    func testParseDate_trimsWhitespace() throws {
        let parsed = try XCTUnwrap(StatementImporter.parseDate("  2024-03-15\n", format: "yyyy-MM-dd"))
        XCTAssertEqual(localYMD(parsed), [2024, 3, 15])
    }

    func testParseDate_invalidInputsAreNil() {
        XCTAssertNil(StatementImporter.parseDate("", format: nil))
        XCTAssertNil(StatementImporter.parseDate("   ", format: nil))
        XCTAssertNil(StatementImporter.parseDate("not a date", format: nil))
        XCTAssertNil(StatementImporter.parseDate("2024-13-45", format: "yyyy-MM-dd"))
        XCTAssertNil(StatementImporter.parseDate("2024-02-30", format: "yyyy-MM-dd"))
    }

    func testCommonDateFormatsStartWithISO() {
        XCTAssertEqual(StatementImporter.commonDateFormats.first, "yyyy-MM-dd")
        XCTAssertTrue(StatementImporter.commonDateFormats.contains("dd/MM/yyyy"))
        XCTAssertTrue(StatementImporter.commonDateFormats.contains("MM/dd/yyyy"))
    }

    // MARK: suggestMapping

    func testSuggestMapping_englishHeader() {
        let rows = [
            ["Date", "Description", "Amount"],
            ["2024-01-05", "Coffee", "-3.50"],
            ["2024-01-06", "Salary", "2500.00"]
        ]
        let mapping = StatementImporter.suggestMapping(for: rows)
        XCTAssertTrue(mapping.hasHeader)
        XCTAssertEqual(mapping.dateColumn, 0)
        XCTAssertEqual(mapping.descriptionColumn, 1)
        XCTAssertEqual(mapping.amountColumn, 2)
        XCTAssertNil(mapping.debitColumn)
        XCTAssertNil(mapping.creditColumn)
        XCTAssertEqual(mapping.dateFormat, "yyyy-MM-dd")
    }

    func testSuggestMapping_headerColumnsInADifferentOrder() {
        let rows = [
            ["Amount", "Payee", "Posted Date"],
            ["-3.50", "Coffee", "05/01/2024"]
        ]
        let mapping = StatementImporter.suggestMapping(for: rows)
        XCTAssertTrue(mapping.hasHeader)
        XCTAssertEqual(mapping.amountColumn, 0)
        XCTAssertEqual(mapping.descriptionColumn, 1)
        XCTAssertEqual(mapping.dateColumn, 2)
        XCTAssertEqual(mapping.dateFormat, "dd/MM/yyyy")
    }

    func testSuggestMapping_debitCreditHeader() {
        let rows = [
            ["Date", "Description", "Debit", "Credit", "Balance"],
            ["2024-01-05", "Rent", "1000.00", "", "500.00"],
            ["2024-01-06", "Pay", "", "2500.00", "3000.00"]
        ]
        let mapping = StatementImporter.suggestMapping(for: rows)
        XCTAssertTrue(mapping.hasHeader)
        XCTAssertNil(mapping.amountColumn)
        XCTAssertEqual(mapping.debitColumn, 2)
        XCTAssertEqual(mapping.creditColumn, 3)
        XCTAssertEqual(mapping.dateColumn, 0)
        XCTAssertEqual(mapping.descriptionColumn, 1)
    }

    func testSuggestMapping_withdrawalDepositHeader() {
        let rows = [["Transaction Date", "Memo", "Withdrawals", "Deposits"], ["2024-01-05", "ATM", "20.00", ""]]
        let mapping = StatementImporter.suggestMapping(for: rows)
        XCTAssertNil(mapping.amountColumn)
        XCTAssertEqual(mapping.debitColumn, 2)
        XCTAssertEqual(mapping.creditColumn, 3)
        XCTAssertEqual(mapping.descriptionColumn, 1)
    }

    func testSuggestMapping_swedishHeaders() {
        let single = StatementImporter.suggestMapping(for: [["Datum", "Beskrivning", "Belopp"], ["2024-01-05", "ICA", "-45,00"]])
        XCTAssertEqual(single.dateColumn, 0)
        XCTAssertEqual(single.descriptionColumn, 1)
        XCTAssertEqual(single.amountColumn, 2)

        let split = StatementImporter.suggestMapping(for: [["Datum", "Text", "Uttag", "Ins\u{00E4}ttning"], ["2024-01-05", "ICA", "45,00", ""]])
        XCTAssertNil(split.amountColumn)
        XCTAssertEqual(split.debitColumn, 2)
        XCTAssertEqual(split.creditColumn, 3)
    }

    func testSuggestMapping_headerlessFile() {
        let rows = [
            ["2024-01-05", "Coffee", "-3.50"],
            ["2024-01-06", "Lunch", "-12.00"]
        ]
        let mapping = StatementImporter.suggestMapping(for: rows)
        XCTAssertFalse(mapping.hasHeader)
        XCTAssertEqual(mapping.dateColumn, 0)
        XCTAssertEqual(mapping.amountColumn, 2)
        XCTAssertEqual(mapping.descriptionColumn, 1)
        XCTAssertEqual(mapping.dateFormat, "yyyy-MM-dd")
    }

    func testSuggestMapping_usDateFormatIsDetectedFromSamples() {
        let rows = [
            ["Date", "Description", "Amount"],
            ["01/15/2024", "A", "-1.00"],
            ["02/20/2024", "B", "-2.00"]
        ]
        XCTAssertEqual(StatementImporter.suggestMapping(for: rows).dateFormat, "MM/dd/yyyy")
    }

    func testSuggestMapping_noDateFormatWhenSamplesDoNotAgree() {
        let rows = [
            ["Date", "Description", "Amount"],
            ["2024-01-15", "A", "-1.00"],
            ["15.01.2024", "B", "-2.00"]
        ]
        XCTAssertNil(StatementImporter.suggestMapping(for: rows).dateFormat)
    }

    func testSuggestMapping_headerOnlyAndEmpty() {
        let headerOnly = StatementImporter.suggestMapping(for: [["Date", "Description", "Amount"]])
        XCTAssertTrue(headerOnly.hasHeader)
        XCTAssertNil(headerOnly.dateFormat)
        XCTAssertEqual(StatementImporter.suggestMapping(for: []), ImportColumnMapping())
    }

    /// "Value date" contains "value", which the amount heuristic also uses as a keyword, so the
    /// column order of a common bank layout (Booking date, Value date, Description, Amount)
    /// makes the importer pick the date column as the amount column.
    func testSuggestMapping_valueDateColumnIsNotTheAmountColumn() {
        let rows = [
            ["Booking date", "Value date", "Description", "Amount"],
            ["2024-01-05", "2024-01-06", "Coffee", "-3.50"]
        ]
        let mapping = StatementImporter.suggestMapping(for: rows)
        XCTAssertEqual(mapping.dateColumn, 0)
        XCTAssertEqual(mapping.descriptionColumn, 2)
        XCTAssertEqual(mapping.amountColumn, 3)
    }

    // MARK: importRows

    func testImportRows_basicWithHeader() throws {
        let rows = [
            ["Date", "Description", "Amount"],
            ["2024-01-05", "  Coffee  ", "-3.50"],
            ["2024-01-06", "Salary", "2,500.00"]
        ]
        let mapping = StatementImporter.suggestMapping(for: rows)
        let result = StatementImporter.importRows(rows, mapping: mapping)
        XCTAssertTrue(result.failedRows.isEmpty)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows[0].description, "Coffee")
        XCTAssertEqual(result.rows[0].amount, dec("-3.50"))
        XCTAssertEqual(localYMD(result.rows[0].date), [2024, 1, 5])
        XCTAssertEqual(result.rows[1].amount, dec("2500"))
        XCTAssertEqual(result.rows[1].id, result.rows[1].fingerprint)
    }

    func testImportRows_invertSign() {
        let rows = [
            ["Date", "Description", "Amount"],
            ["2024-01-05", "Coffee", "3.50"],
            ["2024-01-06", "Refund", "-10.00"]
        ]
        var mapping = StatementImporter.suggestMapping(for: rows)
        mapping.invertSign = true
        let result = StatementImporter.importRows(rows, mapping: mapping)
        XCTAssertEqual(result.rows.map(\.amount), [dec("-3.50"), dec("10.00")])

        mapping.invertSign = false
        let plain = StatementImporter.importRows(rows, mapping: mapping)
        XCTAssertEqual(plain.rows.map(\.amount), [dec("3.50"), dec("-10.00")])
    }

    func testImportRows_failedRowsAreReportedBySourceIndex() {
        let rows = [
            ["Date", "Description", "Amount"],   // 0: header, skipped (not a failure)
            ["2024-01-05", "OK one", "-1.00"],   // 1
            ["yesterday", "Bad date", "-2.00"],  // 2
            ["2024-01-07", "No amount", ""],     // 3
            ["2024-01-08", "Zero", "0.00"],      // 4
            ["2024-01-09"],                      // 5: too short
            ["2024-01-10", "OK two", "-5.00"]    // 6
        ]
        var mapping = ImportColumnMapping()
        mapping.dateFormat = "yyyy-MM-dd"
        let result = StatementImporter.importRows(rows, mapping: mapping)
        XCTAssertEqual(result.failedRows, [2, 3, 4, 5])
        XCTAssertEqual(result.rows.map(\.description), ["OK one", "OK two"])
    }

    func testImportRows_withoutHeaderFirstRowIsData() {
        let rows = [
            ["2024-01-05", "Coffee", "-3.50"],
            ["2024-01-06", "Lunch", "-12.00"]
        ]
        let mapping = StatementImporter.suggestMapping(for: rows)
        XCTAssertFalse(mapping.hasHeader)
        let result = StatementImporter.importRows(rows, mapping: mapping)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertTrue(result.failedRows.isEmpty)
    }

    func testImportRows_headerRowIsFailureWhenMappingSaysNoHeader() {
        let rows = [["Date", "Description", "Amount"], ["2024-01-05", "Coffee", "-3.50"]]
        var mapping = ImportColumnMapping()
        mapping.hasHeader = false
        let result = StatementImporter.importRows(rows, mapping: mapping)
        XCTAssertEqual(result.failedRows, [0])
        XCTAssertEqual(result.rows.count, 1)
    }

    func testImportRows_debitAndCreditColumns() {
        let rows = [
            ["Date", "Description", "Debit", "Credit"],
            ["2024-01-05", "Rent", "1,000.00", ""],
            ["2024-01-06", "Pay", "", "2,500.00"],
            ["2024-01-07", "Both", "10.00", "4.00"],
            ["2024-01-08", "Negative debit", "-12.00", ""],
            ["2024-01-09", "Nothing", "", ""]
        ]
        let mapping = StatementImporter.suggestMapping(for: rows)
        XCTAssertNil(mapping.amountColumn)
        let result = StatementImporter.importRows(rows, mapping: mapping)
        XCTAssertEqual(result.rows.map(\.amount), [dec("-1000"), dec("2500"), dec("-6"), dec("-12")])
        XCTAssertEqual(result.failedRows, [5])
    }

    func testImportRows_decimalSeparatorFromMapping() {
        let rows = [["Date", "Description", "Amount"], ["2024-01-05", "Shop", "1.234,56"], ["2024-01-06", "Cafe", "12,5"]]
        var mapping = StatementImporter.suggestMapping(for: rows)
        mapping.decimalSeparator = ","
        let result = StatementImporter.importRows(rows, mapping: mapping)
        XCTAssertEqual(result.rows.map(\.amount), [dec("1234.56"), dec("12.5")])
    }

    func testImportRows_fromParsedSemicolonCSV() {
        let text = "Datum;Beskrivning;Belopp\n2024-01-05;ICA Maxi;-1 234,56 kr\n2024-01-06;L\u{00F6}n;25 000,00\n"
        let rows = CSV.parse(text)
        let mapping = StatementImporter.suggestMapping(for: rows)
        let result = StatementImporter.importRows(rows, mapping: mapping)
        XCTAssertEqual(result.rows.map(\.amount), [dec("-1234.56"), dec("25000")])
        XCTAssertEqual(result.rows.map(\.description), ["ICA Maxi", "L\u{00F6}n"])
        XCTAssertTrue(result.failedRows.isEmpty)
    }

    func testImportRows_emptyInput() {
        let result = StatementImporter.importRows([], mapping: ImportColumnMapping())
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertTrue(result.failedRows.isEmpty)
    }

    // MARK: Fingerprints

    func testFingerprintIsStableAndNormalisesDescription() throws {
        let day = try XCTUnwrap(StatementImporter.parseDate("2024-01-05", format: "yyyy-MM-dd"))
        let a = ImportedRow(date: day, description: "  COFFEE ", amount: dec("-3.50"))
        let b = ImportedRow(date: day, description: "coffee", amount: dec("-3.5"))
        XCTAssertEqual(a.fingerprint, b.fingerprint)
        XCTAssertEqual(a.id, a.fingerprint)
        XCTAssertTrue(a.fingerprint.hasPrefix("2024-01-05|"), a.fingerprint)
        XCTAssertTrue(a.fingerprint.hasSuffix("|coffee"), a.fingerprint)
        XCTAssertTrue(a.fingerprint.contains("|-3.5|"), a.fingerprint)
    }

    func testFingerprintDiffersByAmountDescriptionAndDay() throws {
        let day = try XCTUnwrap(StatementImporter.parseDate("2024-01-05", format: "yyyy-MM-dd"))
        let nextDay = try XCTUnwrap(StatementImporter.parseDate("2024-01-06", format: "yyyy-MM-dd"))
        let base = ImportedRow.fingerprint(date: day, description: "Coffee", amount: dec("-3.50"))
        XCTAssertNotEqual(base, ImportedRow.fingerprint(date: day, description: "Coffee", amount: dec("-3.51")))
        XCTAssertNotEqual(base, ImportedRow.fingerprint(date: day, description: "Tea", amount: dec("-3.50")))
        XCTAssertNotEqual(base, ImportedRow.fingerprint(date: nextDay, description: "Coffee", amount: dec("-3.50")))
    }

    func testFingerprintIgnoresTimeOfDay() throws {
        let morning = try XCTUnwrap(StatementImporter.parseDate("2024-01-05 08:00:00", format: "yyyy-MM-dd HH:mm:ss"))
        let evening = try XCTUnwrap(StatementImporter.parseDate("2024-01-05 20:00:00", format: "yyyy-MM-dd HH:mm:ss"))
        XCTAssertEqual(
            ImportedRow.fingerprint(date: morning, description: "x", amount: dec("1")),
            ImportedRow.fingerprint(date: evening, description: "x", amount: dec("1"))
        )
    }

    // MARK: OFX

    private let sgmlSample = """
    OFXHEADER:100
    DATA:OFXSGML
    VERSION:102

    <OFX>
    <BANKMSGSRSV1>
    <STMTTRNRS>
    <STMTRS>
    <BANKTRANLIST>
    <STMTTRN>
    <TRNTYPE>DEBIT
    <DTPOSTED>20240105120000[0:GMT]
    <TRNAMT>-45.67
    <FITID>0001
    <NAME>COFFEE SHOP
    <MEMO>Card purchase
    </STMTTRN>
    <STMTTRN>
    <TRNTYPE>CREDIT
    <DTPOSTED>20240110
    <TRNAMT>1500.00
    <FITID>0002
    <MEMO>Salary January
    </STMTTRN>
    </BANKTRANLIST>
    </STMTRS>
    </STMTTRNRS>
    </BANKMSGSRSV1>
    </OFX>
    """

    func testParseOFX_sgmlWithTwoTransactions() {
        let rows = StatementImporter.parseOFX(sgmlSample)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].description, "COFFEE SHOP", "NAME wins over MEMO")
        XCTAssertEqual(rows[0].amount, dec("-45.67"))
        XCTAssertEqual(localYMD(rows[0].date), [2024, 1, 5])
        XCTAssertEqual(rows[1].description, "Salary January", "MEMO is the fallback when NAME is missing")
        XCTAssertEqual(rows[1].amount, dec("1500.00"))
        XCTAssertEqual(localYMD(rows[1].date), [2024, 1, 10])
    }

    func testParseOFX_crlfLineEndings() {
        let crlf = sgmlSample.replacingOccurrences(of: "\n", with: "\r\n")
        let rows = StatementImporter.parseOFX(crlf)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.description), ["COFFEE SHOP", "Salary January"])
        XCTAssertEqual(rows.map(\.amount), [dec("-45.67"), dec("1500.00")])
    }

    func testParseOFX_xmlFlavourOnOneLine() {
        let xml = "<OFX><STMTTRN><DTPOSTED>20240301</DTPOSTED><TRNAMT>-9.99</TRNAMT><NAME>Streaming</NAME></STMTTRN>"
            + "<STMTTRN><DTPOSTED>20240302</DTPOSTED><TRNAMT>20.00</TRNAMT><NAME>Refund</NAME></STMTTRN></OFX>"
        let rows = StatementImporter.parseOFX(xml)
        XCTAssertEqual(rows.map(\.description), ["Streaming", "Refund"])
        XCTAssertEqual(rows.map(\.amount), [dec("-9.99"), dec("20.00")])
    }

    func testParseOFX_incompleteTransactionsAreSkipped() {
        let text = """
        <STMTTRN>
        <DTPOSTED>20240105
        <NAME>No amount
        </STMTTRN>
        <STMTTRN>
        <TRNAMT>-5.00
        <NAME>No date
        </STMTTRN>
        <STMTTRN>
        <DTPOSTED>garbage
        <TRNAMT>-5.00
        </STMTTRN>
        <STMTTRN>
        <DTPOSTED>20240106
        <TRNAMT>-7.25
        </STMTTRN>
        """
        let rows = StatementImporter.parseOFX(text)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].amount, dec("-7.25"))
        XCTAssertEqual(rows[0].description, "")
    }

    func testParseOFX_withoutTransactionsIsEmpty() {
        XCTAssertTrue(StatementImporter.parseOFX("").isEmpty)
        XCTAssertTrue(StatementImporter.parseOFX("<OFX></OFX>").isEmpty)
    }

    func testTagValueHelper() {
        XCTAssertEqual(StatementImporter.tagValue("NAME", in: "<NAME>Foo Bar\n<MEMO>x"), "Foo Bar")
        XCTAssertEqual(StatementImporter.tagValue("NAME", in: "<NAME>Foo</NAME>"), "Foo")
        XCTAssertEqual(StatementImporter.tagValue("NAME", in: "<NAME>  padded  \r\n"), "padded")
        XCTAssertNil(StatementImporter.tagValue("NAME", in: "<MEMO>x"))
        XCTAssertNil(StatementImporter.tagValue("NAME", in: "<NAME>\n<MEMO>x"))
    }

    func testParseOFXDateUsesFirstEightCharacters() throws {
        let parsed = try XCTUnwrap(StatementImporter.parseOFXDate("20240229235959.000[-5:EST]"))
        XCTAssertEqual(localYMD(parsed), [2024, 2, 29])
        XCTAssertNil(StatementImporter.parseOFXDate(""))
    }

    // MARK: ImportColumnMapping defaults

    func testMappingDefaults() {
        let mapping = ImportColumnMapping()
        XCTAssertTrue(mapping.hasHeader)
        XCTAssertEqual(mapping.dateColumn, 0)
        XCTAssertEqual(mapping.descriptionColumn, 1)
        XCTAssertEqual(mapping.amountColumn, 2)
        XCTAssertNil(mapping.debitColumn)
        XCTAssertNil(mapping.creditColumn)
        XCTAssertNil(mapping.dateFormat)
        XCTAssertNil(mapping.decimalSeparator)
        XCTAssertFalse(mapping.invertSign)
    }

    func testSafeSubscript() {
        let values = [10, 20, 30]
        XCTAssertEqual(values[safe: 0], 10)
        XCTAssertEqual(values[safe: 2], 30)
        XCTAssertNil(values[safe: 3])
        XCTAssertNil(values[safe: -1])
    }
}
