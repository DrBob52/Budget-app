import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import TallyCore

// MARK: - Flow

private enum ImportStage {
    case start
    case mapping
    case review
    case finished
}

/// One parsed statement row on the review screen.
private struct ImportReviewRow: Identifiable {
    /// Position in the parsed list; fingerprints can repeat for identical rows in one file.
    let id: Int
    let row: ImportedRow
    let alreadyImported: Bool
    /// Category reused from an earlier transaction with the same title.
    let suggested: Category?

    var isExpense: Bool { row.amount < 0 }
}

private enum ImportTextDecoding {
    /// Tries UTF-8 first, then Latin-1 (common for older bank exports). Drops a leading BOM.
    static func decode(_ data: Data) -> String? {
        var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        if let value = text, value.hasPrefix("\u{FEFF}") {
            text = String(value.dropFirst())
        }
        return text
    }
}

/// Imports a bank statement (CSV, OFX or QFX) into the ledger: pick a file, map columns,
/// review rows, then add them as transactions.
struct ImportStatementView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(filter: #Predicate<Category> { !$0.isArchived }, sort: \Category.sortOrder)
    private var categories: [Category]
    @Query private var transactions: [Transaction]

    @State private var stage: ImportStage = .start
    @State private var showImporter = false
    @State private var errorMessage: String?

    @State private var fileName = ""
    @State private var csvRows: [[String]] = []
    @State private var mapping = ImportColumnMapping()
    @State private var unreadableCount = 0

    @State private var reviewRows: [ImportReviewRow] = []
    @State private var selected: Set<Int> = []
    @State private var targetAccount: Account?
    @State private var expenseCategory: Category?
    @State private var incomeCategory: Category?

    @State private var importedCount = 0
    @State private var skippedCount = 0

    private var allowedTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .plainText]
        let extra: [UTType] = ["ofx", "qfx"].compactMap { UTType(filenameExtension: $0) }
        types.append(contentsOf: extra)
        return types
    }

    var body: some View {
        Group {
            switch stage {
            case .start:
                ImportStartView { showImporter = true }
            case .mapping:
                ImportMappingForm(
                    fileName: fileName,
                    csvRows: csvRows,
                    mapping: $mapping,
                    onContinue: continueFromMapping
                )
            case .review:
                ImportReviewView(
                    fileName: fileName,
                    rows: reviewRows,
                    unreadableCount: unreadableCount,
                    selected: $selected,
                    targetAccount: $targetAccount,
                    expenseCategory: $expenseCategory,
                    incomeCategory: $incomeCategory,
                    expenseCategories: categories.filter { $0.kind == .expense },
                    incomeCategories: categories.filter { $0.kind == .income },
                    canAdjustColumns: !csvRows.isEmpty,
                    onAdjustColumns: { stage = .mapping },
                    onImport: performImport
                )
            case .finished:
                ImportDoneView(
                    importedCount: importedCount,
                    skippedCount: skippedCount,
                    onAnother: reset,
                    onDone: { dismiss() }
                )
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("Import statement")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: allowedTypes, allowsMultipleSelection: false) { result in
            handlePicked(result)
        }
        .alert("Couldn't read that file", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            if targetAccount == nil {
                targetAccount = accounts.first { $0.id == settings.defaultAccountID } ?? accounts.first
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding<Bool>(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue { errorMessage = nil }
            }
        )
    }

    // MARK: Loading

    private func handlePicked(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            guard let text = ImportTextDecoding.decode(data) else {
                errorMessage = "The file is not readable text. Export it from your bank as CSV or OFX and try again."
                return
            }
            load(text: text, fileName: url.lastPathComponent, pathExtension: url.pathExtension.lowercased())
        }
    }

    private func load(text: String, fileName: String, pathExtension: String) {
        self.fileName = fileName
        let isOFX = pathExtension == "ofx" || pathExtension == "qfx" || text.uppercased().contains("<STMTTRN>")
        if isOFX {
            let parsed = StatementImporter.parseOFX(text)
            guard !parsed.isEmpty else {
                errorMessage = "No transactions were found in this statement."
                return
            }
            csvRows = []
            unreadableCount = 0
            prepareReview(with: parsed)
        } else {
            let parsed = CSV.parse(text)
            guard parsed.count > 1 else {
                errorMessage = "This file has no rows to import."
                return
            }
            csvRows = parsed
            mapping = StatementImporter.suggestMapping(for: parsed)
            stage = .mapping
        }
    }

    private func continueFromMapping() {
        let result = StatementImporter.importRows(csvRows, mapping: mapping)
        unreadableCount = result.failedRows.count
        prepareReview(with: result.rows)
    }

    // MARK: Review

    private func prepareReview(with rows: [ImportedRow]) {
        let existingFingerprints = Set(transactions.compactMap { $0.importFingerprint })

        // Latest transaction per title wins.
        var categoryByTitle: [String: Category] = [:]
        for transaction in transactions.sorted(by: { $0.date < $1.date }) {
            guard let category = transaction.category, !category.isArchived else { continue }
            let key = transaction.title.trimmingCharacters(in: .whitespaces).lowercased()
            if key.isEmpty { continue }
            categoryByTitle[key] = category
        }

        var built: [ImportReviewRow] = []
        var initiallySelected: Set<Int> = []
        for (index, row) in rows.enumerated() {
            let key = row.description.trimmingCharacters(in: .whitespaces).lowercased()
            let wantedKind: CategoryKind = row.amount < 0 ? .expense : .income
            var suggestion: Category?
            if let candidate = categoryByTitle[key], candidate.kind == wantedKind {
                suggestion = candidate
            }
            let duplicate = existingFingerprints.contains(row.fingerprint)
            built.append(ImportReviewRow(id: index, row: row, alreadyImported: duplicate, suggested: suggestion))
            if !duplicate { initiallySelected.insert(index) }
        }
        reviewRows = built
        selected = initiallySelected
        stage = .review
    }

    private func performImport() {
        var count = 0
        for item in reviewRows where selected.contains(item.id) {
            let kind: TransactionKind = item.isExpense ? .expense : .income
            let fallback: Category? = item.isExpense ? expenseCategory : incomeCategory
            let transaction = Transaction(
                amount: item.row.amount.magnitudeValue,
                kind: kind,
                title: item.row.description,
                date: item.row.date,
                category: item.suggested ?? fallback,
                account: targetAccount
            )
            transaction.importFingerprint = item.row.fingerprint
            context.insert(transaction)
            count += 1
        }
        try? context.save()
        importedCount = count
        skippedCount = reviewRows.count - count
        stage = .finished
    }

    private func reset() {
        csvRows = []
        reviewRows = []
        selected = []
        fileName = ""
        unreadableCount = 0
        stage = .start
        showImporter = true
    }
}

