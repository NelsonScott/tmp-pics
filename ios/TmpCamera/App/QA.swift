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

    /// TMP_RESET=1: forget every tracked shot and setting at launch (fresh first run). Photos are not touched.
    static var reset: Bool { env["TMP_RESET"] == "1" }

    /// TMP_LIFETIME=oneHour|oneDay|...: start with this lifetime setting.
    static var lifetime: Lifetime? { env["TMP_LIFETIME"].flatMap(Lifetime.init(rawValue:)) }

    /// TMP_QA_LOG=1: write a plain log to Documents/tmp.log (identifiers and events only).
    static var log: Bool { env["TMP_QA_LOG"] == "1" }

    #if DEBUG
    /// TMP_QA_SEED_FOREIGN=1 (debug builds only): after Photos access is granted, add one photo to the
    /// album that the app does NOT track, to prove Clear never deletes anything else.
    static var seedForeign: Bool { env["TMP_QA_SEED_FOREIGN"] == "1" }
    #else
    static var seedForeign: Bool { false }
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
