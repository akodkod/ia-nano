import AppKit
import XCTest
@testable import IaNano

final class AccentCardTests: XCTestCase {
    @MainActor
    func testEntireCardTracksClicks() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let card = AccentCard(accent: .purple)
        window.contentView!.addSubview(card)
        card.frame = NSRect(x: 20, y: 20, width: 86, height: 72)
        let cell = try XCTUnwrap(card.cell)
        let points: [NSPoint] = [
            NSPoint(x: 43, y: 36),
            NSPoint(x: 10, y: 10), NSPoint(x: 76, y: 10),
            NSPoint(x: 10, y: 62), NSPoint(x: 76, y: 62),
            NSPoint(x: 43, y: 5), NSPoint(x: 43, y: 67),
            NSPoint(x: 4, y: 36), NSPoint(x: 82, y: 36)
        ]
        for point in points {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
                location: card.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            let hit = cell.hitTest(for: event, in: card.bounds, of: card)
            XCTAssertTrue(hit.contains(.trackableArea), "Card must track clicks at \(point); got \(hit)")
        }
        let outside = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: card.convert(NSPoint(x: -2, y: 36), to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        XCTAssertTrue(cell.hitTest(for: outside, in: card.bounds, of: card).isEmpty)
    }
}
