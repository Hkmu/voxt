import Foundation
import Combine

enum DictionaryEntrySource: String, Codable, CaseIterable {
    case manual
    case auto

    var titleKey: String {
        switch self {
        case .manual:
            return "Manual"
        case .auto:
            return "Automatic"
        }
    }
}

enum DictionaryEntryStatus: String, Codable {
    case active
    case disabled
}

enum DictionaryVariantConfidence: String, Codable {
    case high
    case medium
    case low
}

enum DictionaryFilter: String, CaseIterable, Identifiable {
    case all
    case autoAdded
    case manualAdded

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all:
            return "All"
        case .autoAdded:
            return "Automatic"
        case .manualAdded:
            return "Manual"
        }
    }
}

struct ObservedVariant: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var normalizedText: String
    var count: Int
    var lastSeenAt: Date
    var confidence: DictionaryVariantConfidence

    init(
        id: UUID = UUID(),
        text: String,
        normalizedText: String,
        count: Int = 1,
        lastSeenAt: Date = Date(),
        confidence: DictionaryVariantConfidence
    ) {
        self.id = id
        self.text = text
        self.normalizedText = normalizedText
        self.count = count
        self.lastSeenAt = lastSeenAt
        self.confidence = confidence
    }
}

struct DictionaryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var term: String
    var normalizedTerm: String
    var groupID: UUID?
    var groupNameSnapshot: String?
    var source: DictionaryEntrySource
    var createdAt: Date
    var updatedAt: Date
    var lastMatchedAt: Date?
    var matchCount: Int
    var status: DictionaryEntryStatus
    var observedVariants: [ObservedVariant]

    init(
        id: UUID = UUID(),
        term: String,
        normalizedTerm: String,
        groupID: UUID? = nil,
        groupNameSnapshot: String? = nil,
        source: DictionaryEntrySource,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastMatchedAt: Date? = nil,
        matchCount: Int = 0,
        status: DictionaryEntryStatus = .active,
        observedVariants: [ObservedVariant] = []
    ) {
        self.id = id
        self.term = term
        self.normalizedTerm = normalizedTerm
        self.groupID = groupID
        self.groupNameSnapshot = groupNameSnapshot
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMatchedAt = lastMatchedAt
        self.matchCount = matchCount
        self.status = status
        self.observedVariants = observedVariants
    }
}

enum DictionaryMatchReason: String, Codable {
    case exactTerm
    case exactVariant
    case exactWindow
    case fuzzyWindow
}

struct DictionaryMatchCandidate: Identifiable, Hashable {
    let entryID: UUID
    let term: String
    let matchedText: String
    let normalizedMatchedText: String
    let score: Double
    let reason: DictionaryMatchReason

    var id: String {
        "\(entryID.uuidString)|\(normalizedMatchedText)|\(reason.rawValue)"
    }

    var allowsAutomaticReplacement: Bool {
        switch reason {
        case .exactVariant:
            return true
        case .exactWindow:
            return score >= 0.985
        case .fuzzyWindow:
            return score >= 0.97 && normalizedMatchedText.count >= 5
        case .exactTerm:
            return false
        }
    }
}

struct DictionaryPromptContext {
    let entries: [DictionaryEntry]
    let candidates: [DictionaryMatchCandidate]

    var isEmpty: Bool {
        entries.isEmpty || candidates.isEmpty
    }

    func glossaryText(limit: Int = 12) -> String {
        guard !isEmpty else { return "" }

        var seen = Set<UUID>()
        var lines: [String] = []
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard let entry = entries.first(where: { $0.id == candidate.entryID }) else { continue }
            guard seen.insert(entry.id).inserted else { continue }
            lines.append("- \(entry.term)")
            if lines.count >= limit {
                break
            }
        }
        return lines.joined(separator: "\n")
    }
}

struct DictionaryCorrectionResult {
    let text: String
    let candidates: [DictionaryMatchCandidate]
    let correctedTerms: [String]
}

