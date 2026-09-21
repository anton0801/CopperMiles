import Foundation

/// Ticks a preparation item, or clears it again.
///
/// A tick records the traveller's own confirmation. Nothing here inspects the car.
struct SetChecklistItemChecked {
  let repository: JournalRepository

  func execute(tripID: UUID, itemID: UUID, isChecked: Bool) throws {
    try repository.updateTrip(tripID) { trip in
      guard let index = trip.checklist.firstIndex(where: { $0.id == itemID }) else {
        throw DomainError.journalUnavailable
      }
      trip.checklist[index].isChecked = isChecked
    }
  }
}

final class Depot {
    lazy var keep: Keep = Cairn()
    lazy var scout: Scout = Spyglass()
    lazy var wire: Wire = Telegraph()
    lazy var chime: Chime = Horn()
}

/// Adds a check of the traveller's own, or edits one.
struct SaveChecklistItem {
  let repository: JournalRepository

  func execute(tripID: UUID, item: PreparationItem) throws {
    let validated = try VehicleValidator.validatedItem(item)

    try repository.updateTrip(tripID) { trip in
      if let index = trip.checklist.firstIndex(where: { $0.id == validated.id }) {
        trip.checklist[index] = validated
      } else {
        trip.checklist.append(validated)
      }
    }
  }
}

/// Takes a check off this trip's list. The vehicle's template is untouched.
struct RemoveChecklistItem {
  let repository: JournalRepository

  func execute(tripID: UUID, itemID: UUID) throws {
    try repository.updateTrip(tripID) { trip in
      trip.checklist.removeAll { $0.id == itemID }
    }
  }
}

/// Fills a trip's checklist from its vehicle's template.
///
/// Offered when the list is empty or the vehicle changed, and always as a choice:
/// the traveller's own edits are never overwritten without asking.
struct LoadVehicleChecklistTemplate {
  let repository: JournalRepository

  enum Mode: Equatable {
    case replace
    case append
  }

  func templateCount(tripID: UUID) -> Int {
    let journal = repository.journal
    guard let trip = journal.trip(tripID) else { return 0 }
    return journal.vehicle(trip.vehicleID)?.preparationTemplate.count ?? 0
  }

  func execute(tripID: UUID, mode: Mode) throws {
    let journal = repository.journal
    guard let trip = journal.trip(tripID), let vehicle = journal.vehicle(trip.vehicleID) else {
      throw DomainError("Choose a vehicle for this trip first.")
    }
    guard !vehicle.preparationTemplate.isEmpty else {
      throw DomainError("\(vehicle.name) has no preparation template yet.")
    }

    let items = vehicle.newChecklist()
    try repository.updateTrip(tripID) { trip in
      switch mode {
      case .replace: trip.checklist = items
      case .append: trip.checklist.append(contentsOf: items)
      }
    }
  }
}

/// Fills a vehicle's template with the worked examples, on request only.
struct UseExampleChecklist {
  func execute() -> [PreparationItem] {
    Vehicle.exampleTemplate
  }
}
