import Foundation

/// What kind of place a stop is, used for its icon and for grouping.
///
/// `destination` is structural rather than descriptive: exactly one stop carries it
/// and it always sits last in the plan.
enum StopKind: String, CaseIterable, Equatable {
  case rest
  case food
  case fuel
  case viewpoint
  case overnight
  case custom
  case destination

  /// Kinds the traveller may choose freely for an intermediate stop.
  static var selectableKinds: [StopKind] {
    allCases.filter { $0 != .destination }
  }
}

/// A geographic point the traveller entered or captured.
struct Coordinate: Equatable {
  var latitude: Double
  var longitude: Double

  var isValid: Bool {
    latitude.isFinite && longitude.isFinite
      && (-90...90).contains(latitude) && (-180...180).contains(longitude)
  }
}

/// A recorded stay at a stop.
///
/// A visit with no departure is still open; only one visit in a trip may be open at
/// a time, and a finished trip may contain none.
struct Visit: Equatable {
  var arrival: Date
  var departure: Date?

  var isOpen: Bool { departure == nil }
}

/// One place along the way.
///
/// A stop carries both the plan (name, optional address, the traveller's own
/// intended arrival) and what actually happened (`visit`, `isSkipped`). Planned
/// arrival is the traveller's intention, never a computed estimate: this app does
/// not calculate routes or traffic.
struct Stop: Identifiable, Equatable {
  let id: UUID
  var name: String
  var kind: StopKind
  var address: String
  var coordinate: Coordinate?
  var plannedArrival: Date?
  var plannedStayMinutes: Int?
  var parkingNote: String
  var personalNote: String
  var visit: Visit?
  var skipReason: String?
  var isArchived: Bool

  init(
    id: UUID = UUID(),
    name: String = "",
    kind: StopKind = .rest,
    address: String = "",
    coordinate: Coordinate? = nil,
    plannedArrival: Date? = nil,
    plannedStayMinutes: Int? = nil,
    parkingNote: String = "",
    personalNote: String = "",
    visit: Visit? = nil,
    skipReason: String? = nil,
    isArchived: Bool = false
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.address = address
    self.coordinate = coordinate
    self.plannedArrival = plannedArrival
    self.plannedStayMinutes = plannedStayMinutes
    self.parkingNote = parkingNote
    self.personalNote = personalNote
    self.visit = visit
    self.skipReason = skipReason
    self.isArchived = isArchived
  }

  var isVisited: Bool { visit != nil }
  var isSkipped: Bool { skipReason != nil }

  /// True when the traveller has neither arrived here nor decided to pass it by.
  var isOutstanding: Bool { !isVisited && !isSkipped && !isArchived }

  /// Whether this stop can be handed to the system maps app.
  var canOpenInMaps: Bool {
    coordinate != nil || !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// A copy of this place ready to be planned again — no visit, no skip, no time.
  func replanned(as kind: StopKind? = nil) -> Stop {
    Stop(
      name: name,
      kind: kind ?? (self.kind == .destination ? .custom : self.kind),
      address: address,
      coordinate: coordinate,
      plannedStayMinutes: plannedStayMinutes,
      parkingNote: parkingNote,
      personalNote: personalNote
    )
  }
}
