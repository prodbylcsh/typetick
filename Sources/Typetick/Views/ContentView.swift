import SwiftUI
import TypetickCore
import TypetickScene

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            NotesSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            ZStack {
                StageContainer(stage: model.controller.stage)
                    .ignoresSafeArea()
                if model.selectedNoteID == nil {
                    EmptyDeskView()
                }
                if model.preferences.showHUD && model.selectedNoteID != nil {
                    MachineHUD()
                }
            }
            .sheet(isPresented: Binding(get: { model.showReader }, set: { model.showReader = $0 })) {
                ReaderView().environment(model)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.newNote() } label: { Label("New Note", systemImage: "square.and.pencil") }
                    .help("New note (⌘N)")
                Button { model.controller.newSheet() } label: { Label("Feed Sheet", systemImage: "doc.badge.plus") }
                    .help("Feed a new sheet (⇧⌘N)")
                    .disabled(model.selectedNoteID == nil)
                Button { model.showReader = true } label: { Label("Read", systemImage: "text.viewfinder") }
                    .help("Read the sheet (⇧⌘R)")
                    .disabled(model.selectedNoteID == nil)
                Button { openWindow(id: "workshop") } label: { Label("Workshop", systemImage: "wrench.and.screwdriver") }
                    .help("Customize the machine, paper, ink and desk (⇧⌘K)")
            }
        }
    }
}

/// Hosts the persistent RealityKit view.
struct StageContainer: NSViewRepresentable {
    let stage: Stage
    func makeNSView(context: Context) -> StageView { stage.view }
    func updateNSView(_ nsView: StageView, context: Context) {}
}

struct EmptyDeskView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("No sheet in the machine")
                .font(.title3.weight(.semibold))
            Text("Create a note to roll in a fresh sheet of paper.")
                .foregroundStyle(.secondary)
            Button("New Note") { model.newNote() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
