import Foundation

/// How long a new shot lives before it counts as expired.
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

/// One photo this app saved to the library. `id` is the PhotoKit local identifier.
/// The app only ever deletes assets whose identifiers are in the ledger.
struct Shot: Codable, Identifiable, Equatable {
    let id: String
    let capturedAt: Date
    let expiresAt: Date

    func isExpired(at now: Date) -> Bool { now >= expiresAt }
    func remaining(at now: Date) -> TimeInterval { max(0, expiresAt.timeIntervalSince(now)) }
}

/// The list of temporary shots the app is tracking. Pure logic, no PhotoKit, so it is unit tested.
struct Ledger: Codable, Equatable {
    private(set) var shots: [Shot] = []

    /// Track a newly saved asset. A `nil` lifetime (Never) means the app does not track it at all:
    /// it is an ordinary photo from then on. `timeScale` > 1 is the fast-forward QA mode.
    @discardableResult
    mutating func track(id: String, capturedAt: Date, lifetime: Lifetime, timeScale: Double = 1) -> Shot? {
        guard let seconds = lifetime.seconds else { return nil }
        guard !shots.contains(where: { $0.id == id }) else { return nil }
        let scale = timeScale > 0 ? timeScale : 1
        let shot = Shot(id: id, capturedAt: capturedAt, expiresAt: capturedAt.addingTimeInterval(seconds / scale))
        shots.append(shot)
        return shot
    }

    /// Stop tracking (Keep, Delete now, cleared, or gone from the library).
    mutating func forget(_ ids: some Sequence<String>) {
        let drop = Set(ids)
        shots.removeAll { drop.contains($0.id) }
    }

    func contains(_ id: String) -> Bool { shots.contains { $0.id == id } }

    func expired(at now: Date) -> [Shot] {
        shots.filter { $0.isExpired(at: now) }.sorted { $0.capturedAt < $1.capturedAt }
    }

    /// Newest first, for the strip. Expired shots stay listed until cleared.
    func recent(at now: Date) -> [Shot] {
        shots.sorted { $0.capturedAt > $1.capturedAt }
    }

    /// The identifiers the app may delete right now: expired AND tracked. Anything else is never returned.
    func deletable(at now: Date) -> [String] { expired(at: now).map(\.id) }

    /// When the next tracked shot expires, so the UI can refresh then.
    func nextExpiry(after now: Date) -> Date? {
        shots.map(\.expiresAt).filter { $0 > now }.min()
    }

    /// One line for the home screen: "3 photos. Next one expires in 5 hours." `nil` when nothing is tracked.
    func summary(at now: Date) -> String? {
        let n = shots.count
        guard n > 0 else { return nil }
        guard let next = nextExpiry(after: now) else {
            return n == 1 ? "1 photo, expired." : "\(n) photos, all expired."
        }
        let phrase = durationPhrase(next.timeIntervalSince(now))
        return n == 1 ? "1 photo. It expires in \(phrase)." : "\(n) photos. Next one expires in \(phrase)."
    }
}

/// Short time-left label for a thumbnail: "6d", "23h", "45m", "30s", "Expired".
func remainingLabel(_ seconds: TimeInterval) -> String {
    if seconds <= 0 { return "Expired" }
    let s = Int(seconds.rounded(.up))
    if s >= 86_400 { return "\(s / 86_400)d" }
    if s >= 3600 { return "\(s / 3600)h" }
    if s >= 60 { return "\(s / 60)m" }
    return "\(s)s"
}

/// Longer phrase for the viewer: "Expires in 23 hours", "Expired".
func remainingPhrase(_ seconds: TimeInterval) -> String {
    seconds <= 0 ? "Expired" : "Expires in " + durationPhrase(seconds)
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

/// Saves the ledger as a small JSON file in Application Support. Identifiers and dates only, no image data.
struct LedgerFile {
    let url: URL

    static var standard: LedgerFile {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LedgerFile(url: dir.appendingPathComponent("ledger.json"))
    }

    func load() -> Ledger {
        guard let data = try? Data(contentsOf: url) else { return Ledger() }
        return (try? JSONDecoder().decode(Ledger.self, from: data)) ?? Ledger()
    }

    func save(_ ledger: Ledger) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(ledger)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            QALog.write("ledger save failed: \(error)")
        }
    }

    func reset() { try? FileManager.default.removeItem(at: url) }
}
