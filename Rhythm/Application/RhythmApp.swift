import AppKit
import SwiftUI

@main
struct RhythmApp: App {
  @NSApplicationDelegateAdaptor(RhythmAppDelegate.self) private var appDelegate
  @State private var appModel = AppModel()

  init() {
    AppIdentityMigration.run()
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarMenuContent()
    } label: {
      MenuBarStatusLabel(hasEnabledServices: appModel.hasEnabledServices)
    }
    .menuBarExtraStyle(.menu)

    Window("Settings", id: AppSceneID.settings) {
      SettingView()
        .environment(appModel)
    }
    .defaultLaunchBehavior(.suppressed)
    .defaultSize(width: SettingsMetrics.windowWidth, height: SettingsMetrics.windowHeight)
    .commands {
      AppMenuCommands()
    }
  }
}

@MainActor
private final class RhythmAppDelegate: NSObject, NSApplicationDelegate {
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      Task {
        _ = await ThingsCallbackExecutor.shared.handle(url)
      }
    }
  }
}

private enum AppSceneID {
  static let settings = "settings"
}

private struct MenuBarMenuContent: View {
  @Environment(\.openWindow) private var openWindow

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
    Button("Settings...") {
      openWindow(id: AppSceneID.settings)
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

private struct AppMenuCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      Button("Settings...") {
        openWindow(id: AppSceneID.settings)
      }
      .keyboardShortcut(",", modifiers: .command)
    }

    CommandGroup(replacing: .appTermination) {
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q", modifiers: .command)
    }
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
