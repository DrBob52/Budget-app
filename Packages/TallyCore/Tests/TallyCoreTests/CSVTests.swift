import XCTest
@testable import TallyCore

final class CSVTests: XCTestCase {
    // MARK: Basic parsing

    func testParsesSimpleRows() {
        let rows = CSV.parse("a,b,c\n1,2,3\n")
        XCTAssertEqual(rows, [["a", "b", "c"], ["1", "2", "3"]])
    }

    func testParsesWithoutTrailingNewline() {
        XCTAssertEqual(CSV.parse("a,b\n1,2"), [["a", "b"], ["1", "2"]])
    }

    func testEmptyInputGivesNoRows() {
        XCTAssertEqual(CSV.parse(""), [])
        XCTAssertEqual(CSV.parse("\n\n"), [])
    }

    func testEmptyFieldsArePreserved() {
        XCTAssertEqual(CSV.parse("a,,c\n,,\n"), [["a", "", "c"], ["", "", ""]])
        XCTAssertEqual(CSV.parse("a,b,"), [["a", "b", ""]])
    }

    // MARK: Quoting

    func testQuotedFieldWithComma() {
        let rows = CSV.parse("name,age\n\"Smith, John\",42\n")
        XCTAssertEqual(rows, [["name", "age"], ["Smith, John", "42"]])
    }

    func testEscapedQuotesInsideQuotedField() {
        let rows = CSV.parse("name,quote\nBob,\"He said \"\"hi\"\"\"\n")
        XCTAssertEqual(rows[1], ["Bob", "He said \"hi\""])
    }

    func testQuotedFieldThatIsOnlyAnEscapedQuote() {
        let rows = CSV.parse("a,b\n\"\"\"\",x\n")
        XCTAssertEqual(rows[1], ["\"", "x"])
    }

    func testNewlineInsideQuotes() {
        let rows = CSV.parse("id,note\n1,\"line1\nline2\"\n2,ok\n")
        XCTAssertEqual(rows, [["id", "note"], ["1", "line1\nline2"], ["2", "ok"]])
    }

    func testEmptyQuotedFieldInTheMiddle() {
        XCTAssertEqual(CSV.parse("a,\"\",c\n"), [["a", "", "c"]])
    }

    func testQuoteInTheMiddleOfAnUnquotedFieldIsLiteral() {
        let rows = CSV.parse("a,b\n5\" pipe,x\n")
        XCTAssertEqual(rows[1], ["5\" pipe", "x"])
    }

    func testClosingQuoteAtEndOfInput() {
        XCTAssertEqual(CSV.parse("\"abc\""), [["abc"]])
        XCTAssertEqual(CSV.parse("x,\"abc\""), [["x", "abc"]])
    }

    func testDelimiterInsideQuotesWithSemicolon() {
        let rows = CSV.parse("a;b\n\"x;y\";z\n")
        XCTAssertEqual(rows, [["a", "b"], ["x;y", "z"]])
    }

    // MARK: Line endings and blank lines

    func testCRLFLineEndings() {
        let rows = CSV.parse("a,b\r\n1,2\r\n3,4\r\n")
        XCTAssertEqual(rows, [["a", "b"], ["1", "2"], ["3", "4"]])
    }

    func testCRLFWithoutTrailingNewline() {
        XCTAssertEqual(CSV.parse("a,b\r\n1,2"), [["a", "b"], ["1", "2"]])
    }

    func testBareCarriageReturnLineEndings() {
        XCTAssertEqual(CSV.parse("a,b\r1,2\r"), [["a", "b"], ["1", "2"]])
    }

