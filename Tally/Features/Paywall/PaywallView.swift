import SwiftUI
import StoreKit

/// Tally Pro upsell, presented as a sheet.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProStore.self) private var store

    @State private var selectedID: String?
    /// Whether the user can still get each product's introductory offer.
    @State private var introEligibility: [String: Bool] = [:]

    private var proFeatures: [ProFeature] {
        ProFeature.allCases.filter { $0.requiresPro }
    }

    private var selectedProduct: Product? {
        if let selectedID, let match = store.products.first(where: { $0.id == selectedID }) {
            return match
        }
        return store.products.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                closeRow
                if store.isPro {
                    PaywallProState(onDone: { dismiss() })
                } else {
                    PaywallHeadline()
                }
                featureList
                if !store.isPro {
                    plansSection
                    errorText
                    PaywallLegalFootnote()
                }
            }
            .padding(.horizontal, Metrics.screenPadding + 4)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.paper.ignoresSafeArea())
        .task(id: store.products.map { $0.id }) {
            await loadEligibility()
        }
    }

    // MARK: Pieces

    private var closeRow: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 34, height: 34)
                    .background(Palette.sunken, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Overline(store.isPro ? "Included with Pro" : "What you get")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(proFeatures) { feature in
                    PaywallFeatureRow(feature: feature)
                    if feature != proFeatures.last {
                        Rule().padding(.leading, 56)
                    }
                }
            }
            .tallyCard(padding: 0)
            Text("Recurring transactions, widgets and the Apple Watch app stay free.")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    @ViewBuilder
    private var plansSection: some View {
        if store.products.isEmpty {
            PaywallUnavailable(
                isLoading: store.isLoadingProducts,
                onRetry: {
                    store.errorMessage = nil
                    Task { await store.loadProducts() }
                }
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Overline("Choose a plan")
                ForEach(store.products, id: \.id) { product in
                    PaywallPlanCard(
                        product: product,
                        isSelected: product.id == selectedProduct?.id,
                        savingsPercent: savingsPercent(for: product),
                        introText: introText(for: product),
                        onSelect: { selectedID = product.id }
                    )
                }
                purchaseButton
                Button("Restore purchases") {
                    Task { await store.restore() }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.inkSecondary)
                .disabled(store.isPurchasing)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
    }

    private var purchaseButton: some View {
        VStack(spacing: 8) {
            Button {
                if let product = selectedProduct {
                    Task { await buy(product) }
                }
            } label: {
                if store.isPurchasing {
                    ProgressView()
                        .tint(Palette.paper)
                } else {
                    Text(purchaseTitle)
                }
            }
            .buttonStyle(.tallyPrimary)
            .disabled(selectedProduct == nil || store.isPurchasing)

            if let product = selectedProduct {
                Text(summaryLine(for: product))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var errorText: some View {
        if let message = store.errorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(Palette.negative)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    private func buy(_ product: Product) async {
        do {
            try await store.purchase(product)
        } catch {
            store.errorMessage = "The purchase did not go through. \(error.localizedDescription)"
        }
    }

    private func loadEligibility() async {
        var result: [String: Bool] = [:]
        for product in store.products {
            guard let subscription = product.subscription, subscription.introductoryOffer != nil else { continue }
            result[product.id] = await subscription.isEligibleForIntroOffer
        }
        introEligibility = result
    }

    // MARK: Copy

    private var purchaseTitle: String {
        guard let product = selectedProduct else { return "Subscribe" }
        if hasEligibleIntro(product) { return "Try Tally Pro free" }
        return "Subscribe to Tally Pro"
    }

    private func hasEligibleIntro(_ product: Product) -> Bool {
        guard product.subscription?.introductoryOffer != nil else { return false }
        return introEligibility[product.id] ?? false
    }

    private func introText(for product: Product) -> String? {
        guard hasEligibleIntro(product), let offer = product.subscription?.introductoryOffer else { return nil }
        let length: String = PaywallFormat.periodLength(offer.period, count: offer.periodCount)
        switch offer.paymentMode {
        case .freeTrial:
            return "\(length) free"
        case .payAsYouGo:
            return "\(offer.displayPrice) per \(PaywallFormat.periodUnit(offer.period)) for \(length)"
        case .payUpFront:
            return "\(offer.displayPrice) for the first \(length)"
        default:
            return nil
        }
    }

    private func summaryLine(for product: Product) -> String {
        let renewal: String = "\(product.displayPrice) per \(PaywallFormat.periodUnit(product.subscription?.subscriptionPeriod))"
        if hasEligibleIntro(product), let intro = introText(for: product), let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
            return "\(intro), then \(renewal). Cancel anytime."
        }
        return "\(renewal). Cancel anytime."
    }

    /// Yearly saving against twelve months of the monthly plan, as a whole percent.
    private func savingsPercent(for product: Product) -> Int? {
        guard let period = product.subscription?.subscriptionPeriod, period.unit == .year, period.value == 1 else { return nil }
        let monthly: Product? = store.products.first { candidate in
            guard let candidatePeriod = candidate.subscription?.subscriptionPeriod else { return false }
            return candidatePeriod.unit == .month && candidatePeriod.value == 1
        }
        guard let monthly else { return nil }
        let full: Decimal = monthly.price * 12
        guard full > 0 else { return nil }
        let saved: Decimal = (full - product.price) / full * 100
        let percent: Int = Int(NSDecimalNumber(decimal: saved).doubleValue.rounded())
        return percent >= 1 ? percent : nil
    }
}

// MARK: - Formatting helpers

private enum PaywallFormat {
    /// "month", "year" ...
    static func periodUnit(_ period: Product.SubscriptionPeriod?) -> String {
        guard let period else { return "period" }
        let base: String = unitName(period.unit)
        return period.value == 1 ? base : "\(period.value) \(base)s"
    }

    /// "7 days", "1 month" for an offer that lasts `count` periods.
    static func periodLength(_ period: Product.SubscriptionPeriod, count: Int) -> String {
        let total: Int = max(period.value * max(count, 1), 1)
        let base: String = unitName(period.unit)
        if period.unit == .week && total % 1 == 0 && total == 1 {
            return "1 week"
        }
        return total == 1 ? "1 \(base)" : "\(total) \(base)s"
    }

    private static func unitName(_ unit: Product.SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return "period"
        }
    }
}

// MARK: - Subviews

private struct PaywallHeadline: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingTallyMark(scale: 0.5)
            Overline("Tally Pro")
            Text("Budget with the whole picture.")
                .font(.display(32))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Share costs, bring in your statements and see the patterns behind your spending.")
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PaywallProState: View {
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.accent)
            Text("You're on Pro")
                .font(.display(32))
                .foregroundStyle(Palette.ink)
            Text("Thank you for backing Tally. Every Pro feature is unlocked.")
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done", action: onDone)
                .buttonStyle(.tallyPrimary)
                .padding(.top, 4)
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                Link("Manage subscription", destination: url)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct PaywallFeatureRow: View {
    let feature: ProFeature

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: feature.symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Palette.accent)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.headlineSerif)
                    .foregroundStyle(Palette.ink)
                Text(feature.blurb)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

private struct PaywallPlanCard: View {
    let product: Product
    let isSelected: Bool
    let savingsPercent: Int?
    let introText: String?
    let onSelect: () -> Void

    private var isYearly: Bool {
        product.subscription?.subscriptionPeriod.unit == .year
    }

    private var title: String {
        isYearly ? "Yearly" : "Monthly"
    }

    private var priceLine: String {
        "\(product.displayPrice) per \(PaywallFormat.periodUnit(product.subscription?.subscriptionPeriod))"
    }

    private var perMonthLine: String? {
        guard isYearly else { return nil }
        let perMonth: Decimal = product.price / 12
        return "About \(product.priceFormatStyle.format(perMonth)) a month"
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Palette.accent : Palette.inkTertiary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headlineSerif)
                            .foregroundStyle(Palette.ink)
                        if let savingsPercent {
                            Text("Save \(savingsPercent)%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Palette.accent.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(priceLine)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                    if let perMonthLine {
                        Text(perMonthLine)
                            .font(.caption)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    if let introText {
                        Text(introText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.accent)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Palette.accent : Palette.rule, lineWidth: isSelected ? 1.5 : Metrics.hairline)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PaywallUnavailable: View {
    let isLoading: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if isLoading {
                ProgressView()
                Text("Loading plans...")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Palette.inkTertiary)
                Text("Plans are not available right now")
                    .font(.headlineSerif)
                    .foregroundStyle(Palette.ink)
                Text("We could not reach the App Store. Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                Button("Try again", action: onRetry)
                    .buttonStyle(.tallySecondary)
                    .frame(maxWidth: 200)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .tallyCard(padding: 24)
    }
}

private struct PaywallLegalFootnote: View {
    var body: some View {
        Text("Subscriptions renew automatically at the price shown unless cancelled at least 24 hours before the end of the current period. Payment is charged to your Apple ID when you confirm the purchase. Manage or cancel any time in your Apple ID settings. Any free trial is for new subscribers only and converts to a paid plan when it ends.")
            .font(.caption2)
            .foregroundStyle(Palette.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Paywall") {
    PaywallView()
        .previewEnvironment()
}

#Preview("Paywall, on Pro") {
    PaywallView()
        .previewEnvironment()
}
