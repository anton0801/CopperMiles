import Foundation

/// Checks a vehicle before it enters the journal.
enum VehicleValidator {
  static let nameLength = 1...60

  /// Returns the vehicle in the exact shape it should be stored in, or throws with a
  /// message the traveller can act on.
  static func validated(_ vehicle: Vehicle) throws -> Vehicle {
    var vehicle = vehicle
    vehicle.name = vehicle.name.trimmed
    vehicle.make = vehicle.make.trimmed
    vehicle.model = vehicle.model.trimmed
    vehicle.colourNote = vehicle.colourNote.trimmed

    guard nameLength.contains(vehicle.name.count) else {
      throw DomainError("Give your vehicle a name of 1 to 60 characters.")
    }

    vehicle.preparationTemplate = try vehicle.preparationTemplate.map(validatedItem)
    return vehicle
  }

  static func validatedItem(_ item: PreparationItem) throws -> PreparationItem {
    var item = item
    item.name = item.name.trimmed
    item.note = item.note.trimmed

    guard !item.name.isEmpty else {
      throw DomainError("Give this preparation item a name.")
    }
    return item
  }
}
