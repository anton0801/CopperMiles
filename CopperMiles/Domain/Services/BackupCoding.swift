import Foundation

/// A whole journal together with the photos it refers to.
///
/// A backup is deliberately self-contained: restoring it on another device must
/// bring the pictures with the trips, not leave a journal pointing at files that are
/// not there.
struct BackupPayload {
  var journal: Journal
  var attachments: [AttachmentID: Data]

  init(journal: Journal, attachments: [AttachmentID: Data] = [:]) {
    self.journal = journal
    self.attachments = attachments
  }
}

/// Writes and reads the backup archive.
protocol BackupCoding: AnyObject {
  func encode(_ payload: BackupPayload) throws -> Data

  /// Reads an archive, rejecting anything that is not a Copper Miles backup.
  ///
  /// Decoding never touches the traveller's current journal — the caller decides
  /// whether to replace it once the preview has been seen.
  func decode(_ data: Data) throws -> BackupPayload
}
