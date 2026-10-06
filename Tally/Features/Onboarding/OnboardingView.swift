import SwiftUI
import SwiftData
import Observation
import TallyCore

/// The steps of first-run setup, in order.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case currency
    case rhythm
    case income
    case categories
    case account
    case done

    var isSkippable: Bool { self == .income || self == .account }
}

/// Everything the user chooses during onboarding that is not stored in `AppSettings`
/// until the flow finishes.
@Observable
final class OnboardingDraft {
    /// Expected income per budget period.
    var income: Decimal = 0
    var selectedExpenses: Set<String> = Set<String>(StarterCategories.expense.prefix(8).map { $0.name })
    var selectedIncome: Set<String> = Set<String>(["Salary"])
    /// Limits the user typed by hand. Everything else follows the suggestion.
    var customLimits: [String: Decimal] = [:]

    var accountName: String = "Everyday"
    var accountKind: AccountKind = .checking
    var accountBalance: Decimal = 0
    var addsAccount: Bool = true

    func suggestedLimit(for template: StarterCategories.Template) -> Decimal {
        (income * template.suggestedShare).rounded(scale: 0)
    }

    func limit(for template: StarterCategories.Template) -> Decimal {
        customLimits[template.name] ?? suggestedLimit(for: template)
    }

    func limitBinding(for template: StarterCategories.Template) -> Binding<Decimal> {
        Binding<Decimal>(
            get: { self.limit(for: template) },
            set: { newValue in
                if newValue != self.limit(for: template) {
                    self.customLimits[template.name] = newValue
                }
            }
        )
    }

    var chosenExpenses: [StarterCategories.Template] {
        StarterCategories.expense.filter { selectedExpenses.contains($0.name) }
    }

    var chosenIncome: [StarterCategories.Template] {
        StarterCategories.income.filter { selectedIncome.contains($0.name) }
    }

    var assignedTotal: Decimal {
        chosenExpenses.reduce(Decimal(0)) { $0 + limit(for: $1) }
    }

    var trimmedAccountName: String {
        accountName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var willCreateAccount: Bool {
        addsAccount && !trimmedAccountName.isEmpty
    }
}

/// First-run flow. Collects a few preferences, creates starter categories and an account,
/// then marks onboarding as complete.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var step: OnboardingStep = .welcome
    @State private var draft = OnboardingDraft()

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                header
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(Palette.paper.ignoresSafeArea())
        .onAppear {
            draft.income = settings.monthlyIncome
        }
        .onChange(of: draft.income) { _, newValue in
            settings.monthlyIncome = newValue
        }
    }

    // MARK: Pieces

    private var stepCount: Int { OnboardingStep.allCases.count - 1 }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Overline("Step \(step.rawValue) of \(stepCount)")
                Spacer()
            }
            BudgetBar(progress: Double(step.rawValue) / Double(stepCount), height: 3, tint: Palette.ink)
        }
        .padding(.horizontal, Metrics.screenPadding + 4)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var content: some View {
        Group {
            switch step {
            case .welcome:
                OnboardingWelcomeStep()
            case .currency:
                OnboardingCurrencyStep()
            case .rhythm:
                OnboardingRhythmStep()
            case .income:
                OnboardingIncomeStep(draft: draft)
            case .categories:
                OnboardingCategoriesStep(draft: draft)
            case .account:
                OnboardingAccountStep(draft: draft)
            case .done:
                OnboardingDoneStep(draft: draft)
            }
        }
        .id(step)
        .transition(.opacity)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            Rule()
                .padding(.bottom, 4)
            if step == .welcome {
                Button("Get started") { advance() }
                    .buttonStyle(.tallyPrimary)
                Button("Explore with sample data") { exploreWithSampleData() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.vertical, 6)
            } else {
                if step.isSkippable {
                    Button("Skip for now") { skip() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.inkSecondary)
                }
                HStack(spacing: 10) {
                    Button {
                        goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .frame(width: 24)
                    }
                    .buttonStyle(.tallySecondary)
                    .frame(width: 72)
                    .accessibilityLabel("Back")

                    if step == .done {
                        Button("Open my budget") { finish() }
                            .buttonStyle(.tallyPrimary)
                    } else {
                        Button("Continue") { advance() }
                            .buttonStyle(.tallyPrimary)
                    }
                }
            }
        }
        .padding(.horizontal, Metrics.screenPadding + 4)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Palette.paper)
    }

    // MARK: Navigation

    private func move(to newStep: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.2)) {
            step = newStep
        }
    }

    private func advance() {
        if step == .account { draft.addsAccount = true }
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        move(to: next)
    }

    private func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        move(to: previous)
    }

    private func skip() {
        if step == .income { draft.income = 0 }
        if step == .account { draft.addsAccount = false }
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        move(to: next)
    }

    // MARK: Finishing

    /// Inserts the chosen categories and account, then leaves onboarding.
    @MainActor
    private func finish() {
        var order = 0
        for template in draft.chosenExpenses {
            let category = Category(
                name: template.name,
                symbol: template.symbol,
                colorHex: template.colorHex,
                kind: .expense,
                budgetLimit: draft.limit(for: template),
                sortOrder: order
            )
            context.insert(category)
            order += 1
        }
        for template in draft.chosenIncome {
            let category = Category(
                name: template.name,
                symbol: template.symbol,
                colorHex: template.colorHex,
                kind: .income,
                budgetLimit: 0,
                sortOrder: order
            )
            context.insert(category)
            order += 1
        }

        var createdAccountID: UUID?
        if draft.willCreateAccount {
            let kind: AccountKind = draft.accountKind
            // Money owed on a card reduces net worth, so it is stored as a negative balance.
            let opening: Decimal = kind.isLiability ? -draft.accountBalance : draft.accountBalance
            let account = Account(
                name: draft.trimmedAccountName,
                kind: kind,
                openingBalance: opening,
                colorHex: Self.accountColor(for: kind),
                sortOrder: 0
            )
            context.insert(account)
            createdAccountID = account.id
        }

        try? context.save()

        settings.monthlyIncome = draft.income
        if let createdAccountID {
            settings.defaultAccountID = createdAccountID
        }
        settings.hasCompletedOnboarding = true
    }

    @MainActor
    private func exploreWithSampleData() {
        SampleData.insert(into: context)
        if settings.monthlyIncome == 0 {
            settings.monthlyIncome = 4_000
        }
        var descriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\Account.sortOrder)])
        descriptor.fetchLimit = 1
        if let first = try? context.fetch(descriptor).first {
            settings.defaultAccountID = first.id
        }
        settings.hasCompletedOnboarding = true
    }

    private static func accountColor(for kind: AccountKind) -> String {
        switch kind {
        case .cash: return "#5A6B2F"
        case .checking: return "#2F4B7C"
        case .savings: return "#1F5C4A"
        case .credit: return "#A23B57"
        case .investment: return "#6B4E71"
        case .other: return "#4A5560"
        }
    }
}

#Preview {
    OnboardingView()
        .previewEnvironment()
}
