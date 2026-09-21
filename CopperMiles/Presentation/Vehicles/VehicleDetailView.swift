import SwiftUI

/// One vehicle, its history and the checks the traveller likes to make with it.
struct VehicleDetailView: View {
  let vehicleID: UUID

  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @State private var isEditing = false
  @State private var isConverting = false
  @State private var isConfirmingDelete = false

  private var vehicle: Vehicle? { environment.vehicle(vehicleID) }

  var body: some View {
    Group {
      if let vehicle {
        content(vehicle)
      } else {
        CMScreen {
          CMEmptyState(
            illustration: .compactCar,
            title: "This vehicle is gone",
            message: "It is no longer in your garage."
          )
        }
      }
    }
    .navigationTitle("Vehicle")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func content(_ vehicle: Vehicle) -> some View {
    CMScreen {
      header(vehicle)
      facts(vehicle)
      template(vehicle)
      tripsLink(vehicle)
      actions(vehicle)
    }
    .sheet(isPresented: $isEditing) { VehicleEditorSheet(vehicle: vehicle) }
    .sheet(isPresented: $isConverting) { UnitConversionSheet(vehicle: vehicle) }
    .alert("Delete \(vehicle.name)?", isPresented: $isConfirmingDelete) {
      Button("Delete", role: .destructive) {
        if environment.perform({ try environment.useCases.deleteVehicle.execute(vehicleID) }) {
          dismiss()
        }
      }
      Button("Keep vehicle", role: .cancel) {}
    } message: {
      Text("No trips refer to this vehicle. Its photo and preparation template go with it.")
    }
  }

  // MARK: - Sections

  private func header(_ vehicle: Vehicle) -> some View {
    HStack(alignment: .top, spacing: Theme.Spacing.large) {
      VehiclePortrait(vehicle: vehicle, size: CGSize(width: 88, height: 78))

      VStack(alignment: .leading, spacing: Theme.Spacing.small) {
        CMEyebrow(text: vehicle.isArchived ? "Archived vehicle" : "Ready for the road")
        Text(vehicle.name)
          .font(Font.CM.screenTitle)
          .foregroundColor(Theme.Colour.primaryText)
          .fixedSize(horizontal: false, vertical: true)
        if !vehicle.descriptor.isEmpty {
          Text(vehicle.descriptor)
            .font(Font.CM.callout)
            .foregroundColor(Theme.Colour.secondaryText)
        }
      }
    }
  }

  private func facts(_ vehicle: Vehicle) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
      CMCard(padding: 0) {
        VStack(spacing: 0) {
          CMInfoRow(
            icon: "paintpalette",
            title: "Colour",
            value: vehicle.colourNote.isEmpty ? "Not noted" : vehicle.colourNote
          )
          CMDivider()
          CMInfoRow(icon: "speedometer", title: "Distance unit", value: vehicle.unit.longName)
          CMDivider()
          CMInfoRow(
            icon: "gauge",
            title: "Last odometer",
            value: lastReadingValue(vehicle)
          )
          CMDivider()
          CMInfoRow(icon: "map", title: "Trips", value: "\(tripCount(vehicle))")
        }
      }

      if let reading = environment.journal.latestOdometerReading(forVehicle: vehicle.id) {
        CMHint(text: "Recorded \(environment.formatters.fullDateAndTime(reading.recordedAt)).")
      }
    }
  }

  private func template(_ vehicle: Vehicle) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSectionHeader(
        title: "Preparation template",
        detail: vehicle.preparationTemplate.isEmpty
          ? nil
          : "\(vehicle.preparationTemplate.count) items"
      )

      if vehicle.preparationTemplate.isEmpty {
        CMCard {
          Text(
            "Your own checks, your own routine. Add them when you edit this vehicle, and every new trip starts with a copy."
          )
          .font(Font.CM.callout)
          .foregroundColor(Theme.Colour.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
        }
      } else {
        CMRowList(elements: vehicle.preparationTemplate) { item in
          HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: item.group.icon)
              .font(.system(.footnote))
              .foregroundColor(Theme.Colour.secondaryText)
              .frame(width: 24)

            VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
              Text(item.name)
                .font(Font.CM.label)
                .foregroundColor(Theme.Colour.primaryText)
              Text(item.group.displayName)
                .font(Font.CM.footnote)
                .foregroundColor(Theme.Colour.secondaryText)
            }

            Spacer(minLength: Theme.Spacing.small)

            if item.isImportant {
              CMTag(text: "Important", colour: Theme.Colour.accent)
            }
          }
          .padding(.horizontal, Theme.Spacing.cardPadding)
          .padding(.vertical, Theme.Spacing.medium)
        }
      }
    }
  }

  private func tripsLink(_ vehicle: Vehicle) -> some View {
    CMCard(padding: 0) {
      CMNavigationRow(
        icon: "map",
        title: "This vehicle’s trips",
        detail: tripCount(vehicle) == 0 ? "None yet" : "\(tripCount(vehicle)) in your journal"
      ) {
        TripsListView(initialVehicleID: vehicle.id)
      }
    }
  }

  private func actions(_ vehicle: Vehicle) -> some View {
    VStack(spacing: Theme.Spacing.medium) {
      CMButton(title: "Edit vehicle", icon: "pencil") { isEditing = true }

      CMCard(padding: 0) {
        VStack(spacing: 0) {
          CMActionRow(
            icon: "arrow.left.arrow.right",
            title: "Convert distance unit",
            detail: conversionDetail(vehicle)
          ) {
            isConverting = true
          }
          .disabled(isOnActiveTrip(vehicle))

          CMDivider()

          CMActionRow(
            icon: vehicle.isArchived ? "arrow.uturn.backward" : "archivebox",
            title: vehicle.isArchived ? "Restore vehicle" : "Archive vehicle",
            detail: vehicle.isArchived
              ? "Bring it back to the garage"
              : "Keep its trips, hide it from the list"
          ) {
            environment.perform {
              try environment.useCases.setVehicleArchived.execute(
                vehicle.id,
                isArchived: !vehicle.isArchived
              )
            }
          }
          .disabled(isOnActiveTrip(vehicle))

          if tripCount(vehicle) == 0 {
            CMDivider()
            CMActionRow(
              icon: "trash",
              title: "Delete vehicle",
              isDestructive: true
            ) {
              isConfirmingDelete = true
            }
          }
        }
      }

      if isOnActiveTrip(vehicle) {
        CMHint(
          text: "This vehicle is on a trip right now. Finish it to convert units or archive.",
          icon: "info.circle"
        )
      } else if tripCount(vehicle) > 0 {
        CMHint(
          text: "A vehicle with trips is archived rather than deleted, so your journal keeps every journey it carried.",
          icon: "info.circle"
        )
      }
    }
  }

  // MARK: - Helpers

  private func tripCount(_ vehicle: Vehicle) -> Int {
    environment.journal.trips(forVehicle: vehicle.id).count
  }

  private func isOnActiveTrip(_ vehicle: Vehicle) -> Bool {
    environment.activeTrip?.vehicleID == vehicle.id
  }

  private func lastReadingValue(_ vehicle: Vehicle) -> String {
    let reading = environment.journal.latestOdometerReading(forVehicle: vehicle.id)
    return environment.formatters.odometer(reading?.value, unit: vehicle.unit)
  }

  private func conversionDetail(_ vehicle: Vehicle) -> String {
    let target: DistanceUnit = vehicle.unit == .kilometres ? .miles : .kilometres
    return "\(vehicle.unit.shortName) → \(target.shortName)"
  }
}

