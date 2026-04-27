import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: NotchAppState
    @ObservedObject var volumeService: SystemVolumeService

    var body: some View {
        Toggle("Mostrar isla", isOn: $appState.isIslandEnabled)
        Toggle("Iniciar al arrancar Mac", isOn: $appState.launchAtLogin)

        Button(appState.isPinnedExpanded ? "Contraer" : "Expandir") {
            appState.togglePinnedExpanded()
        }

        Divider()

        Menu("Pantalla") {
            Button {
                appState.preferredScreenID = nil
            } label: {
                Label("Automática (notch)", systemImage: appState.preferredScreenID == nil ? "checkmark" : "")
            }

            Divider()

            ForEach(NSScreen.screens, id: \.self) { screen in
                let id = NotchGeometry.displayID(for: screen)
                Button {
                    appState.preferredScreenID = id
                } label: {
                    Label(screen.localizedName, systemImage: appState.preferredScreenID == id ? "checkmark" : "")
                }
            }
        }

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
