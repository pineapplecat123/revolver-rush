# v0.4.90 验证

- CYL-18：只改「枪口：」右侧小图标。相同 `effect_kind`（无则用 id）合并为一枚，剩余层数 N>1 时在图标旁标明 ×N（乘号 ×，×1 省略）；不同类型按首次出现顺序分开。弹层文案显示合并后的层数。向上燃烧的大火焰轮廓、envelope（视觉重量仍封顶 12 层）和内外层规则未改。
- CYL-19：崩溃原因（无当时日志，由代码与复现推断）：批准规则「双倍给下一个」会把跨齐射仍存活的组原地翻倍（1→2→4→…），再叠加「传递」按 `round(伤害)-3` 授予，层数可到数百。小图标过去一层一枚 Control，每帧重建，最容易把网页版撑崩。消耗逻辑与预览深拷贝看起来正常，不是主因。修复：授予与翻倍时单组剩余层数安全上限 99，超出写入对局日志的 `flame cap` 事件；不超过 99 的批准例子（12 层翻倍成 24、传递 +9、N≤6）行为不变。同时小图标改为 ×N，避免再为数百层生成数百个控件。
- CYL-20：每局（闯关／rush!／沙盒）开始写一份对局日志，记录错误、战斗 `_log` 行、火焰翻倍／授予截断、每发后的层数快照（总数、组数、按类型）。网页崩溃时 JS 的 `error`／`unhandledrejection` 另记到 `rr.sessionLog.errors`。

## 如何查看日志

主菜单「导出对局日志」或战斗顶栏「导出日志」：

- 网页（GitHub Pages `/redo/` 等）：浏览器下载 `rr-session-….log`。崩溃刷新后仍可导出上一局——写在 `localStorage` 的 `rr.sessionLog.current`／`previous`（及错误键 `rr.sessionLog.errors`）。「清理缓存并刷新」会保留这三项，不会把未保存的对局日志清掉。若在浏览器设置里清除整个站点数据，这些键才会消失。
- 桌面／编辑器：文件在 `user://session_logs`（最多 5 份），导出后绝对路径会复制到剪贴板。本机可用 `ProjectSettings.globalize_path("user://session_logs")` 打开，Linux 上一般为 `~/.local/share/godot/app_userdata/Revolver Rush/session_logs`。
- 没有后台遥测，也没有改鉴权。GUT 写入 `user://session_logs_gut`，不会覆盖玩家日志。

再出现火焰堆叠或崩溃时，日志里应有 `FLAME {"kind":"cap",…}`、`kind":"double"` 以及 `snapshot` 的 `total`／`by_type`，足够对照本次崩溃。

## 原生证据

`docs/shots/rr_v0490_{icons_stacked,icons_consumed}.png`，均为 720×1280，版本角标 v0.4.90。叠层静帧在「枪口：」下为 ×5、一枚无标记、×4，枪口上的大火焰仍按总层数变大；消耗后变为 ×4、×3（无标记的那类被耗尽），大火焰明显变矮，没有收成一个 ×N。战斗顶栏已有「导出日志」。此为原生 Godot 检查，不是手机／浏览器交互验收；夹具在 `/workspace/rr-v0490-verification/`，未加入生产。

## 最终本地门禁

GUT 94 脚本／793 测试／19191 断言通过；版本单一来源与 UI 字库覆盖通过（补了「崩护枚溃」等字形）；Web 正式导出见同批记录。GUT 仍有既有预热协程退出和资源／孤立对象告警，未借本批做无关清理。
