import Foundation

/// Translates between the journal the domain works with and the journal on disk.
///
/// Enumerations are stored as their case names rather than as numbers, so a file
/// stays readable and reordering a Swift enum can never silently change what a
/// stored record means.
enum JournalMapper {

  // MARK: - Domain → stored

  static func dto(_ journal: Journal) -> JournalDTO {
    JournalDTO(
      version: JournalDTO.currentVersion,
      vehicles: journal.vehicles.map(dto),
      trips: journal.trips.map(dto),
      settings: dto(journal.settings)
    )
  }

  private static func dto(_ vehicle: Vehicle) -> VehicleDTO {
    VehicleDTO(
      id: vehicle.id,
      name: vehicle.name,
      make: vehicle.make,
      model: vehicle.model,
      colourNote: vehicle.colourNote,
      unit: vehicle.unit.rawValue,
      photoID: vehicle.photoID?.rawValue,
      preparationTemplate: vehicle.preparationTemplate.map(dto),
      isArchived: vehicle.isArchived
    )
  }

  private static func dto(_ item: PreparationItem) -> PreparationItemDTO {
    PreparationItemDTO(
      id: item.id,
      name: item.name,
      group: item.group.rawValue,
      isImportant: item.isImportant,
      isChecked: item.isChecked,
      note: item.note
    )
  }

  private static func dto(_ stop: Stop) -> StopDTO {
    StopDTO(
      id: stop.id,
      name: stop.name,
      kind: stop.kind.rawValue,
      address: stop.address,
      coordinate: stop.coordinate.map {
        CoordinateDTO(latitude: $0.latitude, longitude: $0.longitude)
      },
      plannedArrival: stop.plannedArrival,
      plannedStayMinutes: stop.plannedStayMinutes,
      parkingNote: stop.parkingNote,
      personalNote: stop.personalNote,
      visit: stop.visit.map { VisitDTO(arrival: $0.arrival, departure: $0.departure) },
      skipReason: stop.skipReason,
      isArchived: stop.isArchived
    )
  }

  private static func dto(_ note: RoadNote) -> RoadNoteDTO {
    RoadNoteDTO(
      id: note.id,
      kind: note.kind.rawValue,
      text: note.text,
      recordedAt: note.recordedAt,
      stopID: note.stopID,
      photoIDs: note.photoIDs.map(\.rawValue),
      isPinnedForRepeat: note.isPinnedForRepeat
    )
  }

  private static func dto(_ reminder: TripReminder) -> TripReminderDTO {
    TripReminderDTO(
      id: reminder.id,
      kind: reminder.kind.rawValue,
      leadTime: reminder.leadTime,
      isEnabled: reminder.isEnabled,
      isScheduled: reminder.isScheduled
    )
  }

  private static func dto(_ trip: Trip) -> TripDTO {
    TripDTO(
      id: trip.id,
      name: trip.name,
      vehicleID: trip.vehicleID,
      status: trip.status.rawValue,
      plannedDeparture: trip.plannedDeparture,
      expectedEnd: trip.expectedEnd,
      startPlace: trip.startPlace,
      travellers: trip.travellers,
      note: trip.note,
      stops: trip.stops.map(dto),
      checklist: trip.checklist.map(dto),
      notes: trip.notes.map(dto),
      reminders: trip.reminders.map(dto),
      actualStart: trip.actualStart,
      actualEnd: trip.actualEnd,
      startOdometer: trip.startOdometer,
      endOdometer: trip.endOdometer,
      odometerExplanation: trip.odometerExplanation?.rawValue,
      hasReadingDiscontinuity: trip.hasReadingDiscontinuity,
      outcome: trip.outcome?.rawValue,
      endReason: trip.endReason,
      finalNote: trip.finalNote,
      isArchived: trip.isArchived
    )
  }

  private static func dto(_ settings: AppSettings) -> SettingsDTO {
    SettingsDTO(
      reportUnit: settings.reportUnit.rawValue,
      uses24HourTime: settings.uses24HourTime,
      prefersReducedMotion: settings.prefersReducedMotion,
      includesAddressesInExport: settings.exportOptions.includesAddresses,
      includesCoordinatesInExport: settings.exportOptions.includesCoordinates,
      includesPhotosInExport: settings.exportOptions.includesPhotos,
      hasSeenOnboarding: settings.hasSeenOnboarding
    )
  }

  // MARK: - Stored → domain

  static func journal(_ dto: JournalDTO) throws -> Journal {
    guard dto.version == JournalDTO.currentVersion else {
      throw JournalVersionError(isNewer: dto.version > JournalDTO.currentVersion)
    }

    return Journal(
      vehicles: try dto.vehicles.map(vehicle),
      trips: try dto.trips.map(trip),
      settings: settings(dto.settings)
    )
  }

