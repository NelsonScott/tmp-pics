#if DEBUG
import UIKit

/// TMP_DEMO_PHOTOS=1 (debug builds only): plausible stand-in photos for App Store screenshots, drawn here so
/// nothing is downloaded and nothing is copyrighted. Each is the kind of thing the app is for: where you
/// parked, a receipt, a router sticker, a printer test page, a sticky note, a paint chip. No people.
/// The mock camera shows scene N in the viewfinder and saves it as shot N.
@MainActor
enum DemoScenes {
    static let size = CGSize(width: 1200, height: 1600)
    private static var cache: [Int: UIImage] = [:]

    /// Scene for shot `number` (1-based), cycling through the six.
    static func photo(_ number: Int) -> UIImage {
        let index = (max(number, 1) - 1) % 6
        if let hit = cache[index] { return hit }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            switch index {
            case 0: parking(cg)
            case 1: receipt(cg)
            case 2: routerLabel(cg)
            case 3: testPage(cg)
            case 4: stickyNote(cg)
            default: paintChip(cg)
            }
        }
        cache[index] = image
        return image
    }

    // MARK: Scenes

    /// A painted level marker on a concrete pillar in a parking garage.
    private static func parking(_ cg: CGContext) {
        fillGradient(cg, rgb(0x9a9c9e), rgb(0x707274))
        speckle(cg, seed: 3, count: 900, alpha: 0.10)
        // form lines in the concrete
        cg.setStrokeColor(UIColor.black.withAlphaComponent(0.12).cgColor)
        cg.setLineWidth(3)
        for y in stride(from: 180.0, to: 1600, by: 330) {
            cg.move(to: CGPoint(x: 0, y: y)); cg.addLine(to: CGPoint(x: 1200, y: y + 6)); cg.strokePath()
        }
        // blue disc with the level number
        cg.setFillColor(rgb(0x1f5fae).cgColor)
        cg.fillEllipse(in: CGRect(x: 260, y: 260, width: 680, height: 680))
        text("3", in: CGRect(x: 260, y: 330, width: 680, height: 560), font: .systemFont(ofSize: 470, weight: .heavy), color: .white)
        text("LEVEL 3", in: CGRect(x: 100, y: 990, width: 1000, height: 150), font: .systemFont(ofSize: 120, weight: .heavy), color: .white)
        // row sign
        cg.setFillColor(rgb(0x2e7d32).cgColor)
        cg.fill(CGRect(x: 330, y: 1160, width: 540, height: 170))
        text("ROW C", in: CGRect(x: 330, y: 1178, width: 540, height: 140), font: .systemFont(ofSize: 110, weight: .bold), color: .white)
        // hazard stripe at the foot of the pillar
        cg.saveGState()
        cg.clip(to: CGRect(x: 0, y: 1440, width: 1200, height: 160))
        cg.setFillColor(rgb(0xf2c200).cgColor)
        cg.fill(CGRect(x: 0, y: 1440, width: 1200, height: 160))
        cg.setFillColor(rgb(0x1b1b1b).cgColor)
        for x in stride(from: -200.0, to: 1400, by: 160) {
            cg.move(to: CGPoint(x: x, y: 1600)); cg.addLine(to: CGPoint(x: x + 80, y: 1600))
            cg.addLine(to: CGPoint(x: x + 240, y: 1440)); cg.addLine(to: CGPoint(x: x + 160, y: 1440)); cg.fillPath()
        }
        cg.restoreGState()
        vignette(cg)
    }

    /// A shop receipt on a wooden table.
    private static func receipt(_ cg: CGContext) {
        wood(cg)
        onCard(cg, rect: CGRect(x: 250, y: 120, width: 700, height: 1380), angle: -0.05, fill: rgb(0xf8f5ee)) {
            let mono = UIFont.monospacedSystemFont(ofSize: 40, weight: .medium)
            let bold = UIFont.monospacedSystemFont(ofSize: 52, weight: .bold)
            let ink = rgb(0x2b2b2b)
            text("CORNER MARKET", in: CGRect(x: 0, y: 80, width: 700, height: 70), font: bold, color: ink)
            text("Thank you!", in: CGRect(x: 0, y: 160, width: 700, height: 50), font: mono, color: ink)
            let rows = [("Coffee beans", "12.99"), ("Oat milk", "4.49"), ("Bananas", "1.86"), ("Sourdough", "5.25"),
                        ("Eggs, dozen", "3.79"), ("Tomatoes", "2.40")]
            var y: CGFloat = 300
            for (item, price) in rows {
                text(item, in: CGRect(x: 60, y: y, width: 420, height: 50), font: mono, color: ink, align: .left)
                text(price, in: CGRect(x: 420, y: y, width: 220, height: 50), font: mono, color: ink, align: .right)
                y += 70
            }
            text(String(repeating: "-", count: 26), in: CGRect(x: 0, y: y + 10, width: 700, height: 50), font: mono, color: ink)
            text("TOTAL", in: CGRect(x: 60, y: y + 80, width: 300, height: 60), font: bold, color: ink, align: .left)
            text("30.78", in: CGRect(x: 360, y: y + 80, width: 280, height: 60), font: bold, color: ink, align: .right)
            text("11/23  09:14", in: CGRect(x: 0, y: y + 220, width: 700, height: 50), font: mono, color: ink)
            barcode(seed: 11, in: CGRect(x: 130, y: y + 320, width: 440, height: 120), color: ink)
        }
        vignette(cg)
    }

    /// The sticker under a Wi-Fi router, on a cardboard box.
    private static func routerLabel(_ cg: CGContext) {
        fillGradient(cg, rgb(0xc9a274), rgb(0xa8814f))
        speckle(cg, seed: 7, count: 700, alpha: 0.08)
        cg.setStrokeColor(UIColor.black.withAlphaComponent(0.10).cgColor)
        cg.setLineWidth(4)
        cg.move(to: CGPoint(x: 0, y: 260)); cg.addLine(to: CGPoint(x: 1200, y: 250)); cg.strokePath()
        onCard(cg, rect: CGRect(x: 120, y: 420, width: 960, height: 820), angle: 0.03, fill: rgb(0xfbfbfb)) {
            let ink = rgb(0x222222)
            let label = UIFont.systemFont(ofSize: 44, weight: .semibold)
            let value = UIFont.monospacedSystemFont(ofSize: 62, weight: .bold)
            text("Wireless router  AX1800", in: CGRect(x: 60, y: 60, width: 840, height: 60), font: label, color: ink, align: .left)
            cg.setFillColor(ink.cgColor); cg.fill(CGRect(x: 60, y: 140, width: 840, height: 4))
            text("Network name", in: CGRect(x: 60, y: 190, width: 840, height: 56), font: label, color: rgb(0x555555), align: .left)
            text("HOME-4821", in: CGRect(x: 60, y: 250, width: 840, height: 80), font: value, color: ink, align: .left)
            text("Password", in: CGRect(x: 60, y: 370, width: 840, height: 56), font: label, color: rgb(0x555555), align: .left)
            text("maple-river-42", in: CGRect(x: 60, y: 430, width: 840, height: 80), font: value, color: ink, align: .left)
            barcode(seed: 5, in: CGRect(x: 60, y: 580, width: 560, height: 150), color: ink)
            text("S/N 7A21-0937", in: CGRect(x: 640, y: 640, width: 280, height: 50), font: .systemFont(ofSize: 34, weight: .medium), color: ink, align: .left)
        }
        vignette(cg)
    }

    /// A printer test page on a grey desk.
    private static func testPage(_ cg: CGContext) {
        fillGradient(cg, rgb(0x5d6166), rgb(0x3f4246))
        speckle(cg, seed: 13, count: 600, alpha: 0.06)
        onCard(cg, rect: CGRect(x: 170, y: 130, width: 860, height: 1240), angle: 0.04, fill: .white) {
            let ink = rgb(0x1e1e1e)
            text("Print test page", in: CGRect(x: 70, y: 70, width: 720, height: 70), font: .systemFont(ofSize: 58, weight: .bold), color: ink, align: .left)
            text("Nozzle check", in: CGRect(x: 70, y: 150, width: 720, height: 50), font: .systemFont(ofSize: 38, weight: .regular), color: rgb(0x666666), align: .left)
            let colors = [rgb(0x00a3e0), rgb(0xe0218a), rgb(0xffd400), rgb(0x111111)]
            for (i, color) in colors.enumerated() {
                let x = 70 + CGFloat(i) * 185
                cg.setFillColor(color.cgColor)
                cg.fill(CGRect(x: x, y: 260, width: 165, height: 300))
            }
            // a faint missing line in the yellow, the reason you took the picture
            cg.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
            cg.fill(CGRect(x: 440, y: 400, width: 165, height: 8))
            for i in 0..<8 {
                let gray = CGFloat(i) / 8
                cg.setFillColor(UIColor(white: gray, alpha: 1).cgColor)
                cg.fill(CGRect(x: 70 + CGFloat(i) * 90, y: 620, width: 90, height: 120))
            }
            cg.setFillColor(rgb(0xc9c9c9).cgColor)
            for row in 0..<6 {
                let width: CGFloat = row % 3 == 2 ? 460 : 720
                cg.fill(CGRect(x: 70, y: 810 + CGFloat(row) * 56, width: width, height: 22))
            }
        }
        vignette(cg)
    }

    /// A sticky note on a desk.
    private static func stickyNote(_ cg: CGContext) {
        wood(cg, light: true)
        onCard(cg, rect: CGRect(x: 190, y: 330, width: 820, height: 820), angle: -0.06, fill: rgb(0xfde86a)) {
            let hand = UIFont(name: "Noteworthy-Bold", size: 92) ?? .systemFont(ofSize: 88, weight: .semibold)
            let ink = rgb(0x1d3f8f)
            text("Call plumber back", in: CGRect(x: 50, y: 120, width: 720, height: 130), font: hand, color: ink, align: .left)
            text("Tue 3:30", in: CGRect(x: 50, y: 290, width: 720, height: 130), font: hand, color: ink, align: .left)
            text("555-0142", in: CGRect(x: 50, y: 460, width: 720, height: 130), font: hand, color: ink, align: .left)
        }
        vignette(cg)
    }

    /// A paint chip held against a wall.
    private static func paintChip(_ cg: CGContext) {
        fillGradient(cg, rgb(0xe9e4da), rgb(0xcfc8bb))
        speckle(cg, seed: 17, count: 500, alpha: 0.05)
        onCard(cg, rect: CGRect(x: 280, y: 170, width: 640, height: 1260), angle: 0.02, fill: .white) {
            let swatches = [(rgb(0xc9dbe8), "Mist"), (rgb(0x8fb1cc), "Lake"), (rgb(0x4f7fa6), "Harbor Blue"), (rgb(0x2c4f6e), "Deep Sea")]
            for (i, (color, name)) in swatches.enumerated() {
                let y = 40 + CGFloat(i) * 280
                cg.setFillColor(color.cgColor)
                cg.fill(CGRect(x: 40, y: y, width: 560, height: 210))
                text(name, in: CGRect(x: 40, y: y + 214, width: 400, height: 50), font: .systemFont(ofSize: 36, weight: .semibold), color: rgb(0x333333), align: .left)
                text("40\(21 + i)", in: CGRect(x: 420, y: y + 214, width: 180, height: 50), font: .systemFont(ofSize: 36, weight: .regular), color: rgb(0x666666), align: .right)
            }
        }
        vignette(cg)
    }

    // MARK: Drawing helpers

    private static func rgb(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }

    private static func fillGradient(_ cg: CGContext, _ top: UIColor, _ bottom: UIColor) {
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
        cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width * 0.3, y: size.height),
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// Deterministic flecks, so the surface does not look like flat paint.
    private static func speckle(_ cg: CGContext, seed: UInt64, count: Int, alpha: CGFloat) {
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 33) % 10_000) / 10_000
        }
        for _ in 0..<count {
            let dark = next() > 0.5
            cg.setFillColor((dark ? UIColor.black : UIColor.white).withAlphaComponent(alpha * (0.5 + next())).cgColor)
            let r = 2 + next() * 5
            cg.fillEllipse(in: CGRect(x: next() * size.width, y: next() * size.height, width: r, height: r))
        }
    }

    private static func wood(_ cg: CGContext, light: Bool = false) {
        fillGradient(cg, light ? rgb(0xb88a5a) : rgb(0x8a5a35), light ? rgb(0x9a6d42) : rgb(0x6a4126))
        cg.setLineWidth(3)
        for i in 0..<28 {
            let y = CGFloat(i) * 60 + CGFloat((i * 37) % 23)
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.06 + CGFloat(i % 3) * 0.03).cgColor)
            cg.move(to: CGPoint(x: 0, y: y))
            cg.addCurve(to: CGPoint(x: 1200, y: y + 20), control1: CGPoint(x: 400, y: y - 18), control2: CGPoint(x: 800, y: y + 30))
            cg.strokePath()
        }
    }

    /// Darker corners, like a phone photo.
    private static func vignette(_ cg: CGContext) {
        let colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.28).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.55, 1])!
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.height * 0.62, options: [.drawsAfterEndLocation])
    }

    /// A paper card with a soft shadow, turned slightly; `draw` works in the card's own coordinates.
    private static func onCard(_ cg: CGContext, rect: CGRect, angle: CGFloat, fill: UIColor, draw: () -> Void) {
        cg.saveGState()
        cg.translateBy(x: rect.midX, y: rect.midY)
        cg.rotate(by: angle)
        cg.translateBy(x: -rect.width / 2, y: -rect.height / 2)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: UIColor.black.withAlphaComponent(0.45).cgColor)
        cg.setFillColor(fill.cgColor)
        cg.fill(CGRect(origin: .zero, size: rect.size))
        cg.restoreGState()
        UIGraphicsPushContext(cg)
        draw()
        UIGraphicsPopContext()
        cg.restoreGState()
    }

    private static func text(_ string: String, in rect: CGRect, font: UIFont, color: UIColor, align: NSTextAlignment = .center) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        (string as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    private static func barcode(seed: Int, in rect: CGRect, color: UIColor) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.setFillColor(color.cgColor)
        var x = rect.minX
        var i = seed
        while x < rect.maxX - 6 {
            i = (i * 1103515245 + 12345) & 0x7fffffff
            let w = CGFloat(2 + (i >> 8) % 7)
            if (i >> 4) % 3 != 0 { cg.fill(CGRect(x: x, y: rect.minY, width: w, height: rect.height)) }
            x += w + CGFloat(2 + (i >> 12) % 4)
        }
    }
}
#endif
