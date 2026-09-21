import SwiftUI

/// Planning a trip from nothing.
///
/// A trip needs a vehicle, so a traveller with an empty garage is taken through
/// adding one first and then returned to the trip they were making — rather than
/// being shown a picker with nothing in it.
struct NewTripFlow: View {
  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @State private var createdVehicleID: UUID?
  @State private var savedTrip: Trip?

  private var hasVehicle: Bool {
    !environment.journal.availableVehicles.isEmpty
  }

  var body: some View {
    if let savedTrip {
      NavigationView {
        TripPlanView(tripID: savedTrip.id)
          .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
              Button("Done") { dismiss() }
            }
          }
      }
      .navigationViewStyle(.stack)
    } else if hasVehicle {
      TripEditorSheet(
        trip: Trip(vehicleID: preferredVehicleID),
        now: environment.dates.now,
        onSaved: { savedTrip = $0 },
        dismissesOnSave: false
      )
    } else {
      VehicleEditorSheet(
        vehicle: Vehicle(),
        onSaved: { createdVehicleID = $0.id },
        dismissesOnSave: false
      )
    }
  }

  /// The vehicle just added, or the first one in the garage.
  private var preferredVehicleID: UUID? {
    createdVehicleID ?? environment.journal.availableVehicles.first?.id
  }
}
