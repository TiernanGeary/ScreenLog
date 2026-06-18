import FamilyControls
import Foundation

enum BlockingSelectionCodec {
    static func encode(_ selection: FamilyActivitySelection) throws -> Data {
        try PropertyListEncoder().encode(selection)
    }

    static func decode(_ data: Data) throws -> FamilyActivitySelection {
        try PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
    }
}
