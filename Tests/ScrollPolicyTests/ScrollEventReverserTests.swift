import XCTest
import CoreGraphics
@testable import ScrollPolicy

final class ScrollEventReverserTests: XCTestCase {
    func testEveryRepresentationReversesFromOriginalValue() throws {
        for unit: CGScrollEventUnit in [.line, .pixel] {
            let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: unit,
                wheelCount: 2, wheel1: 3, wheel2: -2, wheel3: 0))
            // Use non-proportional values to verify acceleration/fractions survive.
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 3.25)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -2.5)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 37)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -19)
            let integerFields: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
                .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2]
            let fixedFields: [CGEventField] = [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2]
            let originalIntegers = integerFields.map { event.getIntegerValueField($0) }
            let originalFixed = fixedFields.map { event.getDoubleValueField($0) }
            ScrollEventReverser.reverse(event)
            for (field, original) in zip(integerFields, originalIntegers) {
                XCTAssertEqual(event.getIntegerValueField(field), -original, "Field \(field.rawValue), units \(unit)")
            }
            for (field, original) in zip(fixedFields, originalFixed) {
                XCTAssertEqual(event.getDoubleValueField(field), -original, accuracy: 0.00001)
            }
        }
    }
}
