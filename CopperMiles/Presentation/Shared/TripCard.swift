import SwiftUI

/// One trip, as it appears in a list.
///
/// Carries what the traveller needs to tell their trips apart at a glance — where it
/// goes, which car, when it leaves and how the preparation is coming along — without
/// making them open it.
struct TripCard: View {
  let trip: Trip
  var isHighlighted = false

  @EnvironmentObject private var environment: AppEnvironment

  var body: some View {
    CMCard(isHighlighted: isHighlighted) {
      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        header
        route
        CMDivider(isInset: false)
        footer
        if trip.status.isPlanning, !trip.checklistProgress.isEmpty {
          preparation
        }
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var needsReview: Bool { trip.needsReview(now: environment.dates.now) }

  private var header: some View {
    HStack(alignment: .top) {
      CMTag(
        text: needsReview ? "Needs review" : trip.status.displayName,
        colour: needsReview ? Theme.Colour.accent : trip.status.tagColour
      )
      Spacer()
      Image(systemName: "arrow.up.right")
        .font(.system(.footnote).weight(.semibold))
        .foregroundColor(Theme.Colour.secondaryText)
    }
  }

  private var route: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
      Text(trip.name.isEmpty ? "Untitled trip" : trip.name)
        .font(Font.CM.cardTitle)
        .foregroundColor(Theme.Colour.primaryText)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: Theme.Spacing.small) {
        Text(trip.startPlace.isEmpty ? "Starting place" : trip.startPlace)
        Image(systemName: "arrow.right").font(.system(.caption2))
        Text(trip.destination?.name ?? "Destination")
      }
      .font(Font.CM.footnote)
      .foregroundColor(Theme.Colour.secondaryText)
      .lineLimit(1)
    }
  }

  private var footer: some View {
    HStack(spacing: Theme.Spacing.medium) {
      CMAsset(.compactCar, width: 48, height: 40)

      VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
        Text(environment.vehicleName(trip.vehicleID))
          .font(Font.CM.labelEmphasis)
          .foregroundColor(Theme.Colour.primaryText)
          .lineLimit(1)

        Text(departureText)
          .font(Font.CM.footnote)
          .foregroundColor(Theme.Colour.secondaryText)
      }

      Spacer(minLength: Theme.Spacing.small)

      VStack(alignment: .trailing, spacing: Theme.Spacing.hairline) {
        Text(stopsText)
          .font(Font.CM.labelEmphasis)
          .foregroundColor(Theme.Colour.primaryText)

        Text(secondaryText)
          .font(Font.CM.footnote)
          .foregroundColor(Theme.Colour.secondaryText)
      }
    }
  }

  private var preparation: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
      CMProgressBar(progress: trip.checklistProgress)
      Text(
        "\(trip.checklistProgress.checked) of \(trip.checklistProgress.total) checks ready"
      )
      .font(Font.CM.caption)
      .foregroundColor(Theme.Colour.secondaryText)
    }
  }

  private var departureText: String {
    if let start = trip.actualStart {
      return "Set off \(environment.formatters.dateAndTime(start))"
    }
    if let departure = trip.plannedDeparture {
      return environment.formatters.dateAndTime(departure)
    }
    return "No departure set"
  }

  private var stopsText: String {
    let count = trip.activeStops.count
    return count == 1 ? "1 stop" : "\(count) stops"
  }

  private var secondaryText: String {
    switch trip.status {
    case .completed:
      return "\(trip.visitedStops.count) visited"
    case .active:
      return "\(trip.visitedStops.count) of \(trip.activeStops.count) visited"
    case .draft, .planned, .cancelled:
      return trip.checklistProgress.isEmpty ? "No checklist" : "Preparing"
    }
  }
}

/// One stop, as it appears in a plan.
struct StopRow: View {
  let stop: Stop
  var index: Int?
  var showsPlannedArrival = true

  @EnvironmentObject private var environment: AppEnvironment

  var body: some View {
    HStack(spacing: Theme.Spacing.medium) {
      marker

      VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
        Text(stop.name)
          .font(Font.CM.label)
          .foregroundColor(Theme.Colour.primaryText)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)

        Text(detailText)
          .font(Font.CM.footnote)
          .foregroundColor(Theme.Colour.secondaryText)
      }

      Spacer(minLength: Theme.Spacing.small)

      Image(systemName: "chevron.right")
        .font(.system(.caption).weight(.semibold))
        .foregroundColor(Theme.Colour.secondaryText.opacity(0.6))
    }
    .padding(.horizontal, Theme.Spacing.cardPadding)
    .padding(.vertical, Theme.Spacing.medium)
    .frame(minHeight: Theme.minimumTapTarget)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private var marker: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        .fill(stop.isVisited ? Theme.Colour.success.opacity(0.14) : Theme.Colour.accentSoft.opacity(0.2))
        .frame(width: 42, height: 46)

      Image(systemName: stop.isVisited ? "checkmark" : stop.kind.icon)
        .font(.system(.footnote).weight(.semibold))
        .foregroundColor(stop.isVisited ? Theme.Colour.success : Theme.Colour.primaryText)
    }
    .overlay(alignment: .topLeading) {
      if let index, !stop.isVisited {
        Text("\(index + 1)")
          .font(Font.CM.badge)
          .foregroundColor(Theme.Colour.secondaryText)
          .padding(.leading, 2)
          .padding(.top, 2)
      }
    }
  }

  private var detailText: String {
    var parts: [String] = []

    if stop.isVisited || stop.isSkipped {
      parts.append(stop.stateLabel)
    } else {
      parts.append(stop.kind.displayName)
    }

    if showsPlannedArrival, let arrival = stop.plannedArrival {
      parts.append("planned \(environment.formatters.dateAndTime(arrival))")
    }

    if let visit = stop.visit {
      parts.append(environment.formatters.dateAndTime(visit.arrival))
    }

    return parts.joined(separator: " · ")
  }
}
