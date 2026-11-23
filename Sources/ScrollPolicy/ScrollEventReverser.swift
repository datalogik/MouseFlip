import CoreGraphics

public enum ScrollEventReverser {
    public static func reverse(_ event: CGEvent) {
        let axes: [(CGEventField, CGEventField, CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1),
            (.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2)
        ]
        // Snapshot all representations before writing: setting a line delta
        // also changes the event's fixed-point and pixel deltas in Core Graphics.
        let original = axes.map { line, fixed, point in
            (event.getIntegerValueField(line), event.getDoubleValueField(fixed), event.getIntegerValueField(point))
        }
        for ((line, fixed, point), (lineValue, fixedValue, pointValue)) in zip(axes, original) {
            event.setIntegerValueField(line, value: negate(lineValue))
            event.setDoubleValueField(fixed, value: -fixedValue)
            event.setIntegerValueField(point, value: negate(pointValue))
        }
    }

    private static func negate(_ value: Int64) -> Int64 {
        value == .min ? .max : -value
    }
}
