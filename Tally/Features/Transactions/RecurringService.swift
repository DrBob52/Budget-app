import Foundation
import SwiftData
import TallyCore

/// Turns due occurrences of active recurring templates into real transactions.
enum RecurringService {
    /// Inserts one transaction per occurrence that has come due (up to `now`) and
    /// moves each template's `lastGeneratedDate` forward. Saves once if anything changed.
    @MainActor
    static func generateDueTransactions(in context: ModelContext, now: Date = Date()) {
        let descriptor = FetchDescriptor<RecurringTemplate>(
            predicate: #Predicate<RecurringTemplate> { $0.isActive }
        )
        guard let templates = try? context.fetch(descriptor) else { return }

        var changed = false
        for template in templates {
            let dates: [Date] = template.rule.occurrences(after: template.lastGeneratedDate, through: now)
            guard let lastDate = dates.last else { continue }

            for date in dates {
                let transaction = Transaction(
                    amount: template.amount,
                    kind: template.kind,
                    title: template.title,
                    date: date,
                    category: template.category,
                    account: template.account,
                    note: template.note
                )
                transaction.recurringTemplate = template
                context.insert(transaction)
            }
            template.lastGeneratedDate = lastDate
            changed = true
        }

        if changed {
            try? context.save()
        }
    }
}

/// Helpers for showing what repeating items cost.
enum RecurringMath {
    /// Converts an amount that repeats at `frequency` into an approximate monthly amount.
    static func monthlyEquivalent(of amount: Decimal, frequency: RecurrenceFrequency) -> Decimal {
        let daily: Decimal = Decimal(string: "30.44") ?? 30
        let weekly: Decimal = Decimal(string: "4.345") ?? 4
        let biweekly: Decimal = Decimal(string: "2.17") ?? 2
        switch frequency {
        case .daily: return amount * daily
        case .weekly: return amount * weekly
        case .biweekly: return amount * biweekly
        case .monthly: return amount
        case .quarterly: return amount / Decimal(3)
        case .yearly: return amount / Decimal(12)
        }
    }

    /// Approximate monthly total of the active expense templates that still have future occurrences.
    static func monthlyExpenseTotal(of templates: [RecurringTemplate]) -> Decimal {
        var total: Decimal = 0
        for template in templates {
            guard template.isActive, template.kind == .expense, template.nextDueDate != nil else { continue }
            total += monthlyEquivalent(of: template.amount, frequency: template.frequency)
        }
        return total
    }
}
