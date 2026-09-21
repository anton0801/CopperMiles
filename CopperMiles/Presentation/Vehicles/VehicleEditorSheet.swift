import SwiftUI
import UIKit

/// Holds a vehicle while it is being edited.
///
/// The draft lives here rather than in the view so that the rules about what may
/// still be changed — chiefly the unit, which locks once a trip has been recorded —
/// are answered in one place instead of being scattered through the form.
@MainActor
final class VehicleEditorModel: ObservableObject {
  @Published var vehicle: Vehicle
  @Published var photoChange: PhotoChange = .unchanged
  @Published var editingItem: PreparationItem?

  init(vehicle: Vehicle) {
    self.vehicle = vehicle
  }

  /// The image to show right now: a freshly chosen one, or the stored one.
  var previewPhoto: PreviewPhoto {
    switch photoChange {
    case .replaced(let data):
      return UIImage(data: data).map(PreviewPhoto.picked) ?? .none
    case .removed:
      return .none
    case .unchanged:
      return vehicle.photoID.map(PreviewPhoto.stored) ?? .none
    }
  }

  enum PreviewPhoto {
    case none
    case stored(AttachmentID)
    case picked(UIImage)

    var isPresent: Bool {
      if case .none = self { return false }
      return true
    }
  }

  func addExampleChecklist() {
    vehicle.preparationTemplate = Vehicle.exampleTemplate
  }

  func apply(_ item: PreparationItem) {
    if let index = vehicle.preparationTemplate.firstIndex(where: { $0.id == item.id }) {
      vehicle.preparationTemplate[index] = item
    } else {
      vehicle.preparationTemplate.append(item)
    }
  }

  func removeItem(_ id: UUID) {
    vehicle.preparationTemplate.removeAll { $0.id == id }
  }
}

/// The form for adding or editing a vehicle.
struct VehicleEditorSheet: View {
  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @StateObject private var model: VehicleEditorModel

  /// Called with the saved vehicle, for flows that continue afterwards.
  var onSaved: ((Vehicle) -> Void)?
  var dismissesOnSave = true

  @State private var isChoosingPhoto = false
  @State private var isConfirmingCancel = false

  init(
    vehicle: Vehicle,
    onSaved: ((Vehicle) -> Void)? = nil,
    dismissesOnSave: Bool = true
  ) {
    _model = StateObject(wrappedValue: VehicleEditorModel(vehicle: vehicle))
    self.onSaved = onSaved
    self.dismissesOnSave = dismissesOnSave
  }

  /// Whether this vehicle is being added rather than edited.
  private var isNew: Bool {
    environment.vehicle(model.vehicle.id) == nil
  }

  /// Changing the unit would silently reinterpret every reading already recorded, so
  /// after the first trip it becomes a conversion rather than an edit.
  private var isUnitLocked: Bool {
    !environment.journal.trips(forVehicle: model.vehicle.id).isEmpty
  }

  var body: some View {
    CMEditorSheet(
      title: isNew ? "Add a vehicle" : "Edit vehicle",
      saveTitle: "Save vehicle",
      onSave: save,
      onCancel: { isConfirmingCancel = true }
    ) {
      intro
      details
      photo
      preparation
    }
    .sheet(isPresented: $isChoosingPhoto) {
      PhotoLibraryPicker(
        onPicked: { model.photoChange = .replaced($0) },
        onFailed: { environment.show(.error($0)) }
      )
    }
    .sheet(item: $model.editingItem) { item in
      PreparationItemSheet(item: item) { model.apply($0) }
    }
    .confirmationDialog(
      "Keep your changes?",
      isPresented: $isConfirmingCancel,
      titleVisibility: .visible
    ) {
      Button("Save vehicle") { save() }
      Button("Discard changes", role: .destructive) { dismiss() }
      Button("Keep editing", role: .cancel) {}
    }
  }

  // MARK: - Sections

