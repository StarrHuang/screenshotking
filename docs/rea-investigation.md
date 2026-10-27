# REA / Ghidra 深入调查记录

调查时间：2026-10-23（Asia/Shanghai）
范围：对 Shottr 与浮引各做一个截图/剪贴板方向的静态窄调查。不启动两个 App，不读取用户历史或偏好，不绕过许可/激活，不做全量反编译。

## 环境与目标身份

- REA CLI：6.7.0（`rea --version`）。
- Ghidra：12.1.3；REA 的 Ghidra bridge 报告兼容 12.1.x。Java：OpenJDK 21.0.12.1，arm64。
- 仅在分析命令环境设置 `GHIDRA_INSTALL_DIR=/opt/homebrew/opt/ghidra/libexec` 与 `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`；浮引第二次探针另设该次调用的 `REA_GHIDRA_STARTUP_TIMEOUT_MS=600000`。未改全局 REA/MCP/Java/Ghidra 配置。
- 两个目标均为 arm64 Mach-O 分析切片。REA/Ghidra 拒绝直接选 universal Mach-O，因此在 `evidence/` 用 `lipo -thin arm64` 生成分析副本；原始 App 未改写。

| App | Info.plist 版本 | 原始可执行文件 SHA-256 | Ghidra 输入切片 SHA-256 |
|---|---:|---|---|
| `/Applications/Shottr.app` | 1.9.1 | `6981ddeae01d4946f2274086f442c00173266720723c1381ffe0b33a0663da8d` | `dbcfbb72cb12be9d016020a5dacc660c19ce4037bf3db48e468d1ec327b1b412` |
| `/Applications/浮引.app` | 6.1.0 | `c48ec5f17eece62541b5b05824ad024266cd9ccaf768176719d2c8fac1a30f68` | `23530fa7516fd03e3473c93d33763df39763ec18c9eca7bc18845c24886f0012` |

分析切片分别保存在 `evidence/rea-deep-shottr-arm64` 与 `evidence/rea-deep-fuguang-arm64`。bundle 目录摘要和架构信息见原有 artifact/Mach-O Evidence：Shottr `ev_8994bb74ff48f6cfb186f54768f7455ab6a619ae990c54d0f66295481b32f767`、`ev_c4593c6dab486159faf2c6f00515cec8c61585f15c8224c71bd514d53f6750c0`；浮引 `ev_e50b33e66da62a4c475a32fce71a599b6c8f9b6139e524874f46f4b06131fe3f`、`ev_04e6d83779dd4f1856a3fc5bc960c238aedd8422785ca0b02fddda38a8b15b9b`。

## Shottr：从剪贴板打开菜单 handler

**入口选择依据（静态观察）**：已存 Interface Builder Evidence `ev_18c109616b4bf54516a5fc88580f386d0f1fedbaa918263cf6a1bcb8c9b6510f` 的 `MainMenu.nib` 图中，`NSMenuItem` 对象 `202` 有 `V` 键及 Command 修饰掩码 `1048576`，target-action selector 为 `menuOpenFromClipboard:`，destination 是 `_TtC6Shottr11AppDelegate`。据此选精确 handler 做函数级 Ghidra 分析，而不是从任意地址开始。

**Ghidra 结果**：REA Evidence `ev_d096309fe6a75e067817125ad6cddf2d18ad4fc64af5217d5858ddcfd9bc1d28`，provider `ghidra` 12.1.3，操作 `analyze_function`。精确函数名 `_TtC6Shottr11AppDelegate::menuOpenFromClipboard:`，入口 `0x100140454`，函数体 152 字节（`0x100140454–0x1001404eb`）。完整原始 Evidence、assembly、call/reference 列表和伪代码保存在 [`evidence/rea-deep-shottr-function.json`](../evidence/rea-deep-shottr-function.json)；本轮临时分析快照为 `evidence/rea-deep-shottr.snapshot`。

以下是该 Evidence 的原样 Ghidra pseudocode 片段；它是反编译器生成的表示，不是原始源码：

```c
void _TtC6Shottr11AppDelegate::menuOpenFromClipboard_(ID param_1,SEL param_2,ID param_3)

{
  undefined8 uVar1;
  undefined1 auStack_40 [32];

  _swift_unknownObjectRetain(param_3);
  Swift::__bridgeAnyObjectToAny();
  _swift_unknownObjectRelease(param_3);
  if (DAT_100247e00 != -1) {
    _swift_once(&DAT_100247e00,FUN_10013e12c);
  }
  uVar1 = DAT_100259278;
  _swift_retain(DAT_100259278);
  FUN_100124df8(0x756e656d,0xe400000000000000);
  _swift_release(uVar1);
  FUN_100016474(auStack_40);
  return;
}
```

