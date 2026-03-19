import Foundation
import Combine

enum DictionarySuggestionSourceContext: String, Codable {
    case history
    case correction
    case repeatObservation
}

enum DictionarySuggestionStatus: String, Codable {
    case pending
    case dismissed
    case added
}

struct DictionarySuggestionSnapshot: Identifiable, Codable, Hashable {
    let term: String
    let normalizedTerm: String
    let groupID: UUID?
    let groupNameSnapshot: String?

    var id: String {
        "\(normalizedTerm)|\(groupID?.uuidString ?? "global")"
    }
}

struct DictionarySuggestion: Identifiable, Codable, Hashable {
    let id: UUID
    var term: String
    var normalizedTerm: String
    var sourceContext: DictionarySuggestionSourceContext
    var status: DictionarySuggestionStatus
    var firstSeenAt: Date
    var lastSeenAt: Date
    var seenCount: Int
    var lastHistoryEntryID: UUID?
    var groupID: UUID?
    var groupNameSnapshot: String?
    var evidenceSamples: [String]

    init(
        id: UUID = UUID(),
        term: String,
        normalizedTerm: String,
        sourceContext: DictionarySuggestionSourceContext,
        status: DictionarySuggestionStatus = .pending,
        firstSeenAt: Date = Date(),
        lastSeenAt: Date = Date(),
        seenCount: Int = 1,
        lastHistoryEntryID: UUID? = nil,
        groupID: UUID? = nil,
        groupNameSnapshot: String? = nil,
        evidenceSamples: [String] = []
    ) {
        self.id = id
        self.term = term
        self.normalizedTerm = normalizedTerm
        self.sourceContext = sourceContext
        self.status = status
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.seenCount = seenCount
        self.lastHistoryEntryID = lastHistoryEntryID
        self.groupID = groupID
        self.groupNameSnapshot = groupNameSnapshot
        self.evidenceSamples = evidenceSamples
    }
}

struct DictionarySuggestionDraft: Identifiable, Hashable {
    let term: String
    let normalizedTerm: String
    let sourceContext: DictionarySuggestionSourceContext
    let groupID: UUID?
    let groupNameSnapshot: String?
    let evidenceSample: String

    var id: String {
        "\(normalizedTerm)|\(groupID?.uuidString ?? "global")"
    }

    var snapshot: DictionarySuggestionSnapshot {
        DictionarySuggestionSnapshot(
            term: term,
            normalizedTerm: normalizedTerm,
            groupID: groupID,
            groupNameSnapshot: groupNameSnapshot
        )
    }
}

struct DictionaryHistoryScanCheckpoint: Codable, Equatable {
    let lastProcessedAt: Date
    let lastHistoryEntryID: UUID
}

struct DictionaryHistoryScanProgress: Equatable {
    var isRunning = false
    var processedCount = 0
    var totalCount = 0
    var newSuggestionCount = 0
    var duplicateCount = 0
    var lastProcessedCount = 0
    var lastNewSuggestionCount = 0
    var lastDuplicateCount = 0
    var lastRunAt: Date?
    var errorMessage: String?
}

struct DictionaryHistoryScanCandidate: Hashable {
    let term: String
    let historyEntryIDs: [UUID]
    let groupID: UUID?
    let groupNameSnapshot: String?
    let evidenceSample: String
}

struct DictionaryHistoryScanApplyResult {
    let newSuggestionCount: Int
    let duplicateCount: Int
    let snapshotsByHistoryID: [UUID: [DictionarySuggestionSnapshot]]
}

struct DictionarySuggestionBulkAddResult: Equatable {
    let addedCount: Int
    let skippedCount: Int
}

struct DictionarySuggestionFilterSettings: Codable, Equatable, Hashable {
    var prompt: String
    var batchSize: Int
    var maxCandidatesPerBatch: Int

    static let defaultBatchSize = 12
    static let defaultMaxCandidatesPerBatch = 12
    static let minimumBatchSize = 1
    static let maximumBatchSize = 50
    static let minimumMaxCandidates = 1
    static let maximumMaxCandidates = 50

