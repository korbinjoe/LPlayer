# LPlayer：Mac App Store 发布准备

核对日期：2026-10-23。本文记录可在本地完成的改造、发布条件和仍需准备的材料。**生成沙盒测试包、通过播放检查或完成 LGPL 内核构建，不代表 Apple 审核通过，也不代表已经上传商店。**

## 当前发布边界

- Store 构建定位为本地播放器，只读取用户选择的视频、字幕和文件夹；不申请网络、麦克风、相机或全盘访问。
- `Resources/Store.entitlements` 启用 App Sandbox、用户所选文件只读访问、app scope 安全书签。文件夹授权由用户主动选择；选一个文件不能当成授权整个上级目录。
- `Resources/PrivacyPolicy.en.html` 与 `Resources/PrivacyPolicy.zh-Hans.html` 是可随包展示和静态托管的政策文件。公开 HTTPS 隐私政策网址及真实支持联系入口尚待配置；本地文件不能替代 App Store Connect 的公开 URL。
- 主播放引擎关闭用户配置、用户脚本自动加载和 yt-dlp，关闭 mpv 自行发现字幕、音轨、封面与媒体外部引用；应用自身只在已授权范围寻找匹配字幕。商店版不应接收远程播放 URL。
- 普通 Homebrew 开发构建与 Store 内核是不同交付物。不得从普通构建复制一组未经审核的动态库到 Store 包。

本轮新增的构建入口：

```sh
./scripts/build-store-deps.sh
./scripts/build-store-app.sh --preview
./scripts/check-store-app.py 'dist/LPlayer Sandbox.app'
```

预览包为 `dist/LPlayer Sandbox.app`，使用独立标识 `dev.joebon.LPlayer.Sandbox`，版本 `0.8.0`、build `13`。它保留开发版安装与原有数据，供沙盒行为验证。依赖对应源码包路径为 `dist/LPlayer-0.8.0-dependency-sources.zip`。

`./scripts/build-store-app.sh --release` 准备输出 `dist/LPlayer App Store.app`，使用 `dev.joebon.PalmPlayer`。脚本选择包含分发 profile 的路线，以便测试和正式发行配置一致，要求环境变量 `LPLAYER_APP_SIGN_IDENTITY`、`LPLAYER_APP_PROVISION_PROFILE` 提供本机发行签名身份和 profile 文件路径；不要在仓库写入凭据或 profile。此分支检查完整 Xcode、拒绝 ad-hoc 身份，解析 profile 的平台、期限、显式 App ID 和调试权限，并在签名后检查证书类型、团队及 profile 中的证书白名单。真实发行签名和上传尚未验证，仍须完成以下账号及 Xcode 配置。脚本名含 Store 不等于其输出已经是可提交或审核通过的发行包。

这不是 Apple 对所有 Mac App Store 原生应用一律强制 profile 的要求：Apple 允许不声明 restricted entitlements 的 macOS 商店应用不带 profile；TestFlight 则需要 profile。[Apple TN3125 的 macOS 规则](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)

## 隐私清单与 App Store 隐私问卷

