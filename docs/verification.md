# 验证记录

注：文中 `evidence/` 路径为本机验收记录，原始材料不随 GitHub 仓库发布。

当前状态：0.3.0 build9，固定安装包已授权并完成真实截图、鼠标备注/步骤导出、自动长截图及暂停取消验证；主动粘贴在build5已通过且相关源码未变。下文保留历史失败与修复过程，以末节当前安装包结果为准。

本机 macOS 26.3 / Apple Silicon。应用最低 macOS 15。仅有 ad hoc 签名，无可用开发者签名证书，重建后的系统权限需要重新确认，不能把终端进程权限当作 App 实际权限。

## 已有运行证据

- `scripts/test.sh`：几何坐标、导出、私有剪贴板、图像渲染/裁剪/拼接/编辑源、Vision OCR 和二维码。原始日志 `evidence/runtime-tests.log`；0.2.0 build2 全套重跑退出码0；包含备注/步骤说明、重复点击单输入框、主题链接、Retina逻辑尺寸和导出前提交文字。
- 剪贴板测试使用单独命名 pasteboard，11项检查通过：保留多item和format、边界感知哈希、拒绝敏感标记、尺寸限制、原样恢复与失败时保留目标、多种管理与备份行为。
- 几何追加测试已通过：四方向16:9约束、超屏边界、Retina指定像素宽高、全屏。
- OCR自建测试图识别标题/英文，并识别二维码 `screenshotking://qa-fixture`。真实Apple文字与图片翻译现已通过：完成系统英语(美国)/简体中文语言下载后，指定英文源，实际回读译文“屏幕截图王QA / 你好，世界。捕获2026年。”；点击翻译图片后关闭识别窗口，截图确认画布已实际变为中文覆盖图，而不只依赖状态文案。
- 实际编辑器窗口曾发现上下翻转，已修复源像素坐标、预览、模糊/放大镜区域和测试采样；`evidence/qa-render-orientation.png`、`qa-crop-orientation.png`、`qa-stitch-orientation.png` 已生成并目视确认上红下蓝及文字方向。
- UI补充：主窗口和打开图像正常；此前工具动作拥挤在横向工具条外已改为固定动作行。0.2.0真实窗口已看到备注/步骤/形状等主工具和固定复制/保存/钉图入口；样式参数popover实际展示字号、字体、四种格式、底色和描边开关。画布原生鼠标/键盘注入未通过。build3初次原生“添加备注”未显示输入框，经NSHostingView整合测试定位为非key窗口焦点切换失败导致空草稿被提交删除。最终修复增加焦点条件、保留带边框/placeholder的字段、同步当前hosting画布引用；Hosted备注与步骤创建、输入提交、编辑源回读和备注合成像素测试通过。最终安装包原生GUI复验尚待完成。

0.3.0 build3补充：执行代理在源码冻结前运行 `scripts/test.sh` 全套通过；新增快捷键持久化及切换、空格平移后坐标、Shift等比形状、步骤方向修改及撤销、矩形高亮区域内外像素、标准AX动作创建备注→输入提交→编辑源保存和回读。该批结果来自实际运行命令回报；不把旧 `runtime-tests.log` 当成新增用例日志。

## 本轮许可与限制

用户已允许为 ScreenshotKing 开启屏幕与系统音频录制、辅助功能，并继续真实验收。用户只允许录制屏幕和测试音；不启用、不录制、不测试本机麦克风或摄像头。iCloud明确排除。

build2构建3.2 MB（build3约3.3 MB），codesign --verify --deep --strict通过。旧签名TCC开关刷新仍不能截图；通过系统设置仅移除ScreenshotKing旧屏幕授权记录、从本工程build/ScreenshotKing.app重新添加并重启后，真实App进入选区，选择全屏并点击截图，成功进入1920×1080独立编辑器和自动保存编辑源。此为App实际截屏通过证据。

