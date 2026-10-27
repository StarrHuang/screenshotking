# ScreenshotKing

<p align="center">
  <img src="resources/branding/screenshotking-logo-v1.png" width="104" alt="ScreenshotKing 皇冠与截图框标志">
</p>

<p align="center">
  <strong>原生 macOS 截图、丰富标注与本地剪贴板历史。</strong><br>
  截图后静默保存并复制，需要时再标注。
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="https://github.com/StarrHuang/screenshotking/releases/latest">最新版本</a> · <a href="docs/releases/0.3.0-build12.md">build12 发布说明</a>
</p>

**macOS 15+ · Apple Silicon · 下载包 2.3 MiB**

ScreenshotKing 是使用 AppKit、SwiftUI、ScreenCaptureKit 和 Vision 构建的原生菜单栏截图与剪贴板工具。它不使用 Electron，没有账号，也不捆绑第三方运行时。当前界面以简体中文为主。

| 使用需求 | ScreenshotKing 的功能 | 默认行为 |
|---|---|---|
| 截图时不中断当前工作 | 保存截图并复制到剪贴板 | 静默保存并复制 |
| 为截图补充说明 | 随时重新打开图片，添加备注、步骤和视觉标注 | 按需打开编辑器 |
| 重用复制过的内容 | 搜索和整理本地文本、富文本、图片及文件 | 默认关闭剪贴板监听 |

