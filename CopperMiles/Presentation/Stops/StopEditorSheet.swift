import SwiftUI

/// Holds a stop while it is being written.
///
/// Coordinates and the planned stay arrive as text and leave as values, so the
/// parsing and its error messages live in one place rather than inside a save button.
@MainActor
final class StopEditorModel: ObservableObject {
  @Published var stop: Stop
  @Published var latitude: String
  @Published var longitude: String
  @Published var stayMinutes: String
  @Published var hasPlannedArrival: Bool
  @Published var plannedArrival: Date
  @Published var isLocating = false
  @Published var locationMessage: String?

  init(stop: Stop, defaultArrival: Date) {
    self.stop = stop
    self.latitude = stop.coordinate.map { String($0.latitude) } ?? ""
    self.longitude = stop.coordinate.map { String($0.longitude) } ?? ""
    self.stayMinutes = stop.plannedStayMinutes.map(String.init) ?? ""
    self.hasPlannedArrival = stop.plannedArrival != nil
    self.plannedArrival = stop.plannedArrival ?? defaultArrival
  }

  var hasCoordinate: Bool {
    !latitude.isBlank || !longitude.isBlank
  }

  /// The stop as the form currently describes it, or the reason it cannot be.
  func candidate() throws -> Stop {
    var candidate = stop
    candidate.coordinate = try StopValidator.coordinate(latitude: latitude, longitude: longitude)
    candidate.plannedStayMinutes = try StopValidator.stayMinutes(stayMinutes)
    candidate.plannedArrival = hasPlannedArrival ? plannedArrival : nil
    return candidate
  }

  func clearCoordinate() {
    latitude = ""
    longitude = ""
    locationMessage = nil
  }

  func useCurrentLocation(from provider: LocationProviding) async {
    isLocating = true
    locationMessage = nil
    defer { isLocating = false }

    do {
      let coordinate = try await provider.currentCoordinate()
      latitude = String(coordinate.latitude)
      longitude = String(coordinate.longitude)
      locationMessage = "Captured where you are now. Nothing keeps watching after this."
    } catch {
      locationMessage = (error as? DomainError)?.message ?? error.localizedDescription
    }
  }
}

/// The form for a place along the way.
struct StopEditorSheet: View {
  let tripID: UUID

  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @StateObject private var model: StopEditorModel
  @State private var isConfirmingCancel = false

  init(tripID: UUID, stop: Stop, defaultArrival: Date = Date()) {
    self.tripID = tripID
    _model = StateObject(
      wrappedValue: StopEditorModel(stop: stop, defaultArrival: defaultArrival)
    )
  }

  /// The destination's role cannot be changed from here — a plan always has exactly
  /// one, and swapping it is done by promoting another stop.
  private var isDestination: Bool {
    environment.trip(tripID)?.stop(model.stop.id)?.kind == .destination
  }

  private var isNew: Bool {
    environment.trip(tripID)?.stop(model.stop.id) == nil
  }

  var body: some View {
    CMEditorSheet(
      title: isNew ? "Add a stop" : "Edit stop",
      saveTitle: "Save stop",
      onSave: save,
      onCancel: { isConfirmingCancel = true }
    ) {
      intro
      basics
      coordinates
      timing
      notes
    }
    .confirmationDialog(
      "Keep this stop?",
      isPresented: $isConfirmingCancel,
      titleVisibility: .visible
    ) {
      Button("Save stop") { save() }
      Button("Discard changes", role: .destructive) { dismiss() }
      Button("Keep editing", role: .cancel) {}
    }
  }

  // MARK: - Sections

  private var intro: some View {
    HStack(spacing: Theme.Spacing.large) {
      CMAsset(.stopMarker, width: 64, height: 78)

      VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
        Text("Somewhere good.")
          .font(Font.CM.cardTitle)
          .foregroundColor(Theme.Colour.primaryText)
        Text("A name is enough. The rest helps you find it again.")
          .font(Font.CM.footnote)
          .foregroundColor(Theme.Colour.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var basics: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.large) {
      CMTextField(
        title: "Stop name",
        text: $model.stop.name,
        placeholder: "e.g. The little seaside café",
        isRequired: true
      )

      if isDestination {
        CMCard(padding: 0) {
          CMInfoRow(icon: "flag.fill", title: "Type", value: "Destination")
        }
        CMHint(
          text: "This is where the trip is heading, so it stays last in the plan.",
          icon: "info.circle"
        )
      } else {
        CMMenuPicker(
          title: "Type",
          options: StopKind.selectableKinds,
          optionTitle: \.displayName,
          selection: $model.stop.kind
        )
      }

      CMTextField(
        title: "Address",
        text: $model.stop.address,
        placeholder: "Optional · used to search in Maps"
      )
    }
  }

  private var coordinates: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSectionHeader(title: "Exact spot", detail: "Optional")

      HStack(alignment: .top, spacing: Theme.Spacing.medium) {
        CMTextField(
          title: "Latitude",
          text: $model.latitude,
          placeholder: "−90 to 90",
          keyboard: .numbersAndPunctuation,
          capitalisation: .never
        )
        CMTextField(
          title: "Longitude",
          text: $model.longitude,
          placeholder: "−180 to 180",
          keyboard: .numbersAndPunctuation,
          capitalisation: .never
        )
      }

      HStack(spacing: Theme.Spacing.medium) {
        CMButton(
          title: model.isLocating ? "Finding you…" : "Use my location",
          icon: "location",
          prominence: .secondary,
          isLoading: model.isLocating,
          fillsWidth: false
        ) {
          Task { await model.useCurrentLocation(from: environment.location) }
        }

        if model.hasCoordinate {
          CMButton(title: "Clear", prominence: .tertiary, fillsWidth: false) {
            model.clearCoordinate()
          }
        }

        Spacer()
      }

      if let message = model.locationMessage {
        CMHint(text: message, icon: "location.circle")
      }

      CMHint(
        text: "With a coordinate, Maps opens the exact point. With only an address, Maps searches for it and you confirm the place there."
      )
    }
  }

  private var timing: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.large) {
      CMCard(padding: 0) {
        CMToggleRow(
          title: "Add a planned arrival",
          hint: "Your own intention for when to be there.",
          isOn: $model.hasPlannedArrival
        )
      }

      if model.hasPlannedArrival {
        CMDateField(
          title: "Planned arrival",
          date: $model.plannedArrival,
          hint: "This is your plan, not an estimated arrival time. Copper Miles does not calculate routes or traffic."
        )
      }

      CMTextField(
        title: "Planned stay in minutes",
        text: $model.stayMinutes,
        placeholder: "Optional · 1 to 2,880",
        keyboard: .numberPad
      )
    }
  }

  private var notes: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.large) {
      CMTextEditor(
        title: "Parking note",
        text: $model.stop.parkingNote,
        minimumHeight: 80,
        hint: "Where to leave the car, what it cost, anything that helps next time."
      )

      CMTextEditor(
        title: "Personal note",
        text: $model.stop.personalNote,
        minimumHeight: 80
      )
    }
  }

  private func save() {
    let didSave = environment.perform {
      let candidate = try model.candidate()
      try environment.useCases.saveStop.execute(tripID: tripID, stop: candidate)
    }
    if didSave { dismiss() }
  }
}
