import XCTest
@testable import TallyCore

final class SnapshotTests: XCTestCase {
    // Whole-second dates only: the store uses the ISO 8601 strategy, which drops fractions.
    private let updated = Date(timeIntervalSince1970: 1_790_000_000)

    private func sampleSnapshot(dailyAllowance: Decimal? = dec("54.5")) -> BudgetSnapshot {
        BudgetSnapshot(
            currencyCode: "USD",
            periodTitle: "October 2026",
            periodStart: Date(timeIntervalSince1970: 1_790_000_000 - 86_400 * 5),
            periodEnd: Date(timeIntervalSince1970: 1_790_000_000 + 86_400 * 26),
            totalBudget: dec("2400"),
            spent: dec("1310.25"),
            income: dec("3200"),
            leftToSpend: dec("1089.75"),
            dailyAllowance: dailyAllowance,
            daysRemaining: 20,
            categories: [
                .init(id: uuid(1), name: "Groceries", symbol: "cart", colorHex: "#2E6F5E", spent: dec("420.10"), available: dec("600")),
                .init(id: uuid(2), name: "Dining", symbol: "fork.knife", colorHex: "#B84A26", spent: dec("260"), available: dec("250"))
            ],
            quickCategories: [
                .init(id: uuid(3), name: "Coffee", symbol: "cup.and.saucer", colorHex: "#112233")
            ],
            updatedAt: updated
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TallyCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { _ = try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: encode / decode

    func testEncodeDecodeRoundTrip() throws {
        let snapshot = sampleSnapshot()
        let data = try XCTUnwrap(SnapshotStore.encode(snapshot))
        XCTAssertFalse(data.isEmpty)
        let decoded = try XCTUnwrap(SnapshotStore.decode(data))
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.spent, dec("1310.25"))
        XCTAssertEqual(decoded.categories.count, 2)
        XCTAssertEqual(decoded.quickCategories.first?.name, "Coffee")
        XCTAssertEqual(decoded.updatedAt, updated)
    }

    func testRoundTripWithNilDailyAllowanceAndEmptyLists() throws {
        var snapshot = sampleSnapshot(dailyAllowance: nil)
        snapshot.categories = []
        snapshot.quickCategories = []
        let data = try XCTUnwrap(SnapshotStore.encode(snapshot))
        let decoded = try XCTUnwrap(SnapshotStore.decode(data))
        XCTAssertNil(decoded.dailyAllowance)
        XCTAssertEqual(decoded, snapshot)
    }

    func testDatesAreEncodedAsISO8601Strings() throws {
        let data = try XCTUnwrap(SnapshotStore.encode(sampleSnapshot()))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"updatedAt\":\"20"), "expected an ISO 8601 string, got: \(text)")
    }

    func testDecodeRejectsGarbage() {
        XCTAssertNil(SnapshotStore.decode(Data()))
        XCTAssertNil(SnapshotStore.decode(Data("not json".utf8)))
        XCTAssertNil(SnapshotStore.decode(Data("{}".utf8)))
        XCTAssertNil(SnapshotStore.decode(Data("[]".utf8)))
    }

    // MARK: Files

    func testFileURL() {
        let directory = URL(fileURLWithPath: "/tmp/some-dir", isDirectory: true)
        let url = SnapshotStore.url(in: directory)
        XCTAssertEqual(url.lastPathComponent, SnapshotStore.fileName)
        XCTAssertEqual(SnapshotStore.fileName, "budget-snapshot.json")
        XCTAssertEqual(url.deletingLastPathComponent().path, directory.path)
    }

    func testWriteThenReadInTemporaryDirectory() throws {
        let directory = try makeTemporaryDirectory()
        let snapshot = sampleSnapshot()
        try SnapshotStore.write(snapshot, to: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: SnapshotStore.url(in: directory).path))
        XCTAssertEqual(SnapshotStore.read(from: directory), snapshot)
    }

    func testWriteOverwritesPreviousSnapshot() throws {
        let directory = try makeTemporaryDirectory()
        var first = sampleSnapshot()
        try SnapshotStore.write(first, to: directory)
        first.spent = dec("1")
        first.periodTitle = "Changed"
        try SnapshotStore.write(first, to: directory)
        let read = try XCTUnwrap(SnapshotStore.read(from: directory))
        XCTAssertEqual(read.periodTitle, "Changed")
        XCTAssertEqual(read.spent, dec("1"))
    }

    func testReadFromEmptyDirectoryIsNil() throws {
        let directory = try makeTemporaryDirectory()
        XCTAssertNil(SnapshotStore.read(from: directory))
    }

    func testReadFromMissingDirectoryIsNil() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("TallyCoreTests-missing-\(UUID().uuidString)", isDirectory: true)
        XCTAssertNil(SnapshotStore.read(from: missing))
    }

    func testReadOfCorruptFileIsNil() throws {
        let directory = try makeTemporaryDirectory()
        try Data("corrupt".utf8).write(to: SnapshotStore.url(in: directory))
        XCTAssertNil(SnapshotStore.read(from: directory))
    }

    func testWriteToMissingDirectoryThrows() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("TallyCoreTests-missing-\(UUID().uuidString)", isDirectory: true)
        XCTAssertThrowsError(try SnapshotStore.write(sampleSnapshot(), to: missing))
    }

    // MARK: Derived values

    func testSnapshotProgress() {
        var snapshot = sampleSnapshot()
        snapshot.totalBudget = dec("2000")
        snapshot.spent = dec("500")
        XCTAssertEqual(snapshot.progress, 0.25, accuracy: 1e-9)
        snapshot.spent = dec("3000")
        XCTAssertEqual(snapshot.progress, 1.5, accuracy: 1e-9)
        snapshot.totalBudget = 0
        XCTAssertEqual(snapshot.progress, 0)
    }

    func testCategoryLineProgress() {
        func line(spent: String, available: String) -> BudgetSnapshot.CategoryLine {
            .init(id: uuid(1), name: "X", symbol: "s", colorHex: "#000000", spent: dec(spent), available: dec(available))
        }
        XCTAssertEqual(line(spent: "420", available: "600").progress, 0.7, accuracy: 1e-9)
        XCTAssertEqual(line(spent: "260", available: "250").progress, 1.04, accuracy: 1e-9)
        XCTAssertEqual(line(spent: "5", available: "0").progress, 1)
        XCTAssertEqual(line(spent: "0", available: "0").progress, 0)
        XCTAssertEqual(line(spent: "5", available: "-10").progress, 1)
    }

    func testPlaceholderIsSelfConsistentAndRoundTrips() throws {
        let placeholder = BudgetSnapshot.placeholder
        XCTAssertFalse(placeholder.categories.isEmpty)
        XCTAssertGreaterThan(placeholder.totalBudget, 0)
        XCTAssertEqual(placeholder.leftToSpend, placeholder.totalBudget - placeholder.spent)
        // Placeholder dates carry sub-second precision, so compare the stable fields only.
        let decoded = try XCTUnwrap(SnapshotStore.decode(XCTUnwrap(SnapshotStore.encode(placeholder))))
        XCTAssertEqual(decoded.categories, placeholder.categories)
        XCTAssertEqual(decoded.totalBudget, placeholder.totalBudget)
        XCTAssertEqual(decoded.dailyAllowance, placeholder.dailyAllowance)
    }

    func testAppGroupIdentifier() {
        XCTAssertEqual(AppGroup.identifier, "group.com.tallybudget.shared")
    }
}