/// Previews a unit conversion against the readings it would change.
///
/// The traveller confirms against real numbers rather than a promise, because this
/// rewrites every odometer value the vehicle has ever recorded.
struct UnitConversionSheet: View {
  let vehicle: Vehicle

  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  private var target: DistanceUnit {
    vehicle.unit == .kilometres ? .miles : .kilometres
  }

  private var previews: [ConvertVehicleUnit.Preview] {
    environment.useCases.convertVehicleUnit.preview(vehicleID: vehicle.id, to: target)
  }

  var body: some View {
    CMEditorSheet(
      title: "Convert readings",
      saveTitle: "Convert every reading",
      onSave: convert,
      onCancel: { dismiss() }
    ) {
      CMScreenHeader(
        eyebrow: vehicle.name,
        title: "\(vehicle.unit.longName) → \(target.longName)",
        subtitle: "Every odometer reading recorded for this vehicle changes together."
      )

      if previews.isEmpty {
        CMCard {
          Text("No readings have been recorded for this vehicle yet, so only the unit changes.")
            .font(Font.CM.callout)
            .foregroundColor(Theme.Colour.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
      } else {
        CMSectionHeader(title: "What changes", detail: "\(previews.count) trips")

        ForEach(previews) { preview in
          CMCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
              Text(preview.tripName)
                .font(Font.CM.labelEmphasis)
                .foregroundColor(Theme.Colour.primaryText)

              if let start = preview.start {
                conversionLine(label: "Start", from: start.current, to: start.converted)
              }
              if let end = preview.end {
                conversionLine(label: "End", from: end.current, to: end.converted)
              }
            }
          }
        }
      }

      CMHint(
        text: "The report unit in Settings is a separate choice and does not change what is stored.",
        icon: "info.circle"
      )
    }
  }

  private func conversionLine(label: String, from: Double, to: Double) -> some View {
    HStack(spacing: Theme.Spacing.small) {
      Text(label)
        .font(Font.CM.footnote)
        .foregroundColor(Theme.Colour.secondaryText)
        .frame(width: 44, alignment: .leading)

      Text(environment.formatters.odometer(from, unit: vehicle.unit))
        .font(Font.CM.footnote)
        .foregroundColor(Theme.Colour.secondaryText)

      Image(systemName: "arrow.right")
        .font(.system(.caption2))
        .foregroundColor(Theme.Colour.secondaryText)

      Text(environment.formatters.odometer(to, unit: target))
        .font(Font.CM.labelEmphasis)
        .foregroundColor(Theme.Colour.primaryText)
    }
    .accessibilityElement(children: .combine)
  }

  private func convert() {
    let didConvert = environment.perform {
      try environment.useCases.convertVehicleUnit.execute(vehicleID: vehicle.id, to: target)
    }
    if didConvert { dismiss() }
  }
}
