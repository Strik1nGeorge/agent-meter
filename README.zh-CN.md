<p align="center">
  <img src="public/icon.svg" width="72" alt="">
</p>

<h1 align="center">Agent Meter</h1>

<p align="center">
  一眼看清 Codex 与 Claude Code 的用量和额度：本地完整面板 + Windows 与 macOS 毛玻璃桌面小组件。
</p>

<p align="center">
  <img alt="Windows 10 / 11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=flat-square">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-1D1D1F?style=flat-square&logo=apple&logoColor=white">
  <img alt="Node.js 22+" src="https://img.shields.io/badge/Node.js-22%2B-3C873A?style=flat-square&logo=nodedotjs&logoColor=white">
  <img alt="零 npm 依赖" src="https://img.shields.io/badge/npm%20dependencies-0-34C759?style=flat-square">
  <img alt="MIT 许可" src="https://img.shields.io/badge/license-MIT-6E6E73?style=flat-square">
</p>

<p align="center">
  <a href="README.md">English</a> | 简体中文
</p>

<p align="center">
  <img src="docs/images/widget-hover-zh.png" width="640" alt="桌面小组件：Codex 和 Claude 各有一个宠物和一组双层额度圆环，外圈是 5 小时额度、内圈是 7 天额度，中间显示 5 小时额度的百分比和重置时间，每个圆环上有一道刻度标出均匀使用的进度；悬停 Claude 时弹出详情卡片，标出每个额度窗口对应的圆环和按当前节奏的预测（5 小时额度会在重置前用完，以红字提示），并显示 agent 当前状态、今日用量和最近模型">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/dashboard-dark-zh.png">
    <img src="docs/images/dashboard-light-zh.png" width="880" alt="完整面板：账户额度（每个额度窗口带节奏刻度、预测和走势图），以及用量概览和 7 天用量轨迹">
  </picture>
  <br>
  <sub>截图使用演示数据。</sub>
</p>

## 亮点

- 🪟 **桌面小组件（Windows 与 macOS）**：玻璃横条，每个平台一组品牌色双层圆环（外圈 5 小时、内圈 7 天；中间显示 5 小时的剩余和重置时间，点一下圆环切换为 7 天）、圆环上的节奏刻度，以及一只会随 agent 工作、休息、累倒睡着的宠物；悬停查看详情和预测，拖到屏幕左右边缘变成竖排。
- ⏱️ **节奏预测**：按目前的使用节奏，每个额度窗口能不能撑到重置、会在什么时候用完；完整面板为每个窗口画出额度走势图。
- 📊 **完整面板**：账户额度、token 用量、缓存命中率、7 天用量轨迹、按模型 / 思考力度 / 项目的用量和每个 agent 会话，支持浅色与深色。
- 🔒 **只在本机**：读取你自己的 Codex / Claude Code 日志，仅绑定 127.0.0.1，不保存提示词或登录凭据。
- 📌 **不打扰**：一键置顶、靠近屏幕边缘自动贴边，服务停了会自己重启。
- 🌐 **中文 / English**：面板默认跟随浏览器语言，小组件默认跟随系统语言，都能一键切换。

## 快速开始

需要 Windows 10/11 或 macOS 13 及以上、Node.js 22+（Windows 建议 24.5+），以及本机使用过的 Codex 和/或 Claude Code。

**完整面板：**
- Windows：右键 `start.ps1`，选择用 PowerShell 运行；或在项目目录运行 `powershell -ExecutionPolicy Bypass -File .\start.ps1`。用 `stop.ps1` 停止它创建的服务。
- macOS：在项目目录运行 `./start.sh`，用 `./stop.sh` 停止它创建的服务。

启动器在后台启动服务并打开浏览器。也可以直接运行 `node server.mjs`，打开 http://127.0.0.1:4318，按 Ctrl+C 停止。设置环境变量 `PORT` 可更换端口。

