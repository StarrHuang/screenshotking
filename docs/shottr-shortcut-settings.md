# Shottr 快捷键设置学习记录

日期：2026-10-26。目标是核对设置结构、键位录入和冲突引导，并与 ScreenshotKing 对照。

## 证据与范围

初次检查时未找到 Shottr；用户随后恢复 `/Applications/Shottr.app`，本次已打开并确认版本1.9.1 build128，实看Hotkeys页面并测试录入/取消/清除。证据分为本次原生观察、官方说明和历史资源：

- 官方 [Start Guide](https://shottr.cc/kb/startguide)，尤其 Using Custom Hotkeys 一节及其 [Hotkeys 截图](https://shottr.cc/kb/content/files/260212-hotkeys_3.png)。浏览器实际查看截图；本地浏览器截图为 `evidence/shottr-official-hotkeys-browser.png`。
- 2026-10-23 对 Shottr 1.9.1 保存的 REA Interface Builder 图，`evidence/shottr-interface-builder.json`。Hotkeys 的控件/标签已定向提取到 `evidence/shottr-hotkeys-focused.json`，保留原 Evidence ID 和资源路径。它证明静态控件存在，不证明当前运行状态或默认键值。

## 已确认的设计

1. **全局热键在独立 Hotkeys 页按动作设置。** 历史资源列出全屏、区域、重复区域、任意窗口、活动窗口、滚动截图、即时文字/二维码识别、显示 Shottr 八类。当前官方图可见全屏、区域、重复区域、任意窗口、活动窗口等行。
2. **录入框具有明显的状态。** 官方图中未设置时显示 Record Shortcut，录入中显示 Press Shortcut 和焦点边框；已有值显示组合键，并提供 × 清除。截图中的 F12 和 ⌃⌥⌘M 是图示中的配置，不能当成工厂默认值。
3. **把接管系统截图快捷键的步骤放在设置页内。** 官方指南明确支持用户先在 macOS「键盘 → 键盘快捷键 → 截屏」释放 ⌘⇧3/⌘⇧4，再在 Shottr 的全屏/区域字段录入。页面提供 Open System Settings 入口。历史资源中的 Reassign Default 与这些说明同时存在；没有证据把该按钮解释为“恢复所有快捷键出厂值”。
4. **全局热键与应用内菜单快捷键不同。** 官方 [Shortcuts](https://shottr.cc/kb/shortcuts) 说明，通过 macOS App Shortcuts 修改的是 Shottr 前台时可用的菜单命令；菜单标题必须精确匹配。系统快捷键会优先截获冲突组合。
5. **平台限制需要单独说明。** 官方 [Sequoia 说明](https://shottr.cc/kb/sequoia) 记载，Shottr 的沙盒版本受仅 Option / Shift+Option 全局热键限制，建议加入 Command 或 Control。不能将 Shottr 的沙盒约束直接断言为本项目未沙盒构建的实测限制。

## ScreenshotKing 当前差距

代码依据：`Sources/Settings.swift` 的 Shortcut.defaults、SettingsView.record、HotkeyManager.register，以及 `Sources/App.swift` 的 hotkey action。

| 项目 | 当前实现 | 可借鉴的改进 |
|---|---|---|
| 动作范围 | 区域/窗口合一、历史、重复选区、长截图、录屏五项；全屏只有菜单入口 | 全屏独立配置；区域/窗口、OCR和显示编辑器按实际功能逐步开放独立热键；保留历史与录屏 |
| 录入控件 | 复选框启用 + 普通按钮，录入中显示文字；Esc取消 | 统一宽度录入框，空值/录入中/已设置状态清晰，已设置时提供清除 |
| 生效方式 | 录入立即写入UserDefaults，但还要点击“应用快捷键”才重新注册 | 采用录入后校验并注册成功再保存的明确流程，避免界面值与实际生效值不一致 |
| 冲突 | Carbon 注册失败后报错；没有设置前的应用内部重复检查 | 先检查本应用重复组合，在对应行说明冲突动作；系统/其他应用冲突以实际注册结果为准，不承诺识别全部外部占用 |
| 系统截图接管 | 缺少对应引导 | 页面内提供释放系统截屏快捷键的说明和设置入口，提供用户主动选择的 macOS 键位方案 |
| 当前键位 | ⌃⌥⌘1–4 和 ⌃⌥⌘R；用户可自定义 | 保留已有用户配置；接管 ⌘⇧3/4 作为明确选择，不自动改系统设置 |
| 工具单键 | 编辑菜单中的工具布局另有持久化设置 | 清楚区分全局截图热键、编辑器命令、画布工具单键，避免同一录入器混用不同规则 |

## 本次原生实测（用户恢复安装包后）

- 真实页面八项：全屏、区域、重复区域、任意窗口、活动窗口、滚动截图、显示Shottr；文字/二维码识别放在下方单独分区。页面上方常显系统截图快捷键接管说明。
- 本机当前区域截图为⌃A，OCR为⌃⌥⌘O，其他六项为空。这是用户当前配置，不是工厂默认值。
- 点空的全屏录入框后，截图可见占位从Record Shortcut变成Press Shortcut；Esc退出后焦点回到窗口，字段恢复Record Shortcut。
- 测试输入⌘Q，字段立即显示⌘Q，未弹冲突提示；本次未按该键触发全局截图，不把字段显示当作全局注册成功。随后点击该字段右侧×，值立即清空。
- 切换General再回Hotkeys，确认全屏仍为空，区域⌃A和OCR⌃⌥⌘O保留，其他原始空项仍为空。原配置已恢复。整个页面未出现单独Apply按钮。
- 安装包的KeyboardShortcuts资源确实含“已被菜单项使用”和“系统快捷键占用”的英文及简体中文文案。但这只证明资源存在；本次⌘Q录入没有展示这些文案，不能将其推定为已验证的拒绝路径。

结构化记录见 `evidence/shottr-hotkeys-native-observation.json`。

仍未实测：新值跨进程持久化、有效键的全局触发、Backspace/Delete行为、重复组合会否重分配旧动作、系统/其他App占用时的具体行为、关闭设置时录入如何取消。这些不写成已确认事实。

## 对 ScreenshotKing 的具体设计结论

采用动作名称左对齐、录入框右对齐的紧凑列表；未配置显示“录制快捷键”，点击后显示“请按组合键 / Esc取消”，已有值带清除按钮。录入先做本应用重复和允许键校验，再尝试系统注册，成功后保存并更新菜单及主页显示；失败保留旧的有效键位，在当前行解释原因。系统截图快捷键引导折叠放在列表上方。全局、编辑器、工具单键各自说明生效范围。

本次产出为学习记录和差距清单，没有修改应用实现或已安装包。