补充真实验收：
- 全屏截图保存为 `evidence/qa-real-capture-0.2.0.png`，文件回读1920×1080。该图包含本机桌面，保持本地并由.gitignore排除。
- 选区内直接标注已进入与独立窗口共用的工具画布；已恢复默认关闭该选项。画布输入仍待原生手工确认。
- ScreenCaptureKit实际录屏 `qa-screen-system-audio.mp4` 已停止并保存，79.86秒，H264 1920×1080 + AAC 48kHz stereo。抽帧可见桌面，不能宣称QAHost前台画面通过；一次基于QAHost标题的抽帧OCR断言失败，原因是该帧前台为Codex。录音频谱检出440Hz峰，最大1秒RMS0.064726、9个非静音秒；见 `evidence/qa-recording-verification.json`。仅屏幕与合成测试音，麦克风/摄像头一直关闭；录制后恢复系统声音默认关闭。视频仅本地，不加入Git。
- 系统剪贴板验收：开启监听后由自建QAHost复制 `ScreenshotKing clipboard QA 2026`，历史实际显示该条目；暂停监听，点击复制，再在QAHost文本框Command+V，读回同一文本。主动粘贴到上一个App仍未验收。
- 原生OCR窗口实际显示测试图2段文字与二维码 `screenshotking://qa-fixture`。

仍须：原生备注/步骤文字输入确认、真实页面长截图、主动粘贴、完整浮引交互兼容。不能以源码或TCC列表开关冒称这些已通过。

## 工具与路由证据

REA MCP实际握手、版本6.7.0已保存于 `evidence/rea-mcp-identity.json`。Ghidra成功的Shottr函数分析与浮引两次超时均分别保留，见逆向报告。

本任务独立执行子任务请求模型为 `gpt-6-luna` / high；一次风险审阅请求为 `gpt-6.1-sol` / medium。当前工具未暴露可核验的实际模型与effort运行元数据，因此“requested”已记录，实际runtime为unverified；不据此宣称节省量或更改主会话模型。

## 固定安装与权限修复过程

0.3.0 build3已构建、codesign验证并安装到 `/Applications/ScreenshotKing.app`，约3.3MB；哈希见 `evidence/installed-app-sha256.txt`。工程临时构建目录不再作为用户入口。当前源码已冻结。

用户报告权限开关已开但仍提示授权；现场确认录屏与系统录音列表中ScreenshotKing为on，当前ad hoc指定要求为cdhash，重建可造成旧记录失配。尝试仅移除ScreenshotKing旧记录时，macOS弹出本机管理员认证。已请用户在系统弹窗直接完成，不索取密码。随后取消该弹窗，采用系统自带 `tccutil reset ScreenCapture local.screenshotking.app` 和 `reset Accessibility local.screenshotking.app` 仅重置此App。用户完成系统认证并开启屏幕权限；固定安装包重新启动后真实截图通过，进入3840×2160编辑器。不操作其他应用授权。

最终安装包补充原生证据：真实截图上创建备注“截图备注验收”并提交，编辑源回读确认该文字和1个对象。合成fixture上通过canvas标准动作创建步骤，提交“第一步：添加标注”，真实PNG保存至 `evidence/qa-native-step-0.3.0.png`，回读1000×700且编号1与说明可见。工具切换后的编辑焦点仍在修复，暂不称连续备注/步骤交互验收完成。

## 连续标注与主动粘贴的真实验收

0.3.0 build4：真实3840×2160截图上，依次选择步骤、通过画布标准按下动作启动原位输入、输入“步骤验收 build4”、回车，再切换备注输入“备注验收 build4”并提交。编辑源回读确认编号1及两条文字均存在；见 `evidence/native-annotation-verification.json`。这修复了此前工具切换导致空草稿丢失的问题；移除了会在SwiftUI按钮动作结束时抢焦点的临时添加按钮。

build5：排除UniversalControl等非regular后台应用，粘贴按钮显示明确目标“ScreenshotKing QA”。点击后QAHost空文本框实际变为 `ScreenshotKing clipboard QA 2026`，无须再手动Command+V；见 `evidence/native-clipboard-paste-verification.json`。监听已恢复暂停。

