import Foundation

/// Packs the journal and its photos into a backup, and reads one back.
///
/// The archive holds one `journal.json` plus a folder of photos named after the
/// identifiers the journal refers to. Reading checks that the two agree: a photo
/// nothing points at, or a record pointing at a photo that is not there, means the
/// archive is not whole and is refused rather than half-restored.
final class JournalBackupCodec: BackupCoding {
  private enum Path {
    static let journal = "journal.json"
    static let photoFolder = "photos/"
    static let photoExtension = ".jpg"

    static func photo(_ id: AttachmentID) -> String {
      "\(photoFolder)\(id.description)\(photoExtension)"
    }

    static func attachmentID(from name: String) -> AttachmentID? {
      guard name.hasPrefix(photoFolder), name.hasSuffix(photoExtension) else { return nil }
      let raw = name
        .dropFirst(photoFolder.count)
        .dropLast(photoExtension.count)
      return UUID(uuidString: String(raw)).map(AttachmentID.init)
    }

    static func isRecognised(_ name: String) -> Bool {
      name == journal || attachmentID(from: name) != nil
    }
  }

  func encode(_ payload: BackupPayload) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    var entries: [ZipArchive.Entry] = [
      ZipArchive.Entry(
        name: Path.journal,
        contents: try encoder.encode(JournalMapper.dto(payload.journal))
      )
    ]

    // Sorted so that backing up the same journal twice produces the same file.
    for id in payload.attachments.keys.sorted(by: { $0.description < $1.description }) {
      guard let data = payload.attachments[id] else { continue }
      entries.append(ZipArchive.Entry(name: Path.photo(id), contents: data))
    }

    return ZipArchive.archive(entries)
  }

  func decode(_ data: Data) throws -> BackupPayload {
    let entries = try ZipArchive.entries(in: data, allowing: Path.isRecognised)

    guard let document = entries.first(where: { $0.name == Path.journal })?.contents else {
      throw DomainError("That is not a Copper Miles backup.")
    }

    let dto = try JSONDecoder().decode(JournalDTO.self, from: document)
    let journal = try JournalMapper.journal(dto)

    var attachments: [AttachmentID: Data] = [:]
    for entry in entries where entry.name != Path.journal {
      guard let id = Path.attachmentID(from: entry.name) else {
        throw DomainError("That backup contains an unexpected file.")
      }
      attachments[id] = entry.contents
    }

    let referenced = journal.referencedAttachmentIDs
    guard Set(attachments.keys) == referenced else {
      throw DomainError(
        Set(attachments.keys).isSubset(of: referenced)
          ? "That backup is missing some of its photos."
          : "That backup carries photos that none of its trips refer to."
      )
    }

    return BackupPayload(journal: journal, attachments: attachments)
  }
}
