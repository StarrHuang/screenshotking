# 浮引 6.1.0 截图工具参数静态补充

盘点时间：2026-10-23。来源仍是 `/Applications/浮引.app` 6.1.0 的简体中文 `Localizable.strings`、主二进制 `strings -a` 输出及主代理现场 QA 回报。此文把静态候选和已报告的实际 UI 观察分开；我没有启动或操作 GUI，静态字段名不等于已验证功能。

复核证据：

- [`fuguang-parameter-localization-extract.tsv`](../evidence/fuguang-parameter-localization-extract.tsv)：本地化原文命中，`source_line` 是 app 内 `zh-Hans.lproj/Localizable.strings` 的 1-based 行号，附 key/value。
- [`fuguang-parameter-binary-extract.txt`](../evidence/fuguang-parameter-binary-extract.txt)：从全量 `strings -a` 结果摘录的字段、枚举和工具标识；每项保留全量证据文件行号。
- [`fuguang-source-sha256.txt`](../evidence/fuguang-source-sha256.txt)：版本文件哈希；bundle/version 信息在 [`fuguang-info-plist.txt`](../evidence/fuguang-info-plist.txt)。

## 编辑器结构、工具入口与快捷键

**静态候选。** 二进制中出现了截图完成/退出/保存/分享/钉图/撤销/重做/延时，以及录屏、长截图、二维码、翻译、OCR/提取文字、Emoji、贴纸、水印、放大镜、画笔、马赛克、画布、高亮、文字、箭头、形状、步骤/对话框、备注、主题等 `ScreenshotToolbar…` 标识；形状还出现椭圆、矩形、圆角矩形、三角形、五边形、六边形、星形、气泡。定位见二进制证据 656692–656736。该清单是静态工具标识，不证明每个工具在当前 UI 可见、可用或处于默认布局。

简体中文文案称顶部选择截图任务、下方平铺标注与图片工具（本地化 10645），工具可显示/隐藏/排序，并有快捷键提示及参数展开设置（5239、9453、10429）；另有选中工具后在参数栏展开“画布、样式、主题”下拉的说明（9873）。截图、长截图和录屏共用选区与工具快捷键（5251）；标注页标题为“截图与标注快捷键”（5255）。Shift 被留给画正圆，不能设置成纯修饰键快捷键（5299）；空格被留给临时拖动选区，不能设置成工具快捷键（5303）。静态材料没有给出每一个标注工具的默认键位，只有标注入口“标注（B）”等单项标签；每工具键位应以主代理 GUI 实测为准。

二进制还含截图偏好名：`screenshotShortcuts`、`longScreenshotShortcuts`、`screenshot.doubleClickCopyEnabled`、`screenshot.closeConfirmationEnabled`、`screenshot.autoPasteMode`、`screenshot.autoPasteAllowedApplications`、标注历史存储上限和时间限制，以及工具栏顺序/折叠/最近高级工具配置（见 652895–652925）。这些是键名候选，不从中推断默认值、所有应用白名单内容或用户偏好值。

## 工具与二级参数清单

