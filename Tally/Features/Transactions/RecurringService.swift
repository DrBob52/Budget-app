import Foundation
import SwiftData

// STUB: replaced by the Transactions feature.
// Contract: turn every due occurrence of active RecurringTemplates (up to `now`) into Transactions.
enum RecurringService {
    @MainActor
    static func generateDueTransactions(in context: ModelContext, now: Date = Date()) {}
}
