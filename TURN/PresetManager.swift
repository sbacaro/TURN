import Foundation
import os.log

struct PresetConfiguration: Codable {
    let mappings: [MIDIMapping]
}

struct MIDIMapping: Codable {
    let hardwareCC: UInt8
    let huiCommand: String
    let name: String
}

/// Loads the MIDI-to-HUI mapping table shipped in DefaultMappings.json.
/// The table mirrors the decoded `smc-mixer-cc.smc` hardware preset:
/// faders on CC 30-37, channel buttons on Note 40-47 (handled as MUTE 1-8),
/// and reserved CCs 48-96 for Solo/Rec/Select/Transport/Bank configuration.
final class PresetManager: ObservableObject, @unchecked Sendable {
    @Published private(set) var currentMappings: [MIDIMapping] = []

    private let logger = Logger(subsystem: "com.samuelbacaro.TURN", category: "preset")

    init() {
        loadDefaultMappings()
    }

    func loadDefaultMappings() {
        guard let url = Bundle.main.url(forResource: "DefaultMappings", withExtension: "json") else {
            logger.error("DefaultMappings.json not found in bundle.")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(PresetConfiguration.self, from: data)
            currentMappings = config.mappings
            logger.info("Presets loaded: \(self.currentMappings.count, privacy: .public) mappings found.")
        } catch {
            logger.error("Error decoding DefaultMappings.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    func mapping(for cc: UInt8) -> MIDIMapping? {
        currentMappings.first { $0.hardwareCC == cc }
    }
}