| 工具 / 领域 | 可确认的静态参数候选 | 候选枚举/样式名（原始 token） | 实际观察与需要保留的未知 |
|---|---|---|---|
| **备注 / 自由文字** | `textSizeChoice`, `customTextFontSize`, `textThemeWeight`, `fontChoice`, `textFormat`, `textBackgroundEnabled`, `textBackgroundColor`, `textBackgroundCustomColorHex`, `outlineEnabled`, `outlineColor`, `outlineWidthPoints`, `outlineCustomColorHex`（二进制 656490–656512）。本地化确认“备注”“添加备注”“编辑备注”（3581、7771、8647）。 | 共享颜色/粗细 tokens 有 `thin`, `medium`, `thick`, `theme`, `orange`, `yellow`, `purple`, `white`, `black`, `customColorHex`（656545–656554）；格式候选有 `isBold`, `isItalic`, `isUnderlined`, `isStrikethrough`（656605–608）。 | **主代理实测回报**：基础字号小/中/大；调色板红/绿/蓝/紫/白/黑，另有跟随主题与自定义色。展开栏有字号、系统字体、加粗/斜体/下划线/删除线、文字底色和描边；字号当前默认值为 **17 号**（一个字号的默认值，不是 17 项字号选项）。系统字体完整列表、底色和描边的全部色值/宽度仍需按 GUI 记录。 |
| **步骤 / Callout** | `calloutStyle`, `calloutUnifiedIsMirrored`, `calloutUnifiedIsFlippedVertically`, `calloutUnifiedBodyAnchor`（656495–498）。有单独 `callout` 工具标识（656522）。 | `unified`, `connector`（656579–580），与 `calloutStyle` 相邻，对应 GUI 中“一体/连线”。 | **主代理实测回报**：样式为“一体/连线”；展开栏包含字号、字体、加粗/斜体/下划线/删除线、文字底色、描边，与备注共用编辑项。静态字段表明一体样式另有水平/垂直翻转及主体锚点候选；锚点可选值、连线连接规则和端点细节 unknown。 |
| **箭头** | `arrowLineEnding`, `arrowHeadStyle`（656502–503），工具 `arrow`（656524），UI 标签“锥形箭头”（10307）。共享颜色和粗细 token 见 656545–554。 | **主代理实测回报**：直线、单箭头、锥形箭头（默认）、双箭头、虚线、虚线单箭头、虚线双箭头。二进制还含 `simple`, `sharp`, `wide`, `tapered`, `both`, `dashedNone`, `dashedEnd`, `dashedBoth`（656562–569），它们与 UI 中文选项逐项对应关系不再作为实现前提。 | 线型/箭头端点选项已由 GUI 回报确认；颜色和线宽的具体 UI 选项、取值范围及非默认值仍 unknown。 |
| **形状** | `shapeKind`, `rectangleFillMode`（656493–494）。工具标识 `ScreenshotToolbarShape…`（656718–733）。 | **主代理实测回报**：矩形、圆角矩形、圆形、三角形、聊天框、五角星、五边形、六边形，共 8 种。填充为镂空、半透明、实心、虚线镂空、虚线半透明、斜纹填充；形状默认字号 24。二进制 enum tokens `ellipse`, `triangle`, `speechBubble`, `star`, `pentagon`, `hexagon`, `outline`, `translucent`, `filled`, `dashedOutline`, `dashedFilled`（656581–591）与 GUI 选项部分呼应，但静态 strings 没有显露斜纹填充的对应 token。 | 8 种形状及填充选项为 GUI 实测回报；形状默认字号 24。颜色、线宽/边框调节和斜纹参数 unknown。 |
| **序号** | 工具/模型候选 token `step`（658404、658445）；本地化称“序号和备注适合说明步骤或问题”（4613），并列出序号工具（7051）。 | 可静态识别 `step` 这一工具类型；序号初始数字、递增、重置、形态/颜色/字号枚举未发现可靠参数映射。 | 序号与“步骤/Callout”属于不同层面的候选名；不能因都出现 `step` 就合并两工具。实际增量/连续性/编号格式 unknown。 |
| **画笔 / 荧光笔** | 工具标识 `brush`、`highlighter`（656528、656604）；字段 `weightChoice`、`brushStyle`（656489、656555）；单独工具标识 BrushHighlighter（656714）。 | **主代理实测回报**：普通笔、荧光笔两种。静态 `thin/medium/thick`、`brushThin/brushMedium/brushThick`（656545–547、656570–572）为粗细候选；颜色候选共用 tokens 656548–554。 | 普通笔/荧光笔选项已由 GUI 回报确认；线宽单位/具体数值、颜色预设归属、压感/端点表现 unknown。 |
| **高亮** | 工具 `highlight`（656525）；本地化说明高亮用于突出区域（10701）。 | 可能使用共享颜色/宽度配置；没有足以归属高亮工具的专属参数枚举。 | 区域形状、透明度、色彩、拖动/覆盖模式 unknown。不要直接把画笔参数套用到高亮。 |
| **马赛克 / 模糊** | `mosaicStyle`, `mosaicDrawingMode`（656499–500）；工具 `mosaic`（656526）；本地化说明用于遮住隐私信息（10701）。 | **主代理实测回报**：绘制模式为矩形/画笔；画笔大小小/中/大。样式为细像素、像素（默认）、粗像素、轻模糊、模糊、强模糊。静态 token `finePixelated`, `pixelated`, `coarsePixelated`, `lightBlur`, `gaussianBlur`, `strongBlur`（656573–578）可支持候选，但 UI 中文映射以实测为准。 | 绘制模式、大小和六种样式已由 GUI 回报确认；数值粒度/模糊半径及颜色/边界设置 unknown。 |
| **局部放大镜** | 工具 `magnifier`（656527）；标注模型 `magnification`（656501）。 | **主代理实测回报**：倍率 1.5×–4×，步长 0.5×，默认 2×。 | 截图放大镜倍率范围、步长和默认值已由 GUI 回报确认。`magnifierScale/Size/Smoothing/rectangularMagnifier` 出现在 ScreenRecordingFocus 代码字符串段（656354–364），仍不能作为截图放大镜参数断言；截图放大镜尺寸/形状/描边/平滑 unknown。 |
| **水印** | 标注字段 `watermarkOpacity`, `watermarkVisible`, `watermarkDensity`, `watermarkAngle`, `watermarkDirection`（656513–517）；标注工具名 `watermark`、`watermarkText`（656529、656556）；另一个截图输出偏好有 `watermarkEnabled/Text/Opacity/Density/Angle/ColorHex`（642384–389）。本地化有“文字水印”“水印文字”“水印文案”（6215、7377、7379），另有“为导出图片平铺文字水印”（1305）。 | **主代理实测回报**：显示开关、文案（最多 16 字）、颜色；更多选项有不透明度默认 30%、密度默认 100%、字体、四种格式、角度默认 -14°。静态候选方向 `diagonalUp`, `diagonalDown`、密度 `sparse`, `standard`, `dense`（656557–561）只作候选 token，不覆盖 GUI 观察。 | 可确认显示/文案/颜色以及展开项和默认值来自 GUI 实测回报。角度可调范围、密度可调范围、四种格式具体名称、字体列表、平铺间距仍 unknown。 |
| **贴纸** | 工具标识 `sticker`（656530）、toolbar sticker（656708）；字段 `stickerContent`, `stickerRotationAngle`（656518–520）；picker 标识 `ScreenshotStickerPicker`（656535、537）。 | “built-in emoji”及 `PNG` 来源标识（656534–537）；贴纸分类/上传/自定义内容文案存在但与编辑器工具的逐项样式映射不完整。 | 可作为“选贴纸 + 旋转”的候选。缩放、翻转、透明度、图层次序、锚点、贴纸分类列表未知；产品说明写可上传/分类，但工具操作细节待实测。 |
| **画布 / 裁切** | toolbar `ScreenshotToolbarCanvas`（656713）；本地化有“画布”（8045）、“参数栏…画布…下拉”（9873）。另有 `sourceCanvasSize`（656247）但其上下文属于截图/标注记录模型字段。 | 没有确认是尺寸预设、比例、背景色或边距的截图画布枚举。`拖动框选或调整裁切框，按住空格拖动画布，捏合缩放`（localized 5693）是图片裁切/编辑帮助候选，不足以证明属于截图标注 Canvas 工具。 | Canvas 的二级参数和语义 unknown。不要把 `sourceCanvasSize` 或图像裁切提示直接转换成截图画布设置。 |
| **主题** | 工具 `ScreenshotToolbarTheme`（656722）；本地化说明参数栏下拉含主题（9873），并称默认主题在撤销前（10751）。颜色 token 有 `theme`（656548）。 | `theme` 是当前唯一可归属的明显主题 token；主题预设名称和参数组未找到。 | 工具主题究竟是全局配色预设、文字主题还是标注主题、会同时改变哪些标注属性均 unknown。 |
| **其他形状/截图工具** | 工具栏还列 Delay、ScreenRecording、LongCapture、QRCode、Translate、OCRTranslate、OCR、Emoji、Handle、More、Complete、Download、Close、Share、Pin、Undo、Redo（656692–723）。标注历史保留期限/容量配置候选见 652905–908。 | 录屏/长截图/OCR 的具体参数不在本次标注工具字段表范围内。 | 此处只记录工具标识，不推断其二级设置；录屏的摄像头、麦克风、系统音频由主代理另外实测/实现。 |

