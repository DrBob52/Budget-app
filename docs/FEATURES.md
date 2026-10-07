# Feature parity

The feature list below comes from Buddy's public App Store listing and press coverage (Buddy Budgeting AB). Tally implements each feature with its own code, copy, icon and visual design. No code or assets were taken from Buddy.

| Capability seen in the reference app | Tally implementation | Where |
| --- | --- | --- |
| Budget plan per category with remaining amount | Plan tab: left to spend, per-category limits, bars, over-budget states | `Features/Budget` |
| Budget period that follows payday | Monthly (start day 1–28), weekly or biweekly periods | `TallyCore/Period.swift`, Settings |
| Optional rollover of unspent budget | Global switch plus per-category "carry leftover" | `TallyCore/BudgetMath.swift` |
| Unbudgeted spending | "Not budgeted" section with quick "Set limit" | `Features/Budget` |
| Pre-made and custom categories, created inline | Starter categories, editor with SF Symbol + color, "New" tile inside the picker | `DesignSystem/Pickers.swift` |
| Manual expense and income entry | Transaction editor with payee suggestions | `Features/Transactions` |
| Recurring transactions (daily / weekly / monthly) | Daily → yearly templates, auto-generated when due, subscriptions total | `Features/Transactions` |
| Wallets / accounts | Accounts with balances, transfers, balance adjustment, net worth | `Features/Wallet` |
| Savings goals | Goals with deposits / withdrawals, deadline pacing | `Features/Wallet` |
| Insights on spending, income and savings | Category donut, income vs spending, daily pace, top payees, net worth trend | `Features/Insights` |
| Shared budget with partner, who spent what | Members, "paid by", per-member spending | `Features/Together` |
| Split expenses and settle up | Equal / exact / percentage / shares splits, balances, suggested payments, settlement history | `Features/Together`, `TallyCore/Split.swift` |
| Import transactions from your bank | Left out on purpose: every transaction is entered by hand so spending stays deliberate | n/a |
| Reminders | Daily logging reminder, bill reminders, overspend alerts | `Features/Settings/NotificationService.swift` |
| Home screen widget for quick entry | Left-to-spend and quick-add widgets, Lock Screen widgets | `TallyWidgets` |
| Apple Watch | Watch summary + quick expense logging over WatchConnectivity | `TallyWatch` |
| Siri / Shortcuts | Log expense, check budget, open quick add | `Features/Intents` |
| Dozens of currencies | Any ISO 4217 currency | Settings |
| Security settings | Face ID / Touch ID / passcode lock, hide-amounts privacy mode | `Features/Settings` |
| Appearance settings | System / light / dark | Settings |
| Premium subscription | Tally Pro (StoreKit 2): monthly / yearly with free trial | `Features/Paywall` |
| Export | CSV export of all transactions | Settings |

## Product decisions and later work

- **Bank sync and statement import.** Tally is manual by design: you log each transaction yourself, which keeps the budget intentional. The tested CSV/OFX parser stays in `TallyCore` if that ever changes.
- **Real-time sharing across two people's phones.** Planned for later. Today the shared budget lives on one device and exports a summary. Syncing it between people needs CloudKit sharing (`CKShare`) or a backend.
- **Languages.** English and Spanish.
