import FamilyControls
import Foundation

final class FamilyActivitySelectionStore {
    private let defaults: UserDefaults
    private let key = "FamilyActivitySelection.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> FamilyActivitySelection {
        guard let data = defaults.data(forKey: key) else {
            return FamilyActivitySelection()
        }

        do {
            return try PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
        } catch {
            return FamilyActivitySelection()
        }
    }

    func save(_ selection: FamilyActivitySelection) {
        guard let data = try? PropertyListEncoder().encode(selection) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
