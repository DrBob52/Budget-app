import Foundation
import Observation
import TallyCore

enum AppTab: String, CaseIterable, Identifiable {
    case budget
    case ledger
    case insights
    case wallet
    case together

    var id: String { rawValue }

    var title: String {
        switch self {
        case .budget: return "Plan"
        case .ledger: return "Ledger"
        case .insights: return "Insights"
        case .wallet: return "Wallet"
        case .together: return "Together"
        }
    }

    var symbol: String {
        switch self {
        case .budget: return "square.grid.2x2"
        case .ledger: return "list.bullet.rectangle"
        case .insights: return "chart.bar.xaxis"
        case .wallet: return "wallet.pass"
        case .together: return "person.2"
        }
    }
}

/// Sheets that can be opened from anywhere (tab views, deep links, widgets, Siri).
enum AppSheet: Identifiable, Equatable {
    case addTransaction(TransactionKind)
    case settings
    case paywall

    var id: String {
        switch self {
        case .addTransaction(let kind): return "add-\(kind.rawValue)"
        case .settings: return "settings"
        case .paywall: return "paywall"
        }
    }
}

@Observable
final class AppRouter {
    var selectedTab: AppTab = .budget
    var sheet: AppSheet?

    func showAdd(_ kind: TransactionKind = .expense) {
        sheet = .addTransaction(kind)
    }

    /// Handles tally:// links from widgets, the watch and Siri.
    /// - tally://add, tally://add?kind=income
    /// - tally://tab/insights
    /// - tally://settings
    func handle(_ url: URL) {
        guard url.scheme == "tally" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        switch url.host {
        case "add":
            let kindValue = components?.queryItems?.first { $0.name == "kind" }?.value
            showAdd(kindValue.flatMap(TransactionKind.init(rawValue:)) ?? .expense)
        case "tab":
            if let tab = AppTab(rawValue: url.lastPathComponent) {
                sheet = nil
                selectedTab = tab
            }
        case "settings":
            sheet = .settings
        default:
            break
        }
    }
}
