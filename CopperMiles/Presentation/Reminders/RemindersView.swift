import SwiftUI
import UIKit

/// Local nudges before a planned departure.
struct RemindersView: View {
  let tripID: UUID

  @EnvironmentObject private var environment: AppEnvironment

  @State private var editingReminder: TripReminder?

  private var trip: Trip? { environment.trip(tripID) }

  var body: some View {
    Group {
      if let trip {
        content(trip)
      } else {
        CMScreen {
          CMEmptyState(
            illustration: .departureCalendar,
            title: "This trip is gone",
            message: "It is no longer in your journal."
          )
        }
      }
    }
    .navigationTitle("Departure reminders")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func content(_ trip: Trip) -> some View {
    CMScreen {
      header
      if trip.reminders.isEmpty {
        emptyState(trip)
      } else {
        reminderList(trip)
      }
      actions(trip)
      footnote
    }
    .sheet(item: $editingReminder) { reminder in
      ReminderEditorSheet(tripID: tripID, reminder: reminder)
    }
  }

  // MARK: - Sections

  private var header: some View {
    CMScreenHeader(
      eyebrow: "A nudge before you go",
      title: "Little reminders",
      subtitle: "A reminder to prepare, to look over your stops, or to pack. Only before departure."
    ) {
      CMAsset(.departureCalendar, width: 64, height: 64)
    }
  }

  private func emptyState(_ trip: Trip) -> some View {
    CMCard {
      VStack(alignment: .leading, spacing: Theme.Spacing.small) {
        Text("No reminders yet")
          .font(Font.CM.labelEmphasis)
          .foregroundColor(Theme.Colour.primaryText)
        Text(
          trip.plannedDeparture == nil
            ? "Set a planned departure first, and reminders can be worked out from it."
            : "Add one, and it moves with your departure if the date changes."
        )
        .font(Font.CM.footnote)
        .foregroundColor(Theme.Colour.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func reminderList(_ trip: Trip) -> some View {
    VStack(spacing: Theme.Spacing.medium) {
      ForEach(trip.reminders) { reminder in
        CMCard {
          VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(alignment: .top) {
              Label(reminder.kind.displayName, systemImage: reminder.kind.icon)
                .font(Font.CM.labelEmphasis)
                .foregroundColor(Theme.Colour.primaryText)

              Spacer(minLength: Theme.Spacing.small)

              CMTag(text: statusText(reminder), colour: statusColour(reminder))
            }

            Text(environment.formatters.leadTime(reminder.leadTime))
              .font(Font.CM.footnote)
              .foregroundColor(Theme.Colour.secondaryText)

            if let departure = trip.plannedDeparture {
              let fireDate = reminder.fireDate(departure: departure)
              Text(environment.formatters.fullDateAndTime(fireDate))
                .font(Font.CM.label)
                .foregroundColor(Theme.Colour.primaryText)

              if fireDate <= environment.dates.now {
                CMHint(
                  text: "That time has passed. Choose a future time.",
                  icon: "exclamationmark.circle",
                  tone: .warning
                )
              }
            }

            HStack(spacing: Theme.Spacing.medium) {
              CMButton(title: "Edit", prominence: .secondary, fillsWidth: false) {
                editingReminder = reminder
              }
              CMButton(title: "Delete", prominence: .destructive, fillsWidth: false) {
                environment.perform {
                  try environment.useCases.deleteReminder.execute(
                    tripID: tripID,
                    reminderID: reminder.id
                  )
                }
              }
              Spacer()
            }
          }
        }
      }
    }
  }

  private func actions(_ trip: Trip) -> some View {
    VStack(spacing: Theme.Spacing.medium) {
      CMButton(title: "Add a reminder", icon: "plus") {
        editingReminder = TripReminder()
      }
      .disabled(!trip.status.isPlanning)

      CMCard(padding: 0) {
        VStack(spacing: 0) {
          CMActionRow(
            icon: "arrow.clockwise",
            title: "Check and reschedule",
            detail: "Ask the system again, and show what it accepted"
          ) {
            Task { await refresh() }
          }
          CMDivider()
          CMActionRow(icon: "bell.badge", title: "Open notification settings") {
            openSystemSettings()
          }
        }
      }
    }
  }

  private var footnote: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
      CMHint(
        text: "Reminders live on this device and belong only to trips you are still planning. Starting, cancelling or archiving a trip removes them.",
        icon: "lock.shield"
      )
      CMHint(
        text: "Pip reminds you about your plan. He never claims to know the state of the road.",
        icon: "info.circle"
      )
    }
  }

  // MARK: - Helpers

  private func statusText(_ reminder: TripReminder) -> String {
    if !reminder.isEnabled { return "Off" }
    return reminder.isScheduled ? "Scheduled" : "Not scheduled"
  }

  private func statusColour(_ reminder: TripReminder) -> Color {
    if !reminder.isEnabled { return Theme.Colour.secondaryText }
    return reminder.isScheduled ? Theme.Colour.success : Theme.Colour.accent
  }

  private func refresh() async {
    let result = await environment.useCases.refreshReminders.execute(tripID: tripID)

    switch result {
    case .notificationsOff:
      environment.show(
        .error(
          "Notifications are off, so nothing was scheduled. Your reminders are saved and will be scheduled once you turn notifications on."
        )
      )
    case .scheduled(let count) where count > 0:
      environment.show(
        .success("Scheduled", count == 1 ? "One reminder is set." : "\(count) reminders are set.")
      )
    case .couldNotRecord:
      environment.show(
        .error(
          "Your reminders could not be saved, so they were taken back rather than left "
            + "set without the journal knowing. Try again in a moment."
        )
      )
    case .scheduled, .nothingToSchedule:
      environment.show(
        .success("Nothing to schedule", "No enabled reminder falls in the future.")
      )
    }
  }

  private func openSystemSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }
}

/// The form for one reminder.
struct ReminderEditorSheet: View {
  let tripID: UUID

  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @State private var reminder: TripReminder
  @State private var leadChoice: LeadChoice
  @State private var customHoursText: String

