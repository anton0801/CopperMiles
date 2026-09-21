import Foundation

/// A minimal ZIP reader and writer for stored (uncompressed) entries.
///
/// Backups use method 0 so that the app carries no third-party archiving code, while
/// the file the traveller ends up with is still an ordinary ZIP any desktop can
/// open. Photos are already JPEG, so compressing them again would buy almost
/// nothing.
enum ZipArchive {
  /// The largest archive that will be read, so a wrong file cannot exhaust memory.
  static let maximumArchiveBytes = 250 * 1024 * 1024

  struct Entry {
    let name: String
    let contents: Data
  }

  // MARK: - Writing

  static func archive(_ entries: [Entry]) -> Data {
    var body = Data()
    var central = Data()

    for entry in entries {
      let name = Data(entry.name.utf8)
      let checksum = crc32(entry.contents)
      let offset = UInt32(body.count)
      let size = UInt32(entry.contents.count)

      body.appendLittleEndian(Signature.localHeader)
      body.appendLittleEndian(UInt16(20))  // version needed
      body.appendLittleEndian(UInt16(0))  // flags
      body.appendLittleEndian(UInt16(0))  // method: stored
      body.appendLittleEndian(UInt16(0))  // modification time
      body.appendLittleEndian(UInt16(0))  // modification date
      body.appendLittleEndian(checksum)
      body.appendLittleEndian(size)  // compressed
      body.appendLittleEndian(size)  // uncompressed
      body.appendLittleEndian(UInt16(name.count))
      body.appendLittleEndian(UInt16(0))  // extra field length
      body.append(name)
      body.append(entry.contents)

      central.appendLittleEndian(Signature.centralHeader)
      central.appendLittleEndian(UInt16(20))  // version made by
      central.appendLittleEndian(UInt16(20))  // version needed
      central.appendLittleEndian(UInt16(0))  // flags
      central.appendLittleEndian(UInt16(0))  // method: stored
      central.appendLittleEndian(UInt16(0))  // modification time
      central.appendLittleEndian(UInt16(0))  // modification date
      central.appendLittleEndian(checksum)
      central.appendLittleEndian(size)
      central.appendLittleEndian(size)
      central.appendLittleEndian(UInt16(name.count))
      central.appendLittleEndian(UInt16(0))  // extra field length
      central.appendLittleEndian(UInt16(0))  // comment length
      central.appendLittleEndian(UInt16(0))  // disk number
      central.appendLittleEndian(UInt16(0))  // internal attributes
      central.appendLittleEndian(UInt32(0))  // external attributes
      central.appendLittleEndian(offset)
      central.append(name)
    }

    let centralOffset = UInt32(body.count)
    var output = body
    output.append(central)
    output.appendLittleEndian(Signature.endOfDirectory)
    output.appendLittleEndian(UInt16(0))  // this disk
    output.appendLittleEndian(UInt16(0))  // directory start disk
    output.appendLittleEndian(UInt16(entries.count))
    output.appendLittleEndian(UInt16(entries.count))
    output.appendLittleEndian(UInt32(central.count))
    output.appendLittleEndian(centralOffset)
    output.appendLittleEndian(UInt16(0))  // comment length
    return output
  }

  // MARK: - Reading

  /// Reads every stored entry, rejecting anything this writer would not produce.
  ///
  /// Names are checked rather than trusted: an absolute or climbing path in an
  /// archive is the classic way to have a reader write outside its own folder.
  static func entries(in data: Data, allowing isAllowedName: (String) -> Bool) throws -> [Entry] {
    guard data.count <= maximumArchiveBytes else {
      throw DomainError("That backup is larger than 250 MB.")
    }

    let reader = Reader(data: data)
    var entries: [Entry] = []
    var names: Set<String> = []
    var offset = 0

    while try reader.unsigned32(at: offset) == Signature.localHeader {
      guard try reader.unsigned16(at: offset + 6) == 0,  // no flags
        try reader.unsigned16(at: offset + 8) == 0  // stored, not compressed
      else {
        throw DomainError("Choose a backup that Copper Miles wrote.")
      }

      let checksum = try reader.unsigned32(at: offset + 14)
      let compressed = Int(try reader.unsigned32(at: offset + 18))
      let uncompressed = Int(try reader.unsigned32(at: offset + 22))
      let nameLength = Int(try reader.unsigned16(at: offset + 26))
      let extraLength = Int(try reader.unsigned16(at: offset + 28))

      let nameStart = offset + 30
      let contentsStart = nameStart + nameLength + extraLength
      let contentsEnd = contentsStart + compressed

      guard compressed == uncompressed, contentsEnd <= data.count else {
        throw DomainError("That backup file is incomplete.")
      }

      let name = try reader.string(from: nameStart, length: nameLength)
      guard isSafe(name), isAllowedName(name), names.insert(name).inserted else {
        throw DomainError("That backup contains an unexpected file.")
      }

      let contents = try reader.bytes(from: contentsStart, to: contentsEnd)
      guard crc32(contents) == checksum else {
        throw DomainError("That backup did not pass its checksum. The file may be damaged.")
      }

      entries.append(Entry(name: name, contents: contents))
      offset = contentsEnd
    }

    guard try reader.unsigned32(at: offset) == Signature.centralHeader, !entries.isEmpty else {
      throw DomainError("That is not a Copper Miles backup.")
    }
    return entries
  }

  private static func isSafe(_ name: String) -> Bool {
    !name.isEmpty
      && !name.hasPrefix("/")
      && !name.contains("..")
      && !name.contains("\\")
      && !name.contains("\0")
  }

  // MARK: - Primitives

  private enum Signature {
    static let localHeader: UInt32 = 0x0403_4b50
    static let centralHeader: UInt32 = 0x0201_4b50
    static let endOfDirectory: UInt32 = 0x0605_4b50
  }

  /// Bounds-checked little-endian reads over the archive's bytes.
  private struct Reader {
    let data: Data

    func unsigned16(at offset: Int) throws -> UInt16 {
      UInt16(try integer(at: offset, byteCount: 2))
    }

    func unsigned32(at offset: Int) throws -> UInt32 {
      try integer(at: offset, byteCount: 4)
    }

    func bytes(from start: Int, to end: Int) throws -> Data {
      guard start >= 0, start <= end, end <= data.count else {
        throw DomainError("That backup file is incomplete.")
      }
      return Data(data[(data.startIndex + start)..<(data.startIndex + end)])
    }

    func string(from offset: Int, length: Int) throws -> String {
      let raw = try bytes(from: offset, to: offset + length)
      guard let value = String(data: raw, encoding: .utf8) else {
        throw DomainError("That backup contains a name Copper Miles cannot read.")
      }
      return value
    }

    private func integer(at offset: Int, byteCount: Int) throws -> UInt32 {
      let raw = try bytes(from: offset, to: offset + byteCount)
      return raw.enumerated().reduce(into: UInt32(0)) { result, element in
        result |= UInt32(element.element) << (element.offset * 8)
      }
    }
  }

  static func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffff_ffff
    for byte in data {
      crc ^= UInt32(byte)
      for _ in 0..<8 {
        crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb8_8320 : 0)
      }
    }
    return ~crc
  }
}

extension Data {
  fileprivate mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
  }
}
