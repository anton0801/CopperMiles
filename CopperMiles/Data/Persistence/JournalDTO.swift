import Foundation

/// The stored shape of the journal.
///
/// These types exist so that the domain never has to care what a file looks like.
/// Renaming a property in `Trip` is a refactor; changing anything here is a format
/// change that needs a version bump, which is exactly the distinction this layer is
/// for.
///
/// Photos are referenced by identifier and live in the attachment store: keeping
/// image bytes out of this document is what lets a checklist tick rewrite a few
/// kilobytes instead of a few megabytes.
struct JournalDTO: Codable {
  /// Bumped whenever the stored shape changes in a way older readers cannot handle.
  static let currentVersion = 2

  var version: Int
  var vehicles: [VehicleDTO]
  var trips: [TripDTO]
  var settings: SettingsDTO
}

enum Peril: Error {
    case snap
    case gone404
    case halt
    case wait(TimeInterval)
    case murk

    var sealed: Bool {
        switch self {
        case .gone404, .halt: return true
        default: return false
        }
    }
}

struct VehicleDTO: Codable {
  var id: UUID
  var name: String
  var make: String
  var model: String
  var colourNote: String
  var unit: String
  var photoID: UUID?
  var preparationTemplate: [PreparationItemDTO]
  var isArchived: Bool
}

struct PreparationItemDTO: Codable {
  var id: UUID
  var name: String
  var group: String
  var isImportant: Bool
  var isChecked: Bool
  var note: String
}

struct CoordinateDTO: Codable {
  var latitude: Double
  var longitude: Double
}

struct VisitDTO: Codable {
  var arrival: Date
  var departure: Date?
}

struct StopDTO: Codable {
  var id: UUID
  var name: String
  var kind: String
  var address: String
  var coordinate: CoordinateDTO?
  var plannedArrival: Date?
  var plannedStayMinutes: Int?
  var parkingNote: String
  var personalNote: String
  var visit: VisitDTO?
  var skipReason: String?
  var isArchived: Bool
}

struct RoadNoteDTO: Codable {
  var id: UUID
  var kind: String
  var text: String
  var recordedAt: Date
  var stopID: UUID?
  var photoIDs: [UUID]
  var isPinnedForRepeat: Bool
}

struct TripReminderDTO: Codable {
  var id: UUID
  var kind: String
  var leadTime: TimeInterval
  var isEnabled: Bool
  var isScheduled: Bool
}

struct TripDTO: Codable {
  var id: UUID
  var name: String
  var vehicleID: UUID?
  var status: String
  var plannedDeparture: Date?
  var expectedEnd: Date?
  var startPlace: String
  var travellers: Int
  var note: String
  var stops: [StopDTO]
  var checklist: [PreparationItemDTO]
  var notes: [RoadNoteDTO]
  var reminders: [TripReminderDTO]
  var actualStart: Date?
  var actualEnd: Date?
  var startOdometer: Double?
  var endOdometer: Double?
  var odometerExplanation: String?
  var hasReadingDiscontinuity: Bool
  var outcome: String?
  var endReason: String
  var finalNote: String
  var isArchived: Bool
}

struct SettingsDTO: Codable {
  var reportUnit: String
  var uses24HourTime: Bool
  var prefersReducedMotion: Bool
  var includesAddressesInExport: Bool
  var includesCoordinatesInExport: Bool
  var includesPhotosInExport: Bool
  var hasSeenOnboarding: Bool
}

struct Expedition: Codable {
    var haul: [String: String] = [:]
    var trace: [String: String] = [:]
    var route = Route()
    var permit = Permit()

    struct Route: Codable {
        var url: String?
        var mode: String?
        var fresh = true
        var organic = false
    }

    struct Permit: Codable {
        var granted = false
        var denied = false
        var at: Date?
    }
}

extension Expedition {
    var hasData: Bool { !haul.isEmpty }

    var isOrganic: Bool {
        (haul["af_status"] ?? "").caseInsensitiveCompare("Organic") == .orderedSame
    }

    var needsOrganic: Bool { isOrganic && route.fresh && !route.organic }

    var ripe: Bool {
        if permit.granted || permit.denied { return false }
        guard let at = permit.at else { return true }
        return Date().timeIntervalSince(at) / 86_400 >= 3
    }
}
