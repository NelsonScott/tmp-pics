import Foundation

/// How long a new shot lives before the app deletes it.
enum Lifetime: String, CaseIterable, Codable, Identifiable {
    case oneHour, oneDay, threeDays, sevenDays, never

    static let `default` = Lifetime.oneDay

    var id: String { rawValue }

    /// Real seconds, before any fast-forward scaling. `nil` means the shot never expires.
    var seconds: TimeInterval? {
        switch self {
        case .oneHour: return 3600
        case .oneDay: return 86_400
        case .threeDays: return 3 * 86_400
        case .sevenDays: return 7 * 86_400
        case .never: return nil
        }
    }

    var label: String {
        switch self {
        case .oneHour: return "1 hour"
        case .oneDay: return "24 hours"
        case .threeDays: return "3 days"
        case .sevenDays: return "7 days"
        case .never: return "Never"
        }
    }
}

/// One photo the app took. The image is the file `file` in the app's Shots folder (see ShotStore).
/// `id` is a UUID string. `expiresAt` is fixed when the shot is taken; `nil` means it never expires.
/// Dates live here, not in file attributes, so the app never reads file timestamps.
struct Shot: Codable, Identifiable, Equatable {
    let id: String
    var file: String
    let capturedAt: Date
    let expiresAt: Date?

    init(id: String, file: String, capturedAt: Date, expiresAt: Date?) {
        self.id = id
        self.file = file
        self.capturedAt = capturedAt
        self.expiresAt = expiresAt
    }

    /// A new shot with its expiry worked out from the lifetime. `timeScale` > 1 is the fast-forward QA mode.
    init(id: String, file: String, capturedAt: Date, lifetime: Lifetime, timeScale: Double = 1) {
        let scale = timeScale > 0 ? timeScale : 1
        self.init(id: id, file: file, capturedAt: capturedAt,
                  expiresAt: lifetime.seconds.map { capturedAt.addingTimeInterval($0 / scale) })
    }

    func isExpired(at now: Date) -> Bool { expiresAt.map { now >= $0 } ?? false }
    /// Seconds left; `nil` when the shot never expires.
    func remaining(at now: Date) -> TimeInterval? { expiresAt.map { max(0, $0.timeIntervalSince(now)) } }
}

/// The list of shots the app holds. Pure logic, no files, so it is unit tested.
struct Ledger: Codable, Equatable {
    /// Bumped when the format changes. A file with any other version (or none: the old Photos-album
    /// ledger) is ignored and starts empty.
    static let version = 2

    private(set) var shots: [Shot] = []

    init() {}

    private enum CodingKeys: String, CodingKey { case version, shots }
    struct WrongVersion: Error {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decodeIfPresent(Int.self, forKey: .version) == Self.version else { throw WrongVersion() }
        shots = try c.decode([Shot].self, forKey: .shots)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.version, forKey: .version)
        try c.encode(shots, forKey: .shots)
    }

    /// Add a shot whose file is written. Returns false for a duplicate id.
    @discardableResult
    mutating func add(_ shot: Shot) -> Bool {
        guard !shots.contains(where: { $0.id == shot.id }) else { return false }
        shots.append(shot)
        return true
    }

    /// Drop these ids (deleted, expired, or their file is missing).
    mutating func forget(_ ids: some Sequence<String>) {
        let drop = Set(ids)
        shots.removeAll { drop.contains($0.id) }
    }

    /// Removes and returns every shot that has expired at `now`, oldest first.
    mutating func removeExpired(at now: Date) -> [Shot] {
        let gone = expired(at: now)
        forget(gone.map(\.id))
        return gone
    }

    func contains(_ id: String) -> Bool { shots.contains { $0.id == id } }

    /// The file names the ledger knows. Anything else in the Shots folder is left over and can go.
    var files: Set<String> { Set(shots.map(\.file)) }

    func expired(at now: Date) -> [Shot] {
        shots.filter { $0.isExpired(at: now) }.sorted { $0.capturedAt < $1.capturedAt }
    }

    /// Newest first, for the grid.
    func recent() -> [Shot] {
        shots.sorted { $0.capturedAt > $1.capturedAt }
    }

    /// When the next shot expires.
    func nextExpiry(after now: Date) -> Date? {
        shots.compactMap(\.expiresAt).filter { $0 > now }.min()
    }

    /// One line for the home screen: "3 photos. Next one expires in 5 hours." `nil` when there are none.
    func summary(at now: Date) -> String? { Self.summary(count: shots.count, next: nextExpiry(after: now), now: now) }

    static func summary(count n: Int, next: Date?, now: Date) -> String? {
        guard n > 0 else { return nil }
        guard let next else { return n == 1 ? "1 photo." : "\(n) photos." }
        let phrase = durationPhrase(next.timeIntervalSince(now))
        return n == 1 ? "1 photo. It expires in \(phrase)." : "\(n) photos. Next one expires in \(phrase)."
    }
}

/// Short time-left label for a thumbnail: "6d", "23h", "45m", "30s". `nil` for a shot that never expires.
func remainingLabel(_ seconds: TimeInterval?) -> String? {
    guard let seconds else { return nil }
    let s = max(1, Int(seconds.rounded(.up)))
    if s >= 86_400 { return "\(s / 86_400)d" }
    if s >= 3600 { return "\(s / 3600)h" }
    if s >= 60 { return "\(s / 60)m" }
    return "\(s)s"
}

/// Longer phrase for the viewer: "Expires in 23 hours", "Never expires".
func remainingPhrase(_ seconds: TimeInterval?) -> String {
    guard let seconds else { return "Never expires" }
    return "Expires in " + durationPhrase(seconds)
}

/// "23 hours", "1 minute", "30 seconds": the largest whole unit, rounded down (seconds rounded up).
func durationPhrase(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds.rounded(.up)))
    func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
    if s >= 86_400 { return unit(s / 86_400, "day") }
    if s >= 3600 { return unit(s / 3600, "hour") }
    if s >= 60 { return unit(s / 60, "minute") }
    return unit(s, "second")
}

/// Saves the ledger as a small JSON file in Application Support: ids, file names and dates, no image data.
/// Excluded from backups, like the photos.
struct LedgerFile {
    let url: URL

    static var standard: LedgerFile {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LedgerFile(url: dir.appendingPathComponent("ledger.json"))
    }

    /// The saved ledger. A missing file, a corrupt one, or one in an older format loads empty.
    /// `nil` only when the file exists but cannot be read right now (for example before the phone's
    /// first unlock): the caller must then neither save over it nor delete any photo files.
    func load() -> Ledger? {
        guard FileManager.default.fileExists(atPath: url.path) else { return Ledger() }
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(Ledger.self, from: data)
        } catch {
            QALog.write("ledger reset: unreadable or old format")
            return Ledger()
        }
    }

    func save(_ ledger: Ledger) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(ledger)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var copy = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? copy.setResourceValues(values)
        } catch {
            QALog.write("ledger save failed: \(error)")
        }
    }

    func reset() { try? FileManager.default.removeItem(at: url) }
}