> **下载：**[Apple Silicon 版 ScreenshotKing 0.3.0 build12](https://github.com/StarrHuang/screenshotking/releases/download/v0.3.0-build12/ScreenshotKing-0.3.0-build12-macOS-arm64.zip) · [SHA-256 校验值](https://github.com/StarrHuang/screenshotking/releases/download/v0.3.0-build12/SHA256SUMS.txt)
>
> 这是使用 ad hoc 签名、未经 Apple 公证的开发构建。重新构建或更换签名后，macOS 可能要求重新授权。

## 截图、保存，继续工作

默认情况下，截图完成后会静默保存并复制到系统剪贴板，不会自动打开编辑器或保存对话框。需要标注时，从菜单栏或“文件”菜单选择“编辑最近截图”，也可以从截图库打开图片。静默保存沿用设置中的文件夹；未设置时使用 `~/Pictures/ScreenshotKing`。

![ScreenshotKing 编辑器窗口与标注工具栏](docs/assets/editor-build12.png)

### 截图与录屏

- 支持区域、窗口和屏幕截图；可重复上次选区、延迟截图，或指定固定比例和像素尺寸。
- 支持纵向和横向长截图，可自动滚动或手动添加片段。长截图最多 30 帧；动态页面和固定导航栏的兼容性仍需更多验证。
- 可录制屏幕并选择系统音频。系统音频、麦克风和摄像头默认关闭；本次发布尚未实录验证麦克风和摄像头路径。

### 按需标注

编辑器提供备注、带说明的编号步骤、形状、箭头、画笔和荧光笔、文字、编号标记、像素化和模糊、裁剪、贴纸、放大镜、高亮区域及平铺水印。可以调整对象外观、移动或复制对象、撤销和重做，并导出 PNG、JPEG 或 HEIC。

![ScreenshotKing build9 原生导出图，展示备注和带说明的编号步骤](docs/assets/notes-and-steps.png)

*build9 在合成测试图上完成备注与步骤后的真实应用导出。*

<details>
<summary>标注渲染示例</summary>

此图是渲染器测试样例，并非应用工具栏截图。

![合成图片上的标注渲染器测试样例](docs/assets/annotation-tools.png)
</details>

通过编辑器和截图库操作时会保存可编辑的 `.skedit` 源文件。默认静默流程保存的原始截图不会自动成为带标注的项目文件。

### 本地剪贴板历史

剪贴板历史可保存文本、富文本、图片和多个文件，并保留各项格式与顺序。支持搜索、收藏、标签、分类、按原格式或纯文本复制，以及备份和恢复。剪贴板监听**默认关闭**；主动粘贴为可选功能，需要辅助功能权限。

### OCR 与翻译

使用 Apple Vision 在本地识别文字及二维码/条形码。Apple Translation 可翻译识别出的文字，或生成翻译后的图片覆盖层。首次使用可能需要下载离线语言资源；本机已验证英语到简体中文的翻译。

## 实现一览

| 用户目标 | 实现方式 | 源码 |
|---|---|---|
| 使用 macOS 原生框架截图或录屏 | AppKit 截图流程与 ScreenCaptureKit 录屏 | [`Capture.swift`](Sources/Capture.swift) · [`Recorder.swift`](Sources/Recorder.swift) |
| 保存可编辑的备注和编号步骤，并再次打开项目 | `.skedit` JSON 保存标注对象，并保存源图与工作 PNG | [`ImageEditor.swift`](Sources/ImageEditor.swift) · [`AnnotationStyle.swift`](Sources/AnnotationStyle.swift) |
| 在本地保留带类型和格式的剪贴板历史 | 结构化剪贴板条目、搜索与历史管理 | [`Clipboard.swift`](Sources/Clipboard.swift) |
| 识别文字和码，并使用 Apple Translation 翻译 | Vision 识别与系统翻译集成 | [`ImageIntelligence.swift`](Sources/ImageIntelligence.swift) |
| 导出截图时避免覆盖已有文件 | 图像编码与冲突安全的输出命名 | [`Export.swift`](Sources/Export.swift) |

发布 ZIP 大小为 **2.3 MiB**，安装后的应用约 **4.7 MiB**。这是安装包体积数据，不代表速度基准。

## 安装与使用

1. 下载上方的 Apple Silicon ZIP 并解压。
2. 将 `ScreenshotKing.app` 移入“应用程序”后打开。
3. 截图时按提示允许“屏幕与系统音频录制”；自动滚动和主动粘贴需要辅助功能权限。
4. 使用快捷键截图，需要标注时再打开“编辑最近截图”。

默认快捷键：

| 操作 | 快捷键 |
|---|---|
| 区域 / 窗口截图 | `⌃⌥⌘1` |
| 剪贴板历史 | `⌃⌥⌘2` |
| 重复上次选区 | `⌃⌥⌘3` |
| 长截图 | `⌃⌥⌘4` |
| 开始 / 停止录屏 | `⌃⌥⌘R` |

可在设置中修改快捷键；截图时按 Esc 取消。

## 构建与运行测试

需要 macOS 15 或更新版本、Xcode 命令行工具和 Apple Silicon Mac。

```sh
./scripts/build.sh
open build/ScreenshotKing.app
./scripts/test.sh
```

应用使用 Swift、AppKit 和 SwiftUI 实现；截图与录屏使用 ScreenCaptureKit，OCR 和码识别使用 Vision，翻译使用 Apple Translation。测试脚本覆盖几何计算、图像导出与处理、文档恢复、本地剪贴板行为、OCR 和二维码识别。测试使用独立的私有剪贴板；原生 QA 辅助程序与此不同，可能操作系统剪贴板。

详细操作见[截图与标注指南](docs/screenshot-workflow.md)；仓库发布和 README 本地化方法见 [GitHub 发布与 README 维护说明](docs/github-publishing.md)。

## 范围与验证

ScreenshotKing 为独立实现，不导入其他应用的剪贴板数据库，也不链接其可执行文件、私有接口或资源。本项目不包含 iCloud 同步。此仓库目前没有软件许可证。

本版本已验证静默保存和剪贴板图片输出、重新打开截图进行编辑，以及部分标注和剪贴板行为。部分功能已有实现或自动化覆盖，但尚未完成全面的实机验证，包括麦克风和摄像头录制、动态长页面布局，以及与其他截图工具的完整兼容性。证据与限制见[验证记录](docs/verification.md)和[功能覆盖表](docs/parity-matrix.md)。

## 反馈

遇到问题或有功能建议？请[提交 Issue](https://github.com/StarrHuang/screenshotking/issues)。如适用，请附上 macOS 版本、Mac 型号和复现步骤。
