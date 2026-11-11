# MultiSpace — iOS 多账号网页工作台

一个**能在 App Store 上架**的 SwiftUI 应用：给每个「空间」分配一份独立的持久化网站数据仓库，让同一个网站可以同时登录多个账号、互不干扰，外加一个用钥匙串 + 面容 ID 保护的账号保险箱。

> **技术真相**：iOS 沙箱不允许一个 App 加载另一个 App。所以这里打开的是**网页版**，不是第三方原生 App 的分身。市面上截图里那种「微信/WhatsApp 分身」App 也是同样原理。界面文案与上架描述请按「多账号网页工作台」定位，不要写「微信双开」，否则容易撞 4.3 / 5.2.1。

核心机制：`WKWebsiteDataStore(forIdentifier: UUID)`（iOS 17+）。每个空间持有固定 UUID，Cookie / localStorage / IndexedDB / 缓存各自独立且落盘，重启 App 登录态仍在。删除空间时调用 `WKWebsiteDataStore.remove(forIdentifier:)` 清掉对应数据仓库。

---

## 一、配额：本仓库公开，等于无限次

**已确定用公开仓库。** GitHub 对公开仓库的标准 macOS runner **不计费、不计量、不设月度分钟上限**，所以打包次数只受并发排队限制，不用绑卡、不用管 spending limit、不会产生账单。

对照一下不同选择（2026 年计费口径）：

| 场景 | 每月 macOS 实际可用时长 | 按 8 分钟/次 |
|---|---|---|
| **公开仓库（本仓库，任何套餐）** | **不计量、无上限** | **无限次** |
| 免费账号 + 私有仓库 | 200 分钟 | 约 25 次 |
| Pro / Team + 私有仓库 | 300 分钟 | 约 37 次 |

私有仓库那个 200 分钟是这么来的：2026-01-01 调价后免费额度为 $12/月，折算 2,000「Linux 等效分钟」；macOS 标准 runner 按 **10x** 系数扣减，2,000 ÷ 10 = 200 分钟真实时间。这条**只对私有仓库生效**，公开仓库不进这套账。另外私有仓库跑 macOS job 还必须绑支付方式（否则 `Usage blocked`），公开仓库也没这个要求。

单次构建实测 **约 1 分钟**（纯 SwiftUI、7 个源文件、零第三方依赖，`macos-26` runner 预装 Xcode 26.x，2026-11-11 实测为 26.6 / iPhoneOS26.5 SDK，无需下载 SDK 或 pod）。排队或冷启动会更久，看 Actions 的 step summary 里的实际耗时即可。

### 三个仍然要注意的点

1. **Artifact 存储**免费 500MB，是**累计占用**不是月度重置。workflow 已设 `retention-days: 7`，本工程 IPA 仅 164 KB，够用；别把保留期调到 90 天。
2. **公开仓库的 Actions 日志任何人可见。** 这个 workflow 只打印 Xcode 版本、Bundle ID、导出方式和「签名材料是否齐备」这个布尔值，不打印任何证书内容；Secrets 由 GitHub 自动打码，且不会传给 fork 的 PR。往日志里加调试输出时别 `echo` 证书、密码、描述文件原文。
3. **`workflow_dispatch` 只有仓库写权限的人能点。** 别人 fork 后是在自己的账号下跑、算自己的额度，烧不到你头上。

### 构建策略

- 默认**只有手动触发和打 `v*` tag 才构建**，日常 push 不排队（想改：把 workflow 里 `push.tags` 换成 `branches: [main]`）。
- 一个 job 干完所有事，不拆多个短 job —— 每次 job 启动都有一轮固定开销。
- `concurrency.cancel-in-progress`：连点两次不会并行跑两份。
- 显式锁 `macos-26`，不跟 `macos-latest` 漂移 —— 后者 2026 年 7 月起已从 macOS 15 迁到 macOS 26，默认 Xcode 从 16.4 跳到 26.x，哪天构建突然变红很难查。

---

## 二、已经跑通了（2026-11-11 实测）

仓库：`https://github.com/caojunee/MultiSpace`（公开）。
首次成功构建：`actions/runs/43018562973` → **success**，约 1 分钟出包。Xcode **26.6 / iPhoneOS26.5 SDK** 下 7 个 Swift 源文件全部真实编译通过，产出 `MultiSpace-IPA-2`（164 KB，未签名 IPA），结构已核对：`Payload/MultiSpace.app`、arm64 Mach-O、`MinimumOSVersion 17.0`、无签名。

### 重新出包

1. 仓库 → **Actions** → 左侧「构建 iOS IPA」→ **Run workflow**。不勾签名，直接跑。
2. 跑完在 run 页面底部 **Artifacts** 下载 `MultiSpace-IPA-<run号>`，解压得到 `MultiSpace-unsigned.ipa`。
3. 这个 IPA **未签名**，用 Sideloadly / AltStore 配合 Apple ID 自签后就能装到 iOS 27.2 上（免费账号：7 天有效、最多 3 个自签 App）。完整步骤见第三节。

