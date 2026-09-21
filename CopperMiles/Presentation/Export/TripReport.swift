import Foundation

/// Writes a trip out as plain text.
///
/// What goes in is the traveller's decision, made in the preview: addresses and
/// coordinates are left out unless asked for, because a shared trip should be a
/// story about the road rather than a record of where someone lives.
struct TripReport {
  let trip: Trip
  let vehicleName: String
  let unit: DistanceUnit
  let options: ExportOptions
  let formatters: Formatters

  func text() -> String {
    var lines: [String] = ["COPPER MILES", trip.name, ""]

    lines += [
      "Vehicle: \(vehicleName)",
      "Outcome: \(trip.outcome?.displayName ?? trip.status.displayName)",
      "Set off: \(trip.actualStart.map(formatters.fullDateAndTime) ?? "Not recorded")",
      "Came home: \(trip.actualEnd.map(formatters.fullDateAndTime) ?? "Not recorded")",
      "Elapsed, stops included: \(formatters.duration(trip.elapsed(until: Date())))",
      "Distance: \(formatters.distance(trip.recordedDistance, unit: unit))",
    ]

    if trip.hasReadingDiscontinuity {
      lines.append("The odometer was replaced during this trip, so the distance is unknown.")
    }

    lines += ["", "STOPS"]
    // Every stop that carries a record, including one archived out of the plan after
    // it was visited — the journal shows those, and the export should match.
    for stop in trip.stops where !stop.isArchived || stop.isVisited {
      lines.append("· \(stop.name) — \(stopState(stop))")

      if options.includesAddresses, !stop.address.isEmpty {
        lines.append("  \(stop.address)")
      }
      if options.includesCoordinates, let coordinate = stop.coordinate {
        lines.append("  \(coordinate.latitude), \(coordinate.longitude)")
      }
      if let visit = stop.visit {
        lines.append("  Arrived \(formatters.fullDateAndTime(visit.arrival))")
        if let departure = visit.departure {
          lines.append("  Left \(formatters.fullDateAndTime(departure))")
        }
      }
      if let reason = stop.skipReason {
        lines.append("  Passed by: \(reason)")
      }
    }

    let notes = trip.notes.sorted { $0.recordedAt < $1.recordedAt }
    if !notes.isEmpty {
      lines += ["", "ROAD NOTES"]
      for note in notes {
        lines.append("\(formatters.fullDateAndTime(note.recordedAt)) · \(note.kind.displayName)")
        lines.append(note.text)
        lines.append("")
      }
    }

    if !trip.finalNote.isEmpty {
      lines += ["LOOKING BACK", trip.finalNote]
    }
    if !trip.endReason.isEmpty {
      lines += ["", "WHY IT ENDED EARLY", trip.endReason]
    }

    return lines.joined(separator: "\n")
  }

  private func stopState(_ stop: Stop) -> String {
    if stop.isVisited { return "visited" }
    if stop.isSkipped { return "passed by" }
    return "not reached"
  }
}