长截图现场发现两类真实缺陷：旧流程恢复主窗口干扰原窗口，以及自动滚动新造事件直接发送PID没有AppKit窗口注释。build6已绑定原窗口、保持自身旧窗口隐藏、增加会话/循环取消隔离；手动滚动后两帧能捕获正确QA内容，但最大仅搜索50%重叠导致重复一行，自动滚动仍未通过。这些失败没有计为验收成功，后续修复另记。

## 当前安装包 0.3.0 build9（19:18 完成）

安装路径 `/Applications/ScreenshotKing.app`，约3.3MB；构建成功，codesign严格验证通过，源码和安装二进制哈希已更新。最终构建按用户既有授权仅刷新本App两项TCC记录，实际捕获测试区域成功，无权限提示；其他App授权未改。由于仍为ad hoc签名，后续重建可能再需要刷新权限，当前已授权二进制未在验收后改动。

- **实际鼠标标注**：安全fixture上点击备注工具，再用鼠标点画布出现“备注内容”字段，输入“备注：实际鼠标输入已通过”并回车；切步骤后从画布拖出锚点和说明位置，出现“步骤说明”字段，输入“步骤一：添加标注并保存”并提交。原生保存面板导出 `evidence/qa-native-note-step-build9.png`，文件回读1000×700、目视确认备注、编号1、连线和说明。见 `native-annotation-mouse-verification.json`。此项补足早期仅标准AX按下动作的验证。
- **自动长截图**：新造滚动事件经cghid WindowServer路由，QAHost本地monitor实际收到14次窗口号79336、deltaY=-180的滚动事件。滚动条从0到1；重复画面检测自动停止。生成550×2592的 `qa-native-long-capture.png`，Vision OCR断言恰好01至26行且每行一次，并目视确认顺序连续与正确目标窗口。最后两行不在所选400px高子区域中，未声称捕获了整个2800px文档。见 `native-long-capture-verification.json` 和 `qa-native-scroll-events.log`。
- **暂停及取消**：第二个任务启动后暂停，恢复再取消；关闭长截图控制窗后滚动条保持0.4105839416058394，日志累计20行保持不变（稍后完成整个备注/步骤输入导出后再次检查仍20行）。这证明该次取消没有遗留滚动；异步跨会话隔离仍以代码检查为证，不称穷尽所有竞态。
- **修复范围**：拼接搜索从最多50%扩至接近整帧，采样网格控制为约64×80；新增纵横向58.3%重叠、周期相似纹理与稀疏唯一标记回归，完整 `scripts/test.sh` 由执行代理实际运行通过。自动滚动原先安全检查把程序坞高层透明窗口算作遮挡，现只检查正常/浮动应用窗口层，遮挡状态会指出应用名称。

已通过本轮截图、备注/步骤、主动粘贴、原生自动长截图、屏幕+合成系统音录屏和Apple翻译的相应验收。**不能因此声称浮引全部功能/交互完全一致**：完整差异和未验收项仍以覆盖表为准，包括步骤精确锚点语义、原应用高亮交互、全部录屏跟随/光标效果与导出质量等。麦克风/摄像头一直未测试，iCloud按用户决定排除。

## 2026-10-26：logo 打包更新 build10

按用户要求，将 `resources/branding/screenshotking-logo-v1.png` 转成10个标准图标表示（16–1024px，含Retina），生成ScreenshotKing.icns并通过CFBundleIconFile注册；主页使用同一应用图标。构建脚本已包含该过程。版本0.3.0 build10，安装约4.7MB；ZIP约2.3MB，路径 `build/ScreenshotKing-0.3.0-build10-macOS-arm64.zip`。

已实际启动安装包并目视确认主页新logo；严格签名检查、解压后签名检查、图标各尺寸与归档资源一致性检查通过。重签名导致旧授权失配，用户在系统弹窗完成管理员认证后，仅恢复ScreenshotKing原有屏幕录制和辅助功能权限。新包实际进入3840×2160截图选区，无权限提示，随后Esc取消，未生成新的桌面导出文件。见 `evidence/logo-build10-verification.json`。之前build9其他功能验证仍为历史结果，本次没有重跑全部功能。

