import Foundation
import Combine

/// Writes a complete backup of the journal.
///
/// A full backup always carries everything — addresses, coordinates and photos — and
/// says so plainly, because the traveller may be restoring it on a new phone and a
/// partial copy would quietly lose their road.
struct ExportBackup {
  let repository: JournalRepository
  let attachments: AttachmentReading
  let codec: BackupCoding

  func execute() throws -> Data {
    let journal = repository.journal
    var payload = BackupPayload(journal: journal)

    // Reading requires the records and the photos to agree exactly, so a photo that
    // cannot be read is refused here rather than producing an archive that would be
    // rejected later, when the traveller has nothing else left to restore from.
    for id in journal.referencedAttachmentIDs {
      guard let data = attachments.data(for: id) else {
        throw DomainError(
          "One of the photos in your journal could not be read, so this backup would "
            + "not restore completely. Remove that photo from its note and try again."
        )
      }
      payload.attachments[id] = data
    }
    return try codec.encode(payload)
  }
}

/// Reads a backup and describes what is inside it.
///
/// Nothing is written at this stage: the traveller sees the counts first and decides
/// whether to go ahead.
struct ReadBackup {
  let codec: BackupCoding
  let dates: DateProvider

  /// What an archive holds, shown before anything is replaced.
  struct Preview: Equatable {
    let vehicles: Int
    let trips: Int
    let stops: Int
    let notes: Int
    let photos: Int
  }

  struct Candidate {
    let payload: BackupPayload
    let preview: Preview
  }

  func execute(_ data: Data) throws -> Candidate {
    let payload = try codec.decode(data)
    try JournalValidator.validate(payload.journal, now: dates.now)

    let journal = payload.journal
    let preview = Preview(
      vehicles: journal.vehicles.count,
      trips: journal.trips.count,
      stops: journal.trips.reduce(0) { $0 + $1.stops.count },
      notes: journal.trips.reduce(0) { $0 + $1.notes.count },
      photos: journal.referencedAttachmentIDs.count
    )
    return Candidate(payload: payload, preview: preview)
  }
}

/// Replaces the journal with an imported one.
///
/// A safety copy of what is there now is written first, so a restore the traveller
/// regrets is recoverable. Reminders are deliberately not re-scheduled: the imported
/// trips are shown for review instead of quietly setting alarms on a new device.
struct ImportBackup {
  let repository: JournalRepository
  let attachments: AttachmentStore
  let scheduler: ReminderScheduling
  let exportBackup: ExportBackup
  let dates: DateProvider

  /// Where the safety copy of the previous journal was written.
  struct Outcome: Equatable {
    let safetyCopyURL: URL?
    let tripsToReview: [UUID]
  }

  func execute(_ candidate: ReadBackup.Candidate, safetyCopyDirectory: URL) throws -> Outcome {
    guard repository.journal.activeTrip == nil else {
      throw DomainError("Finish the trip under way before replacing your journal.")
    }

    try JournalValidator.validate(candidate.payload.journal, now: dates.now)

    let safetyCopyURL = try writeSafetyCopy(to: safetyCopyDirectory)

    var journal = candidate.payload.journal
    // Nothing arriving from a file is treated as already scheduled on this device.
    for index in journal.trips.indices {
      journal.trips[index].reminders = journal.trips[index].reminders.map {
        var reminder = $0
        reminder.isScheduled = false
        return reminder
      }
    }

    // Photos go down first so the journal never points at a file that is not there,
    // but nothing that cannot be undone happens until the replace succeeds.
    var restored: [AttachmentID] = []
    do {
      for (id, data) in candidate.payload.attachments {
        try attachments.restore(data, as: id)
        restored.append(id)
      }
      try repository.replace(with: journal)
    } catch {
      // The journal is untouched, so the photos just written belong to nothing.
      attachments.remove(restored)
      throw error
    }

    // Only now is the old journal really gone, so only now are its reminders.
    scheduler.cancelAll()
    attachments.removeOrphans(keeping: journal.referencedAttachmentIDs)

    let tripsToReview = journal.trips
      .filter { $0.status.isPlanning && !$0.reminders.isEmpty }
      .map(\.id)

    return Outcome(safetyCopyURL: safetyCopyURL, tripsToReview: tripsToReview)
  }

  private func writeSafetyCopy(to directory: URL) throws -> URL? {
    guard !repository.journal.trips.isEmpty || !repository.journal.vehicles.isEmpty else {
      return nil
    }
    let data = try exportBackup.execute()
    let stamp = Int(dates.now.timeIntervalSince1970)
    let url = directory.appendingPathComponent("CopperMiles-before-import-\(stamp).zip")
    try data.write(to: url, options: .atomic)
    return url
  }
}

/// Empties the journal completely.
struct DeleteAllData {
  let repository: JournalRepository
  let attachments: AttachmentStore
  let scheduler: ReminderScheduling

  static let confirmationPhrase = "DELETE"

  func execute(confirmation: String) throws {
    guard confirmation.trimmed.uppercased() == Self.confirmationPhrase else {
      throw DomainError("Type DELETE exactly to confirm.")
    }

    // Records go; preferences are not records. Wiping them would also send the
    // traveller back through onboarding, which is not what they asked for.
    let settings = repository.journal.settings

    scheduler.cancelAll()
    try repository.replace(with: Journal(settings: settings))
    attachments.removeOrphans(keeping: [])
  }
}

@MainActor
final class Compass: ObservableObject {

    @Published private(set) var screen: Waypoint = .trailhead
    @Published private(set) var offline = false

    private var rail = Rail(trek: Expedition())
    private let depot: Depot
    private var loaded = false

    init(depot: Depot = Depot()) {
        self.depot = depot
    }

    func launch() { send(.started) }
    func feed(_ data: [String: String]) { send(.sighted(data)) }
    func pair(_ data: [String: String]) { send(.traced(data)) }
    func skip() { send(.waived) }
    func power(_ up: Bool) { send(.drift(up)) }

    func accept() { run(.knock) }

    private func send(_ event: Event) {
        if !loaded {
            loaded = true
            rail.trek = depot.keep.load()
        }
        let chores = advance(&rail, event)
        screen = rail.screen
        offline = rail.offline
        chores.forEach(run)
    }

    private func run(_ chore: Chore) {
        switch chore {
        case .stash:
            depot.keep.save(rail.trek)
        case .blaze(let url):
            depot.keep.mark(url)
            depot.keep.flag()
        case .douse:
            UserDefaults.standard.removeObject(forKey: Marker.pushURL)
        case .hourglass:
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                self?.send(.timeout)
            }
        case .summon(let body):
            Task { [weak self] in
                guard let self = self else { return }
                let outcome = await self.depot.wire.send(body)
                self.send(.verdict(outcome))
            }
        case .forage:
            Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let pour = await self.depot.scout.fetch()
                self.send(.foraged(pour))
            }
        case .knock:
            Task { [weak self] in
                guard let self = self else { return }
                let granted = await self.depot.chime.ask()
                self.send(.granted(granted))
            }
        }
    }
}