struct DictionaryImportResult: Equatable {
    let addedCount: Int
    let skippedCount: Int
}

enum DictionaryStoreError: LocalizedError {
    case emptyTerm
    case duplicateTerm

    var errorDescription: String? {
        switch self {
        case .emptyTerm:
            return AppLocalization.localizedString("Dictionary term cannot be empty.")
        case .duplicateTerm:
            return AppLocalization.localizedString("This term already exists in the dictionary.")
        }
    }
}

private struct DictionaryToken {
    let raw: String
    let normalized: String
}

private struct DictionaryScriptProfile {
    var containsLatin = false
    var containsDigit = false
    var containsHan = false
    var containsKana = false
    var containsHangul = false

    var containsCJKLike: Bool {
        containsHan || containsKana || containsHangul
    }

    var isLatinLike: Bool {
        (containsLatin || containsDigit) && !containsCJKLike
    }

    var isMixedScript: Bool {
        containsCJKLike && (containsLatin || containsDigit)
    }
}

struct DictionaryMatcher {
    let entries: [DictionaryEntry]

    func promptContext(for text: String) -> DictionaryPromptContext {
        let candidates = recallCandidates(in: text)
        return DictionaryPromptContext(entries: entries, candidates: candidates)
    }

    func recallCandidates(in text: String) -> [DictionaryMatchCandidate] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let rawTokens = tokenize(trimmed)
        var bestByID: [String: DictionaryMatchCandidate] = [:]

        for entry in entries where entry.status == .active {
            let variants = [entry.term] + entry.observedVariants.map(\.text)
            for variant in variants {
                guard let candidate = bestCandidate(for: entry, variant: variant, text: trimmed, rawTokens: rawTokens) else {
                    continue
                }
                let key = candidate.id
                if let existing = bestByID[key], existing.score >= candidate.score {
                    continue
                }
                bestByID[key] = candidate
            }
        }

