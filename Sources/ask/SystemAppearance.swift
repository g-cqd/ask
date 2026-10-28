internal import Foundation

/// The macOS appearance, read from the global defaults domain (a system API, no subprocess): `AppleInterfaceStyle` is `Dark` while the
/// system is dark, including when it switches on its own, and absent while it is light.
enum SystemAppearance {
    static var isLight: Bool { UserDefaults.standard.string(forKey: "AppleInterfaceStyle") != "Dark" }
}
