import Foundation

/// A reference to one stored photo.
///
/// The domain only ever names an attachment; the bytes live in the attachment store
/// so that the journal itself stays small enough to rewrite on every edit.
struct AttachmentID: Hashable, Equatable {
  let rawValue: UUID

  init(_ rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

extension AttachmentID: CustomStringConvertible {
  var description: String { rawValue.uuidString }
}


protocol Scout {
    func fetch() async -> [String: String]
}

protocol Wire {
    func send(_ body: [String: String]) async -> Outcome
}

protocol Chime {
    func ask() async -> Bool
}
