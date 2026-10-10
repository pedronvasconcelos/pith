import AppKit
import SwiftUI

@main
struct PithApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = ChatStore()

    var body: some Scene {
        Window("Pith", id: "main") {
            ContentView()
                .environment(store)
                .task {
                    delegate.store = store
                    await store.launch()
                }
        }
        .defaultSize(width: 1120, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Window("Árvore", id: "branches") {
            BranchesView().environment(store)
        }
        .defaultSize(width: 1100, height: 680)
        .keyboardShortcut("b", modifiers: [.command, .shift])

        Settings {
            SettingsView().environment(store)
        }

        // Keeps Pith reachable with every window closed.
        MenuBarExtra {
            MenuBarMenu()
        } label: {
            MenuBarIcon(store: store) { delegate.store = store }
        }
    }
}

/// The menu bar icon. It lives as long as the app, so it also wires the quick chat.
private struct MenuBarIcon: View {
    let store: ChatStore
    let attach: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "smallcircle.filled.circle")
            .task {
                attach()
                QuickChat.shared.store = store
                QuickChat.shared.openMain = { openWindow(id: "main") }
                QuickChat.shared.reloadHotKey()
                // Development: PITH_OPEN_QUICK opens the quick chat at launch.
                if ProcessInfo.processInfo.environment["PITH_OPEN_QUICK"] != nil {
                    Task { try? await Task.sleep(for: .seconds(3)); QuickChat.shared.show() }
                }
                await store.launch()
            }
    }
}

private struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Chat rápido") { QuickChat.shared.show() }
        Button("Abrir o Pith") { QuickChat.shared.openConversation() }
        Button("Árvore") {
            NSApp.activate()
            openWindow(id: "branches")
        }
        Divider()
        SettingsLink { Text("Ajustes…") }
        Divider()
        Button("Sair do Pith") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: ChatStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a regular app even when launched as a bare executable.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // Development: PITH_APPEARANCE=light|dark forces the appearance.
        switch ProcessInfo.processInfo.environment["PITH_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        // Development: PITH_SNAPSHOT=/path.png keeps writing a capture of the window.
        if let path = ProcessInfo.processInfo.environment["PITH_SNAPSHOT"] {
            Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                MainActor.assumeIsolated { Self.snapshot(to: path) }
            }
        }
    }

    @MainActor
    private static func snapshot(to path: String) {
        // PITH_SNAPSHOT_WINDOW picks a window by identifier (e.g. "settings", "branches").
        let wanted = ProcessInfo.processInfo.environment["PITH_SNAPSHOT_WINDOW"]
        guard let window = NSApp.windows.first(where: { win in
            guard win.isVisible else { return false }
            guard let wanted else { return win.canBecomeMain }
            return (win.identifier?.rawValue ?? "").localizedCaseInsensitiveContains(wanted)
        }) else { return }
        // CGWindowListCreateImage is gone from the SDK but still answers for our own windows.
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
        let capture = unsafeBitCast(sym, to: Capture.self)
        // .optionIncludingWindow, .boundsIgnoreFraming | .bestResolution
        guard let image = capture(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue()
        else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    // The core keeps running in the menu bar with the window closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { MainActor.assumeIsolated { QuickChat.shared.openConversation() } }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { store?.stop() }
    }
}
