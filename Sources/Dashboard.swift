import AppKit
import Translation

struct LangOption {
    let code: String
    let name: String
}

enum LanguageCatalog {
    static var options: [LangOption] = [
        LangOption(code: "zh-CN", name: LanguageNames.display(.init(identifier: "zh-CN"))),
        LangOption(code: "en-US", name: LanguageNames.display(.init(identifier: "en-US"))),
    ]

    static func load() async -> [LangOption] {
        let langs = await LanguageAvailability().supportedLanguages
        var seen = Set<String>()
        var list: [LangOption] = []
        for l in langs {
            guard let code = l.languageCode?.identifier else { continue }
            var id = code
            if let r = l.region?.identifier { id = "\(code)-\(r)" }
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            list.append(LangOption(code: id, name: LanguageNames.display(l)))
        }
        list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return list
    }
}

/// 主窗口：普通窗口，只负责选语言和打开文件
final class DashboardController: NSWindowController {

    static let shared = DashboardController()

    private let sourcePopup = HoverPopUp(frame: .zero, pullsDown: false)
    private let targetPopup = HoverPopUp(frame: .zero, pullsDown: false)
    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: "检查中…")
    private let manageButton = NSButton(title: "下载…", target: nil, action: nil)

    private convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
                         styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "Translater"
        w.isOpaque = true
        w.backgroundColor = .windowBackgroundColor
        WindowPlacement.place(w)
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        w.hidesOnDeactivate = false
        self.init(window: w)
        build()
        loadLanguages()
    }

    private func build() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

        // 标题
        let icon = NSImageView(image: NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .regular)

        let title = NSTextField(labelWithString: "文档翻译")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let sub = NSTextField(labelWithString: "打开 .md 或 .txt，整篇译成另一种语言，可导出纯译文")
        sub.font = .systemFont(ofSize: 12)
        sub.textColor = .secondaryLabelColor

        let textCol = NSStackView(views: [title, sub])
        textCol.orientation = .vertical
        textCol.spacing = 3
        textCol.alignment = .leading

        let header = NSStackView(views: [icon, textCol])
        header.orientation = .horizontal
        header.spacing = 14
        header.alignment = .centerY
        root.addArrangedSubview(header)

        // 语言
        sourcePopup.target = self
        sourcePopup.action = #selector(selectionChanged)
        targetPopup.target = self
        targetPopup.action = #selector(selectionChanged)
        sourcePopup.widthAnchor.constraint(equalToConstant: 190).isActive = true
        targetPopup.widthAnchor.constraint(equalToConstant: 190).isActive = true

        manageButton.bezelStyle = .inline
        manageButton.controlSize = .small
        manageButton.font = .systemFont(ofSize: 11)
        manageButton.target = self
        manageButton.action = #selector(openLanguageSettings)
        manageButton.isHidden = true

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let statusRow = NSStackView(views: [statusDot, statusLabel, manageButton])
        statusRow.orientation = .horizontal
        statusRow.spacing = 6

        let langCard = card(title: "翻译方向", rows: [
            row("源语言", sourcePopup),
            row("目标语言", targetPopup),
            row("语言包", statusRow),
        ])
        root.addArrangedSubview(langCard)

        let openButton = NSButton(title: "打开文件…", target: self, action: #selector(openFile))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .large
        openButton.keyEquivalent = "\r"
        root.addArrangedSubview(openButton)

        let footer = NSTextField(labelWithString: "设备端翻译 · 不联网 · 不限字数")
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        root.addArrangedSubview(footer)
    }

    private func card(title: String, rows: [NSView]) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.cornerRadius = 10
        box.fillColor = .controlBackgroundColor
        box.borderColor = .separatorColor
        box.borderWidth = 1
        box.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 11, weight: .semibold)
        t.textColor = .secondaryLabelColor
        stack.addArrangedSubview(t)
        rows.forEach { stack.addArrangedSubview($0) }

        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            box.widthAnchor.constraint(equalToConstant: 412),
        ])
        return box
    }

    private func row(_ name: String, _ control: NSView) -> NSView {
        let l = NSTextField(labelWithString: name)
        l.font = .systemFont(ofSize: 12)
        l.textColor = .labelColor
        l.widthAnchor.constraint(equalToConstant: 60).isActive = true
        let r = NSStackView(views: [l, control])
        r.orientation = .horizontal
        r.spacing = 10
        r.alignment = .centerY
        return r
    }

    // MARK: - 动作

    func showWindowAndActivate() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshEngineStatus()
    }

    private func loadLanguages() {
        populatePopups()
        Task { @MainActor in
            let list = await LanguageCatalog.load()
            if list.count > 2 { LanguageCatalog.options = list; populatePopups() }
            refreshEngineStatus()
        }
    }

    private func populatePopups() {
        let opts = LanguageCatalog.options
        sourcePopup.removeAllItems()
        sourcePopup.addItem(withTitle: "自动检测")
        sourcePopup.addItems(withTitles: opts.map { $0.name })
        targetPopup.removeAllItems()
        targetPopup.addItems(withTitles: opts.map { $0.name })
        if Prefs.autoSource { sourcePopup.selectItem(at: 0) }
        else if let i = opts.firstIndex(where: { $0.code == Prefs.sourceCode }) { sourcePopup.selectItem(at: i + 1) }
        if let j = opts.firstIndex(where: { $0.code == Prefs.targetCode }) { targetPopup.selectItem(at: j) }
    }

    @objc private func selectionChanged() {
        let opts = LanguageCatalog.options
        if sourcePopup.indexOfSelectedItem == 0 {
            Prefs.autoSource = true
        } else {
            Prefs.autoSource = false
            let i = sourcePopup.indexOfSelectedItem - 1
            if i >= 0 && i < opts.count { Prefs.sourceCode = opts[i].code }
        }
        let j = targetPopup.indexOfSelectedItem
        if j >= 0 && j < opts.count { Prefs.targetCode = opts[j].code }
        refreshEngineStatus()
    }

    private func refreshEngineStatus() {
        let pair = Prefs.pair()
        Task { @MainActor in
            let st = await Engine.shared.status(pair)
            let d = LanguageSupport.describe(st)
            statusDot.layer?.backgroundColor = d.color.cgColor
            statusLabel.stringValue = d.text
            manageButton.isHidden = !d.needsAction
        }
    }

    @objc private func openLanguageSettings() { LanguageSupport.openSettings() }
    @objc private func openFile() { DocWindowController.shared.openFile() }
}

