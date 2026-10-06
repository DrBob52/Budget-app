import AppIntents
import Foundation
import SwiftData

/// A spending category, exposed to Shortcuts and Siri.
struct IntentCategoryEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Category")
    static var defaultQuery = IntentCategoryQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct IntentCategoryQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [IntentCategoryEntity] {
        await MainActor.run {
            IntentCategoryQuery.expenseCategories().filter { identifiers.contains($0.id) }
        }
    }

    func suggestedEntities() async throws -> [IntentCategoryEntity] {
        await MainActor.run {
            IntentCategoryQuery.expenseCategories()
        }
    }

    func entities(matching string: String) async throws -> [IntentCategoryEntity] {
        await MainActor.run {
            IntentCategoryQuery.expenseCategories().filter {
                $0.name.localizedCaseInsensitiveContains(string)
            }
        }
    }

    @MainActor
    static func expenseCategories() -> [IntentCategoryEntity] {
        let context = IntentDataStack.context
        let all = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        return all
            .filter { !$0.isArchived && $0.kind == .expense }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { IntentCategoryEntity(id: $0.id, name: $0.name) }
    }
}
