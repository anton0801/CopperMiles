import Foundation
import UIKit

enum Atlas {
    static let appCode = "6814457852"
    static let store = "id6814457852"
    static let vault = "cm_trek_log.dat"
    static let pad: UInt8 = 0x3c
    static let folder = "CopperMilesTrail"
    static let relayKey = "dY5m9xk835yDFDyd355Ntm"
    static let endpoint = "https://coppermiles.com/config.php"
    static let suite = "group.coppermiles.trail"
    static let gaps: [TimeInterval] = [75, 150, 300]
    static let cookieJar = "cm_trail_cookies"
    static let tag = "🧭 [CopperMiles]"
}

/// Keeps the traveller's photos as individual files.
///
/// One file per photo is what keeps the journal document small: ticking a checklist
/// item rewrites a few kilobytes of JSON instead of re-encoding every picture in the
/// app. Images are downscaled on the way in, because a journal is for remembering a
/// place, not for archiving a camera's full output.
final class FileAttachmentStore: AttachmentStore {
  /// The longest edge kept for a stored photo.
  private static let maximumDimension: CGFloat = 2048
  private static let compressionQuality: CGFloat = 0.8

  private let directory: URL
  private let fileManager: FileManager

  /// Decoded images, so a scrolling journal does not read and decode the same
  /// picture on every pass. Cleared automatically under memory pressure.
  private let cache = NSCache<NSString, NSData>()

  init(directory: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.directory =
      directory
      ?? fileManager
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CopperMiles/Attachments")
    cache.countLimit = 40
  }

  // MARK: - Reading

  func data(for id: AttachmentID) -> Data? {
    let key = id.description as NSString
    if let cached = cache.object(forKey: key) {
      return cached as Data
    }
    guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
    cache.setObject(data as NSData, forKey: key)
    return data
  }

  // MARK: - Writing

  func store(_ data: Data) throws -> AttachmentID {
    let id = AttachmentID()
    try write(prepared(data), to: id)
    return id
  }

  func restore(_ data: Data, as id: AttachmentID) throws {
    // Backup contents are already prepared; re-encoding would lose quality on every
    // export and import round trip.
    try write(data, to: id)
  }

  func remove(_ ids: [AttachmentID]) {
    for id in ids {
      cache.removeObject(forKey: id.description as NSString)
      try? fileManager.removeItem(at: url(for: id))
    }
  }

  func removeOrphans(keeping referenced: Set<AttachmentID>) {
    let kept = Set(referenced.map(\.description))
    let contents =
      (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []

    for file in contents {
      let name = (file as NSString).deletingPathExtension
      guard !kept.contains(name) else { continue }
      cache.removeObject(forKey: name as NSString)
      try? fileManager.removeItem(at: directory.appendingPathComponent(file))
    }
  }

  // MARK: - Files

  private func url(for id: AttachmentID) -> URL {
    directory.appendingPathComponent("\(id.description).jpg")
  }

  private func write(_ data: Data, to id: AttachmentID) throws {
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(
      to: url(for: id),
      options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
    )
    cache.setObject(data as NSData, forKey: id.description as NSString)
  }

  /// Downscales and re-encodes an image, keeping the original if anything about it
  /// cannot be read — a photo the traveller chose is worth storing as-is rather than
  /// dropping.
  private func prepared(_ data: Data) -> Data {
    guard let image = UIImage(data: data) else { return data }

    let longestEdge = max(image.size.width, image.size.height)
    guard longestEdge > Self.maximumDimension else {
      return image.jpegData(compressionQuality: Self.compressionQuality) ?? data
    }

    let scale = Self.maximumDimension / longestEdge
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    return resized.jpegData(compressionQuality: Self.compressionQuality) ?? data
  }
}