        return bestByID.values
            .sorted {
                if $0.score == $1.score {
                    return $0.term < $1.term
                }
                return $0.score > $1.score
            }
    }

    func applyCorrections(to text: String, automaticReplacementEnabled: Bool) -> DictionaryCorrectionResult {
        let candidates = recallCandidates(in: text)
        guard automaticReplacementEnabled else {
            return DictionaryCorrectionResult(text: text, candidates: candidates, correctedTerms: [])
        }

        var output = text
        var correctedTerms: [String] = []
        for candidate in candidates.sorted(by: { $0.score > $1.score }) where candidate.allowsAutomaticReplacement {
            let matched = candidate.matchedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !matched.isEmpty, matched != candidate.term else { continue }
            if let range = output.range(of: matched) {
                output.replaceSubrange(range, with: candidate.term)
                correctedTerms.append(candidate.term)
            } else if let range = output.range(of: matched, options: [.caseInsensitive, .diacriticInsensitive]) {
                output.replaceSubrange(range, with: candidate.term)
                correctedTerms.append(candidate.term)
            }
        }

        return DictionaryCorrectionResult(
            text: output,
            candidates: candidates,
            correctedTerms: correctedTerms
        )
    }

    private func bestCandidate(
        for entry: DictionaryEntry,
        variant: String,
        text: String,
        rawTokens: [DictionaryToken]
    ) -> DictionaryMatchCandidate? {
        let normalizedVariant = DictionaryStore.normalizeTerm(variant)
        guard !normalizedVariant.isEmpty else { return nil }
        let scriptProfile = scriptProfile(for: variant)

        let normalizedText = DictionaryStore.normalizeTerm(text)
        if normalizedText == normalizedVariant || normalizedText.contains(normalizedVariant) {
            let reason: DictionaryMatchReason = (normalizedVariant == entry.normalizedTerm) ? .exactTerm : .exactVariant
            return DictionaryMatchCandidate(
                entryID: entry.id,
                term: entry.term,
                matchedText: variant,
                normalizedMatchedText: normalizedVariant,
                score: reason == .exactTerm ? 1.0 : 0.995,
                reason: reason
            )
        }

                let variantTokenCount = max(1, tokenize(variant).count)
        let windowSizes = Array(Set([variantTokenCount, max(1, variantTokenCount - 1), variantTokenCount + 1])).sorted()
        var best: DictionaryMatchCandidate?

        for windowSize in windowSizes {
            guard windowSize <= rawTokens.count else { continue }
            for start in 0...(rawTokens.count - windowSize) {
                let window = Array(rawTokens[start..<(start + windowSize)])
                let rawWindow = window.map(\.raw).joined(separator: " ")
                let normalizedWindow = window.map(\.normalized).joined(separator: " ")
                guard !normalizedWindow.isEmpty else { continue }

                if normalizedWindow == normalizedVariant {
                    let reason: DictionaryMatchReason = (normalizedVariant == entry.normalizedTerm) ? .exactWindow : .exactVariant
                    let candidate = DictionaryMatchCandidate(
                        entryID: entry.id,
                        term: entry.term,
                        matchedText: rawWindow,
                        normalizedMatchedText: normalizedWindow,
                        score: reason == .exactWindow ? 0.99 : 0.995,
                        reason: reason
                    )
                    if best == nil || best!.score < candidate.score {
                        best = candidate
                    }
                    continue
                }

                guard allowsFuzzyMatch(for: scriptProfile) else { continue }
                let distance = levenshteinDistance(lhs: normalizedWindow, rhs: normalizedVariant)
                let maxLength = max(normalizedWindow.count, normalizedVariant.count)
                guard maxLength >= minimumFuzzyLength(for: scriptProfile) else { continue }
                let threshold = fuzzyThreshold(for: scriptProfile, maxLength: maxLength)
                guard distance <= threshold else { continue }

                let score = 1.0 - (Double(distance) / Double(maxLength))
                guard score >= minimumFuzzyScore(for: scriptProfile) else { continue }
                let candidate = DictionaryMatchCandidate(
                    entryID: entry.id,
                    term: entry.term,
                    matchedText: rawWindow,
                    normalizedMatchedText: normalizedWindow,
                    score: score,
                    reason: .fuzzyWindow
                )
                if best == nil || best!.score < candidate.score {
                    best = candidate
                }
            }
        }

        return best
    }

    private func tokenize(_ text: String) -> [DictionaryToken] {
        var tokens: [DictionaryToken] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                current = ""
                return
            }
            let normalized = DictionaryStore.normalizeTerm(trimmed)
            if !normalized.isEmpty {
                tokens.append(DictionaryToken(raw: trimmed, normalized: normalized))
            }
            current = ""
        }

        for scalar in text.unicodeScalars {
            if isDictionaryWordScalar(scalar) {
                current.unicodeScalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    private func scriptProfile(for text: String) -> DictionaryScriptProfile {
        var profile = DictionaryScriptProfile()
        for scalar in text.unicodeScalars {
            if CharacterSet.decimalDigits.contains(scalar) {
                profile.containsDigit = true
            } else if CharacterSet.letters.contains(scalar), !isHanLike(scalar), !isKana(scalar), !isHangul(scalar) {
                profile.containsLatin = true
            }

            if isHanLike(scalar) {
                profile.containsHan = true
            }
            if isKana(scalar) {
                profile.containsKana = true
            }
            if isHangul(scalar) {
                profile.containsHangul = true
            }
        }
        return profile
    }

    private func allowsFuzzyMatch(for profile: DictionaryScriptProfile) -> Bool {
        profile.isLatinLike || profile.isMixedScript
    }

    private func minimumFuzzyLength(for profile: DictionaryScriptProfile) -> Int {
        profile.isMixedScript ? 5 : 4
    }

    private func minimumFuzzyScore(for profile: DictionaryScriptProfile) -> Double {
        profile.isMixedScript ? 0.96 : 0.90
    }

    private func fuzzyThreshold(for profile: DictionaryScriptProfile, maxLength: Int) -> Int {
        if profile.isMixedScript {
            return maxLength >= 10 ? 2 : 1
        }
        return max(1, min(2, maxLength / 6))
    }

    private func isDictionaryWordScalar(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || isHanLike(scalar) || isKana(scalar) || isHangul(scalar)
    }

    private func isHanLike(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF,
             0x3400...0x4DBF,
             0x20000...0x2A6DF,
             0x2A700...0x2B73F,
             0x2B740...0x2B81F,
             0x2B820...0x2CEAF:
            return true
        default:
            return false
        }
    }

    private func isKana(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x309F,
             0x30A0...0x30FF,
             0x31F0...0x31FF,
             0xFF66...0xFF9F:
            return true
        default:
            return false
        }
    }

    private func isHangul(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF,
             0x3130...0x318F,
             0xA960...0xA97F,
             0xAC00...0xD7AF,
             0xD7B0...0xD7FF:
            return true
        default:
            return false
        }
    }

    private func levenshteinDistance(lhs: String, rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        guard !lhsChars.isEmpty else { return rhsChars.count }
        guard !rhsChars.isEmpty else { return lhsChars.count }

        var previous = Array(0...rhsChars.count)
        for (i, lhsChar) in lhsChars.enumerated() {
            var current = [i + 1]
            for (j, rhsChar) in rhsChars.enumerated() {
                let cost = lhsChar == rhsChar ? 0 : 1
                current.append(
                    min(
                        current[j] + 1,
                        previous[j + 1] + 1,
                        previous[j] + cost
                    )
                )
            }
            previous = current
        }
        return previous[rhsChars.count]
    }
}