/// 普通按钮（首击生效）
final class HoverButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class HoverPopUp: NSPopUpButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 偏好设置
enum Prefs {
    static var autoSource: Bool {
        get { UserDefaults.standard.object(forKey: "autoSource") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoSource") }
    }
    static var sourceCode: String {
        get { UserDefaults.standard.string(forKey: "sourceCode") ?? "zh-CN" }
        set { UserDefaults.standard.set(newValue, forKey: "sourceCode") }
    }
    static var targetCode: String {
        get { UserDefaults.standard.string(forKey: "targetCode") ?? "en-US" }
        set { UserDefaults.standard.set(newValue, forKey: "targetCode") }
    }
    static func pair() -> LangPair {
        LangPair(from: .init(identifier: sourceCode), to: .init(identifier: targetCode))
    }
    static func pair(for text: String) -> LangPair {
        let target = Locale.Language(identifier: targetCode)
        guard autoSource else { return pair() }
        let detectedId = Engine.shared.isChinese(text) ? "zh-CN" : "en-US"
        let from = Locale.Language(identifier: detectedId)
        if from.languageCode?.identifier == target.languageCode?.identifier {
            let flipped = detectedId == "zh-CN" ? "en-US" : "zh-CN"
            return LangPair(from: from, to: .init(identifier: flipped))
        }
        return LangPair(from: from, to: target)
    }
}

/// 把所有窗口放到主屏（带菜单栏那块）中央，避免跑到外接屏或屏幕外
enum WindowPlacement {
    static func place(_ w: NSWindow) {
        let screen = NSScreen.screens.first ?? NSScreen.main
        guard let v = screen?.visibleFrame else { return }
        var f = w.frame
        f.size.width = min(f.width, v.width - 40)
        f.size.height = min(f.height, v.height - 40)
        f.origin.x = v.midX - f.width / 2
        f.origin.y = v.midY - f.height / 2
        w.setFrame(f, display: false)
    }
}