  private static func vehicle(_ dto: VehicleDTO) throws -> Vehicle {
    Vehicle(
      id: dto.id,
      name: dto.name,
      make: dto.make,
      model: dto.model,
      colourNote: dto.colourNote,
      unit: try decode(DistanceUnit.self, dto.unit, field: "distance unit"),
      photoID: dto.photoID.map(AttachmentID.init),
      preparationTemplate: try dto.preparationTemplate.map(item),
      isArchived: dto.isArchived
    )
  }

  private static func item(_ dto: PreparationItemDTO) throws -> PreparationItem {
    PreparationItem(
      id: dto.id,
      name: dto.name,
      group: try decode(PreparationGroup.self, dto.group, field: "checklist group"),
      isImportant: dto.isImportant,
      isChecked: dto.isChecked,
      note: dto.note
    )
  }

  private static func stop(_ dto: StopDTO) throws -> Stop {
    Stop(
      id: dto.id,
      name: dto.name,
      kind: try decode(StopKind.self, dto.kind, field: "stop type"),
      address: dto.address,
      coordinate: dto.coordinate.map {
        Coordinate(latitude: $0.latitude, longitude: $0.longitude)
      },
      plannedArrival: dto.plannedArrival,
      plannedStayMinutes: dto.plannedStayMinutes,
      parkingNote: dto.parkingNote,
      personalNote: dto.personalNote,
      visit: dto.visit.map { Visit(arrival: $0.arrival, departure: $0.departure) },
      skipReason: dto.skipReason,
      isArchived: dto.isArchived
    )
  }

  private static func note(_ dto: RoadNoteDTO) throws -> RoadNote {
    RoadNote(
      id: dto.id,
      kind: try decode(RoadNoteKind.self, dto.kind, field: "note type"),
      text: dto.text,
      recordedAt: dto.recordedAt,
      stopID: dto.stopID,
      photoIDs: dto.photoIDs.map(AttachmentID.init),
      isPinnedForRepeat: dto.isPinnedForRepeat
    )
  }

  private static func reminder(_ dto: TripReminderDTO) throws -> TripReminder {
    TripReminder(
      id: dto.id,
      kind: try decode(ReminderKind.self, dto.kind, field: "reminder type"),
      leadTime: dto.leadTime,
      isEnabled: dto.isEnabled,
      isScheduled: dto.isScheduled
    )
  }

  private static func trip(_ dto: TripDTO) throws -> Trip {
    Trip(
      id: dto.id,
      name: dto.name,
      vehicleID: dto.vehicleID,
      status: try decode(TripStatus.self, dto.status, field: "trip status"),
      plannedDeparture: dto.plannedDeparture,
      expectedEnd: dto.expectedEnd,
      startPlace: dto.startPlace,
      travellers: dto.travellers,
      note: dto.note,
      stops: try dto.stops.map(stop),
      checklist: try dto.checklist.map(item),
      notes: try dto.notes.map(note),
      reminders: try dto.reminders.map(reminder),
      actualStart: dto.actualStart,
      actualEnd: dto.actualEnd,
      startOdometer: dto.startOdometer,
      endOdometer: dto.endOdometer,
      odometerExplanation: try dto.odometerExplanation.map {
        try decode(OdometerExplanation.self, $0, field: "odometer explanation")
      },
      hasReadingDiscontinuity: dto.hasReadingDiscontinuity,
      outcome: try dto.outcome.map {
        try decode(TripOutcome.self, $0, field: "trip outcome")
      },
      endReason: dto.endReason,
      finalNote: dto.finalNote,
      isArchived: dto.isArchived
    )
  }

  private static func settings(_ dto: SettingsDTO) -> AppSettings {
    AppSettings(
      // A preference is never worth refusing to open a journal over, so an
      // unreadable one quietly falls back to the default.
      reportUnit: DistanceUnit(rawValue: dto.reportUnit) ?? .kilometres,
      uses24HourTime: dto.uses24HourTime,
      prefersReducedMotion: dto.prefersReducedMotion,
      exportOptions: ExportOptions(
        includesAddresses: dto.includesAddressesInExport,
        includesCoordinates: dto.includesCoordinatesInExport,
        includesPhotos: dto.includesPhotosInExport
      ),
      hasSeenOnboarding: dto.hasSeenOnboarding
    )
  }

  private static func decode<T: RawRepresentable>(
    _ type: T.Type,
    _ raw: String,
    field: String
  ) throws -> T where T.RawValue == String {
    guard let value = T(rawValue: raw) else {
      throw DomainError("This journal contains an unknown \(field): “\(raw)”.")
    }
    return value
  }
}

enum Event {
    case started
    case sighted([String: String])
    case traced([String: String])
    case foraged([String: String])
    case verdict(Outcome)
    case granted(Bool)
    case waived
    case drift(Bool)
    case timeout
}

enum Chore {
    case stash
    case blaze(String)
    case douse
    case summon([String: String])
    case forage
    case knock
    case hourglass
}
