import AppKit

/// 轻量 Markdown 渲染：标题、列表、引用、代码、粗体、行内代码。
/// 只用于显示，不改动原文。
enum MarkdownView {

    static func render(_ text: String, sourceSize: CGFloat, sourceColor: NSColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var inCode = false

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 代码块围栏
            if trimmed.hasPrefix("```") {
                inCode.toggle()
                continue
            }
            if inCode {
                out.append(styled(NSAttributedString(string: trimmed), font: .monospacedSystemFont(ofSize: sourceSize - 0.5, weight: .regular),
                                  color: .secondaryLabelColor, indent: 12, spacing: 6, sourceSize: sourceSize))
                continue
            }
            if trimmed.isEmpty { continue }

            // 标题
            if let (level, content) = heading(trimmed) {
                let sizes: [CGFloat] = [0, sourceSize + 7, sourceSize + 4, sourceSize + 2]
                let size = sizes[min(level, 3)]
                let f = NSFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold)
                out.append(styled(inline(content, size: size, bold: true, color: sourceColor),
                                  font: f, color: sourceColor, indent: 0, spacing: 10, sourceSize: sourceSize))
                continue
            }

            // 引用
            if trimmed.hasPrefix(">") {
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                out.append(styled(inline(content, size: sourceSize - 0.5, bold: false, color: .secondaryLabelColor),
                                  font: .systemFont(ofSize: sourceSize - 0.5),
                                  color: .secondaryLabelColor, indent: 14, spacing: 8, sourceSize: sourceSize))
                continue
            }

            // 列表
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                let content = "•  " + String(trimmed.dropFirst(2))
                out.append(styled(inline(content, size: sourceSize, bold: false, color: sourceColor),
                                  font: .systemFont(ofSize: sourceSize), color: sourceColor,
                                  indent: 10, spacing: 5, sourceSize: sourceSize))
                continue
            }

            out.append(styled(inline(trimmed, size: sourceSize, bold: false, color: sourceColor),
                              font: .systemFont(ofSize: sourceSize), color: sourceColor,
                              indent: 0, spacing: 8, sourceSize: sourceSize))
        }
        return out
    }

    private static func heading(_ line: String) -> (Int, String)? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level > 0, level <= 6 else { return nil }
        let content = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return (level, content)
    }

    /// 行内 **粗体**、`代码`
    private static func inline(_ s: String, size: CGFloat, bold: Bool, color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var idx = s.startIndex
        var buffer = ""

        func flush() {
            guard !buffer.isEmpty else { return }
            result.append(NSAttributedString(string: buffer, attributes: [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: color,
            ]))
            buffer = ""
        }

        while idx < s.endIndex {
            let rest = s[idx...]
            if rest.hasPrefix("**"), let end = rest.dropFirst(2).range(of: "**") {
                flush()
                let inner = String(rest.dropFirst(2)[..<end.lowerBound])
                result.append(NSAttributedString(string: inner, attributes: [
                    .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                    .foregroundColor: color,
                ]))
                idx = end.upperBound
                continue
            }
            if rest.hasPrefix("`"), let end = rest.dropFirst().firstIndex(of: "`") {
                flush()
                let inner = String(rest.dropFirst()[..<end])
                result.append(NSAttributedString(string: inner, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12),
                ]))
                idx = s.index(after: end)
                continue
            }
            buffer.append(s[idx])
            idx = s.index(after: idx)
        }
        flush()
        return result
    }

    private static func styled(_ attr: NSAttributedString, font: NSFont, color: NSColor,
                               indent: CGFloat, spacing: CGFloat, sourceSize: CGFloat) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: attr)
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 2.5
        p.paragraphSpacing = spacing
        p.headIndent = indent
        p.firstLineHeadIndent = indent
        m.addAttributes([.paragraphStyle: p, .foregroundColor: color], range: NSRange(location: 0, length: m.length))
        if m.length > 0, m.attribute(.font, at: 0, effectiveRange: nil) == nil {
            m.addAttribute(.font, value: font, range: NSRange(location: 0, length: m.length))
        }
        m.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: p]))
        return m
    }
}
