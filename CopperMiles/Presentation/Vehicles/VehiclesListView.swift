import SwiftUI

/// The traveller's garage.
struct VehiclesListView: View {
  @EnvironmentObject private var environment: AppEnvironment

  @State private var isAdding = false
  @State private var includesArchived = false

  private var vehicles: [Vehicle] {
    environment.journal.vehicles.filter { includesArchived || !$0.isArchived }
  }

  private var archivedCount: Int {
    environment.journal.vehicles.filter(\.isArchived).count
  }

  var body: some View {
    CMScreen {
      CMScreenHeader(
        eyebrow: "Every journey has a companion",
        title: "Your little garage",
        subtitle: "Keep your car, and the checks you like to make, ready for what’s ahead."
      )

      if vehicles.isEmpty {
        CMEmptyState(
          illustration: .compactCar,
          title: "Meet your getaway car",
          message: "Add your vehicle and build a preparation list that suits the way you travel."
        ) {
          CMButton(title: "Add a vehicle", icon: "plus") { isAdding = true }
        }
      } else {
        ForEach(vehicles) { vehicle in
          NavigationLink {
            VehicleDetailView(vehicleID: vehicle.id)
          } label: {
            VehicleCard(vehicle: vehicle)
          }
          .buttonStyle(.plain)
        }

        CMButton(title: "Add a vehicle", icon: "plus") { isAdding = true }
      }

      if archivedCount > 0 {
        CMCard(padding: 0) {
          CMToggleRow(
            title: "Include archived vehicles",
            hint: "\(archivedCount) tidied away",
            isOn: $includesArchived
          )
        }
      }
    }
    .navigationTitle("Vehicles")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isAdding) { VehicleEditorSheet(vehicle: Vehicle()) }
  }
}

/// One vehicle in the list.
struct VehicleCard: View {
  let vehicle: Vehicle

  var body: some View {
    CMCard {
      HStack(spacing: Theme.Spacing.large) {
        VehiclePortrait(vehicle: vehicle, size: CGSize(width: 72, height: 64))

        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
          Text(vehicle.name)
            .font(Font.CM.cardTitle)
            .foregroundColor(Theme.Colour.primaryText)
            .multilineTextAlignment(.leading)

          if !vehicle.descriptor.isEmpty {
            Text(vehicle.descriptor)
              .font(Font.CM.footnote)
              .foregroundColor(Theme.Colour.secondaryText)
          }

          CMTag(
            text: vehicle.isArchived
              ? "Archived"
              : checklistLabel,
            colour: vehicle.isArchived ? Theme.Colour.secondaryText : Theme.Colour.success
          )
        }

        Spacer(minLength: Theme.Spacing.small)

        Image(systemName: "chevron.right")
          .font(.system(.caption).weight(.semibold))
          .foregroundColor(Theme.Colour.secondaryText.opacity(0.6))
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var checklistLabel: String {
    let count = vehicle.preparationTemplate.count
    if count == 0 { return "No checks yet" }
    return count == 1 ? "1 check" : "\(count) checks"
  }
}

/// A vehicle's photo, or a drawn stand-in when there is none.
struct VehiclePortrait: View {
  let vehicle: Vehicle
  var size: CGSize

  var body: some View {
    Group {
      if let photoID = vehicle.photoID {
        CMPhoto(id: photoID)
          .frame(width: size.width, height: size.height)
          .clipped()
      } else {
        CMAsset(.compactCar, width: size.width * 0.86, height: size.height * 0.72)
          .frame(width: size.width, height: size.height)
          .background(Theme.Colour.accentSoft.opacity(0.18))
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
  }
}
