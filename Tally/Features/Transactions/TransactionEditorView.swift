import SwiftUI
import TallyCore

// STUB: replaced by the Transactions feature.
// Contract: add (transaction == nil) or edit a transaction; presented as a sheet.
struct TransactionEditorView: View {
    let transaction: Transaction?
    var initialKind: TransactionKind = .expense

    init(transaction: Transaction? = nil, initialKind: TransactionKind = .expense) {
        self.transaction = transaction
        self.initialKind = initialKind
    }

    var body: some View { Text("Editor") }
}
