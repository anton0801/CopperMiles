import Foundation

/// The single error type the domain speaks.
///
/// Every case carries a message that is safe to show to a traveller: the rules in
/// this app are the user's own rules, so a failure is always something they can fix
/// rather than an internal fault.
struct DomainError: LocalizedError, Equatable {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}

extension DomainError {
  static let journalUnavailable = DomainError("This record is no longer in your journal.")
}

/// A journal document this build cannot read.
///
/// Told apart from ordinary corruption because the file is perfectly good — it was
/// simply written by a different version — and destroying it would take the
/// traveller's records with it.
struct JournalVersionError: LocalizedError, Equatable {
  let isNewer: Bool

  var errorDescription: String? {
    isNewer
      ? "This journal was written by a newer version of Copper Miles. Update the app to open it."
      : "This journal was written by an older version of Copper Miles."
  }
}
