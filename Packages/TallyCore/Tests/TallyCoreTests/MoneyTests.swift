import XCTest
@testable import TallyCore

final class MoneyTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")

    // MARK: MoneyFormat

    func testFractionDigits() {
        XCTAssertEqual(MoneyFormat.fractionDigits(for: "JPY"), 0)
        XCTAssertEqual(MoneyFormat.fractionDigits(for: "USD"), 2)
        XCTAssertEqual(MoneyFormat.fractionDigits(for: "EUR"), 2)
        XCTAssertEqual(MoneyFormat.fractionDigits(for: "SEK"), 2)
    }

    func testStringFormatsUSDInEnglishLocale() {
        let text = MoneyFormat.string(dec("1234.56"), currencyCode: "USD", locale: enUS)
        XCTAssertEqual(text, "$1,234.56")
    }

    func testStringCompactDropsFractionDigits() {
        let text = MoneyFormat.string(dec("1234.56"), currencyCode: "USD", locale: enUS, compact: true)
        XCTAssertTrue(text.contains("1,235"), text)
        XCTAssertFalse(text.contains("."), text)
    }

    func testStringShowsSignForPositiveAmounts() {
        let plain = MoneyFormat.string(dec("5"), currencyCode: "USD", locale: enUS)
        let signed = MoneyFormat.string(dec("5"), currencyCode: "USD", locale: enUS, showsSign: true)
        XCTAssertFalse(plain.contains("+"))
        XCTAssertTrue(signed.contains("+"), signed)
        XCTAssertTrue(signed.contains("5.00"), signed)
    }

    func testStringNegativeAmountKeepsItsSign() {
        let text = MoneyFormat.string(dec("-5"), currencyCode: "USD", locale: enUS)
        XCTAssertTrue(text.contains("-"), text)
        XCTAssertTrue(text.contains("5.00"), text)
    }

    func testStringWithZeroDecimalCurrency() {
        let text = MoneyFormat.string(dec("1235"), currencyCode: "JPY", locale: enUS)
        XCTAssertTrue(text.contains("1,235"), text)
        XCTAssertFalse(text.contains("."), text)
    }

    func testStringWithCurrentLocaleContainsDigits() {
        let text = MoneyFormat.string(dec("42.5"), currencyCode: "USD")
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains(where: \.isNumber))
    }

    func testSymbol() {
        XCTAssertEqual(MoneyFormat.symbol(for: "USD", locale: enUS), "$")
        XCTAssertFalse(MoneyFormat.symbol(for: "EUR", locale: enUS).isEmpty)
        XCTAssertFalse(MoneyFormat.symbol(for: "USD").isEmpty)
    }

    // MARK: Decimal helpers

    func testRoundedPlain() {
        XCTAssertEqual(dec("2.345").rounded(scale: 2), dec("2.35"))
        XCTAssertEqual(dec("2.344").rounded(scale: 2), dec("2.34"))
        XCTAssertEqual(dec("2.5").rounded(scale: 0), dec("3"))
    }

    func testRoundedModes() {
        XCTAssertEqual(dec("2.349").rounded(scale: 2, mode: .down), dec("2.34"))
        XCTAssertEqual(dec("2.341").rounded(scale: 2, mode: .up), dec("2.35"))
        XCTAssertEqual(dec("3.333333").rounded(scale: 2, mode: .down), dec("3.33"))
    }

    func testUnit() {
        XCTAssertEqual(Decimal.unit(scale: 2), dec("0.01"))
        XCTAssertEqual(Decimal.unit(scale: 0), dec("1"))
        XCTAssertEqual(Decimal.unit(scale: 3), dec("0.001"))
    }

    func testSignHelpers() {
        XCTAssertTrue(dec("-0.01").isNegative)
        XCTAssertFalse(dec("0").isNegative)
        XCTAssertFalse(dec("3").isNegative)
        XCTAssertEqual(dec("-12.5").magnitudeValue, dec("12.5"))
        XCTAssertEqual(dec("12.5").magnitudeValue, dec("12.5"))
        XCTAssertEqual(dec("0").magnitudeValue, 0)
    }

    func testDoubleValue() {
        XCTAssertEqual(dec("1.5").doubleValue, 1.5, accuracy: 1e-12)
        XCTAssertEqual(dec("-1234.25").doubleValue, -1234.25, accuracy: 1e-12)
    }

    // MARK: Currency catalog

    func testCurrencyCatalog() {
        let all = CurrencyCatalog.all
        XCTAssertFalse(all.isEmpty)
        XCTAssertTrue(all.contains { $0.code == "USD" })
        XCTAssertTrue(all.contains { $0.code == "JPY" })
        XCTAssertTrue(all.allSatisfy { !$0.name.isEmpty })
        XCTAssertEqual(Set(all.map(\.code)).count, all.count, "codes are unique")
        XCTAssertFalse(CurrencyCatalog.defaultCode.isEmpty)
        XCTAssertFalse(CurrencyCatalog.name(for: "USD").isEmpty)
        XCTAssertFalse(CurrencyCatalog.name(for: "XXXNOTREAL").isEmpty)
    }

    func testCurrencyInfoIdentityAndEquality() {
        let a = CurrencyInfo(code: "USD", name: "US Dollar")
        XCTAssertEqual(a.id, "USD")
        XCTAssertEqual(a, CurrencyInfo(code: "USD", name: "US Dollar"))
        XCTAssertNotEqual(a, CurrencyInfo(code: "EUR", name: "Euro"))
    }
}
