import SwiftUI

/// The traveller's own checks before setting off.
///
/// Nothing here inspects the car. A tick records that the person looked, which is
/// what makes the list worth keeping.
struct ChecklistView: View {
  let tripID: UUID

  @EnvironmentObject private var environment: AppEnvironment

  @State private var editingItem: PreparationItem?
  @State private var isStarting = false
  @State private var isSavingTemplate = false
  @State private var isLoadingTemplate = false

  private var trip: Trip? { environment.trip(tripID) }

  var body: some View {
    Group {
      if let trip {
        content(trip)
      } else {
        CMScreen {
          CMEmptyState(
            illustration: .preparationBoard,
            title: "This trip is gone",
            message: "It is no longer in your journal."
          )
        }
      }
    }
    .navigationTitle("Departure checklist")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func content(_ trip: Trip) -> some View {
    CMScreenWithAction {
      header
      progress(trip)
      groups(trip)
      additions(trip)
    } action: {
      startAction(trip)
    }
    .sheet(item: $editingItem) { item in
      PreparationItemSheet(item: item) { updated in
        environment.perform {
          try environment.useCases.saveChecklistItem.execute(tripID: tripID, item: updated)
        }
      }
    }
    .sheet(isPresented: $isStarting) {
      StartTripSheet(tripID: tripID)
    }
    .alert("Replace the vehicle template?", isPresented: $isSavingTemplate) {
      Button("Replace template") {
        environment.perform {
          guard let vehicleID = trip.vehicleID else {
            throw DomainError("Choose a vehicle for this trip first.")
          }
          try environment.useCases.replaceVehicleTemplate.execute(
            vehicleID: vehicleID,
            with: trip.checklist
          )
        }
      }
      Button("Keep current template", role: .cancel) {}
    } message: {
      Text(
        "\(environment.vehicleName(trip.vehicleID)) will start future trips with these \(trip.checklist.count) checks. Trips you have already planned keep their own copies."
      )
    }
    .confirmationDialog(
      "Load \(environment.vehicleName(trip.vehicleID))’s template?",
      isPresented: $isLoadingTemplate,
      titleVisibility: .visible
    ) {
      Button("Replace this list") { loadTemplate(.replace) }
      Button("Add to this list") { loadTemplate(.append) }
      Button("Keep what I have", role: .cancel) {}
    }
  }

  // MARK: - Sections

  private var header: some View {
    CMScreenHeader(
      eyebrow: "A little peace of mind",
      title: "Ready, set,\nalmost go.",
      subtitle: "Your own checks for a more settled start."
    ) {
      CMAsset(.preparationBoard, width: 80, height: 88)
    }
  }

  private func progress(_ trip: Trip) -> some View {
    let progress = trip.checklistProgress

    return CMCard {
      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        HStack(alignment: .firstTextBaseline) {
          Text(progressTitle(progress))
            .font(Font.CM.cardTitle)
            .foregroundColor(Theme.Colour.primaryText)

          Spacer()

          if !progress.isEmpty {
            Text("\(progress.checked) / \(progress.total)")
              .font(Font.CM.labelEmphasis)
              .foregroundColor(Theme.Colour.success)
          }
        }

        if !progress.isEmpty {
          CMProgressBar(progress: progress)
        }

        if !trip.openImportantItems.isEmpty {
          CMHint(
            text: importantSummary(trip),
            icon: "exclamationmark.circle",
            tone: .warning
          )
        }
      }
    }
  }

  private func progressTitle(_ progress: ChecklistProgress) -> String {
    if progress.isEmpty { return "No checklist yet" }
    if progress.checked == progress.total { return "Everything is ready" }
    return "\(progress.checked) of \(progress.total) ready"
  }

  private func importantSummary(_ trip: Trip) -> String {
    let count = trip.openImportantItems.count
    return count == 1
      ? "One important check is still open."
      : "\(count) important checks are still open."
  }

