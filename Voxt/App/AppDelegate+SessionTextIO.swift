import Foundation
import AppKit
import ApplicationServices

extension AppDelegate {
    private struct NormalizeOutputStage: SessionFinalizeStage {
        let normalize: (String) -> String

        var name: String { "normalizeOutput" }

        func run(context: inout SessionFinalizeContext) {
            context.outputText = normalize(context.outputText)
        }
    }

    private struct DictionaryCorrectionStage: SessionFinalizeStage {
        let correct: (String) -> DictionaryCorrectionResult

        var name: String { "dictionaryCorrection" }

        func run(context: inout SessionFinalizeContext) {
            let result = correct(context.outputText)
            context.outputText = result.text
            context.dictionaryMatches = result.candidates
            context.dictionaryCorrectedTerms = result.correctedTerms
        }
    }

    private struct DictionarySuggestionStage: SessionFinalizeStage {
        let suggest: (String, [DictionaryMatchCandidate], [String]) -> [DictionarySuggestionDraft]

        var name: String { "dictionarySuggestions" }

        func run(context: inout SessionFinalizeContext) {
            context.dictionarySuggestions = suggest(
                context.outputText,
                context.dictionaryMatches,
                context.dictionaryCorrectedTerms
            )
        }
    }

    private struct TypeTextStage: SessionFinalizeStage {
        let write: (String) -> Void

        var name: String { "typeText" }

        func run(context: inout SessionFinalizeContext) {
            write(context.outputText)
        }
    }

    private struct PersistDictionaryEvidenceStage: SessionFinalizeStage {
        let persist: ([DictionaryMatchCandidate], [DictionarySuggestionDraft], UUID?) -> Void

        var name: String { "persistDictionaryEvidence" }

        func run(context: inout SessionFinalizeContext) {
            persist(context.dictionaryMatches, context.dictionarySuggestions, context.historyEntryID)
        }
    }

    private struct AppendHistoryStage: SessionFinalizeStage {
        let append: (String, TimeInterval?, [String], [String], [DictionarySuggestionSnapshot]) -> UUID?

        var name: String { "appendHistory" }

        func run(context: inout SessionFinalizeContext) {
            context.historyEntryID = append(
                context.outputText,
                context.llmDurationSeconds,
                Self.uniqueTerms(from: context.dictionaryMatches),
                Self.deduplicatedTerms(context.dictionaryCorrectedTerms),
                context.dictionarySuggestions.map(\.snapshot)
            )
        }

        private static func uniqueTerms(from candidates: [DictionaryMatchCandidate]) -> [String] {
            var seen = Set<String>()
            var ordered: [String] = []
            for candidate in candidates {
                let normalized = DictionaryStore.normalizeTerm(candidate.term)
                guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
                ordered.append(candidate.term)
            }
            return ordered
        }

        private static func deduplicatedTerms(_ values: [String]) -> [String] {
            var seen = Set<String>()
            var ordered: [String] = []
            for value in values {
                let normalized = DictionaryStore.normalizeTerm(value)
                guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
                ordered.append(value)
            }
            return ordered
        }
    }

    // MARK: - Session Text I/O
    // Keeps clipboard/AX/paste simulation logic isolated from recording orchestration.

