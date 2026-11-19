import AppKit
import SwiftUI
import TypetickCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched straight from `swift run` (no bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct TypetickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Typetick", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 620)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.controller.commitSheet()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { TypetickCommands(model: model) }

        Window("Workshop", id: "workshop") {
            WorkshopView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct TypetickCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { model.newNote() }.keyboardShortcut("n")
            Button("Feed New Sheet") { model.controller.newSheet() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Eject Sheet") { model.controller.ejectSheet() }.keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { model.controller.cut() }.keyboardShortcut("x")
            Button("Copy") { model.controller.copy() }.keyboardShortcut("c")
            Button("Paste") { model.controller.paste() }.keyboardShortcut("v")
            Button("Select All") { model.controller.selectAll() }.keyboardShortcut("a")
            Divider()
            Button("Stop Recorder") { model.controller.stopAutoTyping() }.keyboardShortcut(".")
        }
        CommandMenu("Machine") {
            Button("Carriage Return") { model.controller.carriageReturn() }.keyboardShortcut(.return, modifiers: [.command])
            Button("Cycle Line Spacing") { model.controller.cycleLineSpacing() }.keyboardShortcut("l", modifiers: [.command, .option])
            Button("Switch Ribbon Color") { model.controller.toggleRibbonColor() }.keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Button("Set Left Margin Here") { model.controller.setLeftMargin() }.keyboardShortcut("[")
            Button("Set Right Margin Here") { model.controller.setRightMargin() }.keyboardShortcut("]")
            Button("Set / Clear Tab Stop Here") { model.controller.toggleTab() }.keyboardShortcut("t", modifiers: [.command, .option])
            Button("Clear All Tab Stops") { model.controller.clearTabs() }
            Divider()
            Button("Read Sheet") { model.showReader.toggle() }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Open Workshop…") { openWindow(id: "workshop") }.keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }
}