改完代码推送：

```bash
git add -A && git commit -m "..." && git push origin main
```

`push` 到 main **不会触发构建**（只有手动触发和 `v*` tag 会），别以为推完就有新包。

> App Store 提交要求 Xcode 26+ 构建（2026-04-28 起），runner 当前 Xcode 26.6 满足。正式上架还需要 $99/年开发者账号 + 证书 + App Store Connect 记录，那一步不是 CI 能代劳的。

### 网络与凭据

- **代理**：换机器后如果 push 卡住，先确认代理。可用 `git -c http.proxy= -c https.proxy= push origin main` 强制直连，或按实际环境设 `https_proxy`。GitHub API 与网页端可能走不同路径，别只看一边就下结论。
- **凭据**：GitHub HTTPS 推送早就停用密码，用 Personal Access Token 或让 Git Credential Manager 弹浏览器授权。

### 公开前已核过的内容

- 源码、工程、workflow 里**没有内网地址、设备名、账号口令、证书或令牌**；`${{ secrets.* }}` 只是引用名，值放 GitHub Secrets，不会进仓库或日志。
- Bundle ID 默认 `com.niubige.MultiSpace`（Keychain service 同名前缀）。这是个人标识、公开后可见；想换中性名，改 `project.pbxproj` 两处、`DataStore.swift` 一处、workflow 两处。
- **commit 作者邮箱会永久公开**：本机 git 全局配的是 QQ 邮箱，所以这个仓库用 local config 覆盖成 `Gan@users.noreply.github.com`。要让贡献关联到你的 GitHub 账号，去 `Settings → Emails` 复制 `ID+用户名@users.noreply.github.com` 再执行：
  ```bash
  git config user.email "ID+用户名@users.noreply.github.com"
  git commit --amend --reset-author --no-edit
  ```
- 未附 LICENSE。公开仓库没有许可证时默认「保留所有权利」，别人不能合法复用；不在意就保持现状，想放开就在建仓库时勾 MIT。

---

## 三、把 IPA 装到 iPhone 上

本仓库默认产出的 `MultiSpace-unsigned.ipa` **没有签名，直接拖进手机装不了**。iOS 只认 Apple 签发过的包，能装的渠道一共四条：

| 渠道 | 谁签名 | 有效期 | 用户这边怎么装 |
|---|---|---|---|
| **TestFlight** | 开发者上传到 App Store Connect，Apple 审核后分发 | 构建 90 天 | 装 TestFlight，点邀请邮件或公开链接。内部 100 人免审，外部上限 10,000 人、首个构建要过 Beta 审核 |
| **Ad Hoc / 超级签名** | 开发者把你设备的 UDID 写进描述文件 | 最长 1 年，每类设备 100 台 | 拿 IPA 或网页点 `itms-services` 安装。市面「按设备收费」的签名平台就是这条 |
| **企业签名** | 共用一张企业证书 | 随时可能掉签 | 装完去「设置 → 通用 → VPN 与设备管理」信任企业开发者。Apple 一吊销，装过的 App 全部打不开 |
| **个人自签** | 你自己的 Apple ID 现签 | 7 天，最多 3 个 App | Sideloadly / AltStore / SideStore，需要电脑、数据线、开发者模式 |

未签名 IPA 只能走第 4 条。TrollStore 在 iOS 17.0 之后已失效；欧盟 DMA 的 AltStore PAL / 网页分发只限欧盟账号与地区。

### Windows + Sideloadly 实操

**前置（一次性）**

1. 安装**网页版 iTunes 与 iCloud**（从 Apple 官网下安装包）。Sideloadly 依赖其中的设备驱动和签名组件，**Microsoft Store 版不行**，装了要先卸载。
2. 安装 Sideloadly，只从 `sideloadly.io` 下载，别用第三方镜像。
3. iPhone 开启**开发者模式**：设置 → 隐私与安全性 → 开发者模式 → 打开并重启（iOS 16+ 起，自签应用必须开）。
4. 数据线连接电脑，在手机上点「信任此电脑」。

**安装**

1. 打开 Sideloadly，把 `MultiSpace-unsigned.ipa` 拖进去，选中你的设备。
2. 填 Apple ID。建议单独注册一个小号，**不必与手机登录的 iCloud 账号相同**；推荐使用 App 专用密码。
3. 点 Start，等签名与安装完成。
4. 手机上：设置 → 通用 → VPN 与设备管理 → 找到该 Apple ID 的描述文件 → 点「信任」。
5. 回桌面打开 App。首次若闪退或报权限错误，先看 Sideloadly 的 Installation Log。

**限制与维护**

