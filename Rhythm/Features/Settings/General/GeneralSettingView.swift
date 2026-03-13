//
//  GeneralSettingView.swift
//  Rhythm
//
//  Created by Naicheng Deng on 2026-03-12.
//

import AppKit
import SwiftUI

struct GeneralSettingView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Form {
            Section {
                Toggle("Allow Claude Desktop", isOn: allowClaudeBinding)
                Toggle("Allow OpenClaw", isOn: allowOpenClawBinding)
                Toggle("Allow Others", isOn: allowUnknownClientsBinding)
            } header: {
                Text("Client Access")
            } footer: {
                Text("Enable desktop clients to connect to Rhythm. Other clients stay blocked by default.")
            }

            Section {
                LabeledContent("Claude Desktop") {
                    Button("Configure...") {
                        guard ClaudeDesktop.showConfigurationPanel() else {
                            return
                        }

                        Task {
                            await appModel.setKnownClient(.claudeDesktop, allowed: true)
                        }
                    }
                }
                LabeledContent("OpenClaw") {
                    Button("Configure...") {
                        guard OpenClaw.showConfigurationPanel() else {
                            return
                        }

                        Task {
                            await appModel.setKnownClient(.openClaw, allowed: true)
                        }
                    }
                }
                LabeledContent("Server Command") {
                    HStack(spacing: 8) {
                        Text(verbatim: appModel.serverCommand)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button("Copy") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(appModel.serverCommand, forType: .string)
                        }
                    }
                }
            } header: {
                Text("Integrations")
            } footer: {
                Text("Write MCP settings for supported desktop clients, or copy the bundled command path for manual setup.")
            }

            Section {
                Toggle("Enable MCP Server", isOn: serverEnabledBinding)

                LabeledContent("Server Status") {
                    Text(appModel.serverStatus.rawValue.capitalized)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .padding()
    }

    private var allowClaudeBinding: Binding<Bool> {
        Binding(
            get: { appModel.clientAccessPolicy.allows(.claudeDesktop) },
            set: { allowed in
                Task {
                    await appModel.setKnownClient(.claudeDesktop, allowed: allowed)
                }
            }
        )
    }

    private var allowOpenClawBinding: Binding<Bool> {
        Binding(
            get: { appModel.clientAccessPolicy.allows(.openClaw) },
            set: { allowed in
                Task {
                    await appModel.setKnownClient(.openClaw, allowed: allowed)
                }
            }
        )
    }

    private var allowUnknownClientsBinding: Binding<Bool> {
        Binding(
            get: { appModel.clientAccessPolicy.allowUnknownClients },
            set: { allowed in
                Task {
                    await appModel.setAllowUnknownClients(allowed)
                }
            }
        )
    }

    private var serverEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.isServerEnabled },
            set: { enabled in
                Task {
                    await appModel.setServerEnabled(enabled)
                }
            }
        )
    }
}

#Preview {
    GeneralSettingView()
        .environment(AppModel())
}
