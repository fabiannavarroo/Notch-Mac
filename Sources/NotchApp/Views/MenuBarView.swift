import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: NotchAppState

    var body: some View {
        Toggle("Mostrar isla", isOn: $appState.isIslandEnabled)

        Button(appState.isPinnedExpanded ? "Contraer" : "Expandir") {
            appState.togglePinnedExpanded()
        }

        Divider()

        Button("Subir isla") {
            appState.adjustVerticalOffset(by: 2)
        }

        Button("Bajar isla") {
            appState.adjustVerticalOffset(by: -2)
        }

        Button("Resetear posicion") {
            appState.resetVerticalOffset()
        }

        Divider()

        Button("Anterior") {
            appState.send(.previousTrack)
        }

        Button("Play / Pause") {
            appState.send(.togglePlayPause)
        }

        Button("Siguiente") {
            appState.send(.nextTrack)
        }

        Divider()

        Button("Probar evento") {
            appState.pushEvent(
                title: "Evento",
                detail: "Vista tipo Alcove",
                symbolName: "sparkles"
            )
        }

        Divider()

        Button("Salir") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
