import Foundation
import SwiftUI

// MARK: - 网站目录

struct Site: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var url: String
    var symbol: String
    var tint: String
    var hint: String
}

enum SiteCatalog {
    static let custom = Site(
        id: "custom", name: "自定义网站", url: "https://",
        symbol: "globe", tint: "64748B", hint: "填写任意 https 地址"
    )

    static let all: [Site] = [
        Site(id: "whatsapp", name: "WhatsApp", url: "https://web.whatsapp.com", symbol: "message.fill", tint: "25A65B", hint: "需手机端扫码授权"),
        Site(id: "telegram", name: "Telegram", url: "https://web.telegram.org", symbol: "paperplane.fill", tint: "229ED9", hint: "网页版登录最顺畅"),
        Site(id: "wechat", name: "微信网页版", url: "https://wx.qq.com", symbol: "bubble.left.and.bubble.right.fill", tint: "07B35A", hint: "多数账号已不支持网页登录"),
        Site(id: "weibo", name: "微博", url: "https://weibo.com", symbol: "eye.fill", tint: "E6612C", hint: "建议开桌面模式"),
        Site(id: "xiaohongshu", name: "小红书", url: "https://www.xiaohongshu.com", symbol: "book.fill", tint: "E5323D", hint: "部分功能会引导下载 App"),
        Site(id: "douyin", name: "抖音", url: "https://www.douyin.com", symbol: "music.note", tint: "161823", hint: "网页版功能受限"),
        Site(id: "bilibili", name: "哔哩哔哩", url: "https://www.bilibili.com", symbol: "play.rectangle.fill", tint: "00A1D6", hint: "建议开桌面模式"),
        Site(id: "zhihu", name: "知乎", url: "https://www.zhihu.com", symbol: "questionmark.circle.fill", tint: "1772F6", hint: "建议开桌面模式"),
        Site(id: "x", name: "X", url: "https://x.com", symbol: "at", tint: "1D1D1F", hint: ""),
        Site(id: "instagram", name: "Instagram", url: "https://www.instagram.com", symbol: "camera.fill", tint: "C13584", hint: "网页版发帖受限"),
        Site(id: "facebook", name: "Facebook", url: "https://www.facebook.com", symbol: "f.cursive", tint: "1877F2", hint: ""),
        Site(id: "discord", name: "Discord", url: "https://discord.com/app", symbol: "gamecontroller.fill", tint: "5865F2", hint: "建议开桌面模式"),
        Site(id: "gmail", name: "Gmail", url: "https://mail.google.com", symbol: "envelope.fill", tint: "EA4335", hint: "多账号切换最实用"),
        Site(id: "outlook", name: "Outlook", url: "https://outlook.live.com", symbol: "envelope.fill", tint: "0F6CBD", hint: ""),
        Site(id: "notion", name: "Notion", url: "https://www.notion.so", symbol: "doc.text.fill", tint: "37352F", hint: ""),
        Site(id: "github", name: "GitHub", url: "https://github.com", symbol: "chevron.left.forwardslash.chevron.right", tint: "24292F", hint: ""),
        Site(id: "google", name: "Google", url: "https://www.google.com", symbol: "magnifyingglass", tint: "4285F4", hint: ""),
        Site(id: "taobao", name: "淘宝", url: "https://www.taobao.com", symbol: "bag.fill", tint: "FF5000", hint: "网页版常要求 App 验证"),
        Site(id: "jd", name: "京东", url: "https://www.jd.com", symbol: "cart.fill", tint: "E1251B", hint: ""),
        Site(id: "linkedin", name: "LinkedIn", url: "https://www.linkedin.com", symbol: "briefcase.fill", tint: "0A66C2", hint: ""),
        Site(id: "youtube", name: "YouTube", url: "https://www.youtube.com", symbol: "play.circle.fill", tint: "FF0000", hint: ""),
        custom
    ]

    static func find(_ id: String) -> Site {
        all.first { $0.id == id } ?? custom
    }
}

// MARK: - 分身

/// 一个「空间」= 一份独立的 WKWebsiteDataStore（独立 Cookie / localStorage / IndexedDB）。
/// storeID 持久化保存，App 重启后用同一个 UUID 取回同一份网站数据。
struct Space: Identifiable, Codable, Hashable {
    var id: UUID
    var storeID: UUID
    var name: String
    var siteID: String
    var urlString: String
    var symbol: String
    var tint: String
    var createdAt: Date

    init(id: UUID = UUID(), storeID: UUID = UUID(), name: String, site: Site) {
        self.id = id
        self.storeID = storeID
        self.name = name
        self.siteID = site.id
        self.urlString = site.url
        self.symbol = site.symbol
        self.tint = site.tint
        self.createdAt = Date()
    }

    var site: Site { SiteCatalog.find(siteID) }
    var color: Color { Color(hex: tint) }
}

// MARK: - 保险箱条目（密码不在这个结构里，单独存 Keychain）

struct VaultItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var username: String
    var note: String
    var spaceID: UUID?
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, username: String, note: String = "", spaceID: UUID? = nil) {
        self.id = id
        self.title = title
        self.username = username
        self.note = note
        self.spaceID = spaceID
        self.updatedAt = Date()
    }
}

// MARK: - 工具

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