`PrivacyInfo.xcprivacy` 的 `NSPrivacyTracking` 为 `false`，追踪域名及收集数据列表为空。依据当前源码，没有账号、广告、分析、服务器或主动数据上传。观看历史、文件路径、授权和偏好均在设备上处理。按 Apple 对“收集”的定义，仅本机处理的数据不属于隐私标签中的收集，因此最终包继续保持这些行为时可在 App Store Connect 选择 **Data Not Collected / 未收集数据**。[Apple 隐私标签定义](https://developer.apple.com/app-store/app-privacy-details/)

清单主动记录了应用自身实际使用的 API：

| 类别 | 理由 | 源码用途 |
| --- | --- | --- |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | `App.swift`、`L10n.swift`、`ShortcutBindings.swift` 保存和读取本应用的界面语言、操作布局及自定义快捷键。系统媒体语言从公开 CFPreferences API 单独读取，不以该理由申报显式 `UserDefaults.globalDomain` 读取。 |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `3B52.1` | `PlaylistThumbnailStore.swift` 读取用户授权视频的大小和修改日期，避免显示文件变更前的缩略图。 |
| `NSPrivacyAccessedAPICategorySystemBootTime` | `35F9.1` | `SeekScheduler.swift` 的 `systemUptime` 用于合并连续 seek 操作；`ThumbnailGenerator.swift` 的单调时钟用于超时。这些值不离开设备。 |

理由依据 [Apple API 类别与允许理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)。不为未调用的磁盘空间、键盘列表等类别添加理由。

**macOS 适用范围：** 当前 Apple 文档将 required reason API 申报的强制平台列为 iOS、iPadOS、tvOS、visionOS 和 watchOS，未列 macOS；数据收集信息适用于所有平台。这里主动保留准确的理由记录，不把 iOS 的 required reason 拦截规则误称为 macOS 独有的上架阻断项。[隐私清单说明](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)、[required reason 说明](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)

本应用清单不构成对所有第三方 C 库 API 的完整审计，也不能替代适用第三方 SDK 自身的清单。每次更换内核后，核对最终依赖清单、是否包含 Apple 指定 SDK，以及 SDK 的数据行为；例如 OpenSSL 在 Apple 的指定 SDK 清单中，但不要据旧 Homebrew 包推断新的精简包仍包含它。[Apple 第三方 SDK 要求](https://developer.apple.com/support/third-party-SDK-requirements/)

政策与当前数据实现对应：

- `history.json`：最多 30 条观看记录，包含文件名/路径、进度、时长、倍速、音量、字幕设置、轨道及更新时间。
- `file-access.json`：最多 96 项只读安全范围书签，位于同一 Application Support/PalmPlayer 数据区；沙盒启用后该数据区位于应用容器中。
- 界面语言、左右手布局和自定义快捷键通过本应用的 `UserDefaults` 存储。
- 无痕模式不持久化新的历史和授权；不擦除旧记录或偏好。
- 关闭无痕后执行“清空观看历史”同时删除持久书签。当前进程仍可保留已取得的文件访问至退出，以免中断异步解码。
- “清除保存的文件授权”提供只清理持久书签、保留观看历史的独立入口。
- 时间轴和播放列表预览只缓存在内存，不建立磁盘缩略图库。诊断标志仅在显式启用时写入指定本地文件，没有自动上传。

## 签名与上传所需配置

本机只读检查结果（2026-10-23）：

| 项目 | 结果与下一步 |
| --- | --- |
| Xcode | `/Applications/Xcode.app` 不存在；`xcode-select -p` 指向 `/Library/Developer/CommandLineTools`。安装兼容当前 macOS 的完整 Xcode，并核对当时的上传支持版本。 |
| 应用签名身份 | `security find-identity -v -p codesigning` 为 `0 valid identities found`。需要开发团队和 Mac App Store 应用分发身份。 |
| 安装包签名身份 | 不带 `-p codesigning` 的 `security find-identity -v` 也为 `0 valid identities found`。需要 Mac Installer Distribution 身份，不能用 Developer ID Installer 替代商店身份。 |
| Apple 打包工具 | `/usr/bin/productbuild` 可用。 |
| 上传工具 | 当前所选工具链无 `altool`。完整 Xcode / Transporter 及登录授权仍需配置；本任务未检查账号会员状态，也未取得任何账号凭据。 |
| 公证工具 | CLT 中存在 `notarytool`。Developer ID 公证用于商店外分发，不替代 Mac App Store 签名、验证和审核。 |

[Apple 准备发行说明](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)、[打包及安装包身份说明](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)、[上传方式与支持版本](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)。

建立正式发行配置时逐项完成：

- 注册或确认 Apple Developer Program 团队，并在 App Store Connect 建立 macOS 应用记录。确认能注册所选 bundle ID；不要假定开发版标识 `dev.joebon.PalmPlayer` 已归当前团队所有。
- 对沙盒测试版使用独立 bundle ID 和容器；正式上架前确定最终 bundle ID、版本号、递增 build 号、开发者名称及版权持有人。更换 bundle ID 会影响用户偏好、容器和安全书签，需做迁移决策。
- 通过 Xcode 的 App Store Connect 发行流程配置正确应用签名及所需 provisioning profile。嵌入的 Mach-O 动态库应使用同一发行身份从内到外签名；不启用 `get-task-allow`、关闭库验证、JIT 或临时文件访问例外。
- 将 `PrivacyInfo.xcprivacy`、双语政策和对应第三方许可文件加入 app 的 `Contents/Resources`。`Store.entitlements` 应用于签名，不能仅将文件复制进包就视为开启沙盒。
- 在最终包检查 `CFBundleIdentifier`、版本、`LSApplicationCategoryType`、最低系统版本、支持架构和 `NSHumanReadableCopyright`。只提供 arm64 时按真实兼容范围发布；不得写成已验证 Intel。
- 用 Xcode 提供的打包/提交技术输出并验证商店包。手工路由可用 `productbuild --component <App> /Applications --sign <Mac Installer Distribution identity> <Package.pkg>` 生成商店用安装包；上传前以当前 Apple 流程验证，不把本地 ad-hoc 包当正式包。
- 保存完整构建版本、依赖哈希、构建配置和源代码交付材料；复核 LGPL 组件的源码、修改、再链接与 notices 要求。移除 GPL 组件不自动等于分发义务已经全部完成。

## 必须针对最终沙盒包验证

下面是发布检查项，不能因源码存在对应代码就直接标记通过：

- [ ] 从系统打开面板选单个视频，确认播放/声音/seek、全屏和预览正常；用 Finder 打开及拖放重复验证。
- [ ] 单文件授权时仍能播放，并在没有目录授权时给出可理解的目录访问入口；取消授权不影响单文件路径。
- [ ] 主动允许文件夹后，同目录队列和匹配字幕正常；另一个未授权目录不可枚举。
- [ ] 手动选择外挂字幕正常。新内核包含字幕渲染和所需字体支持，确实能看到字幕。
- [ ] 完全退出再启动后通过安全书签重开历史文件；移动文件、移除外置盘、失效书签和撤销授权后可恢复或明确提示。
- [ ] 无痕模式不产生新的持久历史/书签；清空历史清除持久授权，重启后必须再次授权。
- [ ] 在最终签名包的实际 entitlement 中确认无网络权限，检查最终动态库没有从 `/opt/homebrew`、构建目录或用户环境加载依赖。
- [ ] 在至少目标最低系统和当前正式 macOS 上验证播放及功耗；对 HDR、透传、格式覆盖只写已验证范围。
- [ ] 应用内菜单能打开适当语言的隐私政策，页面无需联网；公开政策 URL 能匿名访问且与打包政策一致。
- [ ] 本地签名检查通过后，仍需 Xcode/Transporter 的上传验证、TestFlight 安装验证以及 App Review。

沙盒权限与安全书签采用 Apple 的[用户所选文件只读权限](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-only)、[安全书签权限](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access)和[文件访问生命周期](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)规则。

## 商店材料缺口

目前没有替开发者创建 App Store Connect 记录或提交审核。正式提交前仍需：

- [ ] 真实开发者支持 URL、隐私联系人和公开 HTTPS 政策 URL。两份 HTML 中的“App Support”须能够指向商店记录中实际可用的支持渠道；不要发布不存在的邮箱或占位网址。
- [ ] 中英文名称、简介、说明、关键词、分类、真实 Mac 截图、年龄分级、内容权利和出口合规问卷；根据实际可执行文件和销售地区回答，不按“本地播放器”自动填免申报。
- [ ] 价格、发行地区、协议和适用的税务/银行资料；免费应用也需有效会员和发行权限。
- [ ] 审核备注及有权分发的短样片，解释“选择文件 → 播放”“允许文件夹 → 同目录视频/字幕”“历史恢复/无痕”。不附用户私人媒体。
- [ ] 如选择面向特定地区发行，在 App Store Connect 检查该地区实际显示的合规资料要求。

依据 [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) 2.4.5，Mac App Store 要求沙盒及自包含安装；5.1.1 要求应用内和商店元数据中的隐私政策入口。这里准备的是提交基础，最终是否获准由 Apple 审核决定。

## OpenGL 与 Metal 决策

Apple 自 macOS 10.14 起弃用 OpenGL 并建议 Metal，但其当前文档没有规定“凡使用 OpenGL 的 Mac 应用立即禁止上架”。审核规则 2.5.1 要求使用公开 API、可在当前系统正常运行并逐步淘汰即将失去支持的技术。因此 OpenGL 是需要安排验证和迁移的维护风险，不能未经证据直接说成必须先全面重写才能提交。[Apple OpenGL 文档](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/opengl_intro/opengl_intro.html)

当前 `MPVVideoView` 通过 `mpv_render_context` 和 OpenGL FBO 渲染。本机头文件公开 OpenGL 与 software 后端；核对的 mpv 上游 `render.h` 也没有 Metal 后端枚举（主线另有 Windows D3D11）。mpv 独立播放器的视频输出支持与 libmpv render API 是不同层，不能把命令行的 GPU/平台选项当成现有 AppKit 视图可直接换用的 Metal API。[mpv 公开 render API](https://github.com/mpv-player/mpv/blob/master/include/mpv/render.h)

本轮先保留已能运行的渲染路径，验证精简内核与沙盒。后续单独比较 native AVFoundation/Metal、可维护的 mpv 渲染集成或其他内核方案，并用同一批媒体测解码覆盖、HDR、字幕、延迟和能耗。软件渲染再上传 Metal 纹理也不应未经测量当成性能等价替代。
