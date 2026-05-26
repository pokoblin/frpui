import SwiftUI
import AppKit

struct SettingsView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case log = "Log"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 8)

            Divider()

            switch tab {
            case .general: GeneralSettingsTab()
            case .log: LogTab()
            }
        }
        .frame(width: 500)
    }
}

struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var configText: String = ConfigStore.read()
    @State private var statusNote: String?

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appState.appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Start service on launch", isOn: $appState.autoStartService)

                Picker("Launch at startup", selection: $appState.launchMode) {
                    ForEach(LaunchMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Configuration (frpc.toml)") {
                TextEditor(text: $configText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
                    .scrollContentBackground(.hidden)

                HStack {
                    if let statusNote {
                        Text(statusNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reload") {
                        configText = ConfigStore.read()
                        statusNote = nil
                    }
                    Button("Save") { save() }
                        .keyboardShortcut("s", modifiers: .command)
                }

                if appState.launchMode == .systemDaemon {
                    Text("Saving updates the system service configuration (requires authorization) and restarts it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if appState.isActive {
                    Text("The service is running. Changes take effect after you stop and start it again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 470)
    }

    private func save() {
        do {
            try ConfigStore.write(configText)
            appState.syncSystemConfigIfNeeded()
            statusNote = appState.launchMode == .systemDaemon
                ? "Saved and applied to the system service."
                : "Saved."
        } catch {
            statusNote = "Save failed: \(error.localizedDescription)"
        }
    }
}

struct LogTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(appState.log.isEmpty ? "No log output yet." : appState.log)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(appState.log.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(8)
                }
                .onChange(of: appState.log) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )

            HStack {
                if appState.launchMode == .systemDaemon {
                    Text("System daemon log (/Library/Logs/frpui-frpc.log)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear") { appState.clearLog() }
                    .disabled(appState.log.isEmpty || appState.launchMode == .systemDaemon)
            }
        }
        .padding()
        .frame(minHeight: 470)
    }
}
