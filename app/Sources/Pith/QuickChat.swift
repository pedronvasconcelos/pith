import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The global shortcut that opens the quick chat. Saved in UserDefaults with
/// Carbon key code and modifiers, plus the label shown in Settings and menus.
struct HotKey: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String

    static let standard = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "⌥Espaço")

    static var current: HotKey? {
        let d = UserDefaults.standard
        if d.bool(forKey: "quickKeyOff") { return nil }
        guard d.object(forKey: "quickKeyCode") != nil else { return .standard }
        return HotKey(
            keyCode: UInt32(d.integer(forKey: "quickKeyCode")),
            modifiers: UInt32(d.integer(forKey: "quickKeyModifiers")),
            label: d.string(forKey: "quickKeyLabel") ?? "?"
        )
    }

    static func save(_ key: HotKey?) {
        let d = UserDefaults.standard
        d.set(key == nil, forKey: "quickKeyOff")
        if let key {
            d.set(Int(key.keyCode), forKey: "quickKeyCode")
            d.set(Int(key.modifiers), forKey: "quickKeyModifiers")
            d.set(key.label, forKey: "quickKeyLabel")
        }
    }

    /// A shortcut from a key press, or nil if it lacks ⌘, ⌥ or ⌃.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.isDisjoint(with: [.command, .option, .control]) else { return nil }
        var mods: UInt32 = 0
        var label = ""
        if flags.contains(.control) { mods |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { mods |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { mods |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { mods |= UInt32(cmdKey); label += "⌘" }
        label += Self.name(event)
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods, label: label)
    }

    init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    private static func name(_ event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: "Espaço"
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_Escape: "⎋"
        case kVK_Delete: "⌫"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        default: (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

/// One system-wide hotkey through Carbon, which needs no accessibility permission.
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()
    var action: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register(_ key: HotKey?) {
        unregister()
        guard let key else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotKey.shared.action?() } }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x5049_5448), id: 1) // "PITH"
        RegisterEventHotKey(key.keyCode, key.modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}

/// A borderless panel that takes the keyboard without activating the app,
/// so the chat opens over whatever you're doing, like Spotlight.
private final class QuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { close() }
}

/// Shows and hides the quick chat. The panel is built once and reused.
@MainActor
final class QuickChat: NSObject, NSWindowDelegate {
    static let shared = QuickChat()
    var store: ChatStore?
    /// Opens the main window; set by a scene that can call openWindow.
    var openMain: (() -> Void)?
    private var panel: QuickPanel?

    func reloadHotKey() {
        GlobalHotKey.shared.action = { [weak self] in self?.toggle() }
        GlobalHotKey.shared.register(HotKey.current)
    }

    func toggle() {
        if let panel, panel.isKeyWindow { panel.close() } else { show() }
    }

