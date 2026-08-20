<div align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="英见 YingSee 图标">
  <h1>英见 · YingSee</h1>
  <p><strong>看见英文，就地理解。</strong></p>
  <p><strong>See it. Translate it.</strong></p>
  <p>A lightweight native macOS screen translator that stays out of your way.</p>

  <p>
    <a href="https://github.com/aaabbssbaishuo-code/yingjian-macos/releases/latest"><img src="https://img.shields.io/github/v/release/aaabbssbaishuo-code/yingjian-macos?display_name=tag&label=Release" alt="Latest Release"></a>
    <img src="https://img.shields.io/badge/macOS-15%2B-111111?logo=apple" alt="macOS 15+">
    <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-2F80ED" alt="MIT License"></a>
    <img src="https://img.shields.io/badge/Account-Not%20Required-18A558" alt="No account required">
  </p>
</div>

> 按下 <kbd>Command</kbd> + <kbd>Shift</kbd> + <kbd>T</kbd>，框选任意英文界面。英见会识别文字、翻译成简体中文，并在原位置附近显示一个轻量浮层。

英见不是一个需要切换过去使用的大窗口翻译软件。它常驻菜单栏，只在你遇到看不懂的英文时出现，用完即走。

## 为什么需要英见

很多英文并不能被正常选中和复制：

| 遇到的问题 | 英见的处理方式 |
| --- | --- |
| 软件按钮、系统弹窗、图片文字无法选中 | 通过 Vision OCR 直接识别屏幕内容 |
| 鼠标移开后，hover 提示和临时气泡立刻消失 | 触发快捷键时先冻结屏幕，再在冻结画面上框选 |
| 右键菜单一打开截图工具就关闭 | 保留触发瞬间的菜单画面，不依赖菜单继续存活 |
| 为一句话切换到翻译网站会打断工作 | 在原英文区域附近直接显示翻译卡片 |
| 多段文字被合并成难读的一大段 | 按阅读顺序识别并保留段落结构 |
| 担心截图和翻译内容被长期保存 | 不做历史记录，不保存截图、OCR 原文或译文 |

## 30 秒了解工作流

```text
打开英文界面或 hover 提示
            ↓
      按下 ⌘ ⇧ T
            ↓
   屏幕定格，拖拽框选英文
            ↓
 Vision OCR 识别并按段落整理
            ↓
 Apple Translation 英译简中
            ↓
 在选区附近显示双语翻译浮层
```

整个过程不需要打开主窗口，也不需要先复制英文。

## 核心体验

### 定格 hover、菜单和临时弹层

英见会在截图模式出现前捕获当前显示器画面。即使底层应用随后收到了鼠标离开事件，触发瞬间看到的 hover 提示、右键菜单和临时气泡仍会留在冻结画面中，用户可以继续框选。这也是它与普通透明遮罩截图方式最重要的区别。

### 原生 OCR 与分段翻译

- 使用 Apple Vision Framework，优先识别英文
- 支持单词、短句、按钮、菜单、弹窗和多行段落
- 根据位置和间距恢复阅读顺序
- 保留列表项和段落边界，逐段展示中文与英文
- OCR 为空时不会发起翻译

### 就地浮层，不打断当前任务

- 浮层优先显示在选区下方，空间不足时自动换位
- 自动避让屏幕边缘，支持多显示器
- 中文译文醒目展示，英文原文弱化但始终可见
- 可手动选择英文文本并复制，也可一键复制全部英文
- 鼠标停留时不会消失，离开后延时淡出

### 朗读与跟读

- 朗读英文原文，支持暂停和继续
- 多段内容按段落依次播放
- 当前朗读单词会同步高亮
- 单击任意英文单词，可单独听该单词发音

### 轻量且私密

- 菜单栏常驻，不显示 Dock 图标
- 默认开机启动，可在菜单栏关闭
- 无账号、无历史记录、无云同步
- 截图和文字仅用于当前一次识别与翻译

## 适合这些场景

- 阅读英文软件的按钮、菜单、设置项和错误提示
- 查看网页中的图片文字或不可复制区域
- 翻译 Figma、开发工具和专业软件里的 hover 提示
- 理解 macOS 系统弹窗、上下文菜单和临时气泡
- 阅读多段英文说明，并通过逐词高亮辅助跟读

## 安装

### 普通用户

