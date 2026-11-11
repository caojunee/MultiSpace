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

单次冷构建经验值 **6~12 分钟**（纯 SwiftUI、7 个源文件、零第三方依赖，`macos-26` runner 预装 Xcode 26.4.1）。首次跑通后看 Actions 的 step summary 里的实际耗时即可。

### 三个仍然要注意的点

1. **Artifact 存储**免费 500MB，是**累计占用**不是月度重置。workflow 已设 `retention-days: 7`，IPA 一般 5~15MB，够用；别把保留期调到 90 天。
2. **公开仓库的 Actions 日志任何人可见。** 这个 workflow 只打印 Xcode 版本、Bundle ID、导出方式和「签名材料是否齐备」这个布尔值，不打印任何证书内容；Secrets 由 GitHub 自动打码，且不会传给 fork 的 PR。往日志里加调试输出时别 `echo` 证书、密码、描述文件原文。
3. **`workflow_dispatch` 只有仓库写权限的人能点。** 别人 fork 后是在自己的账号下跑、算自己的额度，烧不到你头上。

### 构建策略

- 默认**只有手动触发和打 `v*` tag 才构建**，日常 push 不排队（想改：把 workflow 里 `push.tags` 换成 `branches: [main]`）。
- 一个 job 干完所有事，不拆多个短 job —— 每次 job 启动都有一轮固定开销。
- `concurrency.cancel-in-progress`：连点两次不会并行跑两份。
- 显式锁 `macos-26`，不跟 `macos-latest` 漂移 —— 后者 2026 年 7 月起已从 macOS 15 迁到 macOS 26，默认 Xcode 从 16.4 跳到 26.4.1，哪天构建突然变红很难查。

---

## 二、怎么出第一个 IPA

1. 在 GitHub 新建**公开**仓库（不要勾 README / .gitignore / License，保持空仓库），然后：

   ```bash
   cd ios_repo
   git remote add origin https://github.com/<你的用户名>/MultiSpace.git
   git branch -M main
   git push -u origin main
   ```

   本地仓库已 `git init` 并做过首次提交，不用重新初始化。

2. 打开仓库 → **Actions** → 左侧「构建 iOS IPA」→ **Run workflow**。不勾签名，直接跑。
3. 跑完在 run 页面底部 **Artifacts** 下载 `MultiSpace-IPA-1`，解压得到 `MultiSpace-unsigned.ipa`。
4. 这个 IPA **未签名**，用 Sideloadly / AltStore 配合你的 Apple ID 自签后就能装到 iOS 27.2 上（免费账号：7 天有效、最多 3 个自签 App）。

> App Store 提交要求 Xcode 26+ 构建（2026-04-28 起），`macos-26` runner 默认 Xcode 26.4.1，正好满足。但正式上架还需要 $99/年开发者账号 + 证书 + App Store Connect 记录，那一步不是 CI 能代劳的。

### 推送前两个环境细节

- **代理**：本机当前 shell 的默认代理到 github.com 不通，**直连可用**。push 时绕开代理即可：
  ```bash
  git -c http.proxy= -c https.proxy= push -u origin main
  ```
  换个网络环境时，按实际情况设 `https_proxy` 或取消代理再推。
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

## 三、让 CI 直接产出可安装的签名 IPA

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

## 四、工程结构

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

## 五、已知限制（不是 bug，是平台边界）

- **微信网页版**：腾讯早已停止大多数账号的网页登录，这个空间大概率停在扫码页。WhatsApp / Telegram / Gmail / 微博 / 小红书等网页版可用。
- 手机上很多站点会跳移动版或弹「打开 App」，右上角菜单里有**桌面模式**开关（切换 User-Agent + `preferredContentMode`）。
- 有严格反爬、检测 WebView 指纹、要求 App 内验证的站点（部分电商、支付、银行）可能拒绝登录。
- 各空间的网站数据在 App 内，卸载 App 即全部丢失；密码走系统钥匙串，同样不跨设备同步。
- 图标用 SF Symbol，没有提交 `Assets.xcassets`。上架前需补 1024×1024 图标，否则 App Store Connect 会拒。
- `ITSAppUsesNonExemptEncryption = NO` 已设，提交时不会再被追问出口加密合规。

---

## 六、本地 Mac 那条路

本机目前没有可用的 iOS 编译环境：Windows 侧没有 iOS SDK；局域网那台 Mac 只有 CommandLineTools，没有 Xcode.app、iPhoneOS SDK 和签名证书，且系统版本低于 Xcode 26 的最低要求。要走本地编译，得先升级 macOS → 装 Xcode → 配开发者证书，三步都不少。

现阶段云 CI 成本最低。等需要真机调试、或想长期自建 runner 时再回头动本地环境也不迟。