  private var intro: some View {
    HStack(spacing: Theme.Spacing.large) {
      CMAsset(.compactCar, width: 64, height: 50)

      VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
        Text("Your partner in little adventures")
          .font(Font.CM.cardTitle)
          .foregroundColor(Theme.Colour.primaryText)
          .fixedSize(horizontal: false, vertical: true)
        Text("A name is all you need to get started.")
          .font(Font.CM.footnote)
          .foregroundColor(Theme.Colour.secondaryText)
      }
    }
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.large) {
      CMTextField(
        title: "Vehicle name",
        text: $model.vehicle.name,
        placeholder: "e.g. Our little orange car",
        isRequired: true
      )

      HStack(alignment: .top, spacing: Theme.Spacing.medium) {
        CMTextField(title: "Make", text: $model.vehicle.make, placeholder: "Optional")
        CMTextField(title: "Model", text: $model.vehicle.model, placeholder: "Optional")
      }

      CMTextField(
        title: "Colour note",
        text: $model.vehicle.colourNote,
        placeholder: "Optional · how you’d describe it"
      )

      VStack(alignment: .leading, spacing: Theme.Spacing.small) {
        CMFieldLabel(title: "Distance unit", isRequired: true)
        CMSegmentedPicker(
          options: DistanceUnit.allCases,
          title: \.longName,
          selection: $model.vehicle.unit
        )
        .disabled(isUnitLocked)
        .opacity(isUnitLocked ? 0.5 : 1)

        if isUnitLocked {
          CMHint(
            text: "The unit is fixed once a trip has been recorded. Use Convert distance unit in the vehicle’s details to change every reading together.",
            icon: "lock"
          )
        }
      }
    }
  }

  private var photo: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMFieldLabel(title: "Photo")

      switch model.previewPhoto {
      case .none:
        CMButton(title: "Choose a photo", icon: "photo", prominence: .secondary) {
          isChoosingPhoto = true
        }
      case .stored(let id):
        photoPreview { CMPhoto(id: id) }
      case .picked(let image):
        photoPreview { Image(uiImage: image).resizable().aspectRatio(contentMode: .fill) }
      }
    }
  }

  private func photoPreview<Preview: View>(@ViewBuilder _ preview: () -> Preview) -> some View {
    VStack(spacing: Theme.Spacing.medium) {
      preview()
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))

      HStack(spacing: Theme.Spacing.medium) {
        CMButton(title: "Replace", icon: "photo", prominence: .secondary, fillsWidth: false) {
          isChoosingPhoto = true
        }
        CMButton(title: "Remove", icon: "trash", prominence: .destructive, fillsWidth: false) {
          model.photoChange = .removed
        }
        Spacer()
      }
    }
  }

  private var preparation: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSectionHeader(
        title: "Preparation template",
        detail: model.vehicle.preparationTemplate.isEmpty
          ? nil
          : "\(model.vehicle.preparationTemplate.count) items"
      )

      CMHint(text: "Every new trip with this vehicle starts with a copy of these checks.")

      if !model.vehicle.preparationTemplate.isEmpty {
        CMRowList(elements: model.vehicle.preparationTemplate) { item in
          HStack(spacing: Theme.Spacing.small) {
            Button {
              model.editingItem = item
            } label: {
              HStack(spacing: Theme.Spacing.medium) {
                Image(systemName: item.group.icon)
                  .font(.system(.footnote))
                  .foregroundColor(Theme.Colour.secondaryText)
                  .frame(width: 24)

                VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
                  Text(item.name)
                    .font(Font.CM.label)
                    .foregroundColor(Theme.Colour.primaryText)
                    .multilineTextAlignment(.leading)
                  Text(item.isImportant ? "\(item.group.displayName) · Important" : item.group.displayName)
                    .font(Font.CM.footnote)
                    .foregroundColor(Theme.Colour.secondaryText)
                }

                Spacer(minLength: Theme.Spacing.small)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(CMPressStyle())

            Button {
              model.removeItem(item.id)
            } label: {
              Image(systemName: "minus.circle")
                .font(.system(.body))
                .foregroundColor(Theme.Colour.danger)
                .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
            }
            .accessibilityLabel("Remove \(item.name)")
          }
          .padding(.leading, Theme.Spacing.cardPadding)
          .padding(.trailing, Theme.Spacing.small)
          .padding(.vertical, Theme.Spacing.small)
        }
      }

      CMButton(title: "Add a check", icon: "plus", prominence: .secondary) {
        model.editingItem = PreparationItem()
      }

      if model.vehicle.preparationTemplate.isEmpty {
        CMButton(title: "Use example checklist", icon: "sparkles", prominence: .tertiary) {
          model.addExampleChecklist()
        }
        CMHint(text: "Examples are a starting point. Keep the checks that matter to you and change the rest.")
      }
    }
  }

  private func save() {
    let saved = environment.performReturning {
      try environment.useCases.saveVehicle.execute(model.vehicle, photo: model.photoChange)
    }
    guard let saved else { return }

    onSaved?(saved)
    if dismissesOnSave { dismiss() }
  }
}

/// The form for one preparation item.
struct PreparationItemSheet: View {
  @Environment(\.dismiss) private var dismiss

  @State private var item: PreparationItem
  @State private var errorMessage: String?

  private let onSave: (PreparationItem) -> Void

  init(item: PreparationItem, onSave: @escaping (PreparationItem) -> Void) {
    _item = State(initialValue: item)
    self.onSave = onSave
  }

  var body: some View {
    CMEditorSheet(
      title: "Preparation item",
      saveTitle: "Save item",
      onSave: save,
      onCancel: { dismiss() }
    ) {
      CMTextField(
        title: "What to check",
        text: $item.name,
        placeholder: "e.g. Check tyre pressure",
        isRequired: true,
        errorMessage: errorMessage
      )

      CMMenuPicker(
        title: "Group",
        options: PreparationGroup.allCases,
        optionTitle: \.displayName,
        selection: $item.group
      )

      CMCard(padding: 0) {
        CMToggleRow(
          title: "Important before departure",
          hint: "An important check that is still open asks for a confirmation before you set off.",
          isOn: $item.isImportant
        )
      }

      CMTextEditor(
        title: "Note",
        text: $item.note,
        minimumHeight: 80,
        hint: "Anything worth remembering about this check."
      )
    }
  }

  private func save() {
    guard !item.name.isBlank else {
      errorMessage = "Give this check a name."
      return
    }
    onSave(item)
    dismiss()
  }
}