    static let defaultPrompt = """
    You're building a user dictionary for a speech-to-text app. Review history records to extract only terms worthy of recommendation. Ensure the dictionary is accurate, relevant, and aligned with user needs.

    ### Task Scope & Inclusion/Exclusion Rules
    Include only these verified terms:
    1. Personal names (specific individuals)
    2. Organization/brand/product/app/project names (companies, product models, app titles, project codes)
    3. Technical acronyms (domain-specific abbreviations with clear meanings)
    4. Uncommon domain jargon or consistent user-specific spellings

    Exclude:
    1. Common English words (e.g., "hello", "run", "happy")
    2. Generic verbs/adjectives/adverbs (e.g., "walk", "quick", "very")
    3. Ordinary capitalized words at sentence starts (e.g., "The")
    4. Filler words (e.g., "um", "like", "you know")
    5. Terms in `dictionaryHitTerms`/`dictionaryCorrectedTerms` unless records have a new, recommendable spelling (note the new spelling)
    6. Obviously incorrect words
    7. For Asian languages (Chinese, Korean, Japanese): Avoid common character combinations; only include proper nouns, domain jargon, or unique user spellings

    ### Priority & Validation Rules
    - Prioritize terms with >=2 occurrences
    - Analyze based on the user's main language
    - Single-record terms are included only if:
      - Clearly a proper noun (distinctive name/company)
      - Domain-specific technical term with clear context (e.g., rare medical jargon defined in the record)
    - For Asian languages: Ensure terms aren't common everyday expressions; check contextual relevance

    ### Input/Output Specifications
    - User's main language: {{USER_MAIN_LANGUAGE}}
    - Input: {{HISTORY_RECORDS}} (XML-wrapped speech-to-text history)
    - Output: Structured list of recommended terms
      - One term per line
      - Prefer short terms
      - Return null if no worthy terms
    """

    static let defaultValue = DictionarySuggestionFilterSettings(
        prompt: defaultPrompt,
        batchSize: defaultBatchSize,
        maxCandidatesPerBatch: defaultMaxCandidatesPerBatch
    )

    func sanitized() -> DictionarySuggestionFilterSettings {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return DictionarySuggestionFilterSettings(
            prompt: trimmedPrompt.isEmpty ? Self.defaultPrompt : trimmedPrompt,
            batchSize: min(max(batchSize, Self.minimumBatchSize), Self.maximumBatchSize),
            maxCandidatesPerBatch: min(
                max(maxCandidatesPerBatch, Self.minimumMaxCandidates),
                Self.maximumMaxCandidates
            )
        )
    }
}

@MainActor
final class DictionarySuggestionStore: ObservableObject {
    @Published private(set) var suggestions: [DictionarySuggestion] = []
    @Published private(set) var historyScanProgress = DictionaryHistoryScanProgress()
    @Published private(set) var filterSettings = DictionarySuggestionFilterSettings.defaultValue

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private let evidenceLimit = 3

    init() {
        reload()
    }

    var pendingSuggestions: [DictionarySuggestion] {
        suggestions
            .filter { $0.status == .pending }
            .sorted {
                if $0.lastSeenAt == $1.lastSeenAt {
                    return $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
                }
                return $0.lastSeenAt > $1.lastSeenAt
            }
    }

