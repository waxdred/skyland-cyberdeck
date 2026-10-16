import CoreGraphics
import Foundation

// Built-in display brightness through DisplayServices (private, the framework the
// brightness keys use), loaded at run time: nil when it is missing or the main
// display has no software brightness (external monitors need DDC, not done here).

enum Brightness {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getter = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: Get.self) }
    private static let setter = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: Set.self) }

    /// The built-in display, when one is connected.
    private static var builtIn: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(8, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// 0...1
    static func get() -> Float? {
        guard let getter, let display = builtIn else { return nil }
        var value: Float = 0
        return getter(display, &value) == 0 ? value : nil
    }

    static func set(_ value: Float) -> Bool {
        guard let setter, let display = builtIn else { return false }
        return setter(display, min(1, max(0, value))) == 0
    }
}
