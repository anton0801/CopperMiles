import Foundation

/// How much of a trip is carried into a share or export.
///
/// Everything here is off by default: an exported trip is a story about the road,
/// not a map of where the traveller actually is.
struct ExportOptions: Equatable {
  var includesAddresses: Bool
  var includesCoordinates: Bool
  var includesPhotos: Bool

  init(
    includesAddresses: Bool = false,
    includesCoordinates: Bool = false,
    includesPhotos: Bool = false
  ) {
    self.includesAddresses = includesAddresses
    self.includesCoordinates = includesCoordinates
    self.includesPhotos = includesPhotos
  }
}

/// The traveller's own preferences.
///
/// `reportUnit` only affects how summaries are presented; it never rewrites a
/// vehicle's stored odometer readings.
struct AppSettings: Equatable {
  var reportUnit: DistanceUnit
  var uses24HourTime: Bool
  var prefersReducedMotion: Bool
  var exportOptions: ExportOptions
  var hasSeenOnboarding: Bool

  init(
    reportUnit: DistanceUnit = .kilometres,
    uses24HourTime: Bool = false,
    prefersReducedMotion: Bool = false,
    exportOptions: ExportOptions = ExportOptions(),
    hasSeenOnboarding: Bool = false
  ) {
    self.reportUnit = reportUnit
    self.uses24HourTime = uses24HourTime
    self.prefersReducedMotion = prefersReducedMotion
    self.exportOptions = exportOptions
    self.hasSeenOnboarding = hasSeenOnboarding
  }
}

protocol Keep {
    func load() -> Expedition
    func save(_ trek: Expedition)
    func mark(_ url: String)
    func flag()
}
