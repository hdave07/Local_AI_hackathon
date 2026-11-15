import FlowCore
@testable import FlowRouting
import Testing

/// Apps come from the installed-app directory, not from a list in the code, and app/window
/// commands are matched by pattern. Phrasings here are deliberately varied (not the checklist's).
@Suite("Generalization: any installed app, varied phrasing", .serialized)
struct GeneralizationTests {
    static let installed: [AppDirectory.Entry] = [
        .init(app: KnownApp(name: "Calculator", bundleIdentifier: "com.apple.calculator"), aliases: ["calc"]),
        .init(app: KnownApp(name: "System Settings", bundleIdentifier: "com.apple.systempreferences"), aliases: ["settings", "system preferences"]),
        .init(app: KnownApp(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode"), aliases: ["vs code", "code"]),
        .init(app: KnownApp(name: "Spotify", bundleIdentifier: "com.spotify.client")),
        .init(app: KnownApp(name: "Google Chrome", bundleIdentifier: "com.google.Chrome"), aliases: ["chrome"]),
        .init(app: KnownApp(name: "TextEdit", bundleIdentifier: "com.apple.TextEdit")),
        .init(app: KnownApp(name: "Preview", bundleIdentifier: "com.apple.Preview")),
        .init(app: KnownApp(name: "Terminal", bundleIdentifier: "com.apple.Terminal")),
        .init(app: KnownApp(name: "Activity Monitor", bundleIdentifier: "com.apple.ActivityMonitor")),
        .init(app: KnownApp(name: "Notes", bundleIdentifier: "com.apple.Notes")),
    ]

    init() { AppDirectory.install(Self.installed) }

    static let calculator = KnownApp(name: "Calculator", bundleIdentifier: "com.apple.calculator")
    static let settings = KnownApp(name: "System Settings", bundleIdentifier: "com.apple.systempreferences")
    static let code = KnownApp(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode")
    static let spotify = KnownApp(name: "Spotify", bundleIdentifier: "com.spotify.client")
    static let monitor = KnownApp(name: "Activity Monitor", bundleIdentifier: "com.apple.ActivityMonitor")
    static let textEdit = KnownApp(name: "TextEdit", bundleIdentifier: "com.apple.TextEdit")

    @Test(arguments: [
        ("Launch Calculator.", FlowAction.activateApp(calculator)),
        ("could you pull up the calculator app", .activateApp(calculator)),
        ("Bring up System Settings.", .activateApp(settings)),
        ("open settings", .activateApp(settings)),
        ("switch over to vs code", .activateApp(code)),
        ("bring visual studio code to the front", .activateApp(code)),
        ("start spotify please", .activateApp(spotify)),
        ("um take me to activity monitor", .activateApp(monitor)),
        ("go back to textedit", .activateApp(textEdit)),
        ("minimize spotify", .minimizeWindow(.app(spotify))),
        ("close the calculator window", .closeWindow(.app(calculator))),
        ("restore the spotify window", .restoreWindow(.app(spotify))),
        ("put calculator on the left", .moveWindow(.app(calculator), .leftHalf)),
        ("tile spotify and calculator", .tileWindows(left: spotify, right: calculator)),
        ("press seven", .clickElement(label: "seven")),
        ("tap the equals button", .clickElement(label: "the equals button")),
        ("click number 5", .chooseNumber(5)),
        ("show me what I can click here", .showNumbers),
    ])
    func routesWithoutTheModel(utterance: String, expected: FlowAction) async throws {
        let model = FakeModel()
        let d = await route(utterance, model: model)
        #expect(try d.outcome.get().action == expected, "\(utterance)")
        #expect(model.calls.isEmpty, "\(utterance) reached the model")
    }

    @Test(arguments: ["launch Photoshop", "open the app called Zork", "start Garage Band"])
    func appsThatArentInstalledAreSaidPlainly(utterance: String) async throws {
        let intent = try await route(utterance).outcome.get()
        #expect(intent.action == nil)
        #expect(intent.summary.contains("couldn't find an app"), "\(utterance): \(intent.summary)")
    }

    @Test func modelMayNameAnyInstalledAppButNothingElse() {
        #expect(KnownApp.parse("Spotify") == Self.spotify)
        #expect(KnownApp.parse("spotify.app") == Self.spotify)
        #expect(KnownApp.parse("the chrome app")?.name == "Google Chrome")
        #expect(KnownApp.parse("rm -rf /") == nil)
        #expect(KnownApp.parse("Zork") == nil)
    }

    @Test func nameMatchingIsNeverFuzzy() {
        #expect(AppDirectory.lookup("calc") == Self.calculator)          // alias
        #expect(AppDirectory.lookup("activity") == Self.monitor)         // unique prefix ≥ 4 letters
        #expect(AppDirectory.lookup("te") == nil)                        // too short to guess
        #expect(AppDirectory.lookup("textedit") == Self.textEdit)
        #expect(AppDirectory.lookup("text edit") == Self.textEdit)       // spacing ignored
    }
}
