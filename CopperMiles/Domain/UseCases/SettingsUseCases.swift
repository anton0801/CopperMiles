import Foundation

/// Stores a change to the traveller's preferences.
struct UpdateSettings {
  let repository: JournalRepository

  func execute(_ change: (inout AppSettings) -> Void) throws {
    try repository.apply { journal in
      change(&journal.settings)
    }
  }
}

/// Lists the records the traveller has tidied away.
struct FindArchivedRecords {
  let repository: JournalRepository

  struct Records: Equatable {
    let vehicles: [Vehicle]
    let trips: [Trip]

    var isEmpty: Bool { vehicles.isEmpty && trips.isEmpty }
  }

  func execute() -> Records {
    let journal = repository.journal
    return Records(
      vehicles: journal.vehicles.filter(\.isArchived),
      trips: journal.trips.filter(\.isArchived)
        .sorted { ($0.actualStart ?? .distantPast) > ($1.actualStart ?? .distantPast) }
    )
  }
}