    func show() {
        guard let store else { return }
        let panel = panel ?? makePanel(store)
        self.panel = panel
        // Top third of the screen with the mouse, like Spotlight.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            let size = panel.frame.size
            let top = area.maxY - area.height * 0.22 + QuickChatView.margin
            panel.setFrameTopLeftPoint(NSPoint(x: area.midX - size.width / 2, y: min(top, area.maxY)))
        }
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .quickChatShown, object: nil)
    }

    func hide() { panel?.close() }

    /// Leaves the panel for the full conversation.
    func openConversation() {
        hide()
        NSApp.activate()
        if let main = NSApp.windows.first(where: { ($0.identifier?.rawValue ?? "").hasPrefix("main") }), main.isVisible {
            main.makeKeyAndOrderFront(nil)
        } else {
            openMain?()
        }
    }

    private func makePanel(_ store: ChatStore) -> QuickPanel {
        let panel = QuickPanel(
            contentRect: NSRect(origin: .zero, size: QuickChatView.panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // drawn by SwiftUI around the content, not the window
        panel.delegate = self
        panel.identifier = NSUserInterfaceItemIdentifier("quick")
        // A fixed, mostly transparent panel with the content at the top: clicks
        // on the empty part fall through. Resizing a visible window to fit a
        // hosting view loops AppKit's constraint passes until it crashes.
        let host = NSHostingView(rootView: QuickChatView().environment(store))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    // Clicking elsewhere puts it away.
    func windowDidResignKey(_ notification: Notification) { hide() }
}

extension Notification.Name {
    static let quickChatShown = Notification.Name("PithQuickChatShown")
}

/// The last exchanges, the reply as it streams, and the field.
struct QuickChatView: View {
    @Environment(ChatStore.self) private var store
    @State private var draft = ""
    @FocusState private var focused: Bool
    @State private var position = ScrollPosition(edge: .bottom)

    static let margin: CGFloat = 24
    static let panelSize = CGSize(width: 640 + 2 * margin, height: 560)

    /// The last few user and Pith messages; tool chatter stays in the main window.
    private var recent: [ChatRow] {
        let rows = ChatRow.build(store.messages).filter {
            switch $0 { case .user, .pith: true; default: false }
        }
        return Array(rows.suffix(store.live == nil ? 3 : 2))
    }

    private var showsTranscript: Bool {
        store.live != nil || store.lastError != nil || !recent.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsTranscript {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(recent) { row in
                            switch row {
                            case .user(let m): UserBubble(message: m)
                            case .pith(let m): PithReply(message: m, thought: nil)
                            default: EmptyView()
                            }
                        }
                        if let live = store.live {
                            LiveTurnView(
                                live: live,
                                runs: store.agents.values.filter { !$0.done }.sorted { $0.id < $1.id },
                                permissions: store.permissions,
                                answer: { store.answer($0, allow: $1, always: $2) }
                            )
                        }
                        if let err = store.lastError { ErrorBanner(message: err) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 10)
                }
                .scrollPosition($position)
                .defaultScrollAnchor(.bottom)
                .frame(maxHeight: 380)
                .fixedSize(horizontal: false, vertical: true)
                Divider().opacity(0.5)
            }
            field
        }
        .frame(width: 640)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .padding(Self.margin)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: store.messages.last?.i) { _, _ in scrollDown() }
        .onChange(of: store.live?.text.count) { _, _ in scrollDown() }
        .onReceive(NotificationCenter.default.publisher(for: .quickChatShown)) { _ in
            focused = true
            scrollDown()
        }
        .onExitCommand { QuickChat.shared.hide() }
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { send() }
            QuickChat.shared.openConversation()
            return .handled
        }
        .animation(.smooth(duration: 0.2), value: showsTranscript)
    }

    private var field: some View {
        HStack(alignment: .center, spacing: 12) {
            RingsLogo(rings: 6, lineWidth: 1).frame(width: 22, height: 22)
            TextField("Pergunte ao Pith…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                .lineLimit(1...6)
                .focused($focused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.command) { return .ignored }
                    if press.modifiers.contains(.shift) || press.modifiers.contains(.option) { return .ignored }
                    send()
                    return .handled
                }
            if store.busy && draft.isEmpty {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .contentShape(.circle)
                    .onTapGesture(perform: store.cancel)
                    .help("Parar")
            } else {
                Text("⌘↩ abre a conversa")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        store.send(text: text)
    }

    private func scrollDown() {
        DispatchQueue.main.async { position.scrollTo(edge: .bottom) }
    }
}

/// Records a new shortcut: click, then press the keys.
struct HotKeyRecorder: View {
    @State private var key = HotKey.current
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button(recording ? "Pressione o atalho…" : (key?.label ?? "Nenhum")) {
                recording ? stop() : record()
            }
            .frame(minWidth: 110)
            if key != nil && !recording {
                Button("Remover") { set(nil) }
            } else if key == nil && !recording {
                Button("Padrão") { set(.standard) }
            }
        }
        .onDisappear(perform: stop)
    }

    private func record() {
        recording = true
        GlobalHotKey.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            if let new = HotKey(event: event) { set(new) }
            return nil
        }
    }

    private func set(_ new: HotKey?) {
        HotKey.save(new)
        key = new
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { recording = false }
        QuickChat.shared.reloadHotKey()
    }
}
