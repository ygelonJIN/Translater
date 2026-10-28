# macOS 应用构建

## 什么时候读

改打包脚本、加系统能力（服务、屏幕录制、辅助功能）、签名失效、界面不像原生时。

## 不开 Xcode 工程的打包流程

```
Sources/*.swift  --swiftc-->  Translater.app/Contents/MacOS/Translater
                    +
     Contents/Info.plist（手写，含 NSServices 等）
                    +
     codesign --force --sign - Translater.app
```

要点：

- 编译参数带 `-target arm64-apple-macos26.0`，低于此版本 `TranslationSession(installedSource:)` 不可用
- 编译缓存要放到工作区内（`-module-cache-path`），否则受沙箱限制写不进系统临时目录
- 顶层可执行代码只能放在 `main.swift`，其余文件只能是声明
- 图标：`icon.iconset` 里文件名必须严格符合 Apple 规范（`icon_16x16@2x.png` 这种），
  多一个 `icon_64x64.png` 就会整体失败，报错只给一句 "Failed to generate ICNS"

## 注册右键菜单（服务）

`Info.plist` 加：

```
NSServices = [ {
  NSMenuItem = { default = "用 Translater 翻译" },
  NSMessage  = "doTranslateService",
  NSPortName = "Translater",
  NSSendTypes = [ "NSStringPboardType", "public.utf8-plain-text" ],
  NSReturnTypes = []
} ]
```

- 启动时设 `NSApp.servicesProvider = self`，实现
  `@objc func doTranslateService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>)`
- 验证是否登记成功：`/System/Library/CoreServices/pbs -dump | grep <bundle id>`；
  注意 dump 里中文是 `\Uxxxx` 转义，别直接 grep 中文
- 第三方应用只能进「服务」二级菜单，一级菜单（和系统「翻译」并列）拿不到
- 服务表有缓存，改完 Info.plist 要重启应用，必要时重启 Finder

## 原生风格的几个固定动作

- 控件一律 AppKit：`NSStackView` 布局、`NSBox(.custom)` 做圆角卡片、`NSPopUpButton` 做选择
- 图标一律 `NSImage(systemSymbolName:)`，取不到时要有兜底，否则点击区变成一个 "A" 占位图
- 颜色一律语义色：`labelColor` / `secondaryLabelColor` / `separatorColor` / `controlAccentColor`
- 浮窗用 `NSVisualEffectView(.popover, behindWindow)` + 圆角，面板设 `.nonactivatingPanel` 不抢焦点
- 覆盖层要 `ignoresMouseEvents = true`，点击穿透
- 窗口背景记得设 `isOpaque = true` + `backgroundColor`，否则透明到能看到桌面

## 沙箱环境里踩过的坑

| 现象 | 原因 | 处理 |
|---|---|---|
| 写文件报 "not permitted" | `atomically: true` 走系统临时目录 | 改成 `atomically: false`，或自己写 Data |
| SwiftUI `@State` 编译失败 | 宏插件进程起不来 | 用 AppKit，或改用不带 `@State` 的写法 |
| `iconutil` 生成失败 | 需要访问临时目录 | 在完整权限下跑一次 |
| `ps` / `lsof` 被拦 | 进程与网络信息受保护 | 需要时提升权限 |
| Vision OCR 返回 `unknownError` | 走 XPC 服务 | 同上，完整权限下正常 |

## 覆盖层（全屏翻译）

- 窗口：`NSWindow(.borderless)`，`level = .screenSaver`，`isOpaque = false`，
  `backgroundColor = .clear`，`ignoresMouseEvents = true`（点击穿透）
- 视图要重写 `hitTest` 返回 nil，双保险
- **必须给一个能点的关闭出口**。点穿透的窗口连自己都点不到，用户会直接被困住。
  实测教训：第一版只有 Esc 和菜单项，Esc 需要辅助功能权限、菜单栏又被盖住，等于没有出口。
  第二版加了顶部常驻的黑色胶囊「关闭全屏翻译」，`NSPanel(.nonactivatingPanel)`、不穿透、
  `level = .screenSaver`，再加 60 秒自动消失兜底
- 胶囊要在 `.screenSaver` 层级并且**后添加**，否则会被覆盖层压住
- 用 `NSVisualEffectView` 做胶囊在浅色背景上会发灰，直接铺 `black 0.8` 的图层更可靠
- 坐标换算：OCR 的 bbox 是归一化、原点左下；窗口坐标原点也是左下，但要乘缩放系数并翻转 Y

## 签名与系统授权

- **用钥匙串里的 Apple 开发证书签名**（`Apple Development: 861801…`，Team `J7WK3943PY`），
  不要用 ad-hoc：ad-hoc 每次编译都会换哈希，系统按哈希认身份，任何基于签名身份的授权（屏幕录制等）
  会每次失效，用户被反复要求授权。
- 换成开发证书后，授权绑定在「签名身份 + Bundle ID」上，重编译不再掉权限。
- 一旦接入屏幕录制、辅助功能，**必须换成固定自签证书**（钥匙串 → 证书助理 →
  代码签名），否则每次重编译授权都失效，用户要反复点允许
- 应用放 `/Applications` 时服务菜单最稳定，放在外接盘也能用，但服务缓存偶尔要重启 Finder