    func testCRLFInsideQuotesIsPreserved() {
        let rows = CSV.parse("a,b\r\n\"x\r\ny\",z\r\n")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1], ["x\r\ny", "z"])
    }

    func testBlankLinesAreSkipped() {
        XCTAssertEqual(CSV.parse("a,b\n\n\n1,2\n\n"), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(CSV.parse("a,b\r\n\r\n1,2\r\n"), [["a", "b"], ["1", "2"]])
    }

    // MARK: Delimiter detection

    func testDetectsCommaByDefault() {
        XCTAssertEqual(CSV.detectDelimiter(in: "a,b,c\n1,2,3"), ",")
        XCTAssertEqual(CSV.detectDelimiter(in: "single"), ",")
        XCTAssertEqual(CSV.detectDelimiter(in: ""), ",")
    }

    func testDetectsSemicolon() {
        XCTAssertEqual(CSV.detectDelimiter(in: "Date;Description;Amount\n2024-01-01;Coffee;-3,50"), ";")
    }

    func testDetectsTab() {
        XCTAssertEqual(CSV.detectDelimiter(in: "Date\tDescription\tAmount\n"), "\t")
    }

    func testDelimiterDetectionOnlyLooksAtTheFirstLine() {
        // The data row has many commas, but the header decides.
        XCTAssertEqual(CSV.detectDelimiter(in: "a;b\n1,5,6,7,8"), ";")
    }

    func testSemicolonFileParsesWithDecimalCommas() {
        let rows = CSV.parse("Date;Description;Amount\n2024-01-01;Coffee;-3,50\n2024-01-02;\"Shop; Inc\";12,00\n")
        XCTAssertEqual(rows, [
            ["Date", "Description", "Amount"],
            ["2024-01-01", "Coffee", "-3,50"],
            ["2024-01-02", "Shop; Inc", "12,00"]
        ])
    }

    func testTabSeparatedFile() {
        XCTAssertEqual(CSV.parse("a\tb\n1\t2\n"), [["a", "b"], ["1", "2"]])
    }

    func testExplicitDelimiterOverridesDetection() {
        XCTAssertEqual(CSV.parse("a,b|c\n", delimiter: "|"), [["a,b", "c"]])
    }

    // MARK: escape / make

    func testEscape() {
        XCTAssertEqual(CSV.escape("plain"), "plain")
        XCTAssertEqual(CSV.escape(""), "")
        XCTAssertEqual(CSV.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSV.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSV.escape("two\nlines"), "\"two\nlines\"")
        XCTAssertEqual(CSV.escape("cr\rhere"), "\"cr\rhere\"")
    }

    func testEscapeDependsOnTheDelimiter() {
        XCTAssertEqual(CSV.escape("a;b", delimiter: ";"), "\"a;b\"")
        XCTAssertEqual(CSV.escape("a,b", delimiter: ";"), "a,b")
        XCTAssertEqual(CSV.escape("a;b", delimiter: ","), "a;b")
    }

    func testMake() {
        let text = CSV.make(rows: [["a", "b,c"], ["1", "2"]])
        XCTAssertEqual(text, "a,\"b,c\"\n1,2\n")
    }

    func testMakeWithSemicolon() {
        let text = CSV.make(rows: [["a", "b;c"], ["1,5", "2"]], delimiter: ";")
        XCTAssertEqual(text, "a;\"b;c\"\n1,5;2\n")
    }

    // MARK: Round trips

    func testRoundTrip_tricklyContent() {
        let rows = [
            ["Date", "Payee", "Note"],
            ["2024-01-01", "Smith, John", "He said \"hi\""],
            ["2024-01-02", "Multi\nline", "tab\there"],
            ["2024-01-03", "", "trailing comma,"],
            ["2024-01-04", "lone\rcr", "plain"],
            ["2024-01-05", " padded ", "ünïcödé ✓"]
        ]
        XCTAssertEqual(CSV.parse(CSV.make(rows: rows)), rows)
    }

    func testRoundTrip_crlfInsideField() {
        // "\r\n" is a single Character in Swift; escape() must still quote such a field.
        let rows = [["a", "b"], ["1", "windows\r\nbreak"], ["2", "unix\nbreak"]]
        XCTAssertEqual(CSV.escape("windows\r\nbreak"), "\"windows\r\nbreak\"")
        XCTAssertEqual(CSV.parse(CSV.make(rows: rows)), rows)
    }

    func testRoundTrip_semicolonDelimiter() {
        let rows = [
            ["Date", "Payee", "Amount"],
            ["2024-01-01", "Shop; Inc", "-1 234,56"],
            ["2024-01-02", "Quote \"x\"", "10,00"]
        ]
        XCTAssertEqual(CSV.parse(CSV.make(rows: rows, delimiter: ";"), delimiter: ";"), rows)
        XCTAssertEqual(CSV.parse(CSV.make(rows: rows, delimiter: ";")), rows, "auto-detection must agree")
    }

    func testRoundTrip_tabDelimiter() {
        let rows = [["a", "b"], ["x y", "z,w"]]
        XCTAssertEqual(CSV.parse(CSV.make(rows: rows, delimiter: "\t")), rows)
    }

    func testMakeThenParseThenMakeIsStable() {
        let rows = [["h1", "h2"], ["a,b", "c\"d"], ["e\nf", "g"]]
        let once = CSV.make(rows: rows)
        let twice = CSV.make(rows: CSV.parse(once))
        XCTAssertEqual(once, twice)
    }
}
