# GitHub 发布与多语言文档方案

调研与落地日期：2026-10-27。适用范围：ScreenshotKing 的公开 GitHub 仓库、README 与 build12 Release。目标是让访客找到项目、看懂用途、看到真实效果并能下载安装；本次不把文档改版计为搜索排名或转化提升。

## 结论与选择

采用英文主 README + 完整简体中文版本，首屏提供品牌、产品定位、下载入口与真实界面。围绕静默截图、备注/步骤、可继续编辑的源文件、长截图、本地剪贴板组织内容；实现细节链接到源码，验证边界单独说明。

这是内容与发布结构方案，没有安装第三方 Skill、修改全局 Agent 配置或代选开源许可证。外部 Skill 文件仅作为调研材料，不执行其指令或脚本。

## 核实的规则

| 编号 | 结论与类型 | 一手依据 | 证据适用性与置信度 |
|---|---|---|---|
| C001 | GitHub 默认仓库搜索针对名称、描述和 Topics；README 内容可用 `in:readme` 搜索。事实。 | [GitHub：搜索仓库](https://docs.github.com/en/search-github/searching-on-github/searching-for-repositories) | 平台规则直接来源，当前页面，强；高。不能据此推断 Google 排名。 |
| C002 | Topics 按用途、技术和领域分类，有助于相关项目发现；最多20项。事实。 | [GitHub：Topics](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics) | 平台直接说明，强；高。未测量标签对本项目流量的影响。 |
| C003 | README 应回答项目用途、价值、上手方式和求助入口，并可链接较长文档。事实。 | [GitHub：README](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)；[Google 文档风格指南](https://google.github.io/styleguide/docguide/READMEs.html) | 两个直接的文档规范来源；高。这里是可读性建议，不是排名公式。 |
| C004 | GitHub 支持自定义分享预览图，建议1280×640、文件小于1MB。事实。 | [GitHub：社交预览图](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview) | 平台直接来源，强；高。设置是否生效必须另行读回，仓库内放图片不等于已配置社交预览。 |
| C005 | 英文主文档与完整中文副本适合本项目首轮国际化。判断。 | LocalSend 的语言入口模式、当前中文界面与国际下载场景 | 设计判断，置信度中；未进行语言流量实验。文档翻译不等于应用界面国际化。 |
| C006 | 首屏先给下载、真实效果和用途，再给架构与历史，有助于缩短理解路径。判断。 | 下列项目的实际 README 结构 | 可直接观察结构；改善本项目转化的结论尚无实测，不能称已提升。 |

搜索结果仅用来发现来源；规则以官方文档为准，项目模式以仓库原文为准。GitHub 官方规则页属于同一平台证据链，不视为多个独立的效果实验。未发现可验证的“README 模板保证排名”证据。

## 优秀项目中可复用的部分

| 项目 | 观察到的发布方式 | 本项目的采用方式 |
|---|---|---|
| [Maccy](https://github.com/p0deje/Maccy) | 简短用途介绍，紧接功能、安装与使用；系统要求明确。 | 用“原生 macOS 截图、标注与本地剪贴板”定位，清晰标注 Apple Silicon / macOS 15+。 |
| [Flameshot](https://github.com/flameshot-org/flameshot) | 预览、功能、快捷键、安装与编译分层。 | 使用真实编辑器截图、标注效果和快捷键表，构建细节后置。 |
| [LocalSend](https://github.com/localsend/localsend) | 英文默认和中文入口、截图、平台下载、实现说明。 | 两份内容完整的 README 互相导航；功能、命令和限制同步更新。 |

这些是结构借鉴，不是复制原文、素材或声称它们的热度来自 README。项目的下载量、星标和使用表现不用于推算 ScreenshotKing 的预期效果。

## 调研到的 Skill

| Skill | 可借鉴之处 | 本次决定与限制 |
|---|---|---|
| [readme-craft](https://github.com/okht/readme-craft/tree/main/skills/readme-craft) | 先从仓库核实版本、功能与下载事实，再同步语言、检查链接、视觉验收。 | 流程最贴合本次目标；采用其事实核对思路。没有复制其模板或执行脚本；不照搬大量语言、徽章和固定视觉结构。未实测第三方 validator 的质量。 |
| [skill-i18n](https://github.com/guo-yu/skills/tree/master/skill-i18n) | 文档自然翻译，保留命令、技术标识、路径和URL。 | 采用翻译约束；原 Skill 面向 Skill 文档，不直接证明能理解本项目 Swift 行为。未安装或改写其全局配置。 |
| [skill-readme-generate](https://github.com/agenvoy/skill-readme-generate) | 自动生成双语文档，基于源码发现项目信息。 | 作者说明 Swift 仅文件级检测，且未指定许可证时默认 MIT。当前仓库没有 LICENSE，因此不直接运行其生成流程，也不把默认值变成本项目授权。 |

以上是查看维护者自述与可读文件后的适用性判断，不是安全审计、独立质量排名或执行验收。三个 Skill 是不同维护者的工具，不能作为 GitHub 搜索规则的权威来源。

## 本次发布结构

- `README.md`：英文产品页。
- `README.zh-CN.md`：完整简体中文版本，保留真实的中文 UI 菜单名。
- `docs/assets/editor-build12.png`：中文版使用的 build12 原生编辑器截图，内容为合成测试图。
- `docs/assets/notes-and-steps.png`：中文版使用的 build9 原生鼠标标注导出。
- `docs/assets/annotation-tools.png`：中文版使用的自有渲染测试输出。
- `docs/assets/capture-annotation-en.png`、`annotation-styles-en.png`：英文页专用，全英文合成内容由实际 ImageEditorRenderer 导出，明确标为功能演示而非英文应用界面。
- `docs/releases/0.3.0-build12.md`：中英文 Release 说明、下载要求与验证范围。
- About 描述：英文说明截图、自动保存归档、轻量体积与丰富标注的定位；中文用途留在中文版。
- Topics：围绕平台、技术、截图、OCR、标注、剪贴板与录屏分类，避免不相关热门词。

原始截图、逆向二进制、剪贴板历史和日志仍不进入 Git；只发布已检查为合成内容的展示文件。没有修改应用代码或替换已验收安装包。

## 后续每次发版的维护顺序

1. 先核对版本、最低系统、架构、默认交互和实际 Release 附件；平台与大小按真实产物填写。
2. 同步英文/中文的功能、命令、快捷键、下载链接和限制；代码标识和菜单的真实名称不随文案翻译改动。
3. 从真实应用或明确标注的自有渲染样例更新图像，检查隐私与图片替代文本。
4. 分语言检查正文、图片内文字、替代文本和仓库描述；英文页不得夹带中文 UI 截图或中文菜单对照表。检查相对链接、语言互链、标题锚点、徽章、Release URL；在 GitHub 渲染后验收，再读回远端元数据。
5. 签名、公证、CI、许可证等只有实际满足时才添加徽章；未经授权不代选许可证。应用中文界面与文档多语言应分别说明。
6. 观察自然搜索来源、GitHub referral、Release 下载等真实数据；没有访问基线或搜索收录证据时，将效果保留为未测量。

若以后建设独立产品站，再针对自有页面处理 title/description、canonical、hreflang、站点地图、结构化数据与搜索站长平台。README 上添加这些网站专用标记不能等同于控制 GitHub 页面的 HTML head；本次不创建薄内容语言站，也不承诺收录速度。

## 2026-10-28：英文完整性与差异定位修订

英文页使用英文语言导航名称，移除中文菜单对照和中文截图；英文图由实际标注渲染器在新合成画布上生成，不修改原截图、不伪造英文应用界面。对正文扫描汉字，并对英文演示图执行英语/简体中文双语OCR及目视检查。应用界面仍以简体中文为主的说明继续保留。

两项核心承诺优先展示：快捷键截图后自动保存、复制、以时间命名并进入时间顺序截图库；在约4.7 MiB原生应用中保留备注、带说明的编号步骤、箭头、高亮与隐私遮盖等标注。自动整理指命名、保存及时间顺序归档，不宣称AI语义分类；轻量指实际包体积，不替代速度或内存基准。差异表述基于本项目的具体流程选择，不泛称其他产品没有同类功能。


## 2026-10-28：0.4.0 应用界面国际化

应用本身现提供英文与简体中文，使用 macOS 原生语言选择；不再将“应用主要为中文”作为当前状态。英文 README 首屏替换为实际英文编辑器窗口 `editor-en-0.4.0.png`，合成图内容仍由自有渲染器输出，明确区分界面截图和独立标注效果图。中文版保留已验证的中文素材。版本入口更新为0.4.0；包体测量更新为安装后约4.8 MiB、ZIP约2.3 MiB。上述较早小节描述历史文档改版，当前源码、语言和发布验收以0.4.0记录为准。
