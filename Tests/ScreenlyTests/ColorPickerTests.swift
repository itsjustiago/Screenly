import XCTest
import AppKit
@testable import Screenly

/// Covers the colour-picker output: the hex the sampler produces and the RGB/CSS
/// strings the result toast copies. These are what actually land on the clipboard.
final class ColorPickerTests: XCTestCase {

    // MARK: NSColor → hex (what the sampler returns)

    func testHexFromPrimaries() {
        XCTAssertEqual(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).hexStringSRGB, "#FF0000")
        XCTAssertEqual(NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1).hexStringSRGB, "#00FF00")
        XCTAssertEqual(NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1).hexStringSRGB, "#0000FF")
    }

    func testHexBlackAndWhite() {
        XCTAssertEqual(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1).hexStringSRGB, "#000000")
        XCTAssertEqual(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1).hexStringSRGB, "#FFFFFF")
    }

    func testHexRoundsChannels() {
        // 136/255 ≈ 0.5333 — must round-trip back to 0x88.
        XCTAssertEqual(NSColor(srgbRed: 136.0/255, green: 0, blue: 1, alpha: 1).hexStringSRGB, "#8800FF")
    }

    // MARK: hex → RGB / CSS (what the toast copies)

    func testRGBComponents() {
        let c = ColorFormats.rgbComponents("#FF8800")
        XCTAssertEqual(c.r, 255)
        XCTAssertEqual(c.g, 136)
        XCTAssertEqual(c.b, 0)
    }

    func testRGBComponentsToleratesMissingHash() {
        let c = ColorFormats.rgbComponents("00FF00")
        XCTAssertEqual(c.r, 0)
        XCTAssertEqual(c.g, 255)
        XCTAssertEqual(c.b, 0)
    }

    func testRGBAndCSSStrings() {
        XCTAssertEqual(ColorFormats.rgb("#FF8800"), "255, 136, 0")
        XCTAssertEqual(ColorFormats.css("#FF8800"), "rgb(255, 136, 0)")
    }

    // MARK: History (dedup + cap + most-recent-first)

    func testHistoryDedupesAndKeepsNewestFirst() {
        let key = "recentColors"
        let d = UserDefaults.standard
        let saved = d.stringArray(forKey: key)
        defer { d.set(saved, forKey: key) }
        d.removeObject(forKey: key)

        ColorHistory.add("#111111")
        ColorHistory.add("#222222")
        ColorHistory.add("#111111")          // re-picking bumps it to the front, no duplicate

        XCTAssertEqual(ColorHistory.colors, ["#111111", "#222222"])
    }

    func testHistoryIsCappedAtEight() {
        let key = "recentColors"
        let d = UserDefaults.standard
        let saved = d.stringArray(forKey: key)
        defer { d.set(saved, forKey: key) }
        d.removeObject(forKey: key)

        for i in 0..<12 { ColorHistory.add(String(format: "#0000%02X", i)) }

        XCTAssertEqual(ColorHistory.colors.count, 8)
        XCTAssertEqual(ColorHistory.colors.first, "#00000B")   // the most recently added
    }
}
