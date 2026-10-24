import Foundation

enum AppLanguage: String, CaseIterable, Codable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var nativeName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    static func resolve(in defaults: UserDefaults) -> AppLanguage {
        // English is the product default, independent of the Mac's language.
        defaults.string(forKey: "interfaceLanguage").flatMap(AppLanguage.init(rawValue:)) ?? .english
    }
}

enum L10n {
    private static let lock = NSLock()
    private static var preferences = UserDefaults.standard
    private static var current = AppLanguage.resolve(in: .standard)

    static var language: AppLanguage {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    /// Media track selection follows the Mac's language preferences, while
    /// interface language is an independent, app-specific choice.
    static var mediaPreferredLanguages: [String] {
        // Read only the user's language setting through Core Foundation. Keep
        // UserDefaults limited to this app's own preferences (privacy CA92.1).
        // Locale.preferredLanguages includes our app-specific UI override.
        if let languages = CFPreferencesCopyValue("AppleLanguages" as CFString,
                                                  kCFPreferencesAnyApplication,
                                                  kCFPreferencesCurrentUser,
                                                  kCFPreferencesAnyHost) as? [String], !languages.isEmpty {
            return languages
        }
        return Locale.preferredLanguages
    }

    /// Call before creating AppKit objects so native dialogs also start in the
    /// chosen language. An injectable store keeps verification out of user data.
    static func configure(defaults: UserDefaults = .standard, applySystemLanguage: Bool = true) {
        let selected = AppLanguage.resolve(in: defaults)
        lock.lock()
        preferences = defaults
        current = selected
        lock.unlock()
        if applySystemLanguage { defaults.set([selected.rawValue], forKey: "AppleLanguages") }
    }

    static func select(_ language: AppLanguage) {
        lock.lock()
        current = language
        let defaults = preferences
        lock.unlock()
        defaults.set(language.rawValue, forKey: "interfaceLanguage")
        defaults.set([language.rawValue], forKey: "AppleLanguages")
    }

    static func text(_ english: String, _ chinese: String) -> String {
        language == .english ? english : chinese
    }

    static func format(_ english: String, _ chinese: String, _ arguments: CVarArg...) -> String {
        let selected = language
        return String(format: selected == .english ? english : chinese,
                      locale: Locale(identifier: selected.rawValue), arguments: arguments)
    }
}