  @ViewBuilder
  private func groups(_ trip: Trip) -> some View {
    if trip.checklist.isEmpty {
      CMCard {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
          Text("Nothing to check yet")
            .font(Font.CM.labelEmphasis)
            .foregroundColor(Theme.Colour.primaryText)
          Text(
            "An empty list is not the same as a finished one, so it is never shown as ready. Add the checks that matter to you."
          )
          .font(Font.CM.footnote)
          .foregroundColor(Theme.Colour.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
    } else {
      ForEach(PreparationGroup.allCases, id: \.self) { group in
        let items = trip.checklist.filter { $0.group == group }
        if !items.isEmpty {
          VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            CMEyebrow(text: group.displayName)
            CMRowList(elements: items) { item in
              checklistRow(item)
            }
          }
        }
      }
    }
  }

  private func checklistRow(_ item: PreparationItem) -> some View {
    HStack(spacing: Theme.Spacing.medium) {
      Button {
        environment.perform {
          try environment.useCases.setChecklistItemChecked.execute(
            tripID: tripID,
            itemID: item.id,
            isChecked: !item.isChecked
          )
        }
      } label: {
        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
          .font(.system(.title3))
          .foregroundColor(
            item.isChecked ? Theme.Colour.success : Theme.Colour.secondaryText.opacity(0.4)
          )
          .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
      }
      .accessibilityLabel(item.name)
      .accessibilityValue(item.isChecked ? "Checked" : "Not checked")
      .accessibilityAddTraits(item.isChecked ? [.isSelected] : [])

      VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
        Text(item.name)
          .font(Font.CM.label)
          .strikethrough(item.isChecked)
          .foregroundColor(item.isChecked ? Theme.Colour.secondaryText : Theme.Colour.primaryText)
          .multilineTextAlignment(.leading)

        if item.isImportant {
          CMTag(text: "Important", colour: Theme.Colour.accent)
        }

        if !item.note.isEmpty {
          Text(item.note)
            .font(Font.CM.footnote)
            .foregroundColor(Theme.Colour.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Spacer(minLength: Theme.Spacing.small)

      Menu {
        Button {
          editingItem = item
        } label: {
          Label("Edit check", systemImage: "pencil")
        }
        Button(role: .destructive) {
          environment.perform {
            try environment.useCases.removeChecklistItem.execute(tripID: tripID, itemID: item.id)
          }
        } label: {
          Label("Remove check", systemImage: "trash")
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(.body))
          .foregroundColor(Theme.Colour.secondaryText)
          .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
      }
      .accessibilityLabel("More for \(item.name)")
    }
    .padding(.trailing, Theme.Spacing.small)
    .padding(.vertical, Theme.Spacing.tiny)
  }

  private func additions(_ trip: Trip) -> some View {
    VStack(spacing: Theme.Spacing.medium) {
      CMButton(title: "Add your own check", icon: "plus", prominence: .secondary) {
        editingItem = PreparationItem()
      }

      CMCard(padding: 0) {
        VStack(spacing: 0) {
          if templateCount > 0 {
            CMActionRow(
              icon: "square.and.arrow.down",
              title: "Load the vehicle’s template",
              detail: "\(templateCount) checks saved on \(environment.vehicleName(trip.vehicleID))"
            ) {
              isLoadingTemplate = true
            }
            CMDivider()
          }

          CMActionRow(
            icon: "square.and.arrow.up",
            title: "Save as the vehicle’s template",
            detail: "Use this list for future trips in this car"
          ) {
            isSavingTemplate = true
          }
          .disabled(trip.checklist.isEmpty || trip.vehicleID == nil)
        }
      }
    }
  }

  @ViewBuilder
  private func startAction(_ trip: Trip) -> some View {
    VStack(spacing: Theme.Spacing.small) {
      CMButton(title: "Review and set off", icon: "arrow.right") {
        isStarting = true
      }
      .disabled(trip.status != .planned)

      if trip.status == .draft {
        CMHint(
          text: "Save this trip as planned in the trip editor before setting off.",
          icon: "info.circle"
        )
      } else if trip.status == .active {
        CMHint(text: "This trip is already under way.", icon: "checkmark.circle", tone: .positive)
      }
    }
  }

  // MARK: - Helpers

  private var templateCount: Int {
    environment.useCases.loadVehicleChecklistTemplate.templateCount(tripID: tripID)
  }

  private func loadTemplate(_ mode: LoadVehicleChecklistTemplate.Mode) {
    environment.perform {
      try environment.useCases.loadVehicleChecklistTemplate.execute(tripID: tripID, mode: mode)
    }
  }
}
