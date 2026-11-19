import Foundation
import TypetickCore
import TypetickScene

struct Preferences: Codable, Equatable {
    init() {}

    var machine = MachineConfiguration.standard
    var paper = PaperStyle()
    var ink = InkStyle()
    var typeface = TypefaceStyle()
    var desk = DeskStyle()
    var environment = EnvironmentStyle()
    var framing: StageFraming = .seated
    var look = RenderLook()
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

    /// Tolerates preferences saved by older builds (missing keys fall back to defaults).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        machine = (try? c.decode(MachineConfiguration.self, forKey: .machine)) ?? d.machine
        paper = (try? c.decode(PaperStyle.self, forKey: .paper)) ?? d.paper
        ink = (try? c.decode(InkStyle.self, forKey: .ink)) ?? d.ink
        typeface = (try? c.decode(TypefaceStyle.self, forKey: .typeface)) ?? d.typeface
        desk = (try? c.decode(DeskStyle.self, forKey: .desk)) ?? d.desk
        environment = (try? c.decode(EnvironmentStyle.self, forKey: .environment)) ?? d.environment
        framing = (try? c.decode(StageFraming.self, forKey: .framing)) ?? d.framing
        look = (try? c.decode(RenderLook.self, forKey: .look)) ?? d.look
        paperDPI = (try? c.decode(Double.self, forKey: .paperDPI)) ?? d.paperDPI
        volume = (try? c.decode(Double.self, forKey: .volume)) ?? d.volume
        soundEnabled = (try? c.decode(Bool.self, forKey: .soundEnabled)) ?? d.soundEnabled
        roomReverb = (try? c.decode(Double.self, forKey: .roomReverb)) ?? d.roomReverb
        machineSettings = (try? c.decode(MachineSettings.self, forKey: .machineSettings)) ?? d.machineSettings
        controlClipboard = (try? c.decode(Bool.self, forKey: .controlClipboard)) ?? d.controlClipboard
        showHUD = (try? c.decode(Bool.self, forKey: .showHUD)) ?? d.showHUD
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Preferences.key) }
    }
}
