import SwiftUI

/// Holds a trip while it is being planned.
///
/// The form has two fields the trip itself does not carry — the destination's name
/// and address before it becomes a stop — so assembling the finished trip lives here
/// rather than being spread across the view's save button.
@MainActor
final class TripEditorModel: ObservableObject {
  @Published var trip: Trip
  @Published var departure: Date
  @Published var hasExpectedEnd: Bool
  @Published var expectedEnd: Date
  @Published var destinationName: String
  @Published var destinationAddress: String

  init(trip: Trip, now: Date) {
    let departure = trip.plannedDeparture ?? now.addingTimeInterval(3600)

    self.trip = trip
    self.departure = departure
    self.hasExpectedEnd = trip.expectedEnd != nil
    self.expectedEnd = trip.expectedEnd ?? departure.addingTimeInterval(7200)
    self.destinationName = ""
    self.destinationAddress = ""
  }

  /// Whether the destination already exists as a stop.
  ///
  /// Once it does, its name and address are edited through that stop, so the trip
  /// never holds a second, conflicting copy of them.
  var hasDestinationStop: Bool { trip.destination != nil }

  /// The trip as the form currently describes it.
  func candidate() -> Trip {
    var candidate = trip
    candidate.plannedDeparture = departure
    candidate.expectedEnd = hasExpectedEnd ? expectedEnd : nil

    if !hasDestinationStop, !destinationName.isBlank {
      candidate.stops.append(
        Stop(
          name: destinationName.trimmed,
          kind: .destination,
          address: destinationAddress.trimmed
        )
      )
    }
    return candidate
  }

  /// Keeps the expected end behind the departure as the departure moves.
  func departureDidChange() {
    if expectedEnd <= departure {
      expectedEnd = departure.addingTimeInterval(7200)
    }
  }
}

/// The form for planning a trip.
struct TripEditorSheet: View {
  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @StateObject private var model: TripEditorModel

  var onSaved: ((Trip) -> Void)?
  var dismissesOnSave = true

  @State private var isAddingVehicle = false
  @State private var isConfirmingCancel = false
  @State private var overlap: OverlapWarning?

  init(
    trip: Trip,
    now: Date = Date(),
    onSaved: ((Trip) -> Void)? = nil,
    dismissesOnSave: Bool = true
  ) {
    _model = StateObject(wrappedValue: TripEditorModel(trip: trip, now: now))
    self.onSaved = onSaved
    self.dismissesOnSave = dismissesOnSave
  }

  private var isNew: Bool { environment.trip(model.trip.id) == nil }

  private var vehicleOptions: [UUID?] {
    let available = environment.journal.vehicles
      .filter { !$0.isArchived || $0.id == model.trip.vehicleID }
      .map { Optional($0.id) }
    return [nil] + available
  }

  var body: some View {
    CMEditorSheet(
      title: isNew ? "A new trip" : "Edit your plan",
      saveTitle: "Save and plan stops",
      saveIcon: "arrow.right",
      onSave: { save(asPlanned: true) },
      onCancel: { isConfirmingCancel = true }
    ) {
      intro
      basics
      timing
      places
      extras
      draftButton
    }
    .sheet(isPresented: $isAddingVehicle) {
      VehicleEditorSheet(vehicle: Vehicle()) { model.trip.vehicleID = $0.id }
    }
    .sheet(item: $overlap) { warning in
      OverlapWarningSheet(warning: warning) { candidate in
        overlap = nil
        store(candidate)
      } onReturn: {
        overlap = nil
      }
    }
    .confirmationDialog(
      "Save what you’ve entered?",
      isPresented: $isConfirmingCancel,
      titleVisibility: .visible
    ) {
      Button("Keep as a draft") { save(asPlanned: false) }
      Button("Discard changes", role: .destructive) { dismiss() }
      Button("Keep editing", role: .cancel) {}
    }
  }

  // MARK: - Sections

