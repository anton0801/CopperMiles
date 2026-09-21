import Foundation

/// Reads and writes the journal document.
///
/// The document is small — photos live elsewhere — so every change is written whole,
/// atomically. That keeps the guarantee the repository depends on: after a save the
/// file is either entirely the old journal or entirely the new one.
struct JournalFileStore {
  let url: URL
  private let fileManager: FileManager

  init(url: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.url =
      url
      ?? fileManager
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CopperMiles/journal.json")
  }

  /// Loads the journal, or an empty one on a first run.
  ///
  /// A document written by a different version is not guessed at. It is set aside
  /// under a dated name so the traveller still has their file, and the app opens
  /// empty rather than half-reading records it does not understand.
  func load() throws -> Journal {
    guard fileManager.fileExists(atPath: url.path) else { return Journal() }

    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()

    // The version is read on its own, before the rest. A document from a later
    // version will have a shape this build cannot decode at all, so checking it
    // afterwards would mistake a perfectly good journal for a damaged one.
    if let probe = try? decoder.decode(VersionProbe.self, from: data),
      probe.version != JournalDTO.currentVersion
    {
      throw DomainError(
        (JournalVersionError(isNewer: probe.version > JournalDTO.currentVersion)
          .errorDescription ?? "")
          + " Your file has been left untouched, and Copper Miles has opened empty."
      )
    }

    do {
      let dto = try decoder.decode(JournalDTO.self, from: data)
      return try JournalMapper.journal(dto)
    } catch {
      let destination = try setAside()
      throw DomainError(
        "Your journal could not be read. It has been set aside as “\(destination.lastPathComponent)” "
          + "rather than changed, and Copper Miles has started with an empty journal."
      )
    }
  }

  func save(_ journal: Journal) throws {
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(JournalMapper.dto(journal))

    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  /// Just enough of the document to learn which version wrote it.
  private struct VersionProbe: Decodable {
    let version: Int
  }

  /// Moves an unreadable document out of the way and reports where it went.
  @discardableResult
  private func setAside() throws -> URL {
    let stamp = Int(Date().timeIntervalSince1970)
    let destination = url
      .deletingLastPathComponent()
      .appendingPathComponent("journal-unreadable-\(stamp).json")
    try? fileManager.removeItem(at: destination)
    try fileManager.moveItem(at: url, to: destination)
    return destination
  }
}

enum Waypoint: Equatable {
    case trailhead
    case permit
    case vista
    case lost
}

enum Outcome {
    case reached(String)
    case stranded
}

struct Rail {
    var trek: Expedition
    var sealed = false
    var busy = false
    var screen: Waypoint = .trailhead
    var offline = false
}
