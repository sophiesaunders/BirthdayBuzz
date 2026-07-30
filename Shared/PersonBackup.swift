import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Plain-data representation of a `Person` for JSON export/import. Deliberately excludes
/// `lastAcknowledgedYear` — imported people should start fresh, and `Person.init` already
/// handles that correctly when no acknowledgment state is provided.
struct PersonBackupEntry: Codable {
    var name: String
    var birthMonth: Int
    var birthDay: Int
    var birthYear: Int?
    var emoji: String?
    var notes: String?
}

struct PersonBackupFile: Codable {
    var people: [PersonBackupEntry]
}

enum PersonBackup {
    static func exportData(people: [Person]) throws -> Data {
        let entries = people.map {
            PersonBackupEntry(
                name: $0.name,
                birthMonth: $0.birthMonth,
                birthDay: $0.birthDay,
                birthYear: $0.birthYear,
                emoji: $0.emoji,
                notes: $0.notes
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(PersonBackupFile(people: entries))
    }

    struct ImportResult {
        var added: Int
        var skipped: Int
    }

    /// Merges the entries in `data` into `modelContext`, skipping any entry whose name
    /// (exact match) and month/day already exist among `existingPeople`.
    static func importData(_ data: Data, into modelContext: ModelContext, existingPeople: [Person]) throws -> ImportResult {
        let decoder = JSONDecoder()
        let file = try decoder.decode(PersonBackupFile.self, from: data)

        var knownKeys = Set(existingPeople.map { dedupeKey(name: $0.name, birthMonth: $0.birthMonth, birthDay: $0.birthDay) })
        var added = 0
        var skipped = 0

        for entry in file.people {
            let key = dedupeKey(name: entry.name, birthMonth: entry.birthMonth, birthDay: entry.birthDay)
            if knownKeys.contains(key) {
                skipped += 1
                continue
            }
            let person = Person(
                name: entry.name,
                birthMonth: entry.birthMonth,
                birthDay: entry.birthDay,
                birthYear: entry.birthYear,
                emoji: entry.emoji,
                notes: entry.notes
            )
            modelContext.insert(person)
            knownKeys.insert(key)
            added += 1
        }

        try modelContext.save()
        return ImportResult(added: added, skipped: skipped)
    }

    private static func dedupeKey(name: String, birthMonth: Int, birthDay: Int) -> String {
        "\(name)|\(birthMonth)|\(birthDay)"
    }
}

struct PersonBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
