import XCTest
import SwiftData
@testable import Tally

final class TallyTests: XCTestCase {
    @MainActor
    func testSampleDataInserts() throws {
        let container = Persistence.makeContainer(inMemory: true)
        SampleData.insert(into: container.mainContext)
        let categories = try container.mainContext.fetch(FetchDescriptor<Category>())
        XCTAssertFalse(categories.isEmpty)
    }
}