    func reload() {
        filterSettings = loadFilterSettings()
        do {
            let url = try suggestionsFileURL()
            guard fileManager.fileExists(atPath: url.path) else {
                suggestions = []
                return
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([DictionarySuggestion].self, from: data)
            let deduplicated = deduplicatedSuggestions(decoded)
            suggestions = deduplicated
            if decoded != deduplicated {
                persist()
            }
        } catch {
            suggestions = []
        }
    }

    func saveFilterSettings(_ settings: DictionarySuggestionFilterSettings) {
        let sanitized = settings.sanitized()
        filterSettings = sanitized
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        defaults.set(data, forKey: AppPreferenceKey.dictionarySuggestionFilterSettings)
    }

    func resetFilterSettingsToDefault() {
        saveFilterSettings(.defaultValue)
    }

    func status(for snapshot: DictionarySuggestionSnapshot) -> DictionarySuggestionStatus? {
        suggestions.first {
            $0.normalizedTerm == snapshot.normalizedTerm && $0.groupID == snapshot.groupID
        }?.status
    }

    func dismiss(id: UUID) {
        guard let index = suggestions.firstIndex(where: { $0.id == id }) else { return }
        suggestions[index].status = .dismissed
        suggestions[index].lastSeenAt = Date()
        persist()
    }

    func clearAll() {
        suggestions = []
        persist()
    }

    var historyScanCheckpoint: DictionaryHistoryScanCheckpoint? {
        guard let data = defaults.data(forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint),
              let checkpoint = try? JSONDecoder().decode(DictionaryHistoryScanCheckpoint.self, from: data)
        else {
            return nil
        }
        return checkpoint
    }

    func pendingHistoryEntries(in historyStore: TranscriptionHistoryStore) -> [TranscriptionHistoryEntry] {
        let sorted = historyStore.allHistoryEntries.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.createdAt < $1.createdAt
        }

        let pendingEntries: [TranscriptionHistoryEntry]
        if let checkpoint = historyScanCheckpoint {
            pendingEntries = sorted.filter {
                if $0.createdAt > checkpoint.lastProcessedAt {
                    return true
                }
                if $0.createdAt < checkpoint.lastProcessedAt {
                    return false
                }
                return $0.id.uuidString > checkpoint.lastHistoryEntryID.uuidString
            }
        } else {
            pendingEntries = sorted
        }

        return pendingEntries.filter { $0.kind == .normal }
    }

    func beginHistoryScan(totalCount: Int) {
        historyScanProgress = DictionaryHistoryScanProgress(
            isRunning: true,
            processedCount: 0,
            totalCount: totalCount,
            newSuggestionCount: 0,
            duplicateCount: 0,
            lastProcessedCount: historyScanProgress.lastProcessedCount,
            lastNewSuggestionCount: historyScanProgress.lastNewSuggestionCount,
            lastDuplicateCount: historyScanProgress.lastDuplicateCount,
            lastRunAt: historyScanProgress.lastRunAt,
            errorMessage: nil
        )
    }

    func updateHistoryScan(processedCount: Int, newSuggestionCount: Int, duplicateCount: Int) {
        historyScanProgress.processedCount = processedCount
        historyScanProgress.newSuggestionCount = newSuggestionCount
        historyScanProgress.duplicateCount = duplicateCount
    }

    func finishHistoryScan(
        processedCount: Int,
        newSuggestionCount: Int,
        duplicateCount: Int,
        checkpointEntry: TranscriptionHistoryEntry?
    ) {
        if let checkpointEntry {
            persistHistoryScanCheckpoint(
                DictionaryHistoryScanCheckpoint(
                    lastProcessedAt: checkpointEntry.createdAt,
                    lastHistoryEntryID: checkpointEntry.id
                )
            )
        }

        historyScanProgress = DictionaryHistoryScanProgress(
            isRunning: false,
            processedCount: processedCount,
            totalCount: processedCount,
            newSuggestionCount: newSuggestionCount,
            duplicateCount: duplicateCount,
            lastProcessedCount: processedCount,
            lastNewSuggestionCount: newSuggestionCount,
            lastDuplicateCount: duplicateCount,
            lastRunAt: Date(),
            errorMessage: nil
        )
    }

    func advanceHistoryScanCheckpoint(to entry: TranscriptionHistoryEntry) {
        persistHistoryScanCheckpoint(
            DictionaryHistoryScanCheckpoint(
                lastProcessedAt: entry.createdAt,
                lastHistoryEntryID: entry.id
            )
        )
    }