旧安装包备份保留在 `build/backups/ScreenshotKing-build9-before-logo.app`。

## 2026-10-26：Finder图标与自动复制 build11

Finder的应用列表已实际显示蓝色皇冠logo；安装时对应用包更新时间并对固定路径重新登记LaunchServices，列表修改时间与大小也已更新。本轮沿用已存在的主页logo。

新增autoCopyCaptures持久化开关，默认true。设置界面实际确认“截图后=打开编辑器”“截图后自动复制=1”。区域/重复/全屏/完成长截图在共享完成入口复制，内联模式也复制；导入与图库直接edit，不经过完成截图入口。自动复制只写图片，不发送粘贴按键；原有显式复制路径保持既有配置行为。

真实验证：先由QAHost放入已知测试文本，再从其合成内容截取540×200。未点击编辑器复制按钮，系统剪贴板已包含图像；逐像素与本App自动保存的同一截图比较完全一致。编辑器保持打开。PNG回读证据 `evidence/qa-native-autocopy-build11.png`，结构化记录 `autocopy-build11-verification.json`。

取消截图后检查changeCount的负向测试受外部剪贴板更新影响：原32变成34，类型为文件URL，未读取文件地址或内容，未再次覆盖该新内容，因此该检查不计为通过。取消路径不进入复制的判断为代码检查，不冒充已验证运行结果。

执行代理仅负责App.swift和Settings.swift，swiftc typecheck通过；请求gpt-6-luna/high，实际runtime元数据不可见。主代理构建、安装、刷新本App既有两项权限并完成真实截图与Finder视觉验证。未变更其他应用权限，未启用麦克风/摄像头。

## 2026-10-26：静默保存与手动编辑 build12

当前安装包为 `/Applications/ScreenshotKing.app`（0.3.0 build12）。按用户最新决定，默认完成截图后静默保存并保留自动复制；不自动进入编辑器、钉图、保存面板或Finder，不恢复截图前隐藏的自身窗口。配置文件夹优先，未设置时使用 `~/Pictures/ScreenshotKing`。原有其他输出方式仍可在设置选择；静默模式优先于选区内直接标注。菜单栏和文件菜单均新增“编辑最近截图”，也可经截图库选图进入。

真实安装包验证：设置显示“静默保存（稍后编辑）”、自动复制为on；通过文件菜单从QAHost合成图选取540×200区域。完成后CUA无法绑定ScreenshotKing窗口并返回noWindowsAvailable，进程仍运行，未恢复主页/设置或弹编辑器/保存面板。新PNG实际出现在已配置的 `~/Downloads/screenshotking`；系统剪贴板图片与该PNG逐像素完全相等，未点复制按钮。重启后经“文件 → 编辑最近截图”实际打开相同540×200测试图，备注、步骤等工具可见。菜单栏入口使用同一selector，受CUA无法绑定无窗口菜单栏App的限制，本轮未实际点击该入口。证据见 `evidence/background-copy-build12-verification.json`、`qa-native-background-build12.png`、`qa-native-manual-edit-build12.png`。

执行代理运行PNG/JPEG/HEIC导出、同名不覆盖、静默保存忽略询问/Finder/复制路径选项的测试和全源码typecheck通过，测试未访问系统剪贴板；主代理构建、固定路径安装、严格签名校验、ZIP解压后签名校验及安装/归档三项资源哈希一致性验证通过。按既有授权，仅刷新ScreenshotKing的屏幕录制与辅助功能权限并在系统界面确认开启；真实区域截图通过。未重跑全屏/长截图完成或穷尽取消竞态，未启用或测试麦克风/摄像头。

分发包：`build/ScreenshotKing-0.3.0-build12-macOS-arm64.zip`。旧build11备份：`build/backups/ScreenshotKing-build11-before-background.app`。请求的执行模型为gpt-6-luna/high；runtime元数据不可见，未将配置当成模型运行证明。
