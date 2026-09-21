import Foundation

/// The section a preparation item belongs to on the departure checklist.
enum PreparationGroup: String, CaseIterable, Equatable {
  case car
  case documents
  case personal
  case other
}

/// One check the traveller wants to make before setting off.
///
/// A vehicle holds a reusable template of these; a trip holds its own copy, so
/// editing the template never rewrites the checklist of a trip already planned.
/// `isChecked` records the traveller's own confirmation and says nothing about the
/// mechanical state of the car.
struct PreparationItem: Identifiable, Equatable {
  let id: UUID
  var name: String
  var group: PreparationGroup
  var isImportant: Bool
  var isChecked: Bool
  var note: String

  init(
    id: UUID = UUID(),
    name: String = "",
    group: PreparationGroup = .car,
    isImportant: Bool = false,
    isChecked: Bool = false,
    note: String = ""
  ) {
    self.id = id
    self.name = name
    self.group = group
    self.isImportant = isImportant
    self.isChecked = isChecked
    self.note = note
  }

  /// A new item with the same wording, ready for another trip: a fresh identity and
  /// no tick carried over from last time.
  func templateCopy() -> PreparationItem {
    PreparationItem(
      name: name,
      group: group,
      isImportant: isImportant,
      isChecked: false,
      note: note
    )
  }
}
