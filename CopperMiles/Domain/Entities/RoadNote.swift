import Foundation

/// What a road note is about, so the journal can be read at a glance.
enum RoadNoteKind: String, CaseIterable, Equatable {
  case road
  case parking
  case car
  case place
  case other
}

/// Something worth remembering from the road.
///
/// A note belongs to a trip that has actually started, and may optionally attach to
/// one of its stops. Pinning marks it as advice worth carrying into a repeat of the
/// same plan; it never becomes an event of its own in the new trip.
struct RoadNote: Identifiable, Equatable {
  static let maximumCharacters = 2000
  static let maximumPhotos = 3

  let id: UUID
  var kind: RoadNoteKind
  var text: String
  var recordedAt: Date
  var stopID: UUID?
  var photoIDs: [AttachmentID]
  var isPinnedForRepeat: Bool

  init(
    id: UUID = UUID(),
    kind: RoadNoteKind = .road,
    text: String = "",
    recordedAt: Date = Date(),
    stopID: UUID? = nil,
    photoIDs: [AttachmentID] = [],
    isPinnedForRepeat: Bool = false
  ) {
    self.id = id
    self.kind = kind
    self.text = text
    self.recordedAt = recordedAt
    self.stopID = stopID
    self.photoIDs = photoIDs
    self.isPinnedForRepeat = isPinnedForRepeat
  }

  var canAcceptAnotherPhoto: Bool { photoIDs.count < Self.maximumPhotos }
}
