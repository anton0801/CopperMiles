import Foundation

/// Why a start odometer reading sits below the previous one for the same vehicle.
///
/// The traveller must name the reason rather than have the app quietly accept a
/// reading that would make the journal's distances nonsense.
enum OdometerExplanation: String, CaseIterable, Equatable {
  case correctedReading
  case odometerReplaced
}

/// How far the checklist has come.
struct ChecklistProgress: Equatable {
  let checked: Int
  let total: Int

  var isEmpty: Bool { total == 0 }

  /// `nil` for an empty checklist: no items is not the same as everything done.
  var fraction: Double? {
    guard total > 0 else { return nil }
    return Double(checked) / Double(total)
  }

  var hasOutstandingItems: Bool { checked < total }
}

/// One journey, from first idea to journal entry.
///
/// A trip is the aggregate the whole app turns around: it owns its stops, its own
/// copy of the departure checklist, the notes written along the way and its
/// reminders. Nothing here enforces rules — that is the validators' work — but the
/// derived properties below define what the rest of the app means by "next stop",
/// "open visit" or "recorded distance".
struct Trip: Identifiable, Equatable {
  static let travellerRange = 1...9

  let id: UUID
  var name: String
  var vehicleID: UUID?
  var status: TripStatus
  var plannedDeparture: Date?
  var expectedEnd: Date?
  var startPlace: String
  var travellers: Int
  var note: String

  var stops: [Stop]
  var checklist: [PreparationItem]
  var notes: [RoadNote]
  var reminders: [TripReminder]

  var actualStart: Date?
  var actualEnd: Date?
  var startOdometer: Double?
  var endOdometer: Double?
  var odometerExplanation: OdometerExplanation?
  var hasReadingDiscontinuity: Bool
  var outcome: TripOutcome?
  var endReason: String
  var finalNote: String
  var isArchived: Bool

  init(
    id: UUID = UUID(),
    name: String = "",
    vehicleID: UUID? = nil,
    status: TripStatus = .draft,
    plannedDeparture: Date? = nil,
    expectedEnd: Date? = nil,
    startPlace: String = "",
    travellers: Int = 1,
    note: String = "",
    stops: [Stop] = [],
    checklist: [PreparationItem] = [],
    notes: [RoadNote] = [],
    reminders: [TripReminder] = [],
    actualStart: Date? = nil,
    actualEnd: Date? = nil,
    startOdometer: Double? = nil,
    endOdometer: Double? = nil,
    odometerExplanation: OdometerExplanation? = nil,
    hasReadingDiscontinuity: Bool = false,
    outcome: TripOutcome? = nil,
    endReason: String = "",
    finalNote: String = "",
    isArchived: Bool = false
  ) {
    self.id = id
    self.name = name
    self.vehicleID = vehicleID
    self.status = status
    self.plannedDeparture = plannedDeparture
    self.expectedEnd = expectedEnd
    self.startPlace = startPlace
    self.travellers = travellers
    self.note = note
    self.stops = stops
    self.checklist = checklist
    self.notes = notes
    self.reminders = reminders
    self.actualStart = actualStart
    self.actualEnd = actualEnd
    self.startOdometer = startOdometer
    self.endOdometer = endOdometer
    self.odometerExplanation = odometerExplanation
    self.hasReadingDiscontinuity = hasReadingDiscontinuity
    self.outcome = outcome
    self.endReason = endReason
    self.finalNote = finalNote
    self.isArchived = isArchived
  }
}

// MARK: - Stops

extension Trip {
  /// Stops still shown in the plan. An archived stop keeps its visit in the journal
  /// but no longer appears as somewhere to go.
  var activeStops: [Stop] {
    stops.filter { !$0.isArchived }
  }

  var destination: Stop? {
    stops.last(where: { $0.kind == .destination })
  }

  var visitedStops: [Stop] { stops.filter(\.isVisited) }
  var skippedStops: [Stop] { stops.filter(\.isSkipped) }

  /// Places the traveller neither reached nor deliberately passed by.
  var unvisitedStops: [Stop] { activeStops.filter(\.isOutstanding) }

  /// The first place still ahead in the current order.
  var nextStop: Stop? { activeStops.first(where: \.isOutstanding) }

  /// The one visit that has been opened but not closed, if any.
  var openVisit: Stop? {
    stops.first { $0.visit?.isOpen == true }
  }

  func stop(_ id: UUID) -> Stop? {
    stops.first { $0.id == id }
  }

  func index(ofStop id: UUID) -> Int? {
    stops.firstIndex { $0.id == id }
  }
}

// MARK: - Preparation

extension Trip {
  var checklistProgress: ChecklistProgress {
    ChecklistProgress(checked: checklist.filter(\.isChecked).count, total: checklist.count)
  }

  var openImportantItems: [PreparationItem] {
    checklist.filter { $0.isImportant && !$0.isChecked }
  }
}

// MARK: - Time and distance

extension Trip {
  /// A planned trip whose departure has already passed. It is not late, and it is
  /// certainly not finished — it simply needs the traveller to look at it again.
  func needsReview(now: Date) -> Bool {
    status == .planned && (plannedDeparture.map { $0 < now } ?? false)
  }

  /// How long the trip has been under way, stops included. This is never presented
  /// as driving time.
  func elapsed(until moment: Date) -> TimeInterval? {
    guard let start = actualStart else { return nil }
    return max(0, (actualEnd ?? moment).timeIntervalSince(start))
  }

  /// The most recent thing recorded against this trip, used to keep the finish time
  /// behind every event it contains.
  var lastRecordedEvent: Date? {
    var dates: [Date] = []
    if let start = actualStart { dates.append(start) }
    for stop in stops {
      if let visit = stop.visit {
        dates.append(visit.arrival)
        if let departure = visit.departure { dates.append(departure) }
      }
    }
    dates.append(contentsOf: notes.map(\.recordedAt))
    return dates.max()
  }

  /// Distance from the two odometer readings, in the vehicle's own unit.
  ///
  /// Deliberately `nil` whenever the readings cannot be trusted — a replaced
  /// odometer, a missing reading, an end below the start — rather than reporting a
  /// number the journal cannot stand behind.
  var recordedDistance: Double? {
    guard !hasReadingDiscontinuity,
      let start = startOdometer,
      let end = endOdometer,
      end >= start
    else { return nil }
    return end - start
  }
}

// MARK: - Repeating

extension Trip {
  /// A fresh draft of the same plan: the same vehicle, places and checks, with
  /// nothing that belongs to the journey already travelled.
  func duplicated(named name: String? = nil) -> Trip {
    Trip(
      name: name ?? self.name,
      vehicleID: vehicleID,
      status: .draft,
      startPlace: startPlace,
      travellers: travellers,
      note: note,
      stops: activeStops.map { $0.replanned(as: $0.kind) },
      checklist: checklist.map { $0.templateCopy() }
    )
  }
}
