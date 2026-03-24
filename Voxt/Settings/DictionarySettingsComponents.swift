import SwiftUI

struct DictionaryFilterPicker: View {
    @Binding var selectedFilter: DictionaryFilter

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DictionaryFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    Text(LocalizedStringKey(filter.titleKey))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SettingsSegmentedButtonStyle(isSelected: selectedFilter == filter))
            }
        }
        .padding(2)
        .frame(width: 230)
        .settingsCardSurface(cornerRadius: SettingsUIStyle.compactCornerRadius, fillOpacity: 1)
    }
}

struct DictionaryRow: View {
    let entry: DictionaryEntry
    let scopeLabel: String
    let scopeIsMissing: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        DictionaryListRowContainer(
            content: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.term)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .textSelection(.enabled)

                    HStack(spacing: 6) {
                        DictionaryCapsuleBadge(
                            title: LocalizedStringKey(entry.source.titleKey),
                            fill: entry.source == .manual ? Color.accentColor.opacity(0.15) : Color.orange.opacity(0.15),
                            foreground: entry.source == .manual ? Color.accentColor : Color.orange
                        )
                        DictionaryCapsuleBadge(
                            title: scopeLabel,
                            fill: scopeIsMissing ? Color.red.opacity(0.14) : Color.secondary.opacity(0.12),
                            foreground: scopeIsMissing ? Color.red : Color.secondary
                        )
                        Text(metadataText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            },
            actions: {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(SettingsCompactIconButtonStyle())
                .help("Edit")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(SettingsCompactIconButtonStyle(tone: .destructive))
                .help("Delete")
            }
        )
    }

    private var metadataText: String {
        var parts: [String] = []
        if entry.matchCount > 0 {
            parts.append(AppLocalization.format("Matched %d times", entry.matchCount))
        }
        if !entry.replacementTerms.isEmpty {
            parts.append(AppLocalization.format("Aliases %d", entry.replacementTerms.count))
        }
        parts.append(AppLocalization.format("Variants %d", entry.observedVariants.count))
        if let lastMatchedAt = entry.lastMatchedAt {
            parts.append(
                AppLocalization.format(
                    "Last matched %@",
                    Self.timestampFormatter.localizedString(for: lastMatchedAt, relativeTo: Date())
                )
            )
        }
        return parts.joined(separator: " · ")
    }

    private static let timestampFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

struct DictionarySuggestionRow: View {
    let suggestion: DictionarySuggestion
    let scopeLabel: String
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        DictionaryListRowContainer(
            content: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.term)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .textSelection(.enabled)

                    HStack(spacing: 6) {
                        DictionaryCapsuleBadge(
                            title: scopeLabel,
                            fill: Color.secondary.opacity(0.12),
                            foreground: Color.secondary
                        )
                    }
                }
            },
            actions: {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(SettingsCompactIconButtonStyle())
                .help("Add to Dictionary")

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(SettingsCompactIconButtonStyle())
                .help("Ignore")
            }
        )
    }
}

enum DictionaryDialog: Identifiable {
    case create
    case edit(DictionaryEntry)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let entry):
            return "edit-\(entry.id.uuidString)"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .create:
            return "Create Dictionary Term"
        case .edit:
            return "Edit Dictionary Term"
        }
    }

    var confirmButtonTitle: LocalizedStringKey {
        switch self {
        case .create:
            return "Create"
        case .edit:
            return "Save"
        }
    }
}

private struct DictionaryListRowContainer<Content: View, Actions: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            content()

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                actions()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .settingsCardSurface(cornerRadius: SettingsUIStyle.compactCornerRadius, fillOpacity: 1)
    }
}

private struct DictionaryCapsuleBadge: View {
    let title: Text
    let fill: Color
    let foreground: Color

    init<Title: StringProtocol>(title: Title, fill: Color, foreground: Color) {
        self.title = Text(String(title))
        self.fill = fill
        self.foreground = foreground
    }

    init(title: LocalizedStringKey, fill: Color, foreground: Color) {
        self.title = Text(title)
        self.fill = fill
        self.foreground = foreground
    }

    var body: some View {
        title
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
            )
            .foregroundStyle(foreground)
    }
}

struct DictionaryEditableTagList: View {
    let values: [String]
    let onRemove: (String) -> Void

    var body: some View {
        DictionaryTagFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(values, id: \.self) { value in
                HStack(spacing: 6) {
                    Text(value)
                        .lineLimit(1)
                        .textSelection(.enabled)

                    Button {
                        onRemove(value)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
                .fixedSize()
            }
        }
    }
}

private struct DictionaryTagFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(horizontalSpacing: CGFloat = 8, verticalSpacing: CGFloat = 8) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let containerWidth = proposal.width ?? .greatestFiniteMagnitude
        let rows = arrangedRows(for: containerWidth, subviews: subviews)
        let width = rows.map { row in
            row.reduce(CGFloat.zero) { partialResult, item in
                partialResult + item.size.width
            } + horizontalSpacing * CGFloat(max(row.count - 1, 0))
        }.max() ?? 0
        let height = rows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + (row.map(\.size.height).max() ?? 0)
        } + verticalSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = arrangedRows(for: bounds.width, subviews: subviews)
        var currentY = bounds.minY

        for row in rows {
            let rowHeight = row.map(\.size.height).max() ?? 0
            var currentX = bounds.minX

            for item in row {
                item.subview.place(
                    at: CGPoint(x: currentX, y: currentY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                currentX += item.size.width + horizontalSpacing
            }

            currentY += rowHeight + verticalSpacing
        }
    }

    private func arrangedRows(for width: CGFloat, subviews: Subviews) -> [[RowItem]] {
        let maxWidth = width.isFinite && width > 0 ? width : .greatestFiniteMagnitude
        var rows: [[RowItem]] = []
        var currentRow: [RowItem] = []
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedRowWidth = currentRow.isEmpty
                ? size.width
                : currentRowWidth + horizontalSpacing + size.width

            if !currentRow.isEmpty && proposedRowWidth > maxWidth {
                rows.append(currentRow)
                currentRow = []
                currentRowWidth = 0
            }

            currentRow.append(RowItem(subview: subview, size: size))
            currentRowWidth = currentRow.isEmpty
                ? 0
                : currentRow.reduce(CGFloat.zero) { partialResult, item in
                    partialResult + item.size.width
                } + horizontalSpacing * CGFloat(max(currentRow.count - 1, 0))
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    private struct RowItem {
        let subview: LayoutSubview
        let size: CGSize
    }
}
