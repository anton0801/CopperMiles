import SwiftUI

/// The traveller's own history, gathered up.
struct TravelSummaryView: View {
  @EnvironmentObject private var environment: AppEnvironment

  @State private var filter = JournalFilter()
  @State private var share: SharePayload?

  private var summary: TravelSummary {
    environment.useCases.buildTravelSummary.execute(filter)
  }

  var body: some View {
    CMScreen {
      header
      filters

      if summary.isEmpty {
        CMEmptyState(
          illustration: .roadSign,
          title: "No finished trips yet",
          message: "Your story grows with every journey you bring home. Nothing is charted until then."
        )
      } else {
        statistics(summary)
        completeness(summary)
        monthlyChart(summary)
        vehicleTable(summary)
        exportButton
      }

      archiveToggle
    }
    .navigationTitle("Travel summary")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $share) { ShareSheet(items: $0.items) }
  }

  // MARK: - Sections

  private var header: some View {
    CMScreenHeader(
      eyebrow: "All those little adventures",
      title: "Your travel story"
    ) {
      CMAsset(.roadSign, width: 56, height: 61)
    }
  }

  private var filters: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSegmentedPicker(
        options: JournalPeriod.allCases,
        title: \.displayName,
        selection: $filter.period
      )

      if environment.journal.vehicles.count > 1 {
        CMMenuPicker(
          title: "Vehicle",
          options: [nil] + environment.journal.vehicles.map { Optional($0.id) },
          optionTitle: { id in
            guard let id else { return "All vehicles" }
            return environment.vehicle(id)?.name ?? "Unknown"
          },
          selection: $filter.vehicleID
        )
      }
    }
  }

  private func statistics(_ summary: TravelSummary) -> some View {
    VStack(spacing: Theme.Spacing.medium) {
      HStack(alignment: .top, spacing: Theme.Spacing.medium) {
        statisticTile(
          value: "\(summary.completedTrips)",
          label: "Completed trips",
          outcome: .completed
        )
        statisticTile(
          value: "\(summary.endedEarlyTrips)",
          label: "Ended early",
          outcome: .endedEarly
        )
      }

      HStack(alignment: .top, spacing: Theme.Spacing.medium) {
        statisticTile(value: "\(summary.visitedStops)", label: "Stops visited")
        statisticTile(
          value: environment.formatters.number(summary.recordedDistance),
          label: "Recorded \(summary.reportUnit.longName.lowercased())"
        )
      }

      statisticTile(
        value: environment.formatters.duration(summary.elapsedTime),
        label: "Elapsed trip time"
      )

      CMHint(text: "Elapsed time covers whole trips, stops included. It is not driving time.")
    }
  }

  /// A figure that leads back to the trips it was counting.
  ///
  /// Every tile carries the period and vehicle currently chosen here, so the journal
  /// opens showing exactly the trips behind the number rather than everything.
  private func statisticTile(
    value: String,
    label: String,
    outcome: TripOutcome? = nil
  ) -> some View {
    NavigationLink {
      JournalListView(
        initialPeriod: filter.period,
        initialVehicleID: filter.vehicleID,
        initialOutcome: outcome,
        includesArchived: filter.includesArchived
      )
    } label: {
      CMCard {
        CMStatistic(value: value, label: label)
      }
    }
    .buttonStyle(.plain)
    .accessibilityHint("Shows the trips behind this figure")
  }

  private func completeness(_ summary: TravelSummary) -> some View {
    CMCard {
      VStack(alignment: .leading, spacing: Theme.Spacing.small) {
        Text("Distance recorded for \(summary.tripsWithDistance) of \(summary.finishedTrips) finished trips")
          .font(Font.CM.label)
          .foregroundColor(Theme.Colour.primaryText)
          .fixedSize(horizontal: false, vertical: true)

        Text(
          "Only trips with two trustworthy odometer readings add to the total. The rest are journeys all the same."
        )
        .font(Font.CM.footnote)
        .foregroundColor(Theme.Colour.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func monthlyChart(_ summary: TravelSummary) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSectionHeader(title: "A year of getting out", detail: "Finished trips")

      CMCard {
        MonthlyTripsChart(
          counts: summary.monthlyCounts,
          monthLabel: environment.formatters.monthInitial
        )
      }
    }
  }

  private func vehicleTable(_ summary: TravelSummary) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSectionHeader(title: "By travel companion")

      CMRowList(elements: summary.vehicleRows) { row in
        NavigationLink {
          JournalListView(
            initialPeriod: filter.period,
            initialVehicleID: row.id,
            includesArchived: filter.includesArchived
          )
        } label: {
          HStack(spacing: Theme.Spacing.medium) {
            Text(row.name)
              .font(Font.CM.label)
              .foregroundColor(Theme.Colour.primaryText)

            Spacer(minLength: Theme.Spacing.small)

            VStack(alignment: .trailing, spacing: Theme.Spacing.hairline) {
              Text(row.tripCount == 1 ? "1 trip" : "\(row.tripCount) trips")
                .font(Font.CM.labelEmphasis)
                .foregroundColor(Theme.Colour.primaryText)
              Text(
                "\(environment.formatters.number(row.distance)) \(summary.reportUnit.shortName)"
              )
              .font(Font.CM.footnote)
              .foregroundColor(Theme.Colour.secondaryText)
            }

            Image(systemName: "chevron.right")
              .font(.system(.caption).weight(.semibold))
              .foregroundColor(Theme.Colour.secondaryText.opacity(0.6))
          }
          .padding(.horizontal, Theme.Spacing.cardPadding)
          .padding(.vertical, Theme.Spacing.medium)
          .frame(minHeight: Theme.minimumTapTarget)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var exportButton: some View {
    CMButton(title: "Export as CSV", icon: "square.and.arrow.up", prominence: .secondary) {
      exportCSV()
    }
  }

  private var archiveToggle: some View {
    CMCard(padding: 0) {
      CMToggleRow(
        title: "Include archived trips",
        hint: "Reports leave archived trips out unless you ask for them.",
        isOn: $filter.includesArchived
      )
    }
  }

  // MARK: - Export

  private func exportCSV() {
    environment.perform {
      let trips = environment.useCases.findJournalEntries.execute(filter)
      let csv = TravelSummaryCSV.make(
        trips: trips,
        journal: environment.journal,
        reportUnit: environment.settings.reportUnit
      )

      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("CopperMiles-summary.csv")
      try Data(csv.utf8).write(to: url, options: .atomic)
      share = SharePayload(items: [url])
    }
  }
}

/// Finished trips per month, drawn from the journal.
///
/// The chart is built by the interface rather than shipped as an image, so it always
/// shows what is actually recorded — including the empty months, which are part of
/// the story too.
struct MonthlyTripsChart: View {
  let counts: [TravelSummary.MonthlyCount]
  let monthLabel: (Date) -> String

  private var peak: Int {
    max(counts.map(\.count).max() ?? 1, 1)
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: Theme.Spacing.small) {
      ForEach(counts) { entry in
        VStack(spacing: Theme.Spacing.small) {
          Text("\(entry.count)")
            .font(Font.CM.caption)
            .foregroundColor(Theme.Colour.secondaryText)

          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(entry.count == 0 ? Theme.Colour.primaryText.opacity(0.06) : Theme.Colour.accent)
            .frame(height: max(4, CGFloat(entry.count) / CGFloat(peak) * 110))

          Text(monthLabel(entry.month))
            .font(Font.CM.caption)
            .foregroundColor(Theme.Colour.secondaryText)
        }
        .frame(maxWidth: .infinity)
      }
    }
    .frame(height: 160, alignment: .bottom)
    .accessibilityElement()
    .accessibilityLabel("Finished trips over the last twelve months")
    .accessibilityValue(
      counts.map { "\(monthLabel($0.month)): \($0.count)" }.joined(separator: ", ")
    )
  }
}

/// Writes the summary as a spreadsheet.
enum TravelSummaryCSV {
  static func make(trips: [Trip], journal: Journal, reportUnit: DistanceUnit) -> String {
    let header = [
      "Trip", "Set off", "Came home", "Vehicle", "Outcome",
      "Visited stops", "Recorded distance", "Unit", "Elapsed minutes",
    ]

    let rows = trips.map { trip -> String in
      let vehicle = journal.vehicle(trip.vehicleID)
      let distance = trip.recordedDistance.map {
        (vehicle?.unit ?? reportUnit).converting($0, to: reportUnit)
      }
      let elapsed = trip.actualEnd.flatMap { end in
        trip.actualStart.map { Int(end.timeIntervalSince($0) / 60) }
      }

      return cells([
        trip.name,
        trip.actualStart?.ISO8601Format() ?? "",
        trip.actualEnd?.ISO8601Format() ?? "",
        vehicle?.name ?? "",
        trip.outcome?.displayName ?? "",
        String(trip.visitedStops.count),
        distance.map { String(format: "%.1f", $0) } ?? "",
        reportUnit.shortName,
        elapsed.map(String.init) ?? "",
      ])
    }

    return ([cells(header)] + rows).joined(separator: "\n")
  }

  private static func cells(_ values: [String]) -> String {
    values.map(escape).joined(separator: ",")
  }

  /// Quotes a value, and neutralises anything a spreadsheet would treat as a formula.
  ///
  /// A trip named "=HYPERLINK(…)" is a trip name, not something for Excel to run.
  private static func escape(_ value: String) -> String {
    let isFormula = ["=", "+", "-", "@"].contains { value.hasPrefix($0) }
    let safe = isFormula ? "'" + value : value
    return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }
}