## 对实现的明确建议清单

1. 工具面板应有备注、步骤、箭头、形状、序号、画笔、荧光笔、高亮、马赛克/模糊、局部放大镜、水印、贴纸、画布、主题的独立入口；形状需有静态候选中的矩形、圆/椭圆、圆角矩形、三角、气泡、星形、五边形、六边形。
2. 备注和步骤按主代理实测实现完整二级栏：基础字号小/中/大与跟随主题、颜色预设/自定义、系统字体、加粗/斜体/下划线/删除线、文字底色、描边。备注展开字号控件当前默认值为 **17 号**；这不是 17 项字号。步骤再提供“一体/连线”，一体样式含水平/垂直翻转与主体锚点候选。系统字体具体清单、锚点可选值须从主代理实测截图录入。
3. 其他工具按主代理实测实现：形状 8 种及 6 种填充、箭头 7 种线型/箭头组合、画笔普通笔/荧光笔、马赛克矩形/画笔模式及小中大尺寸和 6 种样式、放大镜 1.5×–4×/0.5 步/默认 2×、水印开关/16 字文案/颜色及展开参数。水印格式具体名称、范围和非默认调节值仍待 GUI 记录；静态 enum tokens 作为线索，不替代上述实测值。
4. 做截图编辑快捷键时保留 Shift 画正圆、空格临时拖拽；截图/长截图/录屏共用选区与工具快捷键属于本地化明确说明。具体各工具键位与默认值不能由这次静态材料还原。
5. 把截图工具栏排序、显示/隐藏、折叠、最近高级工具，以及截图双击复制/关闭确认/自动粘贴 allowlist、标注历史保留上限/时限作为独立偏好入口候选；本地二进制仅证明偏好名存在，不证明 UI 可见性、默认值或行为。

## 证据边界

Localizable strings 是产品文案，二进制 strings 是未剥离的字面值/Swift 元数据片段。它们适合证明“应用包内含有这些名称或提示”，不能单独证明控件能运行。部分模型字段来自序列化/持久化结构，不能确定屏幕上的控件一一对应关系。除了主代理回报的备注和步骤面板实测外，本表所有参数均为静态候选；我没有功能验证或阅读许可证状态。运行时方法名和调用关系仍未验证。
