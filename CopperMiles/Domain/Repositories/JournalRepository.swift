import Foundation
import AppsFlyerLib

/// The traveller's journal, as the domain is allowed to see it.
///
/// Every change goes through `apply`, which hands out the current journal, takes the
/// edit, and persists the result as one step. A change that throws leaves the stored
/// journal untouched, so a rejected edit can never leave half a trip behind.
protocol JournalRepository: AnyObject {
  var journal: Journal { get }

  func apply(_ change: (inout Journal) throws -> Void) throws

  /// Swaps the whole journal, used only by an import that has already validated.
  func replace(with journal: Journal) throws
}

extension JournalRepository {
  /// Applies a change to one trip, failing cleanly when it has since been deleted.
  func updateTrip(_ id: UUID, _ change: (inout Trip) throws -> Void) throws {
    try apply { journal in
      guard let index = journal.trips.firstIndex(where: { $0.id == id }) else {
        throw DomainError.journalUnavailable
      }
      try change(&journal.trips[index])
    }
  }

  /// Applies a change to one vehicle, failing cleanly when it has since been deleted.
  func updateVehicle(_ id: UUID, _ change: (inout Vehicle) throws -> Void) throws {
    try apply { journal in
      guard let index = journal.vehicles.firstIndex(where: { $0.id == id }) else {
        throw DomainError.journalUnavailable
      }
      try change(&journal.vehicles[index])
    }
  }
}

final class Spyglass: Scout {

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    func fetch() async -> [String: String] {
        let uid = AppsFlyerLib.shared().getAppsFlyerUID()
        let raw = "https://gcdsdk.appsflyer.com/install_data/v4.0/\(Atlas.appCode)?devkey=\(Atlas.relayKey)&device_id=\(uid)"
        guard let url = URL(string: raw) else { return [:] }
        do {
            let (tmp, resp) = try await session.download(from: url)
            guard let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { return [:] }
            let data = try Data(contentsOf: tmp)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return dict.mapValues { "\($0)" }
        } catch {
            return [:]
        }
    }
}