@MainActor
final class DictionaryStore: ObservableObject {
    @Published private(set) var entries: [DictionaryEntry] = []

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default

    init() {
        reload()
    }

    func reload() {
        do {
            let url = try dictionaryFileURL()
            guard fileManager.fileExists(atPath: url.path) else {
                entries = []
                return
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([DictionaryEntry].self, from: data)
            entries = sortEntries(decoded)
        } catch {
            entries = []
        }
    }

    func filteredEntries(for filter: DictionaryFilter) -> [DictionaryEntry] {
        switch filter {
        case .all:
            return entries
        case .autoAdded:
            return entries.filter { $0.source == .auto }
        case .manualAdded:
            return entries.filter { $0.source == .manual }
        }
    }

    func createManualEntry(term: String, groupID: UUID?, groupNameSnapshot: String?) throws {
        try createEntry(
            term: term,
            groupID: groupID,
            groupNameSnapshot: groupNameSnapshot,
            source: .manual
        )
    }

    func createAutoEntry(term: String, groupID: UUID?, groupNameSnapshot: String?) throws {
        try createEntry(
            term: term,
            groupID: groupID,
            groupNameSnapshot: groupNameSnapshot,
            source: .auto
        )
    }

    private func createEntry(
        term: String,
        groupID: UUID?,
        groupNameSnapshot: String?,
        source: DictionaryEntrySource
    ) throws {
        let prepared = try prepareTerm(term, groupID: groupID)
        let now = Date()
        let entry = DictionaryEntry(
            term: prepared.display,
            normalizedTerm: prepared.normalized,
            groupID: groupID,
            groupNameSnapshot: groupNameSnapshot,
            source: source,
            createdAt: now,
            updatedAt: now
        )
        entries.insert(entry, at: 0)
        entries = sortEntries(entries)
        persist()
    }

    func updateEntry(id: UUID, term: String, groupID: UUID?, groupNameSnapshot: String?) throws {
        let prepared = try prepareTerm(term, groupID: groupID, excluding: id)
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].term = prepared.display
        entries[index].normalizedTerm = prepared.normalized
        entries[index].groupID = groupID
        entries[index].groupNameSnapshot = groupNameSnapshot
        entries[index].updatedAt = Date()
        entries[index].observedVariants.removeAll { $0.normalizedText == prepared.normalized }
        entries = sortEntries(entries)
        persist()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func clearAll() {
        entries = []
        persist()
    }

    func exportTransferJSONString() throws -> String {
        try DictionaryTransferManager.exportJSONString(entries: entries)
    }

    func importTransferJSONString(_ json: String) throws -> DictionaryImportResult {
        let payload = try DictionaryTransferManager.importPayload(from: json)
        return importTransferEntries(payload.entries)
    }

    func makeMatcherIfEnabled(activeGroupID: UUID?) -> DictionaryMatcher? {
        guard defaults.bool(forKey: AppPreferenceKey.dictionaryRecognitionEnabled) else { return nil }
        let activeEntries = eligibleEntries(for: activeGroupID)
        guard !activeEntries.isEmpty else { return nil }
        return DictionaryMatcher(entries: activeEntries)
    }

    func correctionContext(for text: String, activeGroupID: UUID?) -> DictionaryCorrectionResult? {
        guard let matcher = makeMatcherIfEnabled(activeGroupID: activeGroupID) else { return nil }
        return matcher.applyCorrections(
            to: text,
            automaticReplacementEnabled: defaults.bool(forKey: AppPreferenceKey.dictionaryHighConfidenceCorrectionEnabled)
        )
    }

    func glossaryContext(for text: String, activeGroupID: UUID?) -> DictionaryPromptContext? {
        guard let matcher = makeMatcherIfEnabled(activeGroupID: activeGroupID) else { return nil }
        let context = matcher.promptContext(for: text)
        return context.isEmpty ? nil : context
    }

    func hasEntry(normalizedTerm: String, activeGroupID: UUID?) -> Bool {
        let normalized = normalizedTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        return eligibleEntries(for: activeGroupID).contains { $0.normalizedTerm == normalized }
    }

    func recordMatches(_ candidates: [DictionaryMatchCandidate]) {
        recordCandidates(candidates)
        guard !candidates.isEmpty else { return }
        entries = sortEntries(entries)
        persist()
    }

    static func normalizeTerm(_ input: String) -> String {
        let folded = input.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        var output = ""
        var previousWasWhitespace = false

        for scalar in folded.unicodeScalars {
            if isDictionaryWordScalar(scalar) {
                output.unicodeScalars.append(scalar)
                previousWasWhitespace = false
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) || CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar) {
                if !previousWasWhitespace && !output.isEmpty {
                    output.append(" ")
                    previousWasWhitespace = true
                }
            }
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func eligibleEntries(for activeGroupID: UUID?) -> [DictionaryEntry] {
        let globals = entries.filter { $0.status == .active && $0.groupID == nil }
        guard let activeGroupID else {
            return globals
        }

        let scoped = entries.filter { $0.status == .active && $0.groupID == activeGroupID }
        let scopedTerms = Set(scoped.map(\.normalizedTerm))
        let filteredGlobals = globals.filter { !scopedTerms.contains($0.normalizedTerm) }
        return scoped + filteredGlobals
    }

    private func prepareTerm(_ raw: String, groupID: UUID?, excluding excludedID: UUID? = nil) throws -> (display: String, normalized: String) {
        let display = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Self.normalizeTerm(display)
        guard !display.isEmpty, !normalized.isEmpty else {
            throw DictionaryStoreError.emptyTerm
        }

        if entries.contains(where: { $0.normalizedTerm == normalized && $0.groupID == groupID && $0.id != excludedID }) {
            throw DictionaryStoreError.duplicateTerm
        }

        return (display, normalized)
    }

    private func importTransferEntries(_ transferEntries: [DictionaryTransferManager.Entry]) -> DictionaryImportResult {
        var mergedEntries = entries
        var addedCount = 0
        var skippedCount = 0

        for transferEntry in transferEntries {
            let display = transferEntry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = Self.normalizeTerm(display)

            guard !display.isEmpty, !normalized.isEmpty else {
                skippedCount += 1
                continue
            }

            if mergedEntries.contains(where: { $0.normalizedTerm == normalized && $0.groupID == transferEntry.groupID }) {
                skippedCount += 1
                continue
            }

            let now = Date()
            mergedEntries.append(
                DictionaryEntry(
                    term: display,
                    normalizedTerm: normalized,
                    groupID: transferEntry.groupID,
                    groupNameSnapshot: transferEntry.groupNameSnapshot,
                    source: .manual,
                    createdAt: now,
                    updatedAt: now
                )
            )
            addedCount += 1
        }

        entries = sortEntries(mergedEntries)
        persist()
        return DictionaryImportResult(addedCount: addedCount, skippedCount: skippedCount)
    }

    private func recordCandidates(_ candidates: [DictionaryMatchCandidate]) {
        guard !candidates.isEmpty else { return }
        let now = Date()
        let grouped = Dictionary(grouping: candidates, by: \.entryID)

        for (entryID, matches) in grouped {
            guard let index = entries.firstIndex(where: { $0.id == entryID }) else { continue }
            entries[index].lastMatchedAt = now
            entries[index].matchCount += matches.count
            entries[index].updatedAt = now

            for candidate in matches where candidate.normalizedMatchedText != entries[index].normalizedTerm {
                upsertVariant(
                    into: &entries[index],
                    text: candidate.matchedText,
                    normalizedText: candidate.normalizedMatchedText,
                    confidence: confidence(for: candidate)
                )
            }
        }
    }

    private func upsertVariant(
        into entry: inout DictionaryEntry,
        text: String,
        normalizedText: String,
        confidence: DictionaryVariantConfidence
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let variantIndex = entry.observedVariants.firstIndex(where: { $0.normalizedText == normalizedText }) {
            entry.observedVariants[variantIndex].count += 1
            entry.observedVariants[variantIndex].lastSeenAt = Date()
            entry.observedVariants[variantIndex].confidence = higherConfidence(
                lhs: entry.observedVariants[variantIndex].confidence,
                rhs: confidence
            )
        } else {
            entry.observedVariants.append(
                ObservedVariant(
                    text: text,
                    normalizedText: normalizedText,
                    confidence: confidence
                )
            )
            entry.observedVariants.sort { $0.count > $1.count }
        }
    }

    private func confidence(for candidate: DictionaryMatchCandidate) -> DictionaryVariantConfidence {
        if candidate.score >= 0.985 {
            return .high
        }
        if candidate.score >= 0.92 {
            return .medium
        }
        return .low
    }

    private func higherConfidence(lhs: DictionaryVariantConfidence, rhs: DictionaryVariantConfidence) -> DictionaryVariantConfidence {
        let rank: [DictionaryVariantConfidence: Int] = [
            .low: 0,
            .medium: 1,
            .high: 2
        ]
        return (rank[lhs] ?? 0) >= (rank[rhs] ?? 0) ? lhs : rhs
    }

    private static func isDictionaryWordScalar(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || isHanLike(scalar) || isKana(scalar) || isHangul(scalar)
    }

    private static func isHanLike(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF,
             0x3400...0x4DBF,
             0x20000...0x2A6DF,
             0x2A700...0x2B73F,
             0x2B740...0x2B81F,
             0x2B820...0x2CEAF:
            return true
        default:
            return false
        }
    }

    private static func isKana(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x309F,
             0x30A0...0x30FF,
             0x31F0...0x31FF,
             0xFF66...0xFF9F:
            return true
        default:
            return false
        }
    }

    private static func isHangul(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF,
             0x3130...0x318F,
             0xA960...0xA97F,
             0xAC00...0xD7AF,
             0xD7B0...0xD7FF:
            return true
        default:
            return false
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            let url = try dictionaryFileURL()
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Keep UI responsive even if persistence fails.
        }
    }

    private func dictionaryFileURL() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("dictionary.json")
    }

    private func sortEntries(_ values: [DictionaryEntry]) -> [DictionaryEntry] {
        values.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0x2A700...0x2B73F, 0x2B740...0x2B81F, 0x2B820...0x2CEAF:
            return true
        default:
            return false
        }
    }
}