  private var intro: some View {
    HStack(spacing: Theme.Spacing.large) {
      CMAsset(.departureCalendar, width: 76, height: 76)

      VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
        Text("Let’s make a little plan.")
          .font(Font.CM.cardTitle)
          .foregroundColor(Theme.Colour.primaryText)
          .fixedSize(horizontal: false, vertical: true)
        Text("The best journeys start with an idea.")
          .font(Font.CM.footnote)
          .foregroundColor(Theme.Colour.secondaryText)
      }
    }
  }

  private var basics: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.large) {
      CMTextField(
        title: "Trip name",
        text: $model.trip.name,
        placeholder: "e.g. A weekend by the coast",
        isRequired: true
      )

      VStack(alignment: .leading, spacing: Theme.Spacing.small) {
        CMMenuPicker(
          title: "Vehicle",
          isRequired: true,
          options: vehicleOptions,
          optionTitle: { id in
            guard let id else { return "Choose a vehicle" }
            return environment.vehicle(id)?.name ?? "Unknown vehicle"
          },
          selection: $model.trip.vehicleID
        )
        .disabled(model.trip.status == .active)

        if model.trip.status == .active {
          CMHint(text: "The vehicle stays put while a trip is under way.", icon: "lock")
        } else {
          CMButton(title: "Add another vehicle", icon: "plus", prominence: .tertiary) {
            isAddingVehicle = true
          }
        }
      }
    }
  }

  private var timing: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.large) {
      CMDateField(title: "Planned departure", isRequired: true, date: $model.departure)
        .onChange(of: model.departure) { _ in model.departureDidChange() }

      CMCard(padding: 0) {
        CMToggleRow(
          title: "Add an expected end",
          hint: "Useful when you know roughly when you’ll be back.",
          isOn: $model.hasExpectedEnd
        )
      }

      if model.hasExpectedEnd {
        CMDateField(title: "Expected end", date: $model.expectedEnd)
      }
    }
  }

  private var places: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.large) {
      CMTextField(
        title: "Setting off from",
        text: $model.trip.startPlace,
        placeholder: "Where does the journey begin?",
        isRequired: true
      )
      CMHint(text: "Place names are your own labels. Nothing is looked up or sent anywhere.")

      if model.hasDestinationStop {
        CMCard(padding: 0) {
          CMInfoRow(
            icon: "flag.fill",
            title: "Destination",
            value: model.trip.destination?.name ?? ""
          )
        }
        CMHint(
          text: "The destination’s name and address are edited from its stop, so there is only ever one of each.",
          icon: "info.circle"
        )
      } else {
        CMTextField(
          title: "Destination",
          text: $model.destinationName,
          placeholder: "Where are you heading?",
          isRequired: true
        )
        CMTextField(
          title: "Destination address",
          text: $model.destinationAddress,
          placeholder: "Optional · used to search in Maps"
        )
      }
    }
  }

  private var extras: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.large) {
      CMStepperField(
        title: "Travellers",
        value: $model.trip.travellers,
        range: Trip.travellerRange
      ) { count in
        count == 1 ? "1 traveller" : "\(count) travellers"
      }

      CMTextEditor(
        title: "Trip note",
        text: $model.trip.note,
        hint: "Anything worth carrying into the journey."
      )
    }
  }

  private var draftButton: some View {
    CMButton(title: "Save as a draft", icon: "tray.and.arrow.down", prominence: .secondary) {
      save(asPlanned: false)
    }
  }

  // MARK: - Saving

  private func save(asPlanned: Bool) {
    let candidate = model.candidate()

    // A draft may be as unfinished as the traveller likes, so only a real plan is
    // checked against the other trips for this vehicle.
    guard asPlanned else {
      store(candidate, asPlanned: false)
      return
    }

    let overlapping = TripValidator.overlappingTrips(with: candidate, in: environment.journal)
    if overlapping.isEmpty {
      store(candidate)
    } else {
      overlap = OverlapWarning(candidate: candidate, conflicts: overlapping)
    }
  }

  private func store(_ candidate: Trip, asPlanned: Bool = true) {
    let saved = environment.performReturning {
      try environment.useCases.saveTrip.execute(candidate, asPlanned: asPlanned)
    }
    guard let saved else { return }

    onSaved?(saved)
    if dismissesOnSave { dismiss() }
  }
}

/// Two plans for one vehicle whose dates overlap.
struct OverlapWarning: Identifiable {
  let id = UUID()
  let candidate: Trip
  let conflicts: [Trip]
}

/// Warns about overlapping plans without refusing them.
///
/// Two trips in one car on one weekend may well be deliberate, and only the
/// traveller knows. The app shows what it noticed and lets them decide.
struct OverlapWarningSheet: View {
  let warning: OverlapWarning
  let onKeepBoth: (Trip) -> Void
  let onReturn: () -> Void

  var body: some View {
    NavigationView {
      CMScreenWithAction {
        CMScreenHeader(
          eyebrow: "Just so you know",
          title: "This car has another plan",
          subtitle: "These trips share dates with the one you’re saving. That may be exactly what you meant."
        )

        ForEach(warning.conflicts) { trip in
          TripCard(trip: trip)
        }
      } action: {
        VStack(spacing: Theme.Spacing.small) {
          CMButton(title: "Keep both plans", icon: "checkmark") {
            onKeepBoth(warning.candidate)
          }
          CMButton(title: "Back to the editor", prominence: .tertiary, action: onReturn)
        }
      }
      .navigationTitle("Check your dates")
      .navigationBarTitleDisplayMode(.inline)
    }
    .navigationViewStyle(.stack)
  }
}
