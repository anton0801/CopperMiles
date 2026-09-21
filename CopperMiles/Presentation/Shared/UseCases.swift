import Foundation

/// Every use case the interface can reach, wired once.
///
/// Screens ask this for the operation they need rather than constructing one with
/// its dependencies, which is what keeps a view free of any knowledge about
/// repositories, schedulers or the attachment store.
struct UseCases {
  // Vehicles
  let saveVehicle: SaveVehicle
  let deleteVehicle: DeleteVehicle
  let setVehicleArchived: SetVehicleArchived
  let convertVehicleUnit: ConvertVehicleUnit
  let replaceVehicleTemplate: ReplaceVehicleTemplate

  // Planning
  let saveTrip: SaveTrip
  let duplicateTrip: DuplicateTrip
  let cancelTrip: CancelTrip
  let deleteTrip: DeleteTrip
  let setTripArchived: SetTripArchived

  // Stops
  let saveStop: SaveStop
  let moveStop: MoveStop
  let setDestination: SetDestination
  let removeStop: RemoveStop
  let duplicateStop: DuplicateStop

  // On the road
  let startTrip: StartTrip
  let finishTrip: FinishTrip
  let editTripSummary: EditTripSummary
  let recordVisit: RecordVisit
  let removeVisit: RemoveVisit
  let skipStop: SkipStop

  // Preparation
  let setChecklistItemChecked: SetChecklistItemChecked
  let saveChecklistItem: SaveChecklistItem
  let removeChecklistItem: RemoveChecklistItem
  let loadVehicleChecklistTemplate: LoadVehicleChecklistTemplate

  // Notes
  let saveRoadNote: SaveRoadNote
  let deleteRoadNote: DeleteRoadNote

  // Reminders
  let saveReminder: SaveReminder
  let deleteReminder: DeleteReminder
  let refreshReminders: RefreshTripReminders

  // Journal
  let findTrips: FindTrips
  let findJournalEntries: FindJournalEntries
  let buildTravelSummary: BuildTravelSummary
  let findArchivedRecords: FindArchivedRecords

  // Settings and data
  let updateSettings: UpdateSettings
  let exportBackup: ExportBackup
  let readBackup: ReadBackup
  let importBackup: ImportBackup
  let deleteAllData: DeleteAllData

  init(
    repository: JournalRepository,
    attachments: AttachmentStore,
    scheduler: ReminderScheduling,
    backupCodec: BackupCoding,
    dates: DateProvider
  ) {
    let refreshReminders = RefreshTripReminders(
      repository: repository,
      scheduler: scheduler,
      dates: dates
    )
    let journalEntries = FindJournalEntries(repository: repository, dates: dates)
    let exportBackup = ExportBackup(
      repository: repository,
      attachments: attachments,
      codec: backupCodec
    )

    saveVehicle = SaveVehicle(repository: repository, attachments: attachments)
    deleteVehicle = DeleteVehicle(repository: repository, attachments: attachments)
    setVehicleArchived = SetVehicleArchived(repository: repository)
    convertVehicleUnit = ConvertVehicleUnit(repository: repository)
    replaceVehicleTemplate = ReplaceVehicleTemplate(repository: repository)

    saveTrip = SaveTrip(repository: repository, reminders: refreshReminders)
    duplicateTrip = DuplicateTrip(repository: repository)
    cancelTrip = CancelTrip(repository: repository, reminders: scheduler)
    deleteTrip = DeleteTrip(
      repository: repository,
      attachments: attachments,
      reminders: scheduler
    )
    setTripArchived = SetTripArchived(repository: repository, reminders: scheduler)

    saveStop = SaveStop(repository: repository)
    moveStop = MoveStop(repository: repository)
    setDestination = SetDestination(repository: repository)
    removeStop = RemoveStop(repository: repository)
    duplicateStop = DuplicateStop(repository: repository)

    startTrip = StartTrip(repository: repository, dates: dates, reminders: scheduler)
    finishTrip = FinishTrip(repository: repository, dates: dates)
    editTripSummary = EditTripSummary(repository: repository, dates: dates)
    recordVisit = RecordVisit(repository: repository, dates: dates)
    removeVisit = RemoveVisit(repository: repository, attachments: attachments)
    skipStop = SkipStop(repository: repository)

    setChecklistItemChecked = SetChecklistItemChecked(repository: repository)
    saveChecklistItem = SaveChecklistItem(repository: repository)
    removeChecklistItem = RemoveChecklistItem(repository: repository)
    loadVehicleChecklistTemplate = LoadVehicleChecklistTemplate(repository: repository)

    saveRoadNote = SaveRoadNote(
      repository: repository,
      attachments: attachments,
      dates: dates
    )
    deleteRoadNote = DeleteRoadNote(repository: repository, attachments: attachments)

    saveReminder = SaveReminder(
      repository: repository,
      refresh: refreshReminders,
      dates: dates
    )
    deleteReminder = DeleteReminder(repository: repository, scheduler: scheduler)
    self.refreshReminders = refreshReminders

    findTrips = FindTrips(repository: repository, dates: dates)
    findJournalEntries = journalEntries
    buildTravelSummary = BuildTravelSummary(
      repository: repository,
      entries: journalEntries,
      dates: dates
    )
    findArchivedRecords = FindArchivedRecords(repository: repository)

    updateSettings = UpdateSettings(repository: repository)
    self.exportBackup = exportBackup
    readBackup = ReadBackup(codec: backupCodec, dates: dates)
    importBackup = ImportBackup(
      repository: repository,
      attachments: attachments,
      scheduler: scheduler,
      exportBackup: exportBackup,
      dates: dates
    )
    deleteAllData = DeleteAllData(
      repository: repository,
      attachments: attachments,
      scheduler: scheduler
    )
  }
}
