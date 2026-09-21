import Foundation

/// What the traveller did to a photo while editing.
///
/// Modelled explicitly so that saving can tell "left the existing picture alone"
/// apart from "removed it", and only writes or deletes files when something really
/// changed.
enum PhotoChange: Equatable {
  case unchanged
  case removed
  case replaced(Data)
}

/// Adds a vehicle or stores an edit to one.
struct SaveVehicle {
  let repository: JournalRepository
  let attachments: AttachmentStore

  func execute(_ vehicle: Vehicle, photo: PhotoChange = .unchanged) throws -> Vehicle {
    var validated = try VehicleValidator.validated(vehicle)
    let existing = repository.journal.vehicle(vehicle.id)
    let previousPhotoID = existing?.photoID

    // The unit is locked once a reading exists, because changing it here would
    // silently reinterpret every number already recorded. Converting is a separate,
    // previewed operation.
    if let existing,
      existing.unit != validated.unit,
      !repository.journal.trips(forVehicle: existing.id).isEmpty
    {
      throw DomainError(
        "This vehicle already has recorded trips. Use Convert distance unit to change every reading together."
      )
    }

    switch photo {
    case .unchanged:
      break
    case .removed:
      validated.photoID = nil
    case .replaced(let data):
      validated.photoID = try attachments.store(data)
    }

    try repository.apply { journal in
      if let index = journal.vehicles.firstIndex(where: { $0.id == validated.id }) {
        journal.vehicles[index] = validated
      } else {
        journal.vehicles.append(validated)
      }
    }

    if let previousPhotoID, previousPhotoID != validated.photoID {
      attachments.remove([previousPhotoID])
    }
    return validated
  }
}

/// Removes a vehicle that was never travelled in.
///
/// A vehicle with trips is never deleted: doing so would leave journal entries
/// pointing at nothing. The interface offers archiving instead.
struct DeleteVehicle {
  let repository: JournalRepository
  let attachments: AttachmentStore

  func execute(_ id: UUID) throws {
    let journal = repository.journal
    guard journal.trips(forVehicle: id).isEmpty else {
      throw DomainError(
        "This vehicle carries trips in your journal. Archive it instead, and its records stay."
      )
    }
    let photoID = journal.vehicle(id)?.photoID

    try repository.apply { journal in
      journal.vehicles.removeAll { $0.id == id }
    }

    if let photoID {
      attachments.remove([photoID])
    }
  }
}

/// Moves a vehicle out of the everyday list, or brings it back.
struct SetVehicleArchived {
  let repository: JournalRepository

  func execute(_ id: UUID, isArchived: Bool) throws {
    if isArchived, repository.journal.activeTrip?.vehicleID == id {
      throw DomainError("This vehicle is on a trip right now. Finish the trip before archiving it.")
    }
    try repository.updateVehicle(id) { $0.isArchived = isArchived }
  }
}

/// Converts every recorded reading for one vehicle to another unit.
struct ConvertVehicleUnit {
  let repository: JournalRepository

  /// One reading as it stands and as it would read after converting, so the
  /// traveller confirms the change against real numbers rather than a promise.
  struct Preview: Identifiable, Equatable {
    let id: UUID
    let tripName: String
    let start: (current: Double, converted: Double)?
    let end: (current: Double, converted: Double)?

    static func == (lhs: Preview, rhs: Preview) -> Bool {
      lhs.id == rhs.id && lhs.tripName == rhs.tripName
        && lhs.start?.current == rhs.start?.current
        && lhs.start?.converted == rhs.start?.converted
        && lhs.end?.current == rhs.end?.current
        && lhs.end?.converted == rhs.end?.converted
    }
  }

  func preview(vehicleID: UUID, to unit: DistanceUnit) -> [Preview] {
    let journal = repository.journal
    guard let vehicle = journal.vehicle(vehicleID), vehicle.unit != unit else { return [] }

    return journal.trips(forVehicle: vehicleID)
      .filter { $0.startOdometer != nil || $0.endOdometer != nil }
      .map { trip in
        Preview(
          id: trip.id,
          tripName: trip.name,
          start: trip.startOdometer.map { ($0, vehicle.unit.converting($0, to: unit)) },
          end: trip.endOdometer.map { ($0, vehicle.unit.converting($0, to: unit)) }
        )
      }
  }

  func execute(vehicleID: UUID, to unit: DistanceUnit) throws {
    guard repository.journal.activeTrip?.vehicleID != vehicleID else {
      throw DomainError("Finish the trip under way before converting this vehicle's readings.")
    }

    try repository.apply { journal in
      guard let index = journal.vehicles.firstIndex(where: { $0.id == vehicleID }) else {
        throw DomainError.journalUnavailable
      }
      let current = journal.vehicles[index].unit
      guard current != unit else { return }

      for tripIndex in journal.trips.indices where journal.trips[tripIndex].vehicleID == vehicleID {
        journal.trips[tripIndex].startOdometer = journal.trips[tripIndex].startOdometer
          .map { current.converting($0, to: unit) }
        journal.trips[tripIndex].endOdometer = journal.trips[tripIndex].endOdometer
          .map { current.converting($0, to: unit) }
      }
      journal.vehicles[index].unit = unit
    }
  }
}

/// Saves a trip's checklist back onto its vehicle as the template for next time.
///
/// Existing trips keep the copies they already hold — a plan the traveller has
/// already prepared is not rewritten behind their back.
struct ReplaceVehicleTemplate {
  let repository: JournalRepository

  func execute(vehicleID: UUID, with items: [PreparationItem]) throws {
    let template = try items.map { try VehicleValidator.validatedItem($0.templateCopy()) }
    try repository.updateVehicle(vehicleID) { $0.preparationTemplate = template }
  }
}
