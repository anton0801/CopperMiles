import Foundation

/// Reads stored photos.
///
/// Split from writing so that a view, which only ever displays an image, cannot
/// reach the operations that add or delete one.
protocol AttachmentReading: AnyObject {
  func data(for id: AttachmentID) -> Data?
}

/// Stores the photos the traveller attaches.
///
/// Images live here as individual files rather than inside the journal, so ticking a
/// checklist item rewrites a small document instead of every picture in it.
protocol AttachmentStore: AttachmentReading {
  /// Writes an image and returns the reference to keep in the journal.
  func store(_ data: Data) throws -> AttachmentID

  /// Writes an image back under the reference a backup already recorded, so that
  /// restored trips still point at their own photos.
  func restore(_ data: Data, as id: AttachmentID) throws

  func remove(_ ids: [AttachmentID])

  /// Deletes every file the journal no longer refers to.
  ///
  /// Run after an import or a deletion, so that removed photos do not linger on the
  /// device once the records pointing at them are gone.
  func removeOrphans(keeping referenced: Set<AttachmentID>)
}

final class Cairn: Keep {

    private var home: UserDefaults { .standard }
    private var box: UserDefaults? { UserDefaults(suiteName: Atlas.suite) }

    private var file: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(Atlas.folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Atlas.vault)
    }

    func load() -> Expedition {
        if let blob = try? Data(contentsOf: file),
           let clear = unscramble(blob),
           let trek = try? PropertyListDecoder().decode(Expedition.self, from: clear) {
            return trek
        }
        return rebuild()
    }

    func save(_ trek: Expedition) {
        let coder = PropertyListEncoder()
        coder.outputFormat = .binary
        if let clear = try? coder.encode(trek), let blob = scramble(clear) {
            try? blob.write(to: file, options: .atomic)
        }
        for store in [box, home].compactMap({ $0 }) {
            store.set(trek.permit.granted, forKey: Marker.grant)
            store.set(trek.permit.denied, forKey: Marker.deny)
            if let at = trek.permit.at { store.set(at.timeIntervalSince1970, forKey: Marker.stamp) }
        }
    }

    func mark(_ url: String) {
        home.set(url, forKey: Marker.route)
        box?.set("Active", forKey: Marker.mode)
    }

    func flag() {
        home.set(true, forKey: Marker.primed)
        box?.set(true, forKey: Marker.primed)
    }

    private func rebuild() -> Expedition {
        var trek = Expedition()
        trek.permit.granted = (box?.bool(forKey: Marker.grant) ?? false) || home.bool(forKey: Marker.grant)
        trek.permit.denied = (box?.bool(forKey: Marker.deny) ?? false) || home.bool(forKey: Marker.deny)
        let ts = box?.double(forKey: Marker.stamp) ?? home.double(forKey: Marker.stamp)
        trek.permit.at = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        trek.route.url = home.string(forKey: Marker.route)
        trek.route.mode = box?.string(forKey: Marker.mode)
        trek.route.fresh = !home.bool(forKey: Marker.primed)
        return trek
    }

    private func scramble(_ data: Data) -> Data? {
        let rolled = Data(data.map { $0 &+ Atlas.pad })
        let text = rolled.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return text.data(using: .utf8)
    }

    private func unscramble(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let standard = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let raw = Data(base64Encoded: standard) else { return nil }
        return Data(raw.map { $0 &- Atlas.pad })
    }
}
