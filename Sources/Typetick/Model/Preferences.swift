import Foundation
import TypetickCore
import TypetickScene

struct Preferences: Codable, Equatable {
    var machine = MachineConfiguration.standard
    var paper = PaperStyle()
    var ink = InkStyle()
    var typeface = TypefaceStyle()
    var desk = DeskStyle()
    var environment = EnvironmentStyle()
    var framing: StageFraming = .seated
    var paperDPI: Double = 300
    var volume: Double = 0.8
    var soundEnabled = true
    var roomReverb: Double = 10
    var machineSettings = MachineSettings()
    /// Control-C / X / V drive the mechanical clipboard (Command shortcuts always work).
    var controlClipboard = true
    var showHUD = true

    private static let key = "typetick.preferences.v1"

    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let p = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        return p
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Preferences.key) }
    }
}
