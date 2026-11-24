import Foundation

/// Launch switches for testing, read from the environment (simulator: SIMCTL_CHILD_TMP_*,
/// UI tests: launchEnvironment). All off in a normal launch. See qa/README.md.
enum QA {
    private static let env = ProcessInfo.processInfo.environment

    /// TMP_MOCK_CAMERA=1: generated frames instead of the camera. Always on in the simulator, which has no camera.
    static var mockCamera: Bool {
        #if targetEnvironment(simulator)
        return env["TMP_MOCK_CAMERA"] != "0"
        #else
        return env["TMP_MOCK_CAMERA"] == "1"
        #endif
    }

    /// TMP_TIME_SCALE=N: lifetimes run N times faster (3600 makes an hour last a second).
    static var timeScale: Double {
        guard let raw = env["TMP_TIME_SCALE"], let n = Double(raw), n > 0 else { return 1 }
        return n
    }

    /// TMP_RESET=1: delete every shot and setting at launch (fresh first run).
    static var reset: Bool { env["TMP_RESET"] == "1" }

    /// TMP_LIFETIME=oneHour|oneDay|...: start with this lifetime setting.
    static var lifetime: Lifetime? { env["TMP_LIFETIME"].flatMap(Lifetime.init(rawValue:)) }

    /// TMP_QA_LOG=1: write a plain log to Documents/tmp.log (identifiers and events only).
    static var log: Bool { env["TMP_QA_LOG"] == "1" }

    #if DEBUG
    /// TMP_DEMO_PHOTOS=1 (debug builds only): for App Store screenshots. The mock camera shows and saves
    /// stand-in photos (DemoScenes: a parking level sign, a receipt, a router sticker...) instead of numbered
    /// test frames, and the "Test mode" pill and Settings' Testing section are hidden.
    static var demoPhotos: Bool { env["TMP_DEMO_PHOTOS"] == "1" }

    /// TMP_DEMO_AGES=20,16,12.5 (debug builds only): hours to backdate the capture time of shot 1, 2, 3...
    /// of a camera visit, so App Store screenshots show real "23h" labels without the fast clock (which
    /// shows its times in seconds). Shots past the list are not backdated.
    static func demoAge(shot number: Int) -> TimeInterval {
        let ages = (env["TMP_DEMO_AGES"] ?? "").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return number >= 1 && number <= ages.count ? ages[number - 1] * 3600 : 0
    }
    #else
    static var demoPhotos: Bool { false }
    static func demoAge(shot number: Int) -> TimeInterval { 0 }
    #endif

    static var anyActive: Bool { timeScale != 1 || env["TMP_MOCK_CAMERA"] == "1" }
}

/// Opt-in QA log. Nothing is written unless TMP_QA_LOG=1.
enum QALog {
    private static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("tmp.log")
    private static let queue = DispatchQueue(label: "qalog")

    static func reset() { try? FileManager.default.removeItem(at: url) }

    static func write(_ line: String) {
        guard QA.log else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp) \(line)\n"
        queue.async {
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(text.utf8))
                try? h.close()
            } else {
                try? Data(text.utf8).write(to: url)
            }
        }
    }
}