// MARK: - Start

private struct ImportStartView: View {
    let onChoose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.inkTertiary)
            Text("Bring in a bank statement")
                .font(.titleSerif)
                .foregroundStyle(Palette.ink)
            Text("Download a CSV, OFX or QFX file from your bank, then choose it here. You will check every row before anything is added, and rows you have imported before are skipped.")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Choose file", action: onChoose)
                .buttonStyle(.tallyPrimary)
        }
        .padding(24)
    }
}

// MARK: - Mapping

private struct ImportMappingForm: View {
    @Environment(AppSettings.self) private var settings

    let fileName: String
    let csvRows: [[String]]
    @Binding var mapping: ImportColumnMapping
    let onContinue: () -> Void

    private var columnCount: Int {
        let widest = csvRows.prefix(50).map { $0.count }.max() ?? 1
        return max(widest, 1)
    }

    private func columnName(_ index: Int) -> String {
        if mapping.hasHeader, let header = csvRows.first, index < header.count {
            let text = header[index].trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { return text }
        }
        return "Column \(index + 1)"
    }

    /// The first rows, run through the current mapping.
    private var preview: ImportResult {
        StatementImporter.importRows(Array(csvRows.prefix(60)), mapping: mapping)
    }

    var body: some View {
        Form {
            fileSection
            columnsSection
            formatSection
            previewSection
        }
        .tallyScreen()
        .safeAreaInset(edge: .bottom) {
            continueBar
        }
    }

    private var fileSection: some View {
        Section {
            LabeledContent("File", value: fileName)
            Toggle("First row is a header", isOn: $mapping.hasHeader)
        } footer: {
            Text("Match each part of a transaction to a column in your file.")
        }
        .listRowBackground(Palette.surface)
    }

