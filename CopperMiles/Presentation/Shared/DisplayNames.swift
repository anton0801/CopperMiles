import Foundation
import SwiftUI

/// The words the traveller reads for each domain case.
///
/// The domain stores case names, not sentences. Keeping the wording here means a
/// label can be reworded — or one day translated — without touching a stored file or
/// a rule.
extension DistanceUnit {
  var shortName: String {
    switch self {
    case .kilometres: return "km"
    case .miles: return "mi"
    }
  }

  var longName: String {
    switch self {
    case .kilometres: return "Kilometres"
    case .miles: return "Miles"
    }
  }
}

extension TripStatus {
  var displayName: String {
    switch self {
    case .draft: return "Draft"
    case .planned: return "Planned"
    case .active: return "On the road"
    case .completed: return "Completed"
    case .cancelled: return "Cancelled"
    }
  }

  var tagColour: Color {
    switch self {
    case .draft: return Theme.Colour.secondaryText
    case .planned: return Theme.Colour.accent
    case .active: return Theme.Colour.success
    case .completed: return Theme.Colour.success
    case .cancelled: return Theme.Colour.secondaryText
    }
  }
}

extension TripOutcome {
  var displayName: String {
    switch self {
    case .completed: return "Completed"
    case .endedEarly: return "Ended early"
    }
  }
}

extension StopKind {
  var displayName: String {
    switch self {
    case .rest: return "Rest"
    case .food: return "Food"
    case .fuel: return "Fuel"
    case .viewpoint: return "Viewpoint"
    case .overnight: return "Overnight"
    case .custom: return "Somewhere else"
    case .destination: return "Destination"
    }
  }

  var icon: String {
    switch self {
    case .rest: return "cup.and.saucer.fill"
    case .food: return "fork.knife"
    case .fuel: return "fuelpump.fill"
    case .viewpoint: return "binoculars.fill"
    case .overnight: return "bed.double.fill"
    case .custom: return "mappin"
    case .destination: return "flag.fill"
    }
  }
}

extension PreparationGroup {
  var displayName: String {
    switch self {
    case .car: return "Car"
    case .documents: return "Documents"
    case .personal: return "Personal"
    case .other: return "Other"
    }
  }

  var icon: String {
    switch self {
    case .car: return "car.fill"
    case .documents: return "doc.text.fill"
    case .personal: return "bag.fill"
    case .other: return "sparkles"
    }
  }
}

extension RoadNoteKind {
  var displayName: String {
    switch self {
    case .road: return "Road"
    case .parking: return "Parking"
    case .car: return "Car"
    case .place: return "Place"
    case .other: return "Other"
    }
  }

  var icon: String {
    switch self {
    case .road: return "road.lanes"
    case .parking: return "parkingsign"
    case .car: return "car"
    case .place: return "mappin.and.ellipse"
    case .other: return "sparkles"
    }
  }
}

extension ReminderKind {
  var displayName: String {
    switch self {
    case .prepareCar: return "Prepare the car"
    case .reviewStops: return "Review the stops"
    case .packPersonalItems: return "Pack personal items"
    }
  }

  var icon: String {
    switch self {
    case .prepareCar: return "wrench.and.screwdriver"
    case .reviewStops: return "map"
    case .packPersonalItems: return "bag"
    }
  }
}

extension OdometerExplanation {
  var displayName: String {
    switch self {
    case .correctedReading: return "Corrected reading"
    case .odometerReplaced: return "Odometer replaced"
    }
  }
}

extension JournalPeriod {
  var displayName: String {
    switch self {
    case .allTime: return "All time"
    case .thisMonth: return "This month"
    case .thisYear: return "This year"
    }
  }
}

extension TripListFilter.Scope {
  var displayName: String {
    switch self {
    case .all: return "All"
    case .status(let status): return status.displayName
    case .needsReview: return "Needs review"
    }
  }
}

extension Stop {
  /// How this stop currently stands, for a badge.
  var stateLabel: String {
    if isVisited { return "Visited" }
    if isSkipped { return "Skipped" }
    return "Planned"
  }

  var stateColour: Color {
    if isVisited { return Theme.Colour.success }
    if isSkipped { return Theme.Colour.secondaryText }
    return Theme.Colour.accent
  }
}
