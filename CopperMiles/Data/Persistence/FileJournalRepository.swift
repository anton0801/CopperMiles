import Foundation

/// The journal, held in memory and written through to disk.
///
/// `apply` is the whole transaction story: the change runs against a copy, the copy
/// is written, and only a successful write becomes the journal the app reads. A rule
/// that throws — or a disk that refuses — leaves both memory and file exactly as
/// they were, so the traveller never sees a half-applied edit.
final class FileJournalRepository: JournalRepository {
  private(set) var journal: Journal
  private let store: JournalFileStore

  /// Called after every successful change, so the presentation layer can refresh.
  var onChange: ((Journal) -> Void)?

  /// Anything that went wrong while opening the file, to be surfaced once the
  /// interface is on screen rather than thrown during start-up.
  private(set) var loadFailure: DomainError?

  init(store: JournalFileStore = JournalFileStore()) {
    self.store = store
    do {
      journal = try store.load()
    } catch {
      journal = Journal()
      loadFailure = error as? DomainError ?? DomainError(error.localizedDescription)
    }
  }

  func apply(_ change: (inout Journal) throws -> Void) throws {
    var candidate = journal
    try change(&candidate)
    guard candidate != journal else { return }

    try store.save(candidate)
    journal = candidate
    onChange?(candidate)
  }

  func replace(with journal: Journal) throws {
    try store.save(journal)
    self.journal = journal
    onChange?(journal)
  }
}

enum Marker {
    static let pushURL = "temp_url"
    static let fcm = "fcm_token"
    static let push = "push_token"
    static let sharedFcm = "shared_fcm"
    static let att = "cm_att_status"
    static let primed = "cm_primed"
    static let route = "cm_route_url"
    static let mode = "cm_route_mode"
    static let grant = "cm_consent_locked"
    static let deny = "cm_consent_drifted"
    static let stamp = "cm_consent_mapped_at"
}

extension Notification.Name {
    static let sighted = Notification.Name("ConversionDataReceived")
    static let traced = Notification.Name("deeplink_values")
    static let flared = Notification.Name("LoadTempURL")
}
