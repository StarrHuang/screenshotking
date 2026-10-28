import Foundation

/// Resolve user-facing text through the app bundle's system-selected localization.
public func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Keep substitutions outside localization keys so word order can vary by language.
public func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: arguments)
}