1. 打开 [最新版本下载页](https://github.com/aaabbssbaishuo-code/yingjian-macos/releases/latest)。
2. 在 **Assets** 中下载 `yingjian-版本号.pkg`。如果浏览器下载的是 `.pkg.zip`，请先双击解压。
3. 右键点击解压得到的 `.pkg`，选择“打开”，然后按安装器提示继续。
4. 安装器会把英见放入 `/Applications`，安装完成后自动启动。
5. 屏幕顶部菜单栏出现英见图标，即表示启动成功。

不要下载 GitHub 自动生成的 `Source code (zip)` 或 `Source code (tar.gz)`，它们是工程源码，不是安装包。

> 当前公开构建尚未经过 Apple Developer ID 公证，因此 macOS 可能提示“无法验证开发者”。这是 Gatekeeper 对未公证开源构建的正常提示；请确认下载来源是本仓库，再通过“右键 `.pkg` → 打开”启动安装器。

### 首次启动

英见会轻量检查以下项目：

1. **屏幕与系统音频录制权限**：用于读取你主动框选的屏幕区域。
2. **辅助功能权限**：用于可靠监听全局快捷键。
3. **英语与简体中文翻译语言包**：首次使用时，macOS 可能需要联网下载。

权限路径：`系统设置 → 隐私与安全性 → 屏幕与系统音频录制 / 辅助功能`。

授权后如果快捷键仍未生效，请完全退出英见并重新打开。建议始终从“应用程序”文件夹运行，避免 macOS 将不同路径下的副本视为不同应用。

## 使用方法

1. 将鼠标停在想翻译的英文界面上；hover 提示或右键菜单可以保持打开。
2. 按 <kbd>Command</kbd> + <kbd>Shift</kbd> + <kbd>T</kbd>。
3. 屏幕定格后拖拽选择英文区域，松开鼠标即自动确认。
4. 等待 OCR 与翻译完成，结果会显示在选区附近。
5. 点击喇叭朗读英文，点击复制按钮复制英文，点击关闭按钮收起浮层。

按 <kbd>Esc</kbd> 可以随时取消截图。

## 隐私说明

| 数据 | 英见如何处理 |
| --- | --- |
| 截图 | 仅在内存中用于本次 OCR，完成后释放，不写入文件 |
| OCR 英文原文 | 不保存，不建立历史记录 |
| 中文翻译结果 | 不保存，不同步到其他设备 |
| 用户身份 | 不需要账号，不收集登录信息 |
| 翻译 | 使用 Apple Translation Framework；语言包准备完成后由系统翻译能力处理 |

英见没有自己的翻译服务器。首次下载系统语言包时可能需要网络连接。

## 系统要求

- macOS 15 Sequoia 或更高版本
- 当前公开安装包支持 Apple Silicon Mac
- Intel Mac 可从源码构建，实际可用性取决于设备能否运行 macOS 15
- 首次使用需要安装英语与简体中文翻译语言包

当前版本固定支持 **英文 → 简体中文**。

## 原生技术栈

| 能力 | Apple 原生技术 |
| --- | --- |
| 应用与界面 | Swift、SwiftUI、AppKit |
| 屏幕冻结与区域捕获 | ScreenCaptureKit |
| 英文文字识别 | Vision OCR |
| 英译简中 | Translation Framework |
| 英文朗读 | NSSpeechSynthesizer |
| 开机启动 | SMAppService |

不使用 Electron，也不引入大型前端框架。

## 从源码构建

需要 macOS 15+、Swift 6 工具链，推荐使用完整 Xcode。

```bash
git clone https://github.com/aaabbssbaishuo-code/yingjian-macos.git
cd yingjian-macos

chmod +x Scripts/build-app.sh Scripts/build-zip.sh Scripts/build-pkg.sh
./Scripts/build-app.sh release
open .build/英见.app
```

生成分发文件：

```bash
./Scripts/build-zip.sh
./Scripts/build-pkg.sh
open .build/dist
```

也可以直接使用 Xcode 打开 `Package.swift`。

## 项目结构

```text
Sources/QuickLensTranslator/
├── AppDelegate.swift                 # App 生命周期与服务装配
├── MenuBarController.swift           # 菜单栏入口
├── HotKeyManager.swift               # 全局快捷键
├── ScreenshotOverlayWindow.swift     # 冻结画面与框选交互
├── ScreenCaptureService.swift        # ScreenCaptureKit 捕获
├── OCRService.swift                  # Vision OCR 与段落整理
├── TranslationService.swift          # 英译简中与界面语境优化
├── FloatingTranslationPanel.swift    # 双语翻译浮层
├── SpeechService.swift               # 朗读、暂停与逐词高亮
├── LoginItemService.swift            # 开机启动
└── PermissionManager.swift           # 权限检测与系统设置入口
```

## 常见问题

**为什么必须开启屏幕录制权限？**<br>
macOS 将所有读取屏幕像素的行为统一放在这项权限下。英见只读取用户主动框选的区域，不会持续录屏。

**英见会一直共享或录制我的屏幕吗？**<br>
不会。英见只在你触发截图翻译时获取一次静态画面，完成后立即释放，不启动持续录屏流。

**为什么第一次翻译会下载语言？**<br>
Apple Translation 需要在设备上准备英语和简体中文语言包。下载完成后，后续使用会更快。

**为什么 hover 提示在真实应用里消失了，但框选画面里还在？**<br>
这是预期行为。英见在快捷键触发瞬间冻结画面，框选时操作的是冻结副本，因此临时界面仍然可识别。

## 品牌与宣传素材

- 英文副品牌：**YingSee**
- 英文标语：**See it. Translate it.**
- GitHub 宣传图生成说明：[PROMO_IMAGE_PROMPT.md](docs/PROMO_IMAGE_PROMPT.md)

## 许可证

本项目采用 [MIT License](LICENSE)。
