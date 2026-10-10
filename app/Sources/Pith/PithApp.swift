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
                    await store.start()
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

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { store?.stop() }
    }
}
