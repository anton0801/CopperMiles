import Foundation

extension String {
  /// The text with surrounding whitespace removed.
  ///
  /// Names are validated and stored trimmed, so that a stop called " " is treated as
  /// the empty name it really is.
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var isBlank: Bool { trimmed.isEmpty }
}
