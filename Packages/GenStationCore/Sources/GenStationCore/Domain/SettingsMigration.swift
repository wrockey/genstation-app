import Foundation

/// One-time `UserDefaults` key migrations.
///
/// It lives in the package, not next to the `@AppStorage` declaration, because a migration that
/// cannot be tested is a migration nobody can trust: the app target has no XCTest target, and this
/// one is exactly the kind of code whose failure mode is silent and only visible to a user who
/// already had the app installed.
public enum SettingsMigration {

    /// The old key. Its name meant the **opposite** of both its label and its behaviour: `true`
    /// selected advanced mode, in which every model the API serves is listed.
    public static let legacyShowAllAIMLModelsKey = "useSupportedModelsOnly"

    /// The new key, taking its wording from the two toggles that write it, both labelled
    /// "Show all available AI/ML models".
    public static let showAllAIMLModelsKey = "showAllAIMLModels"

    /// Copies the legacy advanced-list flag onto its new key, once.
    ///
    /// Safe to call on every launch and safe on a fresh install. Three properties, each tested:
    ///
    /// - **Never overwrites.** If the new key already has a value, the user has been migrated (or
    ///   has since changed their mind) and this returns immediately.
    /// - **Writes nothing when there is nothing to migrate.** A fresh install ends with neither key
    ///   set, so `@AppStorage`'s declared default still applies and a future change of that default
    ///   would still reach the install.
    /// - **Leaves the legacy key in place.** It costs one boolean and it is the only surviving
    ///   record of the pre-rename choice.
    ///
    /// - Returns: true only when it actually wrote.
    @discardableResult
    public static func migrateShowAllAIMLModels(in defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: showAllAIMLModelsKey) == nil else { return false }
        guard let legacy = defaults.object(forKey: legacyShowAllAIMLModelsKey) as? Bool else {
            return false
        }
        defaults.set(legacy, forKey: showAllAIMLModelsKey)
        return true
    }
}
