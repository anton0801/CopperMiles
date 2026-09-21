import SwiftUI

/// Where a journey is either continued or prepared.
///
/// The screen answers one question first — is something under way, and if not what
/// is next — and only then offers the rest.
struct HomeView: View {
  @EnvironmentObject private var environment: AppEnvironment
  @ScaledMetric(relativeTo: .largeTitle) private var heroSize = Font.CM.heroSize

  @State private var isCreatingTrip = false
  @State private var isAddingVehicle = false

  private var activeTrip: Trip? { environment.activeTrip }
  private var upcomingTrip: Trip? { environment.journal.upcomingTrip(now: environment.dates.now) }
  private var tripsNeedingReview: [Trip] {
    environment.journal.tripsNeedingReview(now: environment.dates.now)
  }

  var body: some View {
    CMScreen(spacing: Theme.Spacing.xxLarge) {
      topBar
      greeting
      PipHeroCard(hasVehicle: !environment.journal.availableVehicles.isEmpty,
                  isOnTheRoad: activeTrip != nil) {
        isAddingVehicle = true
      }

      if let trip = activeTrip {
        activeSection(trip)
      } else if let trip = upcomingTrip {
        upcomingSection(trip)
      } else {
        noPlansSection
      }

      CMButton(
        title: activeTrip == nil ? "Plan a new trip" : "Plan another trip",
        icon: "plus"
      ) {
        isCreatingTrip = true
      }

      if !tripsNeedingReview.isEmpty {
        reviewNotice
      }

      quickLinks
      privacyNote
    }
    .navigationBarHidden(true)
    .sheet(isPresented: $isCreatingTrip) { NewTripFlow() }
    .sheet(isPresented: $isAddingVehicle) { VehicleEditorSheet(vehicle: Vehicle()) }
  }

  // MARK: - Header

  private var topBar: some View {
    HStack {
      HStack(spacing: Theme.Spacing.small) {
        Image(systemName: "sun.max.fill")
          .font(.system(.footnote))
          .foregroundColor(Theme.Colour.accent)
        Text("A GOOD DAY TO WANDER")
          .font(Font.CM.eyebrow)
          .cmTracked(1.5)
          .foregroundColor(Theme.Colour.primaryText)
      }

      Spacer()

      NavigationLink {
        SettingsView()
      } label: {
        Image(systemName: "gearshape")
          .font(.system(.body))
          .foregroundColor(Theme.Colour.secondaryText)
          .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
          .background(Theme.Colour.surface)
          .clipShape(Circle())
      }
      .accessibilityLabel("Settings")
    }
  }

