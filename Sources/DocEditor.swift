import AppKit
import Translation

/// 一个段落：原文 + 译文 + 状态
struct Segment {
    var source: String
    var target: String = ""
    var locked = false
    var sourceDirty = false
    var targetDirty = false
    var backTranslated = false
}

/// 文本视图：滚轮一律交给外层文档滚动，自身不滚动
final class DocTextView: NSTextView {
    override func scrollWheel(with event: NSEvent) {
        if let sv = enclosingScrollView {
            sv.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }
}

/// 段落行：左原文、右译文，都可编辑；不使用内部滚动视图，滚轮交给外层文档
final class SegmentRow: NSView, NSTextViewDelegate {
    var index = 0
    var onChange: ((Int, Bool, String) -> Void)?
    var onFocus: ((Int) -> Void)?
    var onToggleLock: ((Int) -> Void)?

    private let lockButton = NSButton()
    private let sourceView = DocTextView()
    private let targetView = DocTextView()
    private var heightConstraint: NSLayoutConstraint!

    init(index: Int, segment: Segment) {
        super.init(frame: .zero)
        self.index = index
        wantsLayer = true
        layer?.cornerRadius = 6

        lockButton.bezelStyle = .inline
        lockButton.isBordered = false
        lockButton.contentTintColor = .secondaryLabelColor
        lockButton.image = NSImage(systemSymbolName: segment.locked ? "lock.fill" : "lock.open",
                                   accessibilityDescription: "锁定此段")
        lockButton.target = self
        lockButton.action = #selector(toggleLock)
        lockButton.toolTip = "锁定后批量重译会跳过这一段"
        lockButton.translatesAutoresizingMaskIntoConstraints = false

        configure(sourceView)
        configure(targetView)
        sourceView.textColor = .secondaryLabelColor
        sourceView.font = .systemFont(ofSize: 12)
        targetView.textColor = .labelColor
        targetView.font = .systemFont(ofSize: 13)

        sourceView.string = segment.source
        targetView.string = segment.target
        sourceView.delegate = self
        targetView.delegate = self

        addSubview(lockButton)
        addSubview(sourceView)
        addSubview(targetView)

        NSLayoutConstraint.activate([
            lockButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            lockButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            lockButton.widthAnchor.constraint(equalToConstant: 16),
        ])

        let hc = heightAnchor.constraint(equalToConstant: 64)
        hc.isActive = true
        heightConstraint = hc

        layer?.backgroundColor = NSColor.clear.cgColor
        fitHeight()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configure(_ tv: DocTextView) {
        tv.isEditable = true
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.textContainerInset = NSSize(width: 6, height: 4)
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.autoresizingMask = []
    }

    private var lastWidth: CGFloat = 0

    override func layout() {
        super.layout()
        if abs(bounds.width - lastWidth) > 0.5 {
            lastWidth = bounds.width
            fitHeight()
        }
        let left: CGFloat = 28
        let totalW = max(bounds.width - left - 8, 120)
        let colW = (totalW - 10) / 2
        let h = max(bounds.height - 12, 24)
        sourceView.frame = NSRect(x: left, y: 6, width: colW, height: h)
        targetView.frame = NSRect(x: left + colW + 10, y: 6, width: colW, height: h)
    }

    /// 用文本视图自己的排版引擎测量（与绘制完全一致），避免算短
    private func usedHeight(_ tv: NSTextView, colW: CGFloat) -> CGFloat {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return 30 }
        tc.containerSize = NSSize(width: max(colW - 12, 60), height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        return ceil(lm.usedRect(for: tc).height)
    }

    /// 按两侧文本撑开行高
    func fitHeight() {
        let w = bounds.width > 200 ? bounds.width : 900
        let colW = max((w - 28 - 8 - 10) / 2, 120)
        let hs = usedHeight(sourceView, colW: colW)
        let ht = usedHeight(targetView, colW: colW)
        // 12 = 上下内边距，8 = 余量，防止最后一行被贴边裁掉
        let needed = max(hs, ht, 20) + 12 + 8
        if abs(heightConstraint.constant - needed) > 0.5 {
            heightConstraint.constant = needed
        }
        needsLayout = true
    }

    func update(_ s: Segment) {
        if sourceView.string != s.source { sourceView.string = s.source }
        if targetView.string != s.target { targetView.string = s.target }
        lockButton.image = NSImage(systemSymbolName: s.locked ? "lock.fill" : "lock.open",
                                   accessibilityDescription: "锁定此段")
        layer?.backgroundColor = (s.sourceDirty || s.targetDirty)
            ? NSColor.controlAccentColor.withAlphaComponent(0.07).cgColor
            : NSColor.clear.cgColor
        fitHeight()
    }

    /// 调试：最严重的一侧溢出量（>0 表示会被裁）
    func overflow() -> CGFloat {
        func used(_ tv: NSTextView) -> CGFloat {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return 0 }
            lm.ensureLayout(for: tc)
            return lm.usedRect(for: tc).height
        }
        return max(used(sourceView) - sourceView.frame.height, used(targetView) - targetView.frame.height)
    }

    /// 调试：返回视图高度与排版所需高度
    func debugSizes() -> String {
        func used(_ tv: NSTextView) -> CGFloat {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return -1 }
            lm.ensureLayout(for: tc)
            return lm.usedRect(for: tc).height
        }
        return String(format: "row=%.0f srcFrame=%.0f srcUsed=%.0f tgtFrame=%.0f container=%.0f width=%.0f",
                      bounds.height, sourceView.frame.height, used(sourceView),
                      targetView.frame.height,
                      sourceView.textContainer?.containerSize.width ?? -1,
                      sourceView.frame.width)
    }

    @objc private func toggleLock() { onToggleLock?(index) }

    func textDidChange(_ notification: Notification) {
        let v = notification.object as? NSTextView
        fitHeight()
        onChange?(index, v === targetView, v?.string ?? "")
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        onFocus?(index)
    }
}