    func commitTranscription(_ text: String, llmDurationSeconds: TimeInterval?) {
        if didCommitSessionOutput {
            VoxtLog.info("Skipping duplicate commit for current session output.")
            return
        }
        didCommitSessionOutput = true

        let pipeline = SessionFinalizePipelineRunner(
            stages: [
                NormalizeOutputStage(normalize: { [weak self] value in
                    self?.normalizedOutputText(value) ?? value
                }),
                DictionaryCorrectionStage(correct: { [weak self] value in
                    self?.resolveDictionaryCorrection(for: value)
                        ?? DictionaryCorrectionResult(text: value, candidates: [], correctedTerms: [])
                }),
                DictionarySuggestionStage(suggest: { [weak self] value, candidates, correctedTerms in
                    self?.previewDictionarySuggestions(
                        for: value,
                        candidates: candidates,
                        correctedTerms: correctedTerms
                    ) ?? []
                }),
                TypeTextStage(write: { [weak self] value in
                    self?.typeText(value)
                }),
                AppendHistoryStage(append: { [weak self] value, duration, hitTerms, correctedTerms, suggestions in
                    self?.appendHistoryIfNeeded(
                        text: value,
                        llmDurationSeconds: duration,
                        dictionaryHitTerms: hitTerms,
                        dictionaryCorrectedTerms: correctedTerms,
                        dictionarySuggestedTerms: suggestions
                    )
                }),
                PersistDictionaryEvidenceStage(persist: { [weak self] candidates, suggestions, historyEntryID in
                    self?.persistDictionaryEvidence(
                        candidates: candidates,
                        suggestions: suggestions,
                        historyEntryID: historyEntryID
                    )
                })
            ]
        )
        _ = pipeline.run(
            initial: SessionFinalizeContext(
                outputText: text,
                llmDurationSeconds: llmDurationSeconds,
                dictionaryMatches: [],
                dictionaryCorrectedTerms: [],
                dictionarySuggestions: [],
                historyEntryID: nil
            )
        )
    }

    func selectedTextFromSystemSelection() -> String? {
        if let axSelected = selectedTextFromAXFocusedElement(),
           !axSelected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return axSelected
        }
        return selectedTextBySimulatedCopy()
    }

    private func selectedTextFromAXFocusedElement() -> String? {
        guard AccessibilityPermissionManager.isTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard focusedStatus == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let focusedElement = unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        var selectedTextRef: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )
        guard selectedStatus == .success, let selectedTextRef else {
            return nil
        }

        if let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
            return selectedText
        }
        if let selectedText = selectedTextRef as? NSAttributedString, !selectedText.string.isEmpty {
            return selectedText.string
        }
        return nil
    }

    private func selectedTextBySimulatedCopy() -> String? {
        guard AccessibilityPermissionManager.isTrusted() else { return nil }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        let originalChangeCount = pasteboard.changeCount

        let cKeyCode: CGKeyCode = 0x08
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        cmdUp?.flags = .maskCommand
        guard cmdDown != nil, cmdUp != nil else { return nil }

        cmdDown?.post(tap: .cgAnnotatedSessionEventTap)
        cmdUp?.post(tap: .cgAnnotatedSessionEventTap)
        Thread.sleep(forTimeInterval: 0.06)

        let copiedChangeCount = pasteboard.changeCount
        guard copiedChangeCount != originalChangeCount else {
            // No clipboard update means no effective selection copy.
            return nil
        }

        let copied = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        pasteboard.clearContents()
        if let previous, !previous.isEmpty {
            pasteboard.setString(previous, forType: .string)
        }

        guard let copied, !copied.isEmpty else { return nil }
        return copied
    }

    private func normalizedOutputText(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else { return value }

        // Remove paired wrapping quotes from some model outputs.
        let left = value.first
        let right = value.last
        let isWrappedByDoubleQuotes =
            (left == "\"" && right == "\"") ||
            (left == "“" && right == "”")

        if isWrappedByDoubleQuotes {
            value.removeFirst()
            value.removeLast()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return value
    }

    private func typeText(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string) ?? ""
        let accessibilityTrusted = AccessibilityPermissionManager.isTrusted()
        let keepResultInClipboard = autoCopyWhenNoFocusedInput

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard accessibilityTrusted else {
            promptForAccessibilityPermission()
            VoxtLog.warning("Accessibility permission missing. Transcription copied; paste manually after granting permission.")
            return
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            VoxtLog.error("typeText failed: unable to create CGEventSource")
            return
        }

        let vKeyCode: CGKeyCode = 0x09
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        cmdUp?.flags = .maskCommand

        guard cmdDown != nil, cmdUp != nil else {
            VoxtLog.error("typeText failed: unable to create key events")
            return
        }

        cmdDown?.post(tap: .cgAnnotatedSessionEventTap)
        cmdUp?.post(tap: .cgAnnotatedSessionEventTap)

        if !keepResultInClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                pasteboard.clearContents()
                if !previous.isEmpty {
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    private func promptForAccessibilityPermission() {
        _ = AccessibilityPermissionManager.request(prompt: true)
    }
}
