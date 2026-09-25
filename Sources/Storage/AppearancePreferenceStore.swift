import AppKit
import Combine
import Foundation

enum AppearancePreference: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var title: String {
        rawValue.capitalized
    }

    var appKitAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

final class AppearancePreferenceStore: ObservableObject {
    @Published private(set) var preference: AppearancePreference

    private let defaults: UserDefaults
    private let defaultsKey = "appearance.preference"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preference = defaults.string(forKey: defaultsKey)
            .flatMap(AppearancePreference.init(rawValue:)) ?? .system
    }

    func setPreference(_ preference: AppearancePreference) {
        guard self.preference != preference else { return }
        defaults.set(preference.rawValue, forKey: defaultsKey)
        self.preference = preference
    }
}