    private var columnsSection: some View {
        Section("Columns") {
            columnPicker("Date", selection: $mapping.dateColumn)
            columnPicker("Description", selection: $mapping.descriptionColumn)

            Picker("Amounts", selection: splitBinding) {
                Text("One amount column").tag(false)
                Text("Money out and in").tag(true)
            }
            .pickerStyle(.segmented)

            if mapping.amountColumn == nil {
                columnPicker("Money out", selection: optionalColumn(\.debitColumn))
                columnPicker("Money in", selection: optionalColumn(\.creditColumn))
            } else {
                columnPicker("Amount", selection: optionalColumn(\.amountColumn))
            }
        }
        .listRowBackground(Palette.surface)
    }

    private var formatSection: some View {
        Section {
            Picker("Date format", selection: dateFormatBinding) {
                Text("Auto-detect").tag("")
                ForEach(StatementImporter.commonDateFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }
            Picker("Decimal separator", selection: separatorBinding) {
                Text("Auto-detect").tag("auto")
                Text("Period (1,234.50)").tag(".")
                Text("Comma (1.234,50)").tag(",")
            }
            Toggle("Flip signs", isOn: $mapping.invertSign)
        } header: {
            Text("Format")
        } footer: {
            Text("Turn on Flip signs if your bank lists spending as positive numbers.")
        }
        .listRowBackground(Palette.surface)
    }

    private var previewSection: some View {
        let result = preview
        return Section {
            if result.rows.isEmpty {
                Text("No rows can be read with these settings yet. Check the date column and format.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.negative)
            } else {
                ForEach(Array(result.rows.prefix(10).enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.description.isEmpty ? "No description" : row.description)
                                .lineLimit(1)
                                .foregroundStyle(Palette.ink)
                            Text(row.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer()
                        Text(settings.format(row.amount, showsSign: true))
                            .font(.amountSmall)
                            .foregroundStyle(row.amount < 0 ? Palette.ink : Palette.positive)
                            .hidesAmount(settings.hideAmounts)
                    }
                }
                if !result.failedRows.isEmpty {
                    Text("\(result.failedRows.count) of the first rows could not be read and will be skipped.")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        } header: {
            Text("Preview (first 10 rows)")
        }
        .listRowBackground(Palette.surface)
    }

    private var continueBar: some View {
        let ready = !preview.rows.isEmpty
        return Button("Review rows", action: onContinue)
            .buttonStyle(.tallyPrimary)
            .disabled(!ready)
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 10)
            .background(Palette.paper)
    }

    // MARK: Bindings

    private func columnPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(0..<columnCount, id: \.self) { index in
                Text(columnName(index)).tag(index)
            }
        }
    }

    private func optionalColumn(_ keyPath: WritableKeyPath<ImportColumnMapping, Int?>) -> Binding<Int> {
        Binding<Int>(
            get: { mapping[keyPath: keyPath] ?? 0 },
            set: { mapping[keyPath: keyPath] = $0 }
        )
    }

    private var splitBinding: Binding<Bool> {
        Binding<Bool>(
            get: { mapping.amountColumn == nil },
            set: { useSplit in
                if useSplit {
                    mapping.amountColumn = nil
                    if mapping.debitColumn == nil { mapping.debitColumn = min(2, columnCount - 1) }
                    if mapping.creditColumn == nil { mapping.creditColumn = min(3, columnCount - 1) }
                } else if mapping.amountColumn == nil {
                    mapping.amountColumn = min(2, columnCount - 1)
                }
            }
        )
    }

    private var dateFormatBinding: Binding<String> {
        Binding<String>(
            get: { mapping.dateFormat ?? "" },
            set: { mapping.dateFormat = $0.isEmpty ? nil : $0 }
        )
    }

    private var separatorBinding: Binding<String> {
        Binding<String>(
            get: { mapping.decimalSeparator.map { String($0) } ?? "auto" },
            set: { value in
                mapping.decimalSeparator = value == "auto" ? nil : value.first
            }
        )
    }
}

// MARK: - Review

private struct ImportReviewView: View {
    @Environment(AppSettings.self) private var settings

    let fileName: String
    let rows: [ImportReviewRow]
    let unreadableCount: Int
    @Binding var selected: Set<Int>
    @Binding var targetAccount: Account?
    @Binding var expenseCategory: Category?
    @Binding var incomeCategory: Category?
    let expenseCategories: [Category]
    let incomeCategories: [Category]
    let canAdjustColumns: Bool
    let onAdjustColumns: () -> Void
    let onImport: () -> Void

