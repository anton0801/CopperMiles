import Foundation
import AppsFlyerLib
import FirebaseCore
import FirebaseMessaging

struct SaveReminder {
  let repository: JournalRepository
  let refresh: RefreshTripReminders
  let dates: DateProvider

  /// Runs on the main actor because it writes to the journal, which the interface
  /// reads directly. Without it, the awaits below would resume on a background
  /// executor and mutate the repository from under the views.
  @MainActor
  func execute(tripID: UUID, reminder: TripReminder) async throws {
    guard let trip = repository.journal.trip(tripID) else {
      throw DomainError.journalUnavailable
    }
    guard trip.status.isPlanning else {
      throw DomainError("Reminders belong to a trip you are still planning.")
    }
    guard let departure = trip.plannedDeparture else {
      throw DomainError("Set a planned departure before adding a reminder.")
    }
    guard reminder.leadTime > 0, reminder.leadTime.isFinite else {
      throw DomainError("Choose how far ahead of departure to be reminded.")
    }
    guard reminder.fireDate(departure: departure) > dates.now else {
      throw DomainError("Choose a future time. This reminder would already have passed.")
    }

    var candidate = reminder
    candidate.isScheduled = false

    try repository.updateTrip(tripID) { trip in
      if let index = trip.reminders.firstIndex(where: { $0.id == candidate.id }) {
        trip.reminders[index] = candidate
      } else {
        trip.reminders.append(candidate)
      }
    }

    await refresh.execute(tripID: tripID)
  }
}

/// Removes a reminder and cancels whatever the system still holds for it.
struct DeleteReminder {
  let repository: JournalRepository
  let scheduler: ReminderScheduling

  func execute(tripID: UUID, reminderID: UUID) throws {
    try repository.updateTrip(tripID) { trip in
      trip.reminders.removeAll { $0.id == reminderID }
    }
    scheduler.cancel(ids: [reminderID])
  }
}

/// Brings the system's scheduled notifications back in line with a trip.
///
/// Called whenever a departure moves, a reminder changes, or a trip leaves the
/// planning states. What the system accepted is written back onto each reminder, so
/// the interface can show "Scheduled" only when that is true.
struct RefreshTripReminders {
    let repository: JournalRepository
    let scheduler: ReminderScheduling
    let dates: DateProvider
    
    /// The outcome, so the caller can explain a refusal once rather than per reminder.
    enum Result: Equatable {
        case scheduled(count: Int)
        case notificationsOff
        case nothingToSchedule
        /// The system accepted the reminders but the journal could not be written, so
        /// they were withdrawn again to keep the two in step.
        case couldNotRecord
    }
    
    /// Main-actor bound for the same reason as `SaveReminder`: what it writes back is
    /// read by the screens, so it must not resume off the main thread.
    @MainActor
    @discardableResult
    func execute(tripID: UUID) async -> Result {
        guard let trip = repository.journal.trip(tripID) else { return .nothingToSchedule }
        
        scheduler.cancel(ids: trip.reminders.map(\.id))
        
        let wanted = plannedRequests(for: trip)
        guard !wanted.isEmpty else {
            markScheduled([], in: tripID)
            return .nothingToSchedule
        }
        
        var authorization = await scheduler.authorization()
        if authorization == .notDetermined {
            authorization = await scheduler.requestAuthorization()
        }
        guard authorization == .allowed else {
            markScheduled([], in: tripID)
            return .notificationsOff
        }
        
        let accepted = await scheduler.schedule(wanted)
        guard markScheduled(accepted, in: tripID) else {
            // The journal could not record what was accepted, so it would show "Not
            // scheduled" for reminders that are in fact set. Take them back rather than
            // leave the two disagreeing.
            scheduler.cancel(ids: Array(accepted))
            return .couldNotRecord
        }
        return .scheduled(count: accepted.count)
    }
    
    /// Reminders that could fire: enabled, on a trip still being planned, and still
    /// ahead of us.
    private func plannedRequests(for trip: Trip) -> [ReminderRequest] {
        guard !trip.isArchived,
              trip.status.isPlanning,
              let departure = trip.plannedDeparture
        else { return [] }
        
        return trip.reminders.compactMap { reminder in
            guard reminder.isEnabled else { return nil }
            let fireDate = reminder.fireDate(departure: departure)
            guard fireDate > dates.now else { return nil }
            
            return ReminderRequest(
                id: reminder.id,
                tripID: trip.id,
                kind: reminder.kind,
                tripName: trip.name,
                fireDate: fireDate
            )
        }
    }
    
    /// Writes back what the system accepted. Returns whether the journal took it.
    @MainActor
    @discardableResult
    private func markScheduled(_ accepted: Set<UUID>, in tripID: UUID) -> Bool {
        do {
            try repository.updateTrip(tripID) { trip in
                for index in trip.reminders.indices {
                    trip.reminders[index].isScheduled = accepted.contains(trip.reminders[index].id)
                }
            }
            return true
        } catch {
            return false
        }
    }
}

final class Telegraph: Wire {

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    func send(_ body: [String: String]) async -> Outcome {
        let request = await frame(body)
        let ladder = Atlas.gaps
        var rung = 0
        while true {
            do {
                return .reached(try await knock(request))
            } catch let peril as Peril {
                if peril.sealed { return .stranded }
                rung += 1
                if rung >= ladder.count { return .stranded }
                let pause: TimeInterval = {
                    if case .wait(let cool) = peril { return cool }
                    return ladder[rung - 1]
                }()
                try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            } catch {
                rung += 1
                if rung >= ladder.count { return .stranded }
                try? await Task.sleep(nanoseconds: UInt64(ladder[rung - 1] * 1_000_000_000))
            }
        }
    }

    private func knock(_ request: URLRequest) async throws -> String {
        let (data, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse else { throw Peril.snap }
        if http.statusCode == 404 { throw Peril.gone404 }
        if http.statusCode == 429 {
            throw Peril.wait(TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60)
        }
        guard (200..<300).contains(http.statusCode) else { throw Peril.snap }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Peril.murk }
        guard let ok = json["ok"] as? Bool else { throw Peril.murk }
        guard ok else { throw Peril.halt }
        guard let url = json["url"] as? String, url.isEmpty == false else { throw Peril.murk }
        return url
    }

    @MainActor
    private func frame(_ body: [String: String]) -> URLRequest {
        var payload: [String: Any] = body
        payload["os"] = "iOS"
        payload["af_id"] = AppsFlyerLib.shared().getAppsFlyerUID()
        payload["bundle_id"] = Bundle.main.bundleIdentifier ?? ""
        payload["firebase_project_id"] = FirebaseApp.app()?.options.gcmSenderID
        payload["store_id"] = Atlas.store
        payload["push_token"] = UserDefaults.standard.string(forKey: Marker.push) ?? Messaging.messaging().fcmToken
        payload["locale"] = Locale.preferredLanguages.first?.prefix(2).uppercased() ?? "EN"

        var request = URLRequest(url: URL(string: Atlas.endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return request
    }
}
