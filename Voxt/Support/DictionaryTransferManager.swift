import Foundation
import UniformTypeIdentifiers
import SwiftUI

struct DictionaryTransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

enum DictionaryTransferManager {
    struct Payload: Codable {
        var version: Int
        var exportedAt: String
        var entries: [Entry]
    }

    struct Entry: Codable {
        var term: String
        var groupID: UUID?
        var groupNameSnapshot: String?
    }

    static func exportJSONString(entries: [DictionaryEntry]) throws -> String {
        let payload = Payload(
            version: 1,
            exportedAt: iso8601Formatter.string(from: Date()),
            entries: entries.map {
                Entry(
                    term: $0.term,
                    groupID: $0.groupID,
                    groupNameSnapshot: $0.groupNameSnapshot
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return text
    }

    static func importPayload(from json: String) throws -> Payload {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(Payload.self, from: data)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
