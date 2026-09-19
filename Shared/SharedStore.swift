import Foundation
import ManagedSettings

/// The app and extension serialize mutations through the same coordinated App Group file.
/// Shield changes happen within the transaction so completion cannot race a new daily lock.
enum SharedStore {
    static let group = "group.com.quranpause.shared"
    static let shield = ManagedSettingsStore(named: .init("QuranPause"))
    static func fileURL() throws -> URL {
        #if targetEnvironment(simulator)
        let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #else
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw NSError(domain: "QuranTime", code: 1, userInfo: [NSLocalizedDescriptionKey: "QuranPause’s shared storage is unavailable. Check the App Group signing configuration."])
        }
        #endif
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("state.json")
    }
    @discardableResult static func transaction(_ update: (inout AppState) -> Void = { _ in }) throws -> AppState {
        let url = try fileURL()
        var coordinationError: NSError?
        var result: Result<AppState, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { location in
            result = Result {
                var state = AppState()
                if FileManager.default.fileExists(atPath: location.path) {
                    state = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: location))
                }
                update(&state)
                try JSONEncoder().encode(state).write(to: location, options: .atomic)
                applyShield(state)
                return state
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
    static func applyShield(_ state: AppState) {
        #if !targetEnvironment(simulator)
        if state.requiresLockdown {
            // iOS applies this device-wide; release it only after every real commitment.
            shield.application.denyAppRemoval = true
            shield.shield.applications = state.selection.applicationTokens.isEmpty ? nil : state.selection.applicationTokens
            shield.shield.applicationCategories = state.selection.categoryTokens.isEmpty ? nil : .specific(state.selection.categoryTokens)
            shield.shield.webDomains = state.selection.webDomainTokens.isEmpty ? nil : state.selection.webDomainTokens
        } else { shield.clearAllSettings() }
        #endif
    }
}
