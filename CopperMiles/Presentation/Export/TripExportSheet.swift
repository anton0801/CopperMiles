import SwiftUI
import UIKit

/// Shares one trip, after showing exactly what will go out.
struct TripExportSheet: View {
  let tripID: UUID

  @EnvironmentObject private var environment: AppEnvironment
  @Environment(\.dismiss) private var dismiss

  @State private var options = ExportOptions()
  @State private var share: SharePayload?
  @State private var hasLoadedDefaults = false

  private var trip: Trip? { environment.trip(tripID) }

  var body: some View {
    Group {
      if let trip {
        content(trip)
      } else {
        CMEditorSheet(
          title: "Export",
          saveTitle: "Close",
          onSave: { dismiss() },
          onCancel: { dismiss() }
        ) {
          CMEmptyState(
            illustration: .roadNotebook,
            title: "This trip is gone",
            message: "It is no longer in your journal."
          )
        }
      }
    }
    .onAppear {
      guard !hasLoadedDefaults else { return }
      hasLoadedDefaults = true
      options = environment.settings.exportOptions
    }
    .sheet(item: $share) { ShareSheet(items: $0.items) }
  }

  private func content(_ trip: Trip) -> some View {
    CMEditorSheet(
      title: "Export preview",
      saveTitle: "Share as PDF",
      saveIcon: "square.and.arrow.up",
      onSave: { sharePDF(trip) },
      onCancel: { dismiss() }
    ) {
      CMScreenHeader(
        eyebrow: "A story worth sharing",
        title: "What goes out",
        subtitle: "Everything below is what the file will contain. Nothing else leaves this device."
      )

      CMCard(padding: 0) {
        VStack(spacing: 0) {
          CMToggleRow(title: "Include addresses", isOn: $options.includesAddresses)
          CMDivider()
          CMToggleRow(title: "Include coordinates", isOn: $options.includesCoordinates)
          CMDivider()
          CMToggleRow(
            title: "Include photos",
            hint: photoHint(trip),
            isOn: $options.includesPhotos
          )
        }
      }

      CMHint(
        text: "Your written notes are always included. Give them a read before sharing.",
        icon: "eye"
      )

      CMSectionHeader(title: "Preview")

      CMCard {
        Text(report(trip).text())
          .font(.system(.footnote, design: .monospaced))
          .foregroundColor(Theme.Colour.primaryText)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      }

      CMButton(title: "Share as plain text", icon: "doc.plaintext", prominence: .secondary) {
        share = SharePayload(items: [report(trip).text()])
      }
    }
  }

  private func photoHint(_ trip: Trip) -> String {
    let count = trip.notes.reduce(0) { $0 + $1.photoIDs.count }
    if count == 0 { return "This trip has no photos." }
    return count == 1 ? "One photo would be included." : "\(count) photos would be included."
  }

  private func report(_ trip: Trip) -> TripReport {
    TripReport(
      trip: trip,
      vehicleName: environment.vehicleName(trip.vehicleID),
      unit: environment.unit(forTrip: trip),
      options: options,
      formatters: environment.formatters
    )
  }

  private func sharePDF(_ trip: Trip) {
    environment.perform {
      let photos: [Data] =
        options.includesPhotos
        ? trip.notes.flatMap(\.photoIDs).compactMap { environment.attachments.data(for: $0) }
        : []

      let data = TripPDF.render(text: report(trip).text(), photos: photos)
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(safeFileName(trip.name)).pdf")
      try data.write(to: url, options: .atomic)
      share = SharePayload(items: [url])
    }
  }

  /// A file name the traveller will recognise, with anything a file system dislikes
  /// taken out.
  private func safeFileName(_ name: String) -> String {
    let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
      .joined(separator: "-")
      .trimmed
    return cleaned.isEmpty ? "CopperMiles-trip" : cleaned
  }
}

/// Draws a trip report onto pages.
enum TripPDF {
  private static let pageSize = CGSize(width: 595, height: 842)
  private static let margin: CGFloat = 45
  private static let lineHeight: CGFloat = 18

  static func render(text: String, photos: [Data]) -> Data {
    let bounds = CGRect(origin: .zero, size: pageSize)
    let contentWidth = pageSize.width - margin * 2
    let bottomLimit = pageSize.height - margin

    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 12),
      .foregroundColor: UIColor(Theme.Colour.primaryText),
    ]

    return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
      var y = margin

      func startPage() {
        context.beginPage()
        UIColor(Theme.Colour.background).setFill()
        context.cgContext.fill(bounds)
        y = margin
      }

      func draw(_ line: String) {
        if y + lineHeight > bottomLimit { startPage() }
        (line as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: attributes)
        y += lineHeight
      }

      startPage()

      // Wrapped by hand rather than drawn into a fixed rectangle, so a long note
      // flows onto the next page instead of vanishing below the edge.
      for paragraph in text.components(separatedBy: "\n") {
        guard !paragraph.isEmpty else {
          y += lineHeight
          continue
        }

        var line = ""
        for word in paragraph.components(separatedBy: " ") {
          let candidate = line.isEmpty ? word : line + " " + word
          let width = (candidate as NSString).size(withAttributes: attributes).width

          if width > contentWidth, !line.isEmpty {
            draw(line)
            line = word
          } else {
            line = candidate
          }
        }
        if !line.isEmpty { draw(line) }
      }

      for data in photos {
        guard let image = UIImage(data: data), image.size.width > 0 else { continue }

        let scale = min(contentWidth / image.size.width, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let capped = min(size.height, 350)
        let width = size.height > 0 ? size.width * (capped / size.height) : size.width

        if y + capped > bottomLimit { startPage() }
        image.draw(in: CGRect(x: margin, y: y, width: width, height: capped))
        y += capped + 20
      }
    }
  }
}
