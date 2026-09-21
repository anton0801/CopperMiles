import Foundation
import SwiftUI
import UserNotifications

/// Everything the traveller has recorded, in one consistent whole.
///
/// The journal is the aggregate the repository stores and restores. Cross-entity
/// rules live here — a trip refers to a vehicle by identifier, and only one trip may
/// be active — which is why vehicles, trips and settings are saved together rather
/// than as three independent stores that could drift apart.
struct Journal: Equatable {
  var vehicles: [Vehicle]
  var trips: [Trip]
  var settings: AppSettings

  init(
    vehicles: [Vehicle] = [],
    trips: [Trip] = [],
    settings: AppSettings = AppSettings()
  ) {
    self.vehicles = vehicles
    self.trips = trips
    self.settings = settings
  }
}

// MARK: - Lookup

extension Journal {
  func vehicle(_ id: UUID?) -> Vehicle? {
    guard let id else { return nil }
    return vehicles.first { $0.id == id }
  }

  func trip(_ id: UUID) -> Trip? {
    trips.first { $0.id == id }
  }

  var availableVehicles: [Vehicle] {
    vehicles.filter { !$0.isArchived }
  }

  /// The single trip currently under way, if there is one.
  var activeTrip: Trip? {
    trips.first { $0.status == .active }
  }

  func trips(forVehicle id: UUID) -> [Trip] {
    trips.filter { $0.vehicleID == id }
  }

  /// The nearest planned departure still ahead, which is what Home offers to
  /// prepare. A planned trip whose date has passed is deliberately excluded: it
  /// belongs in Needs Review, not in "next".
  func upcomingTrip(now: Date) -> Trip? {
    trips
      .filter { trip in
        !trip.isArchived
          && trip.status == .planned
          && (trip.plannedDeparture.map { $0 >= now } ?? false)
      }
      .min { lhs, rhs in
        (lhs.plannedDeparture ?? .distantFuture) < (rhs.plannedDeparture ?? .distantFuture)
      }
  }

  func tripsNeedingReview(now: Date) -> [Trip] {
    trips.filter { !$0.isArchived && $0.needsReview(now: now) }
  }
}

// MARK: - Odometer history

extension Journal {
  /// A reading taken from a trip, with the moment it was taken.
  struct OdometerRecord: Equatable {
    let value: Double
    let recordedAt: Date
  }

  /// The most recent odometer reading known for a vehicle, across all of its trips.
  ///
  /// New readings are checked against this so that a suspicious drop is explained
  /// rather than silently stored.
  func latestOdometerReading(forVehicle id: UUID?) -> OdometerRecord? {
    guard let id else { return nil }
    return trips(forVehicle: id)
      .flatMap { trip -> [OdometerRecord] in
        var records: [OdometerRecord] = []
        if let date = trip.actualStart, let value = trip.startOdometer {
          records.append(OdometerRecord(value: value, recordedAt: date))
        }
        if let date = trip.actualEnd, let value = trip.endOdometer {
          records.append(OdometerRecord(value: value, recordedAt: date))
        }
        return records
      }
      .max { $0.recordedAt < $1.recordedAt }
  }
}

// MARK: - Attachments

extension Journal {
  /// Every attachment the journal still refers to.
  ///
  /// The attachment store keeps files only for these; anything else is orphaned and
  /// can be swept away after an import or a deletion.
  var referencedAttachmentIDs: Set<AttachmentID> {
    var ids = Set(vehicles.compactMap(\.photoID))
    for trip in trips {
      for note in trip.notes {
        ids.formUnion(note.photoIDs)
      }
    }
    return ids
  }
}

final class Horn: Chime {
    func ask() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        return granted
    }
}
