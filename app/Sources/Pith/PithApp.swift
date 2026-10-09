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
        // Development: PITH_SNAPSHOT=/path.png keeps writing a capture of the window.
        if let path = ProcessInfo.processInfo.environment["PITH_SNAPSHOT"] {
            Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                MainActor.assumeIsolated { Self.snapshot(to: path) }
            }
        }
    }

    @MainActor
    private static func snapshot(to path: String) {
        let settings = ProcessInfo.processInfo.environment["PITH_OPEN_SETTINGS"] != nil
        guard let window = NSApp.windows.first(where: { $0.isVisible && (settings ? ($0.identifier?.rawValue ?? "").localizedCaseInsensitiveContains("settings") : $0.canBecomeMain) })
        else { return }
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