    var body: some View {
        Form {
            destinationSection
            summarySection
            rowsSection
        }
        .tallyScreen()
        .safeAreaInset(edge: .bottom) {
            importBar
        }
    }

    private var destinationSection: some View {
        Section {
            AccountPicker(title: "Account", selection: $targetAccount)
            categoryPicker("Expenses go to", selection: $expenseCategory, options: expenseCategories)
            categoryPicker("Income goes to", selection: $incomeCategory, options: incomeCategories)
        } header: {
            Text("Import into")
        } footer: {
            Text("Rows whose description matches an earlier transaction reuse that transaction's category.")
        }
        .listRowBackground(Palette.surface)
    }

    private var summarySection: some View {
        let importable = rows.filter { !$0.alreadyImported }.count
        return Section {
            HStack {
                Text("\(selected.count) of \(rows.count) selected")
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button("All new") {
                    selected = Set(rows.filter { !$0.alreadyImported }.map { $0.id })
                }
                .buttonStyle(.borderless)
                .disabled(importable == 0)
                Button("None") {
                    selected = []
                }
                .buttonStyle(.borderless)
            }
            if unreadableCount > 0 {
                Text("\(unreadableCount) rows in the file could not be read and are left out.")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            if canAdjustColumns {
                Button("Adjust columns", action: onAdjustColumns)
            }
        } header: {
            Text(fileName)
        }
        .listRowBackground(Palette.surface)
    }

    private var rowsSection: some View {
        Section {
            ForEach(rows) { item in
                rowView(item)
            }
        } header: {
            Text("Transactions")
        }
        .listRowBackground(Palette.surface)
    }

    private func rowView(_ item: ImportReviewRow) -> some View {
        let isSelected = selected.contains(item.id)
        return Button {
            if isSelected {
                selected.remove(item.id)
            } else {
                selected.insert(item.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Palette.accent : Palette.inkTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.row.description.isEmpty ? "No description" : item.row.description)
                        .lineLimit(1)
                        .foregroundStyle(Palette.ink)
                    Text(detailText(for: item))
                        .font(.caption)
                        .foregroundStyle(item.alreadyImported ? Palette.caution : Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(settings.format(item.row.amount, showsSign: true))
                    .font(.amountSmall)
                    .foregroundStyle(item.isExpense ? Palette.ink : Palette.positive)
                    .hidesAmount(settings.hideAmounts)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func detailText(for item: ImportReviewRow) -> String {
        let date = item.row.date.formatted(date: .abbreviated, time: .omitted)
        if item.alreadyImported { return "\(date) · Already imported" }
        if let category = item.suggested { return "\(date) · \(category.name)" }
        return date
    }

    private var importBar: some View {
        Button(action: onImport) {
            Text(selected.isEmpty ? "Nothing selected" : "Import \(selected.count) transaction\(selected.count == 1 ? "" : "s")")
        }
        .buttonStyle(.tallyPrimary)
        .disabled(selected.isEmpty)
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.vertical, 10)
        .background(Palette.paper)
    }

    private func categoryPicker(_ title: String, selection: Binding<Category?>, options: [Category]) -> some View {
        Picker(title, selection: selection) {
            Text("Uncategorized").tag(Category?.none)
            ForEach(options) { category in
                Label(category.name, systemImage: category.symbol).tag(Category?.some(category))
            }
        }
    }
}

// MARK: - Done

private struct ImportDoneView: View {
    let importedCount: Int
    let skippedCount: Int
    let onAnother: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Palette.accent)
            Text("Imported \(importedCount) transaction\(importedCount == 1 ? "" : "s")")
                .font(.titleSerif)
                .foregroundStyle(Palette.ink)
            if skippedCount > 0 {
                Text("\(skippedCount) skipped")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            VStack(spacing: 10) {
                Button("Done", action: onDone)
                    .buttonStyle(.tallyPrimary)
                Button("Import another file", action: onAnother)
                    .buttonStyle(.tallySecondary)
            }
        }
        .padding(24)
    }
}

#Preview {
    NavigationStack {
        ImportStatementView()
    }
    .previewEnvironment()
}
