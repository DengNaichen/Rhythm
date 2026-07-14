import Foundation

enum AppIdentity {
  static let legacyBundleIdentifier = "co.dododo.Rhythm"
  static let migrationMarkerKey = "NaichengDeng.Rhythm.didMigrateLegacyConfiguration"
}

private enum LegacyBookmarkStorageKey {
  static let claudeDesktopConfig = "co.dododo.Rhythm.claudeConfigBookmark"
  static let openClawConfig = "co.dododo.Rhythm.openClawConfigBookmark"
  static let thingsDatabase = "co.dododo.Rhythm.thingsDatabaseBookmark"
}

enum AppIdentityMigration {
  static func run() {
    let defaults = UserDefaults.standard

    guard !defaults.bool(forKey: AppIdentity.migrationMarkerKey) else {
      return
    }

    migrateDefaults(using: defaults)
    defaults.set(true, forKey: AppIdentity.migrationMarkerKey)
  }

  private static func migrateDefaults(using defaults: UserDefaults) {
    guard
      let currentBundleIdentifier = Bundle.main.bundleIdentifier,
      let legacyValues = defaults.persistentDomain(forName: AppIdentity.legacyBundleIdentifier),
      !legacyValues.isEmpty
    else {
      return
    }

    var currentValues = defaults.persistentDomain(forName: currentBundleIdentifier) ?? [:]

    for (key, value) in legacyValues where currentValues[key] == nil {
      currentValues[key] = value
    }

    let bookmarkKeyMappings = [
      LegacyBookmarkStorageKey.claudeDesktopConfig: BookmarkStorageKey.claudeDesktopConfig,
      LegacyBookmarkStorageKey.openClawConfig: BookmarkStorageKey.openClawConfig,
      LegacyBookmarkStorageKey.thingsDatabase: BookmarkStorageKey.thingsDatabase,
    ]

    for (legacyKey, currentKey) in bookmarkKeyMappings where currentValues[currentKey] == nil {
      guard let value = legacyValues[legacyKey] else {
        continue
      }

      currentValues[currentKey] = value
    }

    defaults.setPersistentDomain(currentValues, forName: currentBundleIdentifier)
  }
}
