import SwiftUI

@main
struct RhythmApp: App {
    @State private var appModel = AppModel()

    init() {
        AppIdentityMigration.run()
        SettingsWindowStateMigration.run()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenuContent()
        } label: {
            MenuBarStatusLabel(hasEnabledServices: appModel.hasEnabledServices)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingView()
                .environment(appModel)
        }
        .defaultSize(width: SettingsMetrics.windowWidth, height: SettingsMetrics.windowHeight)

        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

private enum SettingsWindowStateMigration {
    private static let resetKey = "settings.didResetWindowState.v3"
    private static let windowFrameKey = "NSWindow Frame com_apple_SwiftUI_Settings_window"
    private static let splitViewFramesKey =
        "NSSplitView Subview Frames com_apple_SwiftUI_Settings_window, SidebarNavigationSplitView"

    static func run(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: resetKey) else {
            return
        }

        defaults.removeObject(forKey: windowFrameKey)
        defaults.removeObject(forKey: splitViewFramesKey)
        defaults.set(true, forKey: resetKey)
    }
}

private struct MenuBarMenuContent: View {
    private var appName: String {
        Bundle.main.name ?? "Rhythm"
    }

    private var versionText: String {
        guard let shortVersionString = Bundle.main.shortVersionString else {
            return "Version"
        }

        return "Version \(shortVersionString)"
    }

    var body: some View {
        SettingsLink {
            Text("Settings...")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Text(versionText)

        Divider()

        Button("Quit \(appName)") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

private struct MenuBarStatusLabel: View {
    let hasEnabledServices: Bool

    private var iconName: String {
        #"MenuIcon-\#(hasEnabledServices ? "On" : "Off")"#
    }

    var body: some View {
        Image(iconName)
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .modifier(StatusLabelBackgroundModifier(isActive: hasEnabledServices))
    }
}

private struct StatusLabelBackgroundModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08))
            )
    }
}