**能确认的关系**：Ghidra 直接 callees 包含 `FUN_100124df8`（函数体 1,856 字节）、`FUN_100016474`（32 字节）和 Swift runtime retain/release/bridge thunk；调用常量对被 Ghidra 识别为小型 Swift 字符串 `"menu"`。nib selector 到 AppDelegate handler 是资源图里的 observed target-action 连接；这些静态关系不证明运行时菜单已点击或剪贴板读取已完成。

**未确认**：这个 handler 的伪代码未直接显示 NSPasteboard/读取图片数据；下游两个未命名 helper 尚未反编译，所以剪贴板数据怎样进入编辑窗口、是否经异步/间接 dispatch、失败路径如何处理，仍未知。本次窄调查不把 selector 名称扩展为实现行为事实。

初次将 universal 文件直接交给 Ghidra 时，REA 返回 `architecture_unsupported`（Ghidra provider v1 无法从 universal Mach-O 强制选 slice）。原始 CLI 错误保存在 `evidence/rea-deep-shottr-universal-provider-error.json`；改用已验证 SHA 的 arm64 薄片后才得到上面的 Ghidra Evidence。

## 浮引：截图 API anchor 探针（未得到函数级结果）

**候选入口选择依据（仅静态观察/推断）**：已有 Mach-O Evidence `ev_04e6d83779dd4f1856a3fc5bc960c238aedd8422785ca0b02fddda38a8b15b9b` 的 arm64 imports 列出 `_CGDisplayCreateImageForRect`、`_CGDisplayCreateImage`、`_CGRequestScreenCaptureAccess`、`_OBJC_CLASS_$_SCScreenshotManager` 和 NSPasteboard 类型。已有抽取文本 `evidence/fuguang-feature-localizations-focused.tsv` 也包含截图目的/“开始截图”类本地化内容。这里选择 `_CGDisplayCreateImageForRect` 作为一个精确 Ghidra procedure-search 锚点，目标是先定位其内部调用者再选 caller 反编译；导入存在和文案存在只表示候选，不证明函数实际调用或使用路径。

**工具结果与边界**：REA 两次确实启动 Ghidra 12.1.3 并导入同一 arm64 slice（SHA `23530fa…86f0012`），但默认自动分析始终未完成，未生成 Ghidra procedure-search/function Evidence：

- `evidence/rea-deep-fuguang-timeout-330s.json`：REA `provider_timeout`，`search_procedures` 在 330,000 ms 默认 startup deadline 超时。
- `evidence/rea-deep-fuguang-procedure-search.json`：对这次命令单独将 timeout 提高到 600,000 ms 后仍为 `provider_timeout`；错误记录 Ghidra 12.1.3、目标 SHA、run ID `48f4c658-0ca4-4186-97a0-5d02cfeb936b`，并标明 analysis 未完成、输出不完整。

Ghidra 日志在分析中记录它识别并修复 86,859 个 `DYLD_CHAINED_PTR_64_OFFSET` 指针，之后处于 `ANALYZING all memory and code`；10 分钟尝试期间临时 Ghidra cache 曾增至约 356 MB，日志持续出现多个 DecompileCallback `Unable to read bytes at ram:…` 警告。缓存增长与进程活动只证明分析仍在进行，不能当作分析成功或目标函数存在/不存在的证据。失败时 REA 自动清理其临时 Ghidra session；没有可诚实引用的浮引 native function EvidenceID。

**当前结论与未知**：导入证据支持“浮引二进制含截图相关系统 API 符号”的事实；截图路径内部调用者、被选函数 pseudocode/call graph、剪贴板写入关系都未证实。下一步若继续，需要一次更长的有界 Ghidra startup deadline，或根据实测耗时选择有限的 Ghidra analyzer 禁用列表后再跑同一精确锚点，并重新验证 auto-analysis 完成；不能从现有超时推断 API 未使用。

## 成本与复用提示

本轮 Shottr Ghidra 分析约 3.5 分钟；浮引先后花约 5.5 分钟（330 秒失败）和 10 分钟（timeout 提高后仍失败），Ghidra 等待合计约 19 分钟。Shottr 的原始伪代码与 references 可直接复用，不要为同一 selector 重跑；浮引当前没有完成分析快照可复用。本报告和 `evidence/rea-deep-*` 是本轮新增/保留材料。所有发现均为静态分析观察，不是运行时截图行为观察。
