import AppKit
import Translation

// MARK: - 命令行：Translater --selftest <in.md> <out.md>

func runSelfTest(input: String, output: String) {
    Task {
        guard let text = try? String(contentsOfFile: input, encoding: .utf8) else {
            FileHandle.standardError.write("读不到输入\n".data(using: .utf8)!); exit(2)
        }
        let pair = Engine.shared.autoPair(for: text)
        print("方向 \(pair.label)，\(text.count) 字")
        let t0 = Date()
        do {
            let r = try await Engine.shared.translate(text, pair: pair, chunkSize: 1200) { i, n in
                print("  块 \(i)/\(n)")
            }
            try r.write(toFile: output, atomically: false, encoding: .utf8)
            print(String(format: "完成 %.1f s，输出 %d 字 → %@",
                         Date().timeIntervalSince(t0), r.count, output))
            exit(0)
        } catch {
            FileHandle.standardError.write("失败: \(error)\n".data(using: .utf8)!); exit(1)
        }
    }
    dispatchMain()
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ n: Notification) {
        buildMenu()
        DashboardController.shared.showWindowAndActivate()

        if let i = CommandLine.arguments.firstIndex(of: "--open"), CommandLine.arguments.count > i + 1 {
            let path = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                DocWindowController.shared.open(url: URL(fileURLWithPath: path))
            }
        }

        let args = CommandLine.arguments.dropFirst()
        if let path = args.first(where: { !$0.hasPrefix("--") }),
           FileManager.default.fileExists(atPath: path) {
            DocWindowController.shared.open(url: URL(fileURLWithPath: path))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func application(_ app: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        DocWindowController.shared.open(url: url)
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Translater", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "打开文件…", action: #selector(openFile), keyEquivalent: "o")
        appMenu.addItem(withTitle: "打开主界面", action: #selector(showDashboard), keyEquivalent: "1")
        appMenu.addItem(withTitle: "显示文档窗口", action: #selector(showDocWindow), keyEquivalent: "2")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Translater", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        for item in appMenu.items where item.action != #selector(NSApplication.terminate(_:)) && item.action != nil {
            item.target = self
        }
        NSApp.mainMenu = main
    }

    @objc private func showDashboard() { DashboardController.shared.showWindowAndActivate() }
    @objc private func openFile() { DocWindowController.shared.openFile() }
    @objc private func showDocWindow() { DocWindowController.shared.forceShow() }
    @objc private func about() {
        let a = NSAlert()
        a.messageText = "Translater"
        a.informativeText = "文档翻译。\n使用 macOS 设备端翻译模型，不联网、不限字数。"
        a.runModal()
    }
}

// MARK: - 启动

let argv = CommandLine.arguments
if let idx = argv.firstIndex(of: "--selftest"), argv.count > idx + 2 {
    runSelfTest(input: argv[idx + 1], output: argv[idx + 2])
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
