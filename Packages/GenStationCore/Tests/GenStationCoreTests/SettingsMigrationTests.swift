// The one-time key rename (design § 4.7).
//
// `@AppStorage` keys on a string. Renaming one without a migration does not reset a value to its
// default in some abstract sense — it makes the stored value unreachable, which for this flag means
// silently putting every existing user back into curated mode and taking away the 164 unregistered
// models advanced mode exists to reach.

import XCTest
@testable import GenStationCore

final class SettingsMigrationTests: XCTestCase {

    private let suiteName = "art.genstation.app.SettingsMigrationTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private var legacy: String { SettingsMigration.legacyShowAllAIMLModelsKey }
    private var current: String { SettingsMigration.showAllAIMLModelsKey }

    func testTheTwoKeysAreTheOnesTheAppUses() {
        XCTAssertEqual(legacy, "useSupportedModelsOnly")
        XCTAssertEqual(current, "showAllAIMLModels")
    }

    /// A fresh install has neither key. The migration must write nothing at all — writing `false`
    /// would look identical in behaviour but would make the key "user-set" forever, so a later
    /// change of default could never reach that install.
    func testAFreshInstallWritesNothing() {
        XCTAssertFalse(SettingsMigration.migrateShowAllAIMLModels(in: defaults))
        XCTAssertNil(defaults.object(forKey: current))
        XCTAssertNil(defaults.object(forKey: legacy))
    }

    /// The case that matters: an existing advanced-mode user stays in advanced mode.
    func testAnExistingTrueValueMigrates() {
        defaults.set(true, forKey: legacy)
        XCTAssertTrue(SettingsMigration.migrateShowAllAIMLModels(in: defaults))
        XCTAssertEqual(defaults.object(forKey: current) as? Bool, true)
    }

    /// And an explicit `false` migrates too — it is a user decision, not an absence.
    func testAnExistingFalseValueMigrates() {
        defaults.set(false, forKey: legacy)
        XCTAssertTrue(SettingsMigration.migrateShowAllAIMLModels(in: defaults))
        XCTAssertEqual(defaults.object(forKey: current) as? Bool, false)
    }

    func testItIsIdempotent() {
        defaults.set(true, forKey: legacy)
        XCTAssertTrue(SettingsMigration.migrateShowAllAIMLModels(in: defaults))
        XCTAssertFalse(SettingsMigration.migrateShowAllAIMLModels(in: defaults))
        XCTAssertFalse(SettingsMigration.migrateShowAllAIMLModels(in: defaults))
        XCTAssertEqual(defaults.object(forKey: current) as? Bool, true)
    }

    /// It runs on every launch, so it must never overwrite a choice made after the migration.
    func testItNeverOverwritesAnAlreadyMigratedValue() {
        defaults.set(true, forKey: legacy)
        defaults.set(false, forKey: current)          // the user turned it off post-rename
        XCTAssertFalse(SettingsMigration.migrateShowAllAIMLModels(in: defaults))
        XCTAssertEqual(defaults.object(forKey: current) as? Bool, false)
    }

    /// The legacy key is kept, not deleted. It costs one boolean, it is the only record of what the
    /// user's mode was before the rename if the migration is ever found to be wrong, and keeping it
    /// makes the "new key removed" case self-heal on the next launch.
    func testTheLegacyKeyIsLeftInPlace() {
        defaults.set(true, forKey: legacy)
        XCTAssertTrue(SettingsMigration.migrateShowAllAIMLModels(in: defaults))
        XCTAssertEqual(defaults.object(forKey: legacy) as? Bool, true)
    }
}
