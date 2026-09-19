import SwiftUI
import ServiceManagement
import os.log

@main
struct TURNApp: App {
    @StateObject private var presetManager: PresetManager
    @StateObject private var midiManager: CoreMIDIManager

    private let logger = Logger(subsystem: "com.samuelbacaro.TURN", category: "app")

    init() {
        let presetManager = PresetManager()
        let huiEngine = HUIProtocolEngine(presetManager: presetManager)

        _presetManager = StateObject(wrappedValue: presetManager)
        _midiManager = StateObject(wrappedValue: CoreMIDIManager(huiEngine: huiEngine))
    }

    var body: some Scene {
        MenuBarExtra(String(localized: "app_title"), systemImage: statusImageName) {
            Section {
                statusRow(
                    title: String(localized: "status_hardware"),
                    isConnected: midiManager.isHardwareConnected
                )
                statusRow(
                    title: String(localized: "status_virtual_port"),
                    isConnected: midiManager.isVirtualPortActive
                )
            }

            Divider()

            Button(String(localized: "quit_app")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            GeneralSettingsView()
        }
    }

    private var statusImageName: String {
        midiManager.isHardwareConnected ? "slider.vertical.3" : "slider.horizontal.3"
    }

    @ViewBuilder
    private func statusRow(title: String, isConnected: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: isConnected ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(isConnected ? Color.green : Color.secondary)
        }
    }
}

struct GeneralSettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle(String(localized: "launch_at_login"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) {
                    toggleLaunchAtLogin(enabled: launchAtLogin)
                }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func toggleLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