**桌面小组件：**
- Windows：运行 `powershell -ExecutionPolicy Bypass -File desktop/build.ps1` 构建，然后启动 `desktop\bin\AgentHUD.exe`（可以为它创建桌面或任务栏快捷方式）。
- macOS：运行 `sh macos/build.sh` 构建（需要 Apple 命令行工具：`xcode-select --install`），然后运行 `open "macos/bin/Agent Meter.app"`。详见 [macOS 桌面小组件](#macos-桌面小组件)。

小组件会自动启动本地服务，无需先运行启动脚本。

面板右上角可切换语言（EN / 中）、切换外观（跟随系统 / 浅色 / 深色），也可打开紧凑窗口（浏览器是否置顶由系统/浏览器决定）。语言在手动选择前跟随浏览器，选择会被保存；本地服务发来的状态文字也会一并翻译。

## 数据与计数

- Codex：增量读取 `~/.codex/sessions/**/*.jsonl`，从 `session_index.jsonl` 读取标题。优先使用 `token_usage_record` 的请求用量，老版本退回 `token_count` 累计值差分。按 response ID 去重，排除其他 thread 的继承记录，识别父子 agent。
- Claude Code：增量读取 `~/.claude/projects/**/*.jsonl`。按 message ID 合并同一响应的流式记录，跨复制/续接会话去重，读取子 agent 文件。
- 输入包含缓存读取和写入；输出包含推理。缓存和推理不能再次加到合计中。跨平台统一口径为 `input + output`。
- “模型用量”按每次请求实际使用的模型累计，中途切换模型的会话会分别计入各个模型；它跟随时间范围、平台筛选和系统审查 agent 开关。
- 切到“按思考力度”后，同样的请求按模型和客户端记录的思考力度分组：Claude Code 在每条回复上记录，Codex 在每个回合记录。每行是一个模型的一档思考力度，档位下方注明对应模型，因此同一档位在不同模型上（包括 Codex 与 Claude Code 的 `xhigh`）分开显示。“思考 tokens”是输出中推理部分的用量；旧版客户端没有记录档位的请求显示为“未记录”。
- “按项目”统计每个项目（会话所在的文件夹）的用量。浏览器只收到文件夹名称，因此同名的两个文件夹会合并为一个项目。同时用过两个平台的项目会显示两个标志，并按平台颜色拆分占比条。超过十行的列表只显示前八行，其余合并为一行并注明合计。
- 默认隐藏系统审查 agent；可在表格下方开启。系统审查 token 记录不等于订阅额度消耗。
- 统计范围包含本机尚未归档的会话。不是全部云端活动，不是账单。显示的“最近活跃”基于 2 分钟内的记录，不是进程检测。
- 日期范围和图表采用 America/New_York 时区。账户额度始终是平台自身的窗口，不受 token 统计日期筛选影响。

## Codex 账户额度

通过官方 App Server 的只读 `account/rateLimits/read` 每分钟刷新，不发起模型请求。复用 Codex 自身的登录流程；应用不读取、存储或输出登录密钥。连接失败时显示最近会话里的真实额度快照，并标注来源和时间。超过重置时间显示等待更新，不推断为 100%。

在 Mac 上，它先在 Codex.app 或 ChatGPT.app（位于 `/Applications` 或 `~/Applications`）中查找 Codex，再查找常用安装目录（`/opt/homebrew/bin`、`/usr/local/bin`、`~/.local/bin`），最后查找 `PATH`。可设置 `CODEX_BINARY` 指向 Codex 可执行文件，`CODEX_HOME` 指定会话目录。`AGENT_HUD_DISABLE_RPC=1` 可仅使用本地快照。

参考：[Codex 官方 App Server 文档](https://learn.chatgpt.com/docs/app-server)。

## 额度节奏

每个额度窗口在完整面板和小组件里都按同样的规则显示节奏：
- **刻度：** 进度条和圆环上的一道短线，标出在整个窗口内均匀使用时此刻应剩的额度。进度条或圆弧没到刻度，说明用得比均匀节奏快；越过刻度，说明还有富余。
- **预测：** 把这个窗口从开始（100%）到最新读数的平均速度延续下去，给出用完的时间和比重置早多久（红字），或者重置时大约还剩多少。窗口刚开始的前十分之一（5 小时窗口的前 30 分钟、一周的前约 17 小时）和已经用尽时不做预测；因周额度用尽而被压到 0 的 5 小时额度只显示这个原因。
- **走势图：** 完整面板为每个窗口画出从开始到重置的走势：虚线对角线是均匀使用，实线是到目前为止的读数，点线是预测。只针对某个模型的额度（例如 Claude 的 Opus 周额度）改为一行紧凑显示，同样带刻度和预测。

读数来自本地服务每次读取的额度，以及 Codex 每次请求时写进日志的额度快照，因此 Codex 的记录可以一直追溯到每个窗口开始；Claude 的记录从服务第一次读到它时开始。这些读数只按“剩余百分比的变化”保存在 `.data/quota-history.json`，重置超过一小时的窗口会被清理。

## Windows 桌面小组件

<img src="docs/images/widget-docked-zh.png" width="200" align="right" alt="小组件贴在屏幕左边缘时的竖排样式：Codex 的宠物和圆环、Claude 的宠物和圆环，下方是语言、图钉和菜单按钮">

小组件直接启动 `desktop/bin/AgentHUD.exe`，启动后会自动恢复本地额度服务。早期版本通过 `Agent HUD.vbs` 和 `start-widget.ps1` 启动，曾被杀毒软件（Norton）拦截，因此当前入口不再依赖脚本。新编译的程序首次运行时，部分杀毒软件会先扫描数十秒才放行。

小组件是 246 × 52 DIP 的玻璃横条，质感参照 Windows 11 的亚克力：实时模糊背后的内容，再叠上一层浅色底、细微颗粒、顶部的柔和光泽、沿上边缘的一道高光和一圈淡淡的深色描边。没有使用 Windows 自带的亚克力背景，因为 Windows 只在获得焦点的窗口上绘制它，而小组件从不抢焦点；模糊效果则不受焦点影响。小组件使用 Windows 11 原生圆角，随 Windows 显示缩放调整，并跟随 Windows 应用的浅色/深色主题（与完整面板一致）。系统关闭“透明效果”时改用不透明底色，也不加颗粒。每个平台占一块：一只宠物加一组品牌色圆环（Codex 蓝紫渐变、Claude 陶土橙）。

每个平台都有一只宠物，它的姿态反映该平台 agent 正在做什么。Codex 的是一朵蓝紫色的云，嘴巴是 `>_`；Claude 的是一团橙色的小家伙，头顶的嫩芽上开着一朵火花。
- **工作中：** 有 agent 在工作时它会蹦跳（会话在 2 分钟内写过日志且这一轮还没结束）。Claude 的火花会转，Codex 的光标会闪。
- **空闲：** 它会呼吸、眨眼。
- **额度偏低：** 任一圆环剩余低于 20% 时它会犯困冒汗。
- **额度用尽：** 任一额度窗口用尽时，它会瘫成一摊睡着，头顶飘出“z z Z”。
- **服务离线：** 本地服务离线时它会变灰。

收起时动画暂停，并遵循 Windows 的“动画效果”设置。

悬停宠物或圆环会弹出该平台的详情卡片：
- 平台提供的每个额度窗口（标出它对应外圈还是内圈），各带进度条和节奏刻度、重置倒计时和日期，以及[按当前节奏的预测](#额度节奏)；
- agent 当前在做什么、有几个活跃会话；
- 今日 token 和请求数，以及最近使用的模型和思考力度；
- 额度来源和更新时间。

按住空白处拖动可移动，松手时靠近屏幕工作区边缘会贴边。拖到屏幕左边或右边贴边时，它会变成 58 × 260 DIP 的竖排：宠物在圆环上方，按钮在下方，详情卡片和菜单朝屏幕内侧弹出；拖离边缘后恢复横条。显示器、相对位置和横竖样式都会自动保存。恢复位置会避开任务栏和多屏之间的空隙；显示器或缩放变化后重新校正，找不到原屏幕时回到主屏。⋯ 菜单和托盘菜单均提供“重置小组件位置”。

每个平台的外圈是 5 小时额度，里面较细的内圈是整个账户的 7 天额度；只针对某个模型的额度（例如 Claude 的 Opus 周额度）列在详情卡片里。中间显示 5 小时额度的剩余百分比（低于 20% 变红），下方是它的重置时间。点击任一圆环，所有圆环中间都切换为 7 天额度，再点一下切回；选择会被保存，中间数字对应的那一圈以全亮度显示。重置时间一天内显示具体时刻（如“14:30”），一周内显示星期（如“周四”），更远显示日期（如“11/24”）。只有一个额度周期的套餐（例如 ChatGPT 免费版只有一个 30 天额度）只显示一个圆环。每个圆环上横跨一道小刻度，标出均匀使用时此刻应剩的位置；快要在重置前用完的额度也会告诉读屏软件。本地服务离线时数字下方显示“离线”，平台未提供重置时间时显示“剩余”。本地快照每 5 秒读取一次，Codex 官方额度正常约每分钟查询、Claude 桌面额度正常约每 5 分钟查询，连接失败时可能延迟。未知时间不会显示成“刚刚”。

蓝色实心图钉表示已置顶，带斜线的空心图钉表示未置顶；点一下图钉即切换置顶，再点一下取消。横条末端的 ⋯ 打开菜单，可切换置顶、打开面板或 Codex / Claude 官方用量页、收起至托盘、重置位置或退出。

小组件支持中文和英文：默认跟随 Windows 显示语言；点图钉左边的 **EN** / **中** 按钮（或托盘菜单中的“Switch to English / 切换到中文”）可立即切换，选择会被保存。本地服务发来的状态文字（额度来源、连接提示）也会一并翻译。

本地服务离线时边缘变橙并显示“离线”，小组件在连续两次读取失败后自动用 `start.ps1` 重启服务（最多每分钟一次）。值和显示状态未变化时不重复重绘圆环；收起后停止界面更新和动画，继续获取数据，恢复时立即显示最新快照。托盘与退出信号由事件唤醒，不再每秒轮询。

界面视觉遵循 [apple-design-skill](https://github.com/naplesblue/apple-design-skill) 的规范：灰白底、白色面板与发丝分隔线、灰阶层级加单一蓝色强调，玻璃只用于导航、弹窗和悬浮的小组件。

桌面程序使用 Windows 自带 .NET Framework 构建，不需要安装额外桌面运行时。启动入口复用已构建的程序，不执行源码检查和自动重编译。修改源码后，请先从小组件菜单退出，再运行 `powershell -ExecutionPolicy Bypass -File desktop/build.ps1`，然后重新启动。`desktop/build-support.ps1` 中的内容指纹、临时目录构建与有序替换逻辑仍保留，供开发和回归测试使用。启动诊断记录在 `.data/widget-startup.log`，程序错误记录在 `.data/widget-error.log`。

## macOS 桌面小组件

Mac 版小组件是 `macos/` 目录下的原生应用（Swift，基于 AppKit 和 SwiftUI），具备上文 Windows 小组件的全部功能：横条、双层圆环及点击切换中间数字、宠物及其各种状态、节奏刻度、带预测的详情卡片、悬停提示、图钉、语言按钮和 ⋯ 菜单。拖到屏幕左右边缘同样会变成竖排，并记住所在屏幕、位置和横竖样式。圆环、卡片、预测和定位的规则从 Windows 版逐条移植，并用相同的用例测试。在 macOS 有自己惯例的地方，小组件遵循 macOS：
- **菜单栏代替托盘：** 菜单栏里的圆环图标提供托盘菜单的功能：显示或收起小组件、重置位置、打开面板或官方用量页、切换语言、退出。应用不在程序坞显示图标，也从不抢走你正在使用的应用的焦点。
- **玻璃：** 使用 macOS 自带的背景模糊，再叠上同样的浅色底、颗粒、光泽和边缘。跟随 Mac 的浅色/深色外观；开启“减少透明度”或“增强对比度”时改为不透明。开启“减弱动态效果”时，宠物和圆环停止动画。
- **字体与语言：** 文字使用系统字体。语言跟随“系统设置 → 通用 → 语言与地区”中的首选语言，直到你用 EN / 中 按钮或菜单栏图标选择一种。
- **多个桌面：** 小组件在每个桌面（空间）上都会显示，而不只是打开它的那一个。

`sh macos/build.sh` 构建发布版到 `macos/bin/Agent Meter.app`（会先退出正在运行的副本），并做临时签名（ad hoc）。这个签名只对构建它的那台 Mac 有效，所以请在要使用的 Mac 上构建。应用从自身往上三级目录找到项目，因此请把它留在 `macos/bin`，或用 `--root <项目目录>` 启动。如需登录时自动启动，在“系统设置 → 通用 → 登录项”中添加它。本地服务离线时，它会用 `start.sh` 重启服务（最多每分钟一次）。

**现状：** 每次推送都会在 GitHub 的 macOS 运行器上构建并测试应用：渲染横条、竖排和卡片的浅色/深色、中英文预览，再用鼠标操作真实窗口：停在玻璃上显示提示、悬停圆环弹出卡片、点击圆环切换中间数字、拖到屏幕边缘变成竖排、打开 ⋯ 菜单。它还没有在 Mac 上日常使用过；如果发现外观或行为与 Windows 版不同，欢迎提 issue。

## Claude 账户额度

### 桌面账户连接

桌面版账户读取通道默认关闭，支持 Windows 与 macOS。它仅在内存中读取当前用户的 Claude 加密 OAuth 缓存，匹配当前账户和唯一组织，并向固定地址 `https://api.anthropic.com/api/oauth/usage` 发送 GET。此额度由同一账户的桌面版、网页版和 CLI 共享，不依赖状态栏回调，也不发起模型请求。

明确允许此连接后，运行 `node scripts/connect-claude-desktop.mjs --enable`，然后重启 HUD 服务。关闭连接使用同一命令的 `--disable`。开关保存在本项目 `.data/claude-desktop-connection.json`，默认缺失时不会读取任何登录凭据或请求 Claude 额度。

正常每 5 分钟查询，限流时至少等待 15 分钟。HUD 不保存访问令牌、不记录接口原始响应、不修改 Claude 配置、不刷新或轮换令牌；连接过期时需打开 Claude，由原应用续期。多组织无法确定归属时停止读取，防止显示错账户的额度。断线时标注历史快照，注销或账户连接失效时清空旧值。

兼容 Windows 独立安装与 Microsoft Store 的 Claude 数据目录，包括新版 Claude 迁移后的 `%LOCALAPPDATA%\Claude-Data` 目录（优先读取）。依据本机桌面应用的内部接口实现，并非厂商公开承诺稳定的第三方 API，应用更新后可能需要适配。已用真实账户在 Microsoft Store 桌面版上验证，可取得 5 小时和 7 天额度及重置时间。

在 Mac 上，它从 `~/Library/Application Support/Claude` 读取同样的缓存（会先检查其中的 `Claude-Data` 目录，以防新版像在 Windows 上那样迁移）。Claude 用保存在登录钥匙串中、名为“Claude Safe Storage”的密钥加密这份缓存，服务通过 Apple 自带的 `security` 工具读取该密钥。第一次读取时，macOS 会询问是否允许 `security` 使用它：
- “允许”只对本次运行有效。服务仅在内存中保存该密钥，下次服务启动时 macOS 会再次询问。
- “始终允许”以后不再询问，但此后在你账户下运行的任何程序都能通过 `security` 直接读取该密钥，不会有提示。
- “拒绝”则不显示 Claude 额度，并且在服务重启前不再询问。

Mac 上的读取逻辑已用合成数据测试，但尚未在真实安装的 Claude 上验证。

Windows 上建议使用 Node.js 24.5+；HUD 会同时使用 Node 默认证书和 Windows 系统可信证书库，保持完整 HTTPS 校验。

### 终端状态栏桥接

运行 `node scripts/connect-claude.mjs` 接入官方状态栏。脚本备份 `~/.claude/settings.json` 后只添加 `statusLine`；已存在其他自定义状态栏时会停止，避免覆盖。可使用 `CLAUDE_CONFIG_DIR` 指向其他 Claude 配置目录。

此桥接适用于**终端中的 Claude Code CLI**。重新打开 CLI 后，正常模型响应会触发状态栏，HUD 读取其中的平台额度。无需为 HUD 额外发送请求。字段是否出现取决于 Claude Code 版本和账户类型；未提供时保留未知状态，不根据 token 推算。

终端桥接不会被本机的 Claude 桌面会话调用，安装它本身不代表桌面额度已接入。桌面版应使用上述账户连接。HUD 保留 [Claude 官方用量页](https://claude.ai/settings/usage) 入口，桌面版会话的 token 记录也仍可统计。

状态栏桥接仅把 session ID、额度窗口、上下文数值、采集时间写入本项目 `.data`。它不会保存完整 stdin、提示词或凭据。卸载桥接：`node scripts/connect-claude.mjs --remove`，保留其他配置不变。

已有状态栏时，可在自己的状态栏脚本中把同一份 stdin JSON 传给 `scripts/claude-statusline.mjs`，忽略其 stdout，以保留原显示。

参考：[Claude Code 官方状态栏文档](https://code.claude.com/docs/en/statusline)。

## 隐私与实现

服务仅绑定 127.0.0.1，拒绝跨域和陌生 Host。浏览器接收会话标题、项目短名称、模型和用量，不包含原始对话、工具输出、文件路径或登录信息。解析时仅保留计数和元数据；会话文件只读。`.data` 已加入 Git 忽略。

前端每 5 秒获取快照；后台增量扫描新增日志，容忍半行 JSON。Codex 官方额度约每分钟查询，Claude 桌面额度正常约每 5 分钟查询。数据缺失、陈旧、断连都有独立状态。

其他平台可通过 `lib/collector.mjs` 增加适配器，复用 `lib/metrics.mjs` 中的统一会话/请求/额度结构。目前真正接入的只有 Codex 与 Claude Code，不展示模拟平台。

## 验证

`npm test` 或 `node --test test/*.test.mjs`。测试包含缓存口径、推理不重复、流式响应去重、继承记录排除、空额度、重置时间与增量读取。

Windows 桌面回归：`powershell -ExecutionPolicy Bypass -File desktop/test.ps1`。测试会短暂显示独立测试窗口，在 `.data/desktop-tests` 下使用独立状态，不修改实际小组件的位置与设置。覆盖圆环内的文字、宠物的每种状态、详情卡片、贴边变竖排再恢复、置顶恢复、图钉点击切换、⋯ 菜单及其弹出位置、语言按钮、不抢焦点、托盘显示与退出信号、更新时间与重置时间显示、屏幕空隙/负坐标/断屏/缩放后的定位计算、真实窗口越界校正、隐藏停止渲染及未变化的圆环不重绘。真实多屏热插拔和不同显示器 DPI 间的拖动仍需在相应硬件上验收。

自动更新回归：`powershell -ExecutionPolicy Bypass -File desktop/test-launcher.ps1`，使用临时项目与后台测试进程，覆盖首次构建、跳过未变化的源码、时间戳不变时的内容检测、有序替换、编译失败保留旧进程与旧程序；兼容 Windows PowerShell 5.1。

macOS：`swift test --package-path macos` 运行小组件共享规则的测试：圆环、5 小时/7 天切换、周额度用尽、预测、宠物状态、卡片和定位。`.github/workflows/ci.yml` 中的 CI 还会在 Windows、macOS 和 Linux 上运行 `npm test`，并在 macOS 上构建应用、渲染预览、操作真实窗口（见 [macOS 桌面小组件](#macos-桌面小组件)）。

## 许可

本项目以 MIT 许可发布，见 [LICENSE](LICENSE)。小组件与面板中的 Codex、Claude 标志图形来自 [LobeHub Icons](https://github.com/lobehub/lobe-icons)（MIT）；这些标志是 OpenAI 与 Anthropic 的商标，不随本项目的 MIT 许可授予。
