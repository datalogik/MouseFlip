import XCTest
@testable import ScrollPolicy

final class ScrollPolicyTests: XCTestCase {
    func testIndependentDirectionsAndAmbiguousInput() {
        for mouse in [true, false] {
            for pad in [true, false] {
                for fallback in [true, false] {
                    func direction(_ device: InputDevice) -> Bool {
                        ScrollPolicy.direction(for: device, mouse: mouse, trackpad: pad,
                                               unidentifiedSmoothUsesMouse: fallback, system: true)
                    }
                    XCTAssertEqual(direction(.mouse), mouse)
                    XCTAssertEqual(direction(.trackpad), pad)
                    XCTAssertEqual(direction(.smooth), fallback ? mouse : pad)
                    XCTAssertTrue(direction(.unknown))
                }
            }
        }
    }

    func testTrackpadsNeverActivateMouseMode() {
        XCTAssertFalse(ScrollPolicy.isExternalMouse(product: "Apple Internal Keyboard / Trackpad", builtIn: false))
        XCTAssertFalse(ScrollPolicy.isExternalMouse(product: "Magic Trackpad", builtIn: false))
        XCTAssertFalse(ScrollPolicy.isExternalMouse(product: "Pointer", builtIn: true))
        XCTAssertTrue(ScrollPolicy.isExternalMouse(product: "USB Optical Mouse", builtIn: false))
        XCTAssertTrue(ScrollPolicy.isExternalMouse(product: "MX Master", builtIn: false))
    }
}