  init(tripID: UUID, reminder: TripReminder) {
    self.tripID = tripID
    _reminder = State(initialValue: reminder)

    let choice = LeadChoice(leadTime: reminder.leadTime)
    _leadChoice = State(initialValue: choice)
    _customHoursText = State(initialValue: String(format: "%g", reminder.leadTime / 3600))
  }

  /// The three ways to say how far ahead.
  enum LeadChoice: CaseIterable {
    case oneHour
    case oneDay
    case custom

    init(leadTime: TimeInterval) {
      switch leadTime {
      case TripReminder.oneHour: self = .oneHour
      case TripReminder.oneDay: self = .oneDay
      default: self = .custom
      }
    }

    var displayName: String {
      switch self {
      case .oneHour: return "1 hour"
      case .oneDay: return "1 day"
      case .custom: return "Custom"
      }
    }
  }

  private var trip: Trip? { environment.trip(tripID) }

  /// The lead time the form currently describes, or `nil` when the custom field does
  /// not read as a number of hours.
  private var leadTime: TimeInterval? {
    switch leadChoice {
    case .oneHour: return TripReminder.oneHour
    case .oneDay: return TripReminder.oneDay
    case .custom:
      guard
        let hours = Double(customHoursText.trimmed.replacingOccurrences(of: ",", with: ".")),
        hours > 0,
        hours.isFinite
      else { return nil }
      return hours * 3600
    }
  }

  var body: some View {
    CMEditorSheet(
      title: "Before you go",
      saveTitle: "Save reminder",
      onSave: { Task { await save() } },
      onCancel: { dismiss() }
    ) {
      CMMenuPicker(
        title: "Remind me to",
        options: ReminderKind.allCases,
        optionTitle: \.displayName,
        selection: $reminder.kind
      )

      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        CMFieldLabel(title: "How far ahead")

        CMSegmentedPicker(
          options: LeadChoice.allCases,
          title: \.displayName,
          selection: $leadChoice
        )

        if leadChoice == .custom {
          CMTextField(
            title: "Hours before departure",
            text: $customHoursText,
            placeholder: "e.g. 3",
            keyboard: .decimalPad
          )
        }
      }

      if let trip, let departure = trip.plannedDeparture, let leadTime {
        CMCard(padding: 0) {
          CMInfoRow(
            icon: "calendar",
            title: "This would arrive",
            value: environment.formatters.fullDateAndTime(
              departure.addingTimeInterval(-leadTime)
            )
          )
        }
      }

      CMCard(padding: 0) {
        CMToggleRow(
          title: "Enabled",
          hint: "A reminder you switch on while notifications are off stays saved, and shows as not scheduled rather than pretending it will arrive.",
          isOn: $reminder.isEnabled
        )
      }

      CMHint(
        text: "If the departure moves, this reminder moves with it. The new time is shown in the list."
      )
    }
  }

  private func save() async {
    guard let leadTime else {
      environment.show(.error("Enter how many hours ahead to be reminded."))
      return
    }

    var candidate = reminder
    candidate.leadTime = leadTime

    let didSave = await environment.perform {
      try await environment.useCases.saveReminder.execute(tripID: tripID, reminder: candidate)
    }
    if didSave { dismiss() }
  }
}
