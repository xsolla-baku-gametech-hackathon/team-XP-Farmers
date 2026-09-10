import AppKit

struct ChatMessage: Decodable { let id: String; let text: String; let sequence: Int }
struct SessionReply: Decodable {
    let state: String; let detail: String; let channel: String; let cursor: Int; let messages: [ChatMessage]
}
struct LoginReply: Decodable { let session_key: String; let authorize_url: String }

final class MessageView: NSView {
    var messages: [String] = [] { didSet { needsDisplay = true } }
    var movable = false { didSet { needsDisplay = true } }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        if movable {
            NSColor.systemGreen.withAlphaComponent(0.4).setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).stroke()
        }
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black; shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 21, weight: .medium),
            .foregroundColor: NSColor.white, .strokeColor: NSColor.black, .strokeWidth: -2,
            .shadow: shadow, .paragraphStyle: style]
        var bottom: CGFloat = 10
        for text in messages.suffix(30).reversed() {
            let value = NSAttributedString(string: String(text.prefix(2000)), attributes: attributes)
            let height = ceil(value.boundingRect(with: NSSize(width: bounds.width - 24, height: 10000),
                options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
            value.draw(with: NSRect(x: 12, y: bottom, width: bounds.width - 24, height: height),
                       options: [.usesLineFragmentOrigin, .usesFontLeading])
            bottom += height + 10
            if bottom >= bounds.height { break }
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard movable, let window else { return }
        window.performDrag(with: event)
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "chatFrame")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var settings: NSWindow!
    var panel: NSPanel!
    let messages = MessageView()
    let relayField = NSTextField(string: "")
    let status = NSTextField(wrappingLabelWithString: "Kick hesabını qoş və oyuna keç.")
    var menuItem: NSStatusItem!
    var sessionKey: String?
    var relayURL: URL?
    var cursor = 0
    var timer: Timer?
    var polling = false
    var generation = 0
    var failures = 0
    var moveButton: NSButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildOverlay()
        buildSettings()
        buildMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(clampPanel), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if CommandLine.arguments.contains("--smoke-test") {
            precondition(!panel.isOpaque && panel.backgroundColor == .clear && panel.ignoresMouseEvents)
            precondition(panel.collectionBehavior.contains(.fullScreenAuxiliary))
            print("Mac overlay smoke: PASS")
            NSApp.terminate(nil)
            return
        }
        showSettings()
    }

    func buildOverlay() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.contentView = messages
        if let frame = UserDefaults.standard.string(forKey: "chatFrame") {
            panel.setFrame(NSRectFromString(frame), display: false); clampPanel()
        } else { resetPosition() }
        panel.orderFrontRegardless()
    }

    func buildSettings() {
        settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 510, height: 400),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        settings.title = "XP Farmers · Kick Chat"
        settings.isReleasedWhenClosed = false
        settings.delegate = self
        let column = NSStackView(); column.orientation = .vertical; column.alignment = .leading; column.spacing = 14
        column.translatesAutoresizingMaskIntoConstraints = false
        settings.contentView!.addSubview(column)
        NSLayoutConstraint.activate([column.leadingAnchor.constraint(equalTo: settings.contentView!.leadingAnchor, constant: 24),
            column.trailingAnchor.constraint(equalTo: settings.contentView!.trailingAnchor, constant: -24),
            column.topAnchor.constraint(equalTo: settings.contentView!.topAnchor, constant: 24)])
        let title = NSTextField(labelWithString: "Oyunda yalnız çat yazıları")
        title.font = .systemFont(ofSize: 23, weight: .semibold); column.addArrangedSubview(title)
        let help = NSTextField(wrappingLabelWithString: "Kick hesabını brauzerdə qoş. Mesajlar sağ altda görünəcək. Bu pəncərəni bağlasan da çat açıq qalacaq.")
        column.addArrangedSubview(help)
        relayField.placeholderString = "Komandanın Kick server ünvanı (https://…)"
        relayField.stringValue = UserDefaults.standard.string(forKey: "relayURL") ?? ""
        relayField.widthAnchor.constraint(equalToConstant: 460).isActive = true
        column.addArrangedSubview(relayField)
        let loginRow = NSStackView(); loginRow.spacing = 10
        loginRow.addArrangedSubview(button("Kick hesabımı qoş", #selector(connectKick)))
        loginRow.addArrangedSubview(button("Bağlantını kəs", #selector(disconnect)))
        column.addArrangedSubview(loginRow)
        status.textColor = .secondaryLabelColor; column.addArrangedSubview(status)
        let positionRow = NSStackView(); positionRow.spacing = 10
        moveButton = button("Çatın yerini dəyiş", #selector(toggleMove))
        positionRow.addArrangedSubview(moveButton)
        positionRow.addArrangedSubview(button("Sağ alta qaytar", #selector(resetPosition)))
        column.addArrangedSubview(positionRow)
        let previewRow = NSStackView(); previewRow.spacing = 10
        previewRow.addArrangedSubview(button("Sınaq mesajı (OFFLINE)", #selector(preview)))
        previewRow.addArrangedSubview(button("Çatı göstər / gizlət", #selector(toggleOverlay)))
        column.addArrangedSubview(previewRow)
        column.addArrangedSubview(button("Tətbiqdən çıx", #selector(quit)))
        settings.center()
    }

    func button(_ title: String, _ selector: Selector) -> NSButton {
        NSButton(title: title, target: self, action: selector)
    }
    func buildMenu() {
        menuItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menuItem.button?.title = "Kick Chat"
        let menu = NSMenu()
        for (title, action) in [("Ayarlar", #selector(showSettings)), ("Çatı göstər / gizlət", #selector(toggleOverlay)), ("Çıx", #selector(quit))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menuItem.menu = menu
    }
    @objc func showSettings() { settings.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func toggleOverlay() { if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() } }
    @objc func toggleMove() {
        messages.movable.toggle(); panel.ignoresMouseEvents = !messages.movable
        moveButton.title = messages.movable ? "Yeri sabitlə (oyuna qayıt)" : "Çatın yerini dəyiş"
        panel.orderFrontRegardless()
    }
    @objc func resetPosition() {
        guard let screen = NSScreen.main else { return }
        panel.setFrame(NSRect(x: screen.visibleFrame.maxX - 444, y: screen.visibleFrame.minY + 24, width: 420, height: 300), display: true)
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "chatFrame")
    }
    @objc func clampPanel() {
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) }) ?? NSScreen.main else { return }
        var frame = panel.frame
        frame.size = NSSize(width: min(420, screen.visibleFrame.width), height: min(300, screen.visibleFrame.height))
        frame.origin.x = min(max(frame.minX, screen.visibleFrame.minX), screen.visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, screen.visibleFrame.minY), screen.visibleFrame.maxY - frame.height)
        panel.setFrame(frame, display: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if messages.movable { toggleMove() }
        return true
    }
    @objc func preview() {
        disconnect()
        status.stringValue = "OFFLINE sınaq — Kick bağlantısı yoxdur."
        messages.messages = ["OFFLINE SINAQ: Salam!", "OFFLINE SINAQ: Oyun çox gözəldir."]
        panel.orderFrontRegardless()
    }
    @objc func disconnect() {
        let oldKey = sessionKey, oldURL = relayURL
        generation += 1; timer?.invalidate(); timer = nil; polling = false; failures = 0
        sessionKey = nil; cursor = 0; messages.messages = []
        status.stringValue = "Qoşulmayıb."
        if let oldKey, let oldURL {
            var request = URLRequest(url: oldURL.appendingPathComponent("session"))
            request.httpMethod = "DELETE"; request.setValue("Bearer \(oldKey)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: request).resume()
        }
    }
    @objc func connectKick() {
        disconnect()
        let text = relayField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? "")) else {
            status.stringValue = "Komandanın HTTPS server ünvanını daxil et."; return
        }
        relayURL = url; UserDefaults.standard.set(text, forKey: "relayURL")
        status.stringValue = "Kick giriş səhifəsi açılır…"
        let current = generation
        var request = URLRequest(url: url.appendingPathComponent("sessions")); request.httpMethod = "POST"; request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard current == self.generation else { return }
                guard error == nil, (response as? HTTPURLResponse)?.statusCode == 201, let data,
                      let reply = try? JSONDecoder().decode(LoginReply.self, from: data),
                      let login = URL(string: reply.authorize_url), login.scheme == "https", login.host == "id.kick.com" else {
                    self.status.stringValue = "Serverə qoşulmaq alınmadı. Ünvanı və server quruluşunu yoxla."; return
                }
                self.sessionKey = reply.session_key
                NSWorkspace.shared.open(login)
                self.status.stringValue = "Brauzerdə Kick girişini tamamla."
                self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in self.poll() }
                self.poll()
            }
        }.resume()
    }
    func poll() {
        guard !polling, let base = relayURL, let key = sessionKey else { return }
        polling = true
        let current = generation
        var components = URLComponents(url: base.appendingPathComponent("session"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "after", value: String(cursor))]
        var request = URLRequest(url: components.url!); request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard current == self.generation else { return }
                self.polling = false
                if (response as? HTTPURLResponse)?.statusCode == 401 {
                    self.disconnect(); self.status.stringValue = "Sessiya bitib. Kick hesabını yenidən qoş."; return
                }
                guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data,
                      let reply = try? JSONDecoder().decode(SessionReply.self, from: data) else {
                    self.failures += 1
                    self.status.stringValue = "Bağlantı kəsilib. Yenidən yoxlanılır…"
                    if self.failures >= 30 { self.disconnect(); self.status.stringValue = "Server əlçatan deyil. Yenidən qoşul." }
                    return
                }
                self.failures = 0
                self.status.stringValue = reply.channel.isEmpty ? reply.detail : "\(reply.channel): \(reply.detail)"
                self.cursor = reply.cursor
                self.messages.messages = Array((self.messages.messages + reply.messages.map(\.text)).suffix(30))
                if reply.state == "error" { self.timer?.invalidate(); self.timer = nil }
            }
        }.resume()
    }
    @objc func quit() { disconnect(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
