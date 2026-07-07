import AppKit
import Foundation
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var lastBalance: String?
    private let refreshInterval: TimeInterval = 300

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 检查是否需要安装到 /Applications
        if needsInstall() {
            offerInstall()
            return
        }

        setupMenuBar()
        startApp()
    }

    // MARK: - 自动安装

    private func needsInstall() -> Bool {
        return !Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    private func offerInstall() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "安装 DeepSeek Balance"
        alert.informativeText = "为了正常使用所有功能，需要将应用安装到「应用程序」文件夹。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "安装")
        alert.addButton(withTitle: "仅这次使用")
        alert.icon = NSImage(named: NSImage.infoName)

        if alert.runModal() == .alertFirstButtonReturn {
            installToApplications()
        } else {
            setupMenuBar()
            startApp()
        }
    }

    private func installToApplications() {
        let dest = "/Applications/DeepSeekBalance.app"

        // 删除旧版本
        if FileManager.default.fileExists(atPath: dest) {
            try? FileManager.default.removeItem(atPath: dest)
        }

        do {
            try FileManager.default.copyItem(atPath: Bundle.main.bundlePath, toPath: dest)

            // 移除隔离属性
            let task = Process()
            task.launchPath = "/usr/bin/xattr"
            task.arguments = ["-dr", "com.apple.quarantine", dest]
            task.launch()
            task.waitUntilExit()

            // 重新从 /Applications 启动
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: dest), configuration: config) { _, _ in }
            NSApplication.shared.terminate(nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "安装失败"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好的")
            alert.runModal()
            setupMenuBar()
            startApp()
        }
    }

    // MARK: - 启动流程

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⏳"
    }

    private func startApp() {
        let savedKey = UserDefaults.standard.string(forKey: "api_key") ?? ""
        if savedKey.isEmpty {
            showMenu(items: [loadingItem(), separator(), installStatusItem(), separator(), changeKeyItem(), separator(), quitItem()])
            askForAPIKey()
        } else {
            showDefaultMenu()
            fetchBalance(apiKey: savedKey)
            startTimer()
        }
    }

    // MARK: - 菜单项构建

    private func loadingItem() -> NSMenuItem {
        return NSMenuItem(title: "查询中...", action: nil, keyEquivalent: "")
    }

    private func separator() -> NSMenuItem {
        return NSMenuItem.separator()
    }

    private func balanceItem(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: "余额: \(text)", action: nil, keyEquivalent: "")
        return item
    }

    private func copyItem() -> NSMenuItem {
        return NSMenuItem(title: "点击复制余额", action: #selector(copyBalance), keyEquivalent: "c")
    }

    private func installStatusItem() -> NSMenuItem {
        let inApps = Bundle.main.bundlePath.hasPrefix("/Applications/")
        return NSMenuItem(title: inApps ? "✅ 已安装" : "⚠️ 未安装到 Applications", action: nil, keyEquivalent: "")
    }

    private func changeKeyItem() -> NSMenuItem {
        return NSMenuItem(title: "修改 API Key", action: #selector(changeAPIKey), keyEquivalent: "")
    }

    private func refreshItem() -> NSMenuItem {
        return NSMenuItem(title: "立即刷新", action: #selector(refreshBalance), keyEquivalent: "r")
    }

    private func loginItem() -> NSMenuItem {
        let enabled = isLoginItemEnabled()
        return NSMenuItem(
            title: enabled ? "✅ 开机自启" : "☐ 开机自启",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
    }

    private func quitItem() -> NSMenuItem {
        return NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
    }

    private func errorItem(_ msg: String) -> NSMenuItem {
        return NSMenuItem(title: msg, action: nil, keyEquivalent: "")
    }

    // MARK: - 菜单管理

    private func showMenu(items: [NSMenuItem]) {
        let menu = NSMenu()
        for item in items { menu.addItem(item) }
        statusItem.menu = menu
    }

    private func showDefaultMenu(balance: String? = nil, error: String? = nil) {
        let menu = NSMenu()

        if let b = balance {
            menu.addItem(balanceItem(b))
            menu.addItem(copyItem())
        } else if let e = error {
            menu.addItem(NSMenuItem(title: "查询失败", action: nil, keyEquivalent: ""))
            menu.addItem(errorItem(e))
        } else {
            menu.addItem(loadingItem())
        }

        menu.addItem(separator())
        menu.addItem(loginItem())
        menu.addItem(separator())
        menu.addItem(changeKeyItem())
        menu.addItem(refreshItem())
        menu.addItem(separator())
        menu.addItem(quitItem())

        statusItem.menu = menu
    }

    // MARK: - API Key

    private func askForAPIKey() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "欢迎使用 DeepSeek Balance"
        alert.informativeText = "请输入您的 DeepSeek API Key\n在 platform.deepseek.com 的 API Keys 页面获取"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "退出")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 28))
        textField.placeholderString = "sk-xxxxxxxxxxxxxxxx"
        textField.isBordered = true
        textField.bezelStyle = .roundedBezel
        alert.accessoryView = textField
        textField.becomeFirstResponder()

        if alert.runModal() == .alertFirstButtonReturn {
            let key = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                UserDefaults.standard.set(key, forKey: "api_key")
                showDefaultMenu()
                fetchBalance(apiKey: key)
                startTimer()
                return
            }
        }
        NSApplication.shared.terminate(nil)
    }

    @objc private func changeAPIKey() {
        timer?.invalidate()
        statusItem.button?.title = "🔑"
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "修改 API Key"
        alert.informativeText = "输入新的 DeepSeek API Key"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 28))
        textField.placeholderString = "sk-xxxxxxxxxxxxxxxx"
        textField.stringValue = UserDefaults.standard.string(forKey: "api_key") ?? ""
        textField.isBordered = true
        textField.bezelStyle = .roundedBezel
        alert.accessoryView = textField
        textField.becomeFirstResponder()

        if alert.runModal() == .alertFirstButtonReturn {
            let key = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                UserDefaults.standard.set(key, forKey: "api_key")
                showDefaultMenu()
                fetchBalance(apiKey: key)
                startTimer()
                return
            }
        }
        let key = UserDefaults.standard.string(forKey: "api_key") ?? ""
        if !key.isEmpty {
            showDefaultMenu()
            fetchBalance(apiKey: key)
            startTimer()
        } else {
            showMenu(items: [loadingItem(), separator(), installStatusItem(), separator(), changeKeyItem(), separator(), quitItem()])
            askForAPIKey()
        }
    }

    // MARK: - 刷新

    @objc private func refreshBalance() {
        let key = UserDefaults.standard.string(forKey: "api_key") ?? ""
        if key.isEmpty {
            askForAPIKey()
        } else {
            showDefaultMenu()
            fetchBalance(apiKey: key)
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let key = UserDefaults.standard.string(forKey: "api_key") ?? ""
            if !key.isEmpty {
                self.fetchBalance(apiKey: key)
            }
        }
    }

    // MARK: - API

    private func fetchBalance(apiKey: String) {
        guard let url = URL(string: "https://api.deepseek.com/user/balance") else { return }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                guard error == nil, let data = data else {
                    self.statusItem.button?.title = "❌"
                    self.showDefaultMenu(error: error?.localizedDescription ?? "无响应")
                    return
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let isAvailable = json["is_available"] as? Bool
                else {
                    let raw = String(data: data, encoding: .utf8) ?? "解析失败"
                    self.statusItem.button?.title = "❌"
                    self.showDefaultMenu(error: String(raw.prefix(300)))
                    return
                }

                if !isAvailable {
                    self.statusItem.button?.title = "🚫"
                    self.showDefaultMenu(error: "余额不可用")
                    return
                }

                guard let infos = json["balance_infos"] as? [[String: Any]],
                      let first = infos.first,
                      let total = first["total_balance"] as? String,
                      let currency = first["currency"] as? String
                else {
                    self.statusItem.button?.title = "❌"
                    self.showDefaultMenu(error: "数据格式异常")
                    return
                }

                let symbol = currency == "CNY" ? "¥" : (currency == "USD" ? "$" : currency)
                self.lastBalance = total
                self.statusItem.button?.title = "💰 \(symbol)\(total)"
                self.showDefaultMenu(balance: "\(symbol)\(total)")
            }
        }.resume()
    }

    // MARK: - 复制余额

    @objc private func copyBalance() {
        if let balance = lastBalance {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(balance, forType: .string)

            let alert = NSAlert()
            alert.messageText = "已复制"
            alert.informativeText = "余额 \(balance) 已复制到剪贴板"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好的")
            alert.runModal()
        } else {
            // 重新获取
            let key = UserDefaults.standard.string(forKey: "api_key") ?? ""
            guard !key.isEmpty, let url = URL(string: "https://api.deepseek.com/user/balance") else { return }

            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { data, _, _ in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let infos = json["balance_infos"] as? [[String: Any]],
                      let first = infos.first,
                      let total = first["total_balance"] as? String
                else { return }

                DispatchQueue.main.async {
                    self.lastBalance = total
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(total, forType: .string)
                    let alert = NSAlert()
                    alert.messageText = "已复制"
                    alert.informativeText = "余额 \(total) 已复制到剪贴板"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "好的")
                    alert.runModal()
                }
            }.resume()
        }
    }

    // MARK: - 开机自启

    private func isLoginItemEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLoginItem() {
        guard #available(macOS 13.0, *) else {
            let alert = NSAlert()
            alert.messageText = "需要 macOS 13 或更新版本"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好的")
            alert.runModal()
            return
        }

        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            refreshMenuCheckmark()
        } catch {
            let alert = NSAlert()
            alert.messageText = "设置失败"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好的")
            alert.runModal()
        }
    }

    private func refreshMenuCheckmark() {
        let enabled = isLoginItemEnabled()
        if let menu = statusItem.menu {
            for item in menu.items {
                if item.action == #selector(toggleLoginItem) {
                    item.title = enabled ? "✅ 开机自启" : "☐ 开机自启"
                    break
                }
            }
        }
    }

    // MARK: - 退出

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - 启动

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
