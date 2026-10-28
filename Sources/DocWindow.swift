import AppKit
import Translation


enum DLog {
    static let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/Translater.log")
    static func w(_ m: String) {
        let line = "[\(Date().formatted(date: .omitted, time: .standard))] \(m)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.data(using: .utf8)!.write(to: url)
        }
    }
}

/// 文档窗口：逐段对照编辑 + 增量重译 + 回译 + 双版本导出
final class DocWindowController: NSWindowController, NSToolbarDelegate {

    static let shared = DocWindowController()

    private var segments: [Segment] = []
    private var rows: [SegmentRow] = []
    private var fileURL: URL?
    private var pair: LangPair = LangPair(from: .init(identifier: "en-US"), to: .init(identifier: "zh-CN"))
    private var busy = false

    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "打开一个 Markdown 或文本文件开始")
    private var progress: NSProgressIndicator?

    private convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "Translater"
        w.minSize = NSSize(width: 640, height: 400)
        WindowPlacement.place(w)
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        w.hidesOnDeactivate = false
        self.init(window: w)
        buildToolbar()
        buildContent()
    }

    private func buildContent() {
        guard let w = window, let content = w.contentView else { return }

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])

        scroll.documentView = doc
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        // 让文档宽度跟随滚动视图
        if let clip = scroll.contentView as NSClipView? {
            _ = clip
        }
        doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
    }

    // MARK: - 工具栏

    private func buildToolbar() {
        let tb = NSToolbar(identifier: "editor")
        tb.delegate = self
        tb.displayMode = .iconAndLabel
        tb.allowsUserCustomization = false
        window?.toolbar = tb
        window?.toolbarStyle = .unified
    }

    private func item(_ id: String, _ symbol: String, _ label: String, _ action: Selector) -> NSToolbarItem {
        let it = NSToolbarItem(itemIdentifier: .init(id))
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(),
                         target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.isBordered = true
        it.view = b
        it.label = label
        it.paletteLabel = label
        it.toolTip = label
        return it
    }

    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("open"), .init("translate"), .init("retranslate"), .init("backtranslate"),
         .flexibleSpace, .init("exportZh"), .init("exportEn")]
    }

    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("open"), .init("translate"), .init("retranslate"), .init("backtranslate"),
         .flexibleSpace, .init("exportZh"), .init("exportEn")]
    }

    func toolbar(_ t: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id.rawValue {
        case "open": return item("open", "folder", "打开", #selector(openFile))
        case "translate": return item("translate", "character.bubble", "整篇翻译", #selector(translateAll))
        case "retranslate": return item("retranslate", "arrow.clockwise", "重译", #selector(retranslateFocused))
        case "backtranslate": return item("backtranslate", "arrow.uturn.backward", "回译改动", #selector(backTranslateDirty))
        case "exportZh": return item("exportZh", "square.and.arrow.down", "导出译文", #selector(exportTarget))
        case "exportEn": return item("exportEn", "square.and.arrow.up", "导出原文", #selector(exportSource))
        default: return nil
        }
    }

    // MARK: - 打开

    /// 强制把文档窗口拉到当前空间最前面
    func forceShow() {
        WindowPlacement.place(window!)
        window?.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.plainText, .init(filenameExtension: "md")!]
        p.allowsMultipleSelection = false
        p.message = "选择 Markdown 或纯文本文件"
        guard p.runModal() == .OK, let url = p.url else { return }
        open(url: url)
    }

    func open(url: URL) {
        // 同一文件重复打开（双击 + 启动参数同时触发）时，只把窗口拉到前面
        if fileURL == url, !segments.isEmpty {
            forceShow()
            return
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            alert("读不到文件：\(url.lastPathComponent)")
            return
        }
        fileURL = url
        segments = parse(text)
        pair = Prefs.pair(for: segments.first?.source ?? "")
        rebuildRows()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let heights = self.rows.prefix(6).map { Int($0.frame.height) }
            DLog.w("行高=\(heights) 段字数=\(self.segments.prefix(6).map { $0.source.count })")
            if self.rows.count > 1 { DLog.w("段2: " + self.rows[1].debugSizes()) }
            let worst = self.rows.map { $0.overflow() }.max() ?? 0
            DLog.w(String(format: "最大溢出 %.1f pt（<=0 表示没有裁切）", worst))
        }
        window?.title = url.lastPathComponent
        window?.subtitle = "\(segments.count) 段"
        emptyLabel.isHidden = !segments.isEmpty
        DLog.w("open(url:) 开始 \(url.lastPathComponent) 段数=\(segments.count)")
        showWindow(nil)
        window?.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        if !(window?.isOnActiveSpace ?? true) {
            window?.orderOut(nil)
            window?.orderFrontRegardless()
        }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        DLog.w("open 后 visible=\(window?.isVisible ?? false) activeSpace=\(window?.isOnActiveSpace ?? false) frame=\(window?.frame ?? .zero) screen=\(window?.screen?.frame ?? .zero) screens=\(NSScreen.screens.map { $0.frame })")
    }

    private func parse(_ text: String) -> [Segment] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { Segment(source: $0) }
    }

    private func rebuildRows() {
        for r in rows { stack.removeArrangedSubview(r); r.removeFromSuperview() }
        rows.removeAll()

        for (i, seg) in segments.enumerated() {
            let row = SegmentRow(index: i, segment: seg)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.onChange = { [weak self] idx, isTarget, text in
                guard let self, idx < self.segments.count else { return }
                if isTarget {
                    self.segments[idx].target = text
                    self.segments[idx].targetDirty = true
                } else {
                    self.segments[idx].source = text
                    self.segments[idx].sourceDirty = true
                }
                self.refreshRow(idx)
            }
            row.onFocus = { [weak self] idx in self?.focusedIndex = idx }
            row.onToggleLock = { [weak self] idx in
                guard let self, idx < self.segments.count else { return }
                self.segments[idx].locked.toggle()
                self.refreshRow(idx)
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
            rows.append(row)
        }
        emptyLabel.isHidden = !segments.isEmpty
    }

    private var focusedIndex = 0

    private func refreshRow(_ i: Int) {
        guard i < rows.count else { return }
        rows[i].update(segments[i])
    }

    // MARK: - 翻译

    @objc func translateAll() {
        guard !segments.isEmpty, !busy else { return }
        busy = true
        let src = pair
        Task { @MainActor in
            defer { busy = false }
            for i in 0..<segments.count where !segments[i].locked {
                guard !segments[i].source.isEmpty else { continue }
                do {
                    let t = try await self.translate(segments[i].source, from: src.from, to: src.to)
                    self.segments[i].target = t
                    self.segments[i].targetDirty = false
                    self.refreshRow(i)
                    self.window?.subtitle = "翻译中 \(i + 1)/\(self.segments.count)"
                } catch {
                    self.alert("第 \(i + 1) 段翻译失败：\(error.localizedDescription)")
                    break
                }
            }
            self.window?.subtitle = "\(self.segments.count) 段 · 已完成"
        }
    }

    /// 重译当前聚焦段落
    @objc func retranslateFocused() {
        let i = min(focusedIndex, segments.count - 1)
        guard i >= 0, !segments.isEmpty, !segments[i].locked else { return }
        retranslate(index: i)
    }

    private func retranslate(index i: Int) {
        let old = segments[i].target
        Task { @MainActor in
            do {
                let t = try await self.translate(self.segments[i].source, from: self.pair.from, to: self.pair.to)
                if !old.isEmpty && old != t {
                    if self.confirmDiff(old: old, new: t) {
                        self.segments[i].target = t
                        self.segments[i].targetDirty = false
                    }
                } else {
                    self.segments[i].target = t
                    self.segments[i].targetDirty = false
                }
                self.refreshRow(i)
            } catch {
                self.alert("重译失败：\(error.localizedDescription)")
            }
        }
    }

    /// 把「译文被人工改过」的段落回译回原文语言
    @objc func backTranslateDirty() {
        guard !segments.isEmpty, !busy else { return }
        let indices = segments.indices.filter { segments[$0].targetDirty && !segments[$0].locked }
        guard !indices.isEmpty else {
            alert("没有改动过的译文段落")
            return
        }
        busy = true
        let rev = LangPair(from: pair.to, to: pair.from)
        Task { @MainActor in
            defer { busy = false }
            for i in indices {
                let t = self.segments[i].target
                guard !t.isEmpty else { continue }
                do {
                    let back = try await self.translate(t, from: rev.from, to: rev.to)
                    self.segments[i].source = back
                    self.segments[i].backTranslated = true
                    self.segments[i].targetDirty = false
                    self.refreshRow(i)
                    self.window?.subtitle = "回译 \(i + 1)/\(self.segments.count)"
                } catch {
                    self.alert("第 \(i + 1) 段回译失败：\(error.localizedDescription)")
                    break
                }
            }
            self.window?.subtitle = "\(self.segments.count) 段 · 回译完成"
        }
    }

    private func translate(_ text: String, from: Locale.Language, to: Locale.Language) async throws -> String {
        let session = TranslationSession(installedSource: from, target: to)
        try await session.prepareTranslation()
        return try await session.translate(text).targetText
    }

    private func confirmDiff(old: String, new: String) -> Bool {
        let a = NSAlert()
        a.messageText = "重译结果和现有译文不同"
        a.informativeText = "旧：\n\(old)\n\n新：\n\(new)"
        a.addButton(withTitle: "采用新译文")
        a.addButton(withTitle: "保留旧的")
        return a.runModal() == .alertFirstButtonReturn
    }

    // MARK: - 导出

    @objc func exportTarget() { export(side: .target) }
    @objc func exportSource() { export(side: .source) }

    private enum Side { case source, target }

    private func export(side: Side) {
        guard !segments.isEmpty else { return }
        let text = segments.map { side == .target ? $0.target : $0.source }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !text.isEmpty else { alert("没有可导出的内容"); return }

        let p = NSSavePanel()
        let base = fileURL?.deletingPathExtension().lastPathComponent ?? "translation"
        let ext = fileURL?.pathExtension ?? "md"
        let tag = side == .target ? "zh" : "src"
        p.nameFieldStringValue = "\(base).\(tag).\(ext)"
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            try text.write(to: url, atomically: false, encoding: .utf8)
            window?.subtitle = "已导出 \(url.lastPathComponent)"
        } catch {
            alert("写入失败：\(error.localizedDescription)")
        }
    }

    private func alert(_ msg: String) {
        let a = NSAlert()
        a.messageText = "Translater"
        a.informativeText = msg
        a.runModal()
    }
}