    func failHistoryScan(
        processedCount: Int,
        totalCount: Int,
        newSuggestionCount: Int,
        duplicateCount: Int,
        errorMessage: String
    ) {
        historyScanProgress = DictionaryHistoryScanProgress(
            isRunning: false,
            processedCount: processedCount,
            totalCount: totalCount,
            newSuggestionCount: newSuggestionCount,
            duplicateCount: duplicateCount,
            lastProcessedCount: historyScanProgress.lastProcessedCount,
            lastNewSuggestionCount: historyScanProgress.lastNewSuggestionCount,
            lastDuplicateCount: historyScanProgress.lastDuplicateCount,
            lastRunAt: historyScanProgress.lastRunAt,
            errorMessage: errorMessage
        )
    }

    func dismiss(term: String, groupID: UUID?) {
        let normalized = DictionaryStore.normalizeTerm(term)
        guard !normalized.isEmpty else { return }
        if let index = suggestions.firstIndex(where: { $0.normalizedTerm == normalized && $0.groupID == groupID }) {
            suggestions[index].status = .dismissed
            suggestions[index].lastSeenAt = Date()
        } else {
            suggestions.append(
                DictionarySuggestion(
                    term: term,
                    normalizedTerm: normalized,
                    sourceContext: .history,
                    status: .dismissed,
                    groupID: groupID
                )
            )
        }
        persist()
    }

    func addToDictionary(id: UUID, dictionaryStore: DictionaryStore) {
        guard let suggestion = suggestions.first(where: { $0.id == id }) else { return }
        addToDictionary(
            term: suggestion.term,
            groupID: suggestion.groupID,
            groupNameSnapshot: suggestion.groupNameSnapshot,
            dictionaryStore: dictionaryStore
        )
    }

    func addToDictionary(
        term: String,
        groupID: UUID?,
        groupNameSnapshot: String?,
        dictionaryStore: DictionaryStore
    ) {
        let normalized = DictionaryStore.normalizeTerm(term)
        guard !normalized.isEmpty else { return }

        if !dictionaryStore.hasEntry(normalizedTerm: normalized, activeGroupID: groupID) {
            try? dictionaryStore.createAutoEntry(
                term: term,
                groupID: groupID,
                groupNameSnapshot: groupNameSnapshot
            )
        }

        if let index = suggestions.firstIndex(where: { $0.normalizedTerm == normalized && $0.groupID == groupID }) {
            suggestions[index].status = .added
            suggestions[index].lastSeenAt = Date()
        } else {
            suggestions.append(
                DictionarySuggestion(
                    term: term,
                    normalizedTerm: normalized,
                    sourceContext: .history,
                    status: .added,
                    groupID: groupID,
                    groupNameSnapshot: groupNameSnapshot
                )
            )
        }
        persist()
    }

