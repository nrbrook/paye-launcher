import Foundation

/// User settings of PAYE Launcher.
public struct Preferences {
    public static let runtimeKey = "runtime"
    public static let zoomKey = "pageZoom"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The runtime that the user wants. The default is native.
    public var runtime: RuntimeKind {
        get { defaults.string(forKey: Self.runtimeKey).flatMap(RuntimeKind.init(rawValue:)) ?? .native }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.runtimeKey) }
    }

    /// Page zoom, from 0.5 to 3.0. The default is 1.0.
    public var pageZoom: Double {
        get {
            let value = defaults.double(forKey: Self.zoomKey)
            return value > 0 ? Self.clampZoom(value) : 1.0
        }
        nonmutating set { defaults.set(Self.clampZoom(newValue), forKey: Self.zoomKey) }
    }

    public static func clampZoom(_ value: Double) -> Double {
        min(3.0, max(0.5, (value * 10).rounded() / 10))
    }
}
