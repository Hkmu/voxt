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
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedFilter == filter ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selectedFilter == filter ? Color.accentColor.opacity(0.14) : .clear)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(selectedFilter == filter ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1)
                }
            }
        }
        .padding(2)
        .frame(width: 230)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
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
                .buttonStyle(.plain)
                .help("Edit")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        )
    }

    private var metadataText: String {
        var parts: [String] = []
        if entry.matchCount > 0 {
            parts.append(AppLocalization.format("Matched %d times", entry.matchCount))
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
                        Text(AppLocalization.format("Seen %d times", suggestion.seenCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let sample = suggestion.evidenceSamples.first, !sample.isEmpty {
                            Text("· \(sample)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            },
            actions: {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .help("Add to Dictionary")

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
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
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
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
