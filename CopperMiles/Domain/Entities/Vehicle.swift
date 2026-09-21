import Foundation

/// A car the traveller plans trips with.
///
/// The photo is referenced by identifier rather than held inline: attachments live
/// in their own store so that ticking a checklist item does not rewrite every image
/// in the journal.
struct Vehicle: Identifiable, Equatable {
  let id: UUID
  var name: String
  var make: String
  var model: String
  var colourNote: String
  var unit: DistanceUnit
  var photoID: AttachmentID?
  var preparationTemplate: [PreparationItem]
  var isArchived: Bool

  init(
    id: UUID = UUID(),
    name: String = "",
    make: String = "",
    model: String = "",
    colourNote: String = "",
    unit: DistanceUnit = .kilometres,
    photoID: AttachmentID? = nil,
    preparationTemplate: [PreparationItem] = [],
    isArchived: Bool = false
  ) {
    self.id = id
    self.name = name
    self.make = make
    self.model = model
    self.colourNote = colourNote
    self.unit = unit
    self.photoID = photoID
    self.preparationTemplate = preparationTemplate
    self.isArchived = isArchived
  }

  /// Make and model joined for display, empty when neither was filled in.
  var descriptor: String {
    [make, model]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  /// A checklist for a new trip, built from this vehicle's template.
  func newChecklist() -> [PreparationItem] {
    preparationTemplate.map { $0.templateCopy() }
  }
}

extension Vehicle {
  /// Starting points offered behind "Use example checklist", never added on their own.
  static var exampleTemplate: [PreparationItem] {
    [
      PreparationItem(name: "Check tyre pressure", group: .car, isImportant: true),
      PreparationItem(name: "Check fuel level", group: .car),
      PreparationItem(name: "Vehicle documents", group: .documents, isImportant: true),
      PreparationItem(name: "Water and snacks", group: .personal),
      PreparationItem(name: "Phone charger", group: .personal),
    ]
  }
}