  private var greeting: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Little plans.")
        .foregroundColor(Theme.Colour.primaryText)
      Text("Lovely journeys.")
        .foregroundColor(Theme.Colour.accent)
    }
    .font(Font.CM.hero(heroSize))
    .minimumScaleFactor(0.8)
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
  }

  // MARK: - The trip that matters right now

  private func activeSection(_ trip: Trip) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSectionHeader(title: "On the road", detail: "Keep going")

      NavigationLink {
        OnTheRoadView(tripID: trip.id)
      } label: {
        TripCard(trip: trip, isHighlighted: true)
      }
      .buttonStyle(.plain)
    }
  }

  private func upcomingSection(_ trip: Trip) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSectionHeader(title: "Your next trip", detail: "Coming up")

      NavigationLink {
        TripPlanView(tripID: trip.id)
      } label: {
        TripCard(trip: trip)
      }
      .buttonStyle(.plain)

      NavigationLink {
        ChecklistView(tripID: trip.id)
      } label: {
        HStack(spacing: Theme.Spacing.medium) {
          Image(systemName: "checklist")
            .font(.system(.title3))
            .foregroundColor(Theme.Colour.success)

          VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
            Text("Get ready to go")
              .font(Font.CM.labelEmphasis)
              .foregroundColor(Theme.Colour.primaryText)
            Text(preparationSummary(trip))
              .font(Font.CM.footnote)
              .foregroundColor(Theme.Colour.secondaryText)
          }

          Spacer()

          Image(systemName: "chevron.right")
            .font(.system(.caption).weight(.semibold))
            .foregroundColor(Theme.Colour.secondaryText.opacity(0.6))
        }
        .padding(Theme.Spacing.cardPadding)
        .frame(maxWidth: .infinity)
        .background(Theme.Colour.action.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
      }
      .buttonStyle(.plain)
    }
  }

  private var noPlansSection: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
      CMSectionHeader(title: "Your next trip")

      CMCard {
        HStack(alignment: .top, spacing: Theme.Spacing.large) {
          Image(systemName: "map")
            .font(.system(.title2).weight(.light))
            .foregroundColor(Theme.Colour.accent)
            .frame(width: 54, height: 60)
            .background(Theme.Colour.accentSoft.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))

          VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Good things start with a plan")
              .font(Font.CM.labelEmphasis)
              .foregroundColor(Theme.Colour.primaryText)
            Text("Pick your car, add a few stops, and leave room for a little wonder.")
              .font(Font.CM.footnote)
              .foregroundColor(Theme.Colour.secondaryText)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }

  private func preparationSummary(_ trip: Trip) -> String {
    let progress = trip.checklistProgress
    if progress.isEmpty { return "Add the checks that matter to you" }
    if progress.checked == progress.total { return "Everything is ready" }
    return "\(progress.checked) of \(progress.total) checks done"
  }

  // MARK: - The rest

  private var reviewNotice: some View {
    NavigationLink {
      TripsListView(initialScope: .needsReview)
    } label: {
      HStack(spacing: Theme.Spacing.medium) {
        Image(systemName: "calendar.badge.exclamationmark")
          .foregroundColor(Theme.Colour.accent)

        Text(
          tripsNeedingReview.count == 1
            ? "One plan’s departure has passed. Worth a look."
            : "\(tripsNeedingReview.count) plans have departures that have passed."
        )
        .font(Font.CM.footnote)
        .foregroundColor(Theme.Colour.primaryText)
        .multilineTextAlignment(.leading)

        Spacer(minLength: Theme.Spacing.small)

        Image(systemName: "chevron.right")
          .font(.system(.caption).weight(.semibold))
          .foregroundColor(Theme.Colour.secondaryText)
      }
      .padding(Theme.Spacing.cardPadding)
      .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
      .background(Theme.Colour.accentSoft.opacity(0.2))
      .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private var quickLinks: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.medium) {
      NavigationLink {
        VehiclesListView()
      } label: {
        QuickTile(
          icon: "car.fill",
          title: "Your garage",
          value: countLabel(environment.journal.availableVehicles.count, "vehicle", "vehicles"),
          tint: Theme.Colour.accentSoft
        )
      }

      NavigationLink {
        JournalListView()
      } label: {
        QuickTile(
          icon: "book.closed.fill",
          title: "Road memories",
          value: countLabel(finishedTripCount, "journey", "journeys"),
          tint: Theme.Colour.action
        )
      }
    }
    .buttonStyle(.plain)
  }

  private var finishedTripCount: Int {
    environment.journal.trips.filter { $0.status == .completed && !$0.isArchived }.count
  }

  private func countLabel(_ count: Int, _ singular: String, _ plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
  }

  private var privacyNote: some View {
    HStack(spacing: Theme.Spacing.small) {
      Image(systemName: "lock.shield")
      Text("Your roads. Your memories. Kept on this device.")
    }
    .font(Font.CM.caption)
    .foregroundColor(Theme.Colour.secondaryText)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
}

/// The warm card Pip lives on.
struct PipHeroCard: View {
  let hasVehicle: Bool
  let isOnTheRoad: Bool
  let onAddVehicle: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: Theme.Spacing.small) {
      VStack(alignment: .leading, spacing: Theme.Spacing.small) {
        Text("A LITTLE HELLO FROM PIP")
          .font(Font.CM.eyebrow)
          .cmTracked(1.1)
          .foregroundColor(Theme.Colour.primaryText.opacity(0.75))

        Text(isOnTheRoad ? "Adventure is\nunder way." : "Ready when\nyou are.")
          .font(Font.CM.screenTitle)
          .foregroundColor(Theme.Colour.primaryText)
          .fixedSize(horizontal: false, vertical: true)

        Text(
          hasVehicle
            ? "I’ll help with the little things. You make the memories."
            : "Let’s give your travel companion a home."
        )
        .font(Font.CM.footnote)
        .foregroundColor(Theme.Colour.primaryText.opacity(0.8))
        .fixedSize(horizontal: false, vertical: true)

        if !hasVehicle {
          Button(action: onAddVehicle) {
            HStack(spacing: Theme.Spacing.tiny) {
              Text("Add your first vehicle")
              Image(systemName: "arrow.up.right")
            }
            .font(Font.CM.labelEmphasis)
            .foregroundColor(Theme.Colour.primaryText)
            .frame(minHeight: Theme.minimumTapTarget, alignment: .leading)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)

      CMAsset(.pipHome, width: 132, height: 150)
        .padding(.trailing, -Theme.Spacing.small)
    }
    .padding(Theme.Spacing.xLarge)
    .background(Theme.Colour.heroGradient)
    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xLarge + 4, style: .continuous))
  }
}

/// A small tile linking to one of the other tabs.
struct QuickTile: View {
  let icon: String
  let title: String
  let value: String
  let tint: Color

  var body: some View {
    CMCard {
      VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
        HStack {
          Image(systemName: icon)
            .font(.system(.body))
            .foregroundColor(Theme.Colour.primaryText)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.32))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))

          Spacer()

          Image(systemName: "arrow.up.right")
            .font(.system(.caption))
            .foregroundColor(Theme.Colour.secondaryText)
        }

        VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
          Text(title)
            .font(Font.CM.labelEmphasis)
            .foregroundColor(Theme.Colour.primaryText)
          Text(value)
            .font(Font.CM.footnote)
            .foregroundColor(Theme.Colour.secondaryText)
        }
      }
    }
    .accessibilityElement(children: .combine)
  }
}
