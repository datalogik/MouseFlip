public enum InputDevice: String {
    case mouse = "Mouse", trackpad = "Trackpad", smooth = "Smooth input", unknown = "Waiting for input"
}

public enum ScrollPolicy {
    public static func direction(for device: InputDevice, mouse: Bool, trackpad: Bool,
                                 unidentifiedSmoothUsesMouse: Bool, system: Bool) -> Bool {
        switch device {
        case .mouse: return mouse
        case .trackpad: return trackpad
        case .smooth: return unidentifiedSmoothUsesMouse ? mouse : trackpad
        case .unknown: return system
        }
    }

    public static func isExternalMouse(product: String, builtIn: Bool) -> Bool {
        let name = product.lowercased()
        return !builtIn && !name.contains("trackpad") && !name.contains("touchpad")
    }
}