    func addAllPendingToDictionary(dictionaryStore: DictionaryStore) -> DictionarySuggestionBulkAddResult {
        guard !pendingSuggestions.isEmpty else {
            return DictionarySuggestionBulkAddResult(addedCount: 0, skippedCount: 0)
        }

        let now = Date()
        var addedCount = 0
        var skippedCount = 0

        for suggestion in pendingSuggestions {
            if dictionaryStore.hasEntry(
                normalizedTerm: suggestion.normalizedTerm,
                activeGroupID: suggestion.groupID
            ) {
                if let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) {
                    suggestions[index].status = .added
                    suggestions[index].lastSeenAt = now
                }
                skippedCount += 1
                continue
            }

            do {
                try dictionaryStore.createAutoEntry(
                    term: suggestion.term,
                    groupID: suggestion.groupID,
                    groupNameSnapshot: suggestion.groupNameSnapshot
                )
                if let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) {
                    suggestions[index].status = .added
                    suggestions[index].lastSeenAt = now
                }
                addedCount += 1
            } catch {
                if dictionaryStore.hasEntry(
                    normalizedTerm: suggestion.normalizedTerm,
                    activeGroupID: suggestion.groupID
                ), let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) {
                    suggestions[index].status = .added
                    suggestions[index].lastSeenAt = now
                }
                skippedCount += 1
            }
        }

        persist()
        return DictionarySuggestionBulkAddResult(addedCount: addedCount, skippedCount: skippedCount)
    }

    func discoverSuggestions(
        in finalText: String,
        activeGroupID: UUID?,
        activeGroupName: String?,
        dictionaryStore: DictionaryStore,
        matchedCandidates: [DictionaryMatchCandidate],
        correctedTerms: [String]
    ) -> [DictionarySuggestionDraft] {
        _ = finalText
        _ = activeGroupID
        _ = activeGroupName
        _ = dictionaryStore
        _ = matchedCandidates
        _ = correctedTerms
        return []
    }

    func applyDiscoveredSuggestions(_ drafts: [DictionarySuggestionDraft], historyEntryID: UUID?) {
        guard !drafts.isEmpty else { return }
        let now = Date()

        for draft in drafts {
            if let index = suggestions.firstIndex(where: {
                $0.normalizedTerm == draft.normalizedTerm && $0.groupID == draft.groupID
            }) {
                suggestions[index].term = draft.term
                suggestions[index].lastSeenAt = now
                suggestions[index].seenCount += 1
                suggestions[index].lastHistoryEntryID = historyEntryID
                suggestions[index].groupNameSnapshot = draft.groupNameSnapshot ?? suggestions[index].groupNameSnapshot
                if suggestions[index].status == .pending {
                    suggestions[index].sourceContext = draft.sourceContext
                }
                appendEvidenceSample(draft.evidenceSample, to: &suggestions[index])
            } else {
                suggestions.append(
                    DictionarySuggestion(
                        term: draft.term,
                        normalizedTerm: draft.normalizedTerm,
                        sourceContext: draft.sourceContext,
                        firstSeenAt: now,
                        lastSeenAt: now,
                        seenCount: 1,
                        lastHistoryEntryID: historyEntryID,
                        groupID: draft.groupID,
                        groupNameSnapshot: draft.groupNameSnapshot,
                        evidenceSamples: draft.evidenceSample.isEmpty ? [] : [draft.evidenceSample]
                    )
                )
            }
        }

        suggestions = deduplicatedSuggestions(suggestions)
        persist()
    }

    func applyHistoryScanCandidates(
        _ candidates: [DictionaryHistoryScanCandidate],
        dictionaryStore: DictionaryStore
    ) -> DictionaryHistoryScanApplyResult {
        guard !candidates.isEmpty else {
            return DictionaryHistoryScanApplyResult(
                newSuggestionCount: 0,
                duplicateCount: 0,
                snapshotsByHistoryID: [:]
            )
        }

        var newSuggestionCount = 0
        var duplicateCount = 0

        for candidate in candidates {
            let normalized = DictionaryStore.normalizeTerm(candidate.term)
            guard !normalized.isEmpty else { continue }
            guard !dictionaryStore.hasEntry(normalizedTerm: normalized, activeGroupID: candidate.groupID) else {
                duplicateCount += 1
                continue
            }

            do {
                try dictionaryStore.createAutoEntry(
                    term: candidate.term,
                    groupID: candidate.groupID,
                    groupNameSnapshot: candidate.groupNameSnapshot
                )
                newSuggestionCount += 1
            } catch {
                if dictionaryStore.hasEntry(normalizedTerm: normalized, activeGroupID: candidate.groupID) {
                    duplicateCount += 1
                }
            }
        }

        return DictionaryHistoryScanApplyResult(
            newSuggestionCount: newSuggestionCount,
            duplicateCount: duplicateCount,
            snapshotsByHistoryID: [:]
        )
    }

    private func appendEvidenceSample(_ sample: String, to suggestion: inout DictionarySuggestion) {
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        suggestion.evidenceSamples.removeAll { $0 == trimmed }
        suggestion.evidenceSamples.insert(trimmed, at: 0)
        if suggestion.evidenceSamples.count > evidenceLimit {
            suggestion.evidenceSamples = Array(suggestion.evidenceSamples.prefix(evidenceLimit))
        }
    }

    private func loadFilterSettings() -> DictionarySuggestionFilterSettings {
        guard
            let data = defaults.data(forKey: AppPreferenceKey.dictionarySuggestionFilterSettings),
            let decoded = try? JSONDecoder().decode(DictionarySuggestionFilterSettings.self, from: data)
        else {
            return .defaultValue
        }
        return decoded.sanitized()
    }

    private func deduplicatedSuggestions(_ items: [DictionarySuggestion]) -> [DictionarySuggestion] {
        var mergedByKey: [String: DictionarySuggestion] = [:]
        var keyOrder: [String] = []

        for item in items {
            let key = suggestionKey(normalizedTerm: item.normalizedTerm, groupID: item.groupID)
            if var existing = mergedByKey[key] {
                existing = mergeSuggestion(existing, with: item)
                mergedByKey[key] = existing
            } else {
                mergedByKey[key] = item
                keyOrder.append(key)
            }
        }

        return keyOrder
            .compactMap { mergedByKey[$0] }
            .sorted {
                if $0.lastSeenAt == $1.lastSeenAt {
                    return $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
                }
                return $0.lastSeenAt > $1.lastSeenAt
            }
    }

    private func mergeSuggestion(_ lhs: DictionarySuggestion, with rhs: DictionarySuggestion) -> DictionarySuggestion {
        let newer = rhs.lastSeenAt >= lhs.lastSeenAt ? rhs : lhs
        let older = rhs.lastSeenAt >= lhs.lastSeenAt ? lhs : rhs

        var merged = older
        merged.term = newer.term
        merged.normalizedTerm = newer.normalizedTerm
        merged.sourceContext = newer.sourceContext
        merged.status = mergedStatus(lhs.status, rhs.status)
        merged.firstSeenAt = min(lhs.firstSeenAt, rhs.firstSeenAt)
        merged.lastSeenAt = max(lhs.lastSeenAt, rhs.lastSeenAt)
        merged.seenCount = max(lhs.seenCount, 0) + max(rhs.seenCount, 0)
        merged.lastHistoryEntryID = newer.lastHistoryEntryID ?? older.lastHistoryEntryID
        merged.groupID = newer.groupID ?? older.groupID
        merged.groupNameSnapshot = newer.groupNameSnapshot ?? older.groupNameSnapshot
        merged.evidenceSamples = mergedEvidenceSamples(primary: newer.evidenceSamples, secondary: older.evidenceSamples)
        return merged
    }

    private func mergedStatus(
        _ lhs: DictionarySuggestionStatus,
        _ rhs: DictionarySuggestionStatus
    ) -> DictionarySuggestionStatus {
        func rank(for status: DictionarySuggestionStatus) -> Int {
            switch status {
            case .pending:
                return 0
            case .dismissed:
                return 1
            case .added:
                return 2
            }
        }

        return rank(for: rhs) >= rank(for: lhs) ? rhs : lhs
    }

    private func mergedEvidenceSamples(primary: [String], secondary: [String]) -> [String] {
        var merged: [String] = []
        for sample in primary + secondary {
            let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !merged.contains(trimmed) else { continue }
            merged.append(trimmed)
            if merged.count >= evidenceLimit {
                break
            }
        }
        return merged
    }

    private func suggestionKey(normalizedTerm: String, groupID: UUID?) -> String {
        "\(normalizedTerm)|\(groupID?.uuidString ?? "global")"
    }

    private func persist() {
        do {
            let normalizedSuggestions = deduplicatedSuggestions(suggestions)
            suggestions = normalizedSuggestions
            let data = try JSONEncoder().encode(normalizedSuggestions)
            let url = try suggestionsFileURL()
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Keep UI responsive even if persistence fails.
        }
    }

    private func suggestionsFileURL() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("dictionary-suggestions.json")
    }

    private func persistHistoryScanCheckpoint(_ checkpoint: DictionaryHistoryScanCheckpoint) {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        defaults.set(data, forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint)
    }
}
