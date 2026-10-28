import Foundation
import Translation
import AppKit

/// 语言方向
struct LangPair {
    let from: Locale.Language
    let to: Locale.Language

    /// 源语言与目标语言是否为同一语种（同语种无法翻译）
    var isSameLanguage: Bool {
        from.languageCode?.identifier == to.languageCode?.identifier
    }
    var label: String { "\(LanguageNames.display(from)) → \(LanguageNames.display(to))" }
}

/// 中文语言名：英文（美国）、中文（简体）、日文（日本）……
enum LanguageNames {
    private static let zhLocale = Locale(identifier: "zh_CN")

    /// 语 → 文（Apple 中文界面的习惯写法）
    private static let style: [String: String] = [
        "en": "英文", "ja": "日文", "fr": "法文", "de": "德文",
        "ko": "韩文", "es": "西班牙文", "ru": "俄文", "it": "意大利文",
        "pt": "葡萄牙文", "ar": "阿拉伯文", "th": "泰文", "vi": "越南文",
        "nl": "荷兰文", "pl": "波兰文", "tr": "土耳其文", "uk": "乌克兰文",
        "el": "希腊文", "he": "希伯来文", "hi": "印地文", "id": "印尼文",
    ]

    static func display(_ l: Locale.Language) -> String {
        guard let code = l.languageCode?.identifier else { return "未知" }
        let region = l.region?.identifier

        if code.hasPrefix("zh") {
            if let r = region, r == "TW" || r == "HK" || r == "MO" { return "中文（繁体）" }
            return "中文（简体）"
        }

        let base = style[code]
            ?? zhLocale.localizedString(forLanguageCode: code).map { $0.replacingOccurrences(of: "语", with: "文") }
            ?? code

        guard let r = region,
              let regionName = zhLocale.localizedString(forRegionCode: r) else { return base }
        return "\(base)（\(regionName)）"
    }
}

/// 本机翻译引擎（Translation.framework，设备端模型，零网络）
final class Engine {
    static let shared = Engine()
    private init() {}

    /// 粗略判断是否中文原文
    func isChinese(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return false }
        let cjk = scalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        return Double(cjk) / Double(scalars.count) > 0.15
    }

    /// 自动方向：中文→英文，其他→中文
    func autoPair(for text: String) -> LangPair {
        if isChinese(text) {
            return LangPair(from: Locale.Language(identifier: "zh-CN"),
                            to: Locale.Language(identifier: "en-US"))
        }
        return LangPair(from: Locale.Language(identifier: "en-US"),
                        to: Locale.Language(identifier: "zh-CN"))
    }

    func status(_ pair: LangPair) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: pair.from, to: pair.to)
    }

    func isInstalled(_ pair: LangPair) async -> Bool {
        await status(pair) == .installed
    }

    /// 分块：优先段落边界，超长再按句末标点切
    func chunk(_ text: String, maxChars: Int) -> [String] {
        var pieces: [String] = []
        for para in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let p = String(para).trimmingCharacters(in: .whitespaces)
            if p.isEmpty { continue }
            if p.count <= maxChars { pieces.append(p); continue }
            var cur = ""
            for ch in p {
                cur.append(ch)
                if "。！？.!?；;".contains(ch), cur.count >= maxChars / 2 {
                    pieces.append(cur); cur = ""
                }
            }
            if !cur.isEmpty { pieces.append(cur) }
        }
        var chunks: [String] = []
        var buf = ""
        for p in pieces {
            if buf.isEmpty { buf = p }
            else if buf.count + p.count + 1 <= maxChars { buf += "\n" + p }
            else { chunks.append(buf); buf = p }
        }
        if !buf.isEmpty { chunks.append(buf) }
        return chunks
    }

    /// 翻译长文本，逐块回调进度
    func translate(_ text: String,
                   pair: LangPair,
                   chunkSize: Int = 1200,
                   progress: ((Int, Int) -> Void)? = nil) async throws -> String {
        let parts = chunk(text, maxChars: chunkSize)
        let session = TranslationSession(installedSource: pair.from, target: pair.to)
        try await session.prepareTranslation()
        var out: [String] = []
        for (i, p) in parts.enumerated() {
            let r = try await session.translate(p)
            out.append(r.targetText)
            progress?(i + 1, parts.count)
        }
        return out.joined(separator: "\n")
    }

    /// 单段短文本
    func translateShort(_ text: String, pair: LangPair) async throws -> String {
        let session = TranslationSession(installedSource: pair.from, target: pair.to)
        try await session.prepareTranslation()
        return try await session.translate(text).targetText
    }
}


/// 语言包状态与系统设置跳转
enum LanguageSupport {
    static let settingsURL = "x-apple.systempreferences:com.apple.Localization-Settings.extension"

    static func describe(_ s: LanguageAvailability.Status) -> (text: String, color: NSColor, needsAction: Bool) {
        switch s {
        case .installed: return ("已就绪（本机）", .systemGreen, false)
        case .supported: return ("未下载语言包", .systemOrange, true)
        default:         return ("系统不支持该语言", .systemRed, false)
        }
    }

    /// 打开「系统设置 → 通用 → 语言与地区」
    static func openSettings() {
        let fallback = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        if let url = URL(string: settingsURL), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(fallback)
    }
}


enum Alerts {
    /// 源语言与目标语言相同的提示
    static func sameLanguage(_ pair: LangPair) {
        let a = NSAlert()
        a.messageText = "源语言和目标语言相同"
        a.informativeText = "当前方向是 " + pair.label + "，这样没法翻译。\n\n如果原文是另一种语言，请把「目标语言」换成你要的语言，或把源语言设为「自动检测」。"
        a.alertStyle = .informational
        a.addButton(withTitle: "好")
        a.runModal()
    }
    /// 语言包缺失时的统一提示，附带跳转系统设置
    static func needsLanguage(_ pair: LangPair) {
        let a = NSAlert()
        a.messageText = "需要先下载语言包"
        a.informativeText = pair.label + " 的语言包还没装在这台 Mac 上。\n\n注意：语言包按「语言＋地区」分别下载，英文（美国）和英文（英国）是两份不同的包，互不通用。\n\n请在「系统设置 → 通用 → 语言与地区 → 翻译语言」里勾选对应语言下载，完成后回到这里即可使用。"
        a.alertStyle = .informational
        a.addButton(withTitle: "打开系统设置")
        a.addButton(withTitle: "稍后")
        if a.runModal() == .alertFirstButtonReturn { LanguageSupport.openSettings() }
    }
}