- 免费 Apple ID：**7 天到期**、同时最多 **3 个**自签 App、每 7 天最多新建 **10 个 App ID**。
- 续期要用**同一个 Apple ID + 同一个 Bundle ID** 覆盖安装，App 内数据才会保留；或在 Sideloadly 里开启自动刷新（要求电脑开机，手机在同一 WiFi 或插着 USB）。
- 付费开发者账号（$99/年）签名有效期 1 年、不限 3 个 App，做法见第四节把签名接进 CI。
- iOS 27.2 这类很新的版本，签名工具可能滞后：报兼容错误时先升级 Sideloadly 到最新版，再查官方 FAQ。
- 侧载 App 的内购不可用；别用来源不明的 IPA，Sideloadly 只会照原样签名，不负责内容安全。

### 想发给别人装

- **最正规**：付费账号 → 上传到 App Store Connect → TestFlight 公开链接。对方不用电脑、不用提供 UDID，装 TestFlight 点链接即可，构建 90 天有效。
- **小规模定向**：让对方给 UDID，加进 Ad Hoc 描述文件后把签名 IPA 发过去，即第四节 `sign` + `ad-hoc` 的用途。
- **别买**「企业签名 / 超级签名」服务来分发自己的 App：证书来源不明、随时掉签，还可能被夹带篡改过的包。

---

## 四、让 CI 直接产出可安装的签名 IPA

在 `Settings → Secrets and variables → Actions` 里加 4 个 Secret，然后触发构建时勾选 `sign`：

| Secret | 内容 |
|---|---|
| `P12_BASE64` | 证书 `.p12` 的 base64（`base64 -w0 cert.p12`，macOS 用 `base64 -i cert.p12`） |
| `P12_PASSWORD` | 导出 p12 时设的密码 |
| `MOBILEPROVISION_BASE64` | `.mobileprovision` 的 base64 |
| `TEAM_ID` | Apple Developer Team ID（10 位） |

再在触发界面把 `bundle_id` 填成描述文件绑定的 ID，`export_method` 选 `ad-hoc`（装指定设备）/ `development`（开发调试）/ `app-store`（送审）。Secrets 没配齐时会自动回退成未签名 IPA，不会白跑一次。

**注意**：个人免费 Apple ID 拿不到 ad-hoc / app-store 描述文件，这条路需要付费开发者账号。

---

## 五、工程结构

```
ios_repo/
├── .github/workflows/ios-build.yml        # 打包流水线
├── .gitattributes                        # 锁定 LF，防止 CI 上 CRLF 破坏 bash
├── .gitignore
├── MultiSpace.xcodeproj/
│   ├── project.pbxproj                    # 手写工程，无 XcodeGen 依赖
│   └── xcshareddata/xcschemes/MultiSpace.xcscheme
└── MultiSpace/
    ├── MultiSpaceApp.swift                # @main、场景切换、应用锁
    ├── Models.swift                       # 网站目录 / 空间 / 保险箱模型
    ├── DataStore.swift                    # 数据仓库缓存、Keychain、生物识别
    ├── ContentView.swift                  # 空间网格、新建/编辑、锁屏
    ├── WebSpaceView.swift                 # WKWebView 隔离会话 + 浏览器工具栏
    ├── VaultView.swift                    # 账号保险箱
    └── SettingsView.swift                 # 设置与合规说明
```

最低系统 iOS 17.0（独立持久化数据仓库的 API 门槛），iPhone / iPad 通用，零第三方依赖。显示名、Bundle ID、版本号都在 `project.pbxproj` 的 target build settings 里，改 `PRODUCT_BUNDLE_IDENTIFIER` 即可。

---

## 六、已知限制（不是 bug，是平台边界）

- **微信网页版**：腾讯早已停止大多数账号的网页登录，这个空间大概率停在扫码页。WhatsApp / Telegram / Gmail / 微博 / 小红书等网页版可用。
- 手机上很多站点会跳移动版或弹「打开 App」，右上角菜单里有**桌面模式**开关（切换 User-Agent + `preferredContentMode`）。
- 有严格反爬、检测 WebView 指纹、要求 App 内验证的站点（部分电商、支付、银行）可能拒绝登录。
- 各空间的网站数据在 App 内，卸载 App 即全部丢失；密码走系统钥匙串，同样不跨设备同步。
- 图标用 SF Symbol，没有提交 `Assets.xcassets`。上架前需补 1024×1024 图标，否则 App Store Connect 会拒。
- `ITSAppUsesNonExemptEncryption = NO` 已设，提交时不会再被追问出口加密合规。

---

## 七、本地 Mac 那条路

本机目前没有可用的 iOS 编译环境：Windows 侧没有 iOS SDK；局域网那台 Mac 只有 CommandLineTools，没有 Xcode.app、iPhoneOS SDK 和签名证书，且系统版本低于 Xcode 26 的最低要求。要走本地编译，得先升级 macOS → 装 Xcode → 配开发者证书，三步都不少。

现阶段云 CI 成本最低。等需要真机调试、或想长期自建 runner 时再回头动本地环境也不迟。
