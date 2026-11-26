# 弹珠物语（Marble Story）· 完整游戏方案 v0.2

> 手机竖屏 · 在线小游戏 · Roguelike 弹珠台构筑
> 引擎：UrhoX（Lua 5.4 · urhox-libs/UI · NanoVG）
> 本文档 + `scripts/` 下的可玩 Demo 共同构成交接包：**方案说清"做什么、为什么"，Demo 定死"手感、架构、规范"**。后续 AI / 开发者按第 17 章的落地指引扩展内容即可。

### 版本记录

| 版本 | 日期 | 内容 |
|---|---|---|
| v0.1 | 2026-11-26 | 首版方案 + 可玩 Demo |
| v0.2 | 2026-11-26 | 修正出射（珠子不再全部落右侧）与两处卡珠刷分并重新校准数值；新增 UI 控件合图提示词；新增第 19–25 章：完整版内容规格、局外系统细则、新手引导、切图与接入规范、存档结构、开发任务清单、Demo 已知限制 |

---

## 目录

0. [交付物索引](#0-交付物索引)
1. [项目概述](#1-项目概述)
2. [参考玩法拆解](#2-参考玩法拆解)
3. [核心循环](#3-核心循环)
4. [局内规则](#4-局内规则)
5. [爽感设计（核心卖点）](#5-爽感设计核心卖点)
6. [局外决策系统](#6-局外决策系统)
7. [关卡结构与头目](#7-关卡结构与头目)
8. [局外成长（Meta）](#8-局外成长meta)
9. [数值体系](#9-数值体系)
10. [UI / UX](#10-ui--ux)
11. [美术方案与贴图替换提示词](#11-美术方案与贴图替换提示词)
12. [音频](#12-音频)
13. [技术架构](#13-技术架构)
14. [商业化与轻社交](#14-商业化与轻社交)
15. [埋点](#15-埋点)
16. [Demo 现状与路线图](#16-demo-现状与路线图)
17. [给后续 AI 的落地指引](#17-给后续-ai-的落地指引)
18. [风险与对策](#18-风险与对策)
19. [完整版内容规格（可直接实现）](#19-完整版内容规格可直接实现)
20. [局外系统细则](#20-局外系统细则)
21. [新手引导](#21-新手引导)
22. [切图与 UI 贴图接入规范](#22-切图与-ui-贴图接入规范交给切图-ai--接入-ai)
23. [存档数据结构](#23-存档数据结构version--1)
24. [开发任务清单（Backlog）](#24-开发任务清单backlog)
25. [Demo 已知限制与待真机验证项](#25-demo-已知限制与待真机验证项)
- [附录 · 名词表](#附录--名词表)

---

## 0. 交付物索引

| 交付物 | 位置 | 说明 |
|---|---|---|
| 完整游戏方案 | `docs/GDD.md`（本文） | 玩法、数值、UI、美术、技术、路线图 |
| 可玩 Demo | `scripts/` | 入口 `scripts/main.lua`，全部程序化美术，无需任何贴图/音频即可运行 |
| 纯 Lua 冒烟测试 | `tests/test_all.lua` | `lua5.4 tests/test_all.lua`，严格 NanoVG/UI 桩，覆盖完整流程与极值态 |
| 数值模拟器 | `tests/sim_balance.lua` | `lua5.4 tests/sim_balance.lua 60`，贪心 AI 跑整局，校准目标分 |
| 贴图替换提示词 | 本文第 11 章 | 宣发三件套 + 8 张局内合图 + 3 张 UI 控件合图 + 单张大图提示词，含格位→文件名映射 |
| 切图与接入规范 | 本文第 22 章 | 给切图 AI 与接入 AI 的交接标准（去底、尺寸、九宫格切线 `slices.json`） |
| 开发任务清单 | 本文第 24 章 | 20 个任务，带优先级、依赖与验收标准 |

---

## 1. 项目概述

### 1.1 一句话定位

**"局外运筹帷幄，局内一拳干到底"** —— 一款把日式柏青哥（弹珠台）的声光爆炸、小丑牌式的指数爆分构筑、哥布林弹珠式的珠子技能化融合在一起的竖屏 Roguelike。

### 1.2 核心体验宣言

| 玩家在做什么 | 玩家的感受 |
|---|---|
| **局外**：在商店挑珠子、买护符、改台面、瘦身珠袋 | "这套组合要是成了，一定很炸" —— 运筹、期待 |
| **局内**：只按一个按钮「大力干!」 | "交给天意吧！" —— 放手、紧张 |
| **看**：几十颗珠子倾泻、钉子连环点亮、爆炸连锁、老虎机听牌、FEVER 珠雨、数字指数膨胀 | "卧槽卧槽卧槽！" —— 爽 |

局内**刻意不给操作**：没有瞄准、没有力度条、没有暂停换珠。玩家的全部策略压缩在局外，局内的随机性（发射角度、撞钉偏转、老虎机）被设计成**可感知的天意**（看得见的偏转、看得见的听牌）而不是黑箱。

### 1.3 基础信息

| 项 | 值 |
|---|---|
| 品类 | Roguelike 构筑 + 物理弹珠（Pachinko-like） |
| 平台 | TapTap 小游戏 / 竖屏 H5 / 独立微端（`screen_orientation = portrait`） |
| 目标用户 | 18–35 岁碎片时间玩家；喜欢小丑牌、吸血鬼幸存者类"数字爆炸爽游"的人群 |
| 单局时长 | 单台 30–60 秒；一整局（8 层 24 台）约 15–25 分钟，任意台间可断点续玩 |
| 付费模式 | 买断式体验 + 激励视频（复活/双倍/刷新），无数值付费 |
| 美术风格 | 霓虹街机 × 和风祭典 × 糖果质感（Style Bible 见 11.1） |

### 1.4 差异化

1. **"零操作"局内**：同类弹珠 Roguelike（如 Peglin）局内要瞄准；我们把瞄准拿掉，换来**一键开爽 + 极强的观赏性**，更适合竖屏单手与短视频传播。
2. **柏青哥演出语言**：启动口 → 液晶老虎机 → 保留灯 → 听牌（就差一个!）→ 大当 FEVER → 珠雨，这套演出在国内小游戏里几乎没人系统化做过。
3. **小丑牌式乘法爆分**：珠分 × 倍率，护符改写规则，后期单发分数从几万到几亿，数字膨胀本身就是奖励。

---

## 2. 参考玩法拆解

| 参考 | 我们拿什么 | 我们不拿什么 | 落地 |
|---|---|---|---|
| **日式柏青哥 / 东京弹珠物语** | 钢珠从左侧轨道射入、沿顶部圆弧落入钉阵；中央液晶；**启动口**（入赏）触发抽奖；**保留**（最多 4 个待转）；**听牌**演出；**大当 / FEVER**；超级大当 777 | 真实赌博元素、兑换、复杂的确变/时短规则 | 4.3 启动口与老虎机、4.4 FEVER |
| **小丑牌（Balatro）** | **珠分 × 倍率**计分、层（Ante）× 3 关（小/大/头目）、头目规则、**护符=小丑牌**（被动改写规则）、利息经济、商店刷新、卖出 | 扑克牌型、手牌管理、弃牌 | 4.6 计分、6.2 护符、6.4 经济、7 关卡 |
| **哥布林弹珠（Peglin 类）** | **珠子即技能**（火珠爆炸、分裂珠、幽灵穿透）、**钉子有类型**（金/红/炸弹/分裂）、珠袋构筑与瘦身 | 回合制战斗、敌人血条、瞄准 | 6.1 珠子、4.2 钉子 |

一句话：**柏青哥的"演出"＋小丑牌的"乘法"＋Peglin 的"珠子技能"**。

---

## 3. 核心循环

```
┌──────────────── 一局 Run（8 层 × 3 台 = 24 台）────────────────┐
│                                                                │
│   ┌──── 一台 Stage（目标分，3 次发射）────┐                    │
│   │  [大力干!] → 一发（弹匣 10 颗珠）      │                    │
│   │    ├ 珠子沿轨道射入 → 钉阵弹跳 → 计分  │  ← 30~60 秒       │
│   │    ├ 启动口 → 老虎机 → FEVER 珠雨       │                    │
│   │    └ 落袋 → 结算 珠分×倍率 → 累计      │                    │
│   │  累计 ≥ 目标 → 过关；发射用尽 → 失败    │                    │
│   └───────────────┬──────────────────────┘                    │
│                   ↓ 过关奖励 $（基础 + 剩余发射 + 利息）       │
│   ┌──── 商店 ────────────────────────────┐                    │
│   │ 买珠子 / 买护符 / 买改造 / 熔珠 / 刷新 │ ← 唯一决策点      │
│   └───────────────┬──────────────────────┘                    │
│                   ↓ 下一台（每 3 台一个头目）                  │
└───────────────────┴────────────────────────────────────────────┘
        ↓ 通关 / 失败
  局外：解锁台主、图鉴、最佳纪录 → 再来一局（一键直达）
```

**3-10-30 黄金漏斗**：3 秒看懂（大按钮 + 闪烁箭头"▼ 大力干! ▼"）→ 10 秒第一次操作（首屏即可点）→ 30 秒内第一次爽点（第一发必然有珠子入赏/特殊钉连锁）。

---

## 4. 局内规则

### 4.1 盘面结构（盘面单位 BU，360 × 640，y 向下）

```
          ╭──────── 顶部圆弧（半径 156，碰撞）────────╮
   轨道 ║ │      · ·  ┌──────────────┐  · ·           │
   (只  ║ │    · · ·  │ 液晶 老虎机   │  · · ·        │   液晶：碰撞体（圆角矩形）
   是视 ║ │   · · · · └──────────────┘ · · · ·        │
   觉)  ║ │  · · · · ·    ╲ 命钉 ╱    · · · · ·       │
        ║ │ · · · · · · ·◖ 启动口 ◗· · · · · · ·      │   启动口：两颗沿钉 + 传感圆
        ║ │  · ◎ · · · · · · · · · · · · · ◎ ·        │   ◎ 弹力柱（本台固定位置）
   发射 ║ │ · · · · · · · · · · · · · · · · · ·       │   ·  钉子（每发随机替换为特殊钉）
   口 ↑ ║ │  · · · · · · · · · · · · · · · · ·        │
        ║ ├──┬──┬──┬──┬──┬──┬──┤
        ║ │回│+20│+1│+3│+1│+20│回│  ← 7 个底部口袋
        ╚═╧══╧══╧══╧══╧══╧══╧══╛
```

- **钉阵模板**（`Config.LAYOUTS`）：`hex` 蜂窝 / `waves` 波浪 / `diamond` 菱形空洞 / `lanes` 竖通道。每台轮换，配合 4 套主题配色（樱花/霓虹/黄金/深海）保证 24 台视觉不重样。
- **特殊钉每发重新随机布置**：同一台三发看到的特殊钉位置不同 —— 这是"天意"的主要来源之一，也让玩家每发都有新期待。

### 4.2 钉子

| 钉子 | 默认数量/发 | 效果 | 命中后 |
|---|---|---|---|
| 普通钉 | 其余全部 | +2 珠分（FEVER 中 ×3） | 常驻（闪白） |
| 金钉 | 4 | +15 珠分，35% 掉 $1 | 熄灭 |
| 红钉 | 5 | +2 倍率 | 熄灭 |
| 紫钉 | 1 | **×2 倍率**（慢动作 + 紫闪） | 熄灭 |
| 炸弹钉 | 2 | +5 珠分，半径 54 爆炸：波及范围内钉子全部触发 + 推开珠子（**可连锁**） | 熄灭 |
| 分裂钉 | 0（改造获得） | +3 珠分，分裂出 2 颗钢珠 | 熄灭 |
| 弹力柱 | 2（本台固定） | +6 珠分，强力弹射 | 常驻 |

### 4.3 启动口与老虎机（柏青哥演出核心）

1. 珠子落入**启动口**（中央、两颗沿钉之间，宽度只容普通珠，重珠进不去）→ +5 珠分，获得 1 个**保留**（液晶下方 4 盏保留灯，满了不再增加）。
2. 有保留且未在 FEVER 中 → 自动消耗 1 个保留**转动老虎机**（3 轴，符号：7 / 星 / 樱桃 / 铃铛 / 弹珠）。
3. 结果在开转时就决定（便于演出）：

| 结果 | 概率（基础） | 演出 | 奖励 |
|---|---|---|---|
| **超级大当 777** | 16% × 25% = 4% | 前两轴停 7 → **听牌**（第三轴减速 +1 秒，边框红黄闪烁，"就差一个!"，慢动作）→ 777 | 进入超级 FEVER 10 秒 + 18 颗珠雨 + 立刻 +3 倍率并 ×2 倍率 |
| **大当** | 12% | 听牌 → 三连 | FEVER 7 秒 + 10 颗珠雨 + 立刻 +3 倍率 |
| 听牌落空 | 32% | 听牌 → 最后一轴错开 | 安慰 +1 倍率 |
| 无 | 其余 | 三轴依次停 | +10 珠分 |

> 时间轴：一轴 0.45s，二轴 0.75s，三轴 1.05s（听牌 +1.0s）。**听牌落空的比例被刻意调高**，让"差一点"的情绪频繁出现 —— 这是柏青哥最核心的成瘾钩子，但我们只用于情绪，不用于付费。

### 4.4 FEVER

- 盘面背景转金色呼吸、所有普通钉变彩虹色、边框彩虹流动、BGM 切换 `bgm_fever`。
- 普通钉珠分 ×3（狂热太鼓再 ×2），金钉 ×2。
- 顶部降下珠雨（不占珠袋）。
- FEVER 期间新的保留**累积不转**，FEVER 结束后继续转 → 可能**连庄**。

### 4.5 发射

- 每台 3 次发射（改造/护符可加）。一发 = 从珠袋抽出一个**弹匣**（默认 10 颗）依次射出，间隔 0.075s。
- 每颗珠先随机一个**天意落点 x**（46–314，左右均匀），再反推它在顶部轨道上的脱轨角度；脱轨时只带很小的切线速度（0–40）和 ±55 的横向扰动，让重力主导下落 → 天意。
  > 教训：最初按"随机脱轨角 + 大切线速度（260–470）"出射，珠子全部顺时针贴着圆弧冲向右侧，**实测 97% 落在右半边**。修正后 4 种钉阵中场左右比都在 47%–56%。
- 钉阵以中线**左右对称**生成（两侧边道等宽）；离启动口沿钉/命钉太近、会形成"珠子穿不过去的 V 形夹缝"的普通钉一律删除。
- 撞钉反弹带 ±0.1 弧度随机偏转（`PHYS.jitter`），打破"停在钉顶"的同时制造可见的随机。
- 底部**回收口**：珠子重新射入一次（回旋镖护符：3 次）。
- 超过 22 秒仍未落袋 / 飞出盘面的珠子强制回收（"噗"）。
- **防卡珠 / 防刷分**：① 每 0.5 秒检查位移，几乎没动就往中线弹开，连续 6 次救不出直接回收；② 冲击速度 < 20 的"静止贴钉"不计分；③ 计分冷却按"每颗钉"单独计时（防止珠子卡在两颗钉之间交替刷分）。

### 4.6 计分

```
一发得分 = round( 珠分 × 倍率 )
  珠分 = Σ 钉子珠分 × 珠子修正 + 口袋珠分 + 老虎机安慰分 + 护符加成
  倍率 = (1 + Σ 加法倍率) 按发生顺序穿插 × 乘法倍率     ← 先加后乘不固定，按事件时序累计
本台累计 = Σ 一发得分；累计 ≥ 目标 → 过关
```

- 事件时序决定数学：**先吃红钉再吃紫钉**远大于反过来 —— 这是"天意"带来的戏剧性，局外则可以用护符（如"背水一战"最后一发 ×3）锁定结算时的乘法。
- 结算时盘面中央弹出 `珠分 × 倍率 = 得分` 大字，得分滚动上涨；若这一发能过关，分数板**着火**、得分金色放大。

### 4.7 胜负

- 一发结算后累计 ≥ 目标 → **过关**（剩余发射次数折算 $）。
- 最后一发结算后仍不足 → **台崩了**（本局结束）。
- 第 8 层头目台过关 → **全台通关**。

---

## 5. 爽感设计（核心卖点）

### 5.1 反馈阶梯（从小到大，强度递增，必须节制）

| 等级 | 事件 | 视觉 | 听觉 | 时间 | 镜头 |
|---|---|---|---|---|---|
| L0 | 撞普通钉 | 钉子闪白 + 2 颗火花 + 55% 概率飘小数字 | `peg` 音高随单珠连击递增（最多 +50%） | — | — |
| L1 | 撞特殊钉 | 12 颗火星 + 冲击环 + 彩色飘字 | `coin` / `mult` / `bumper` | — | — |
| L2 | 紫钉 ×倍率 / 口袋 ×倍率 | 紫闪 + 大环 + 大号飘字 | `xmult` | **慢动作 0.35× / 0.18s** | 震屏 4 |
| L3 | 炸弹爆炸 | 双环 + 26 火星 + 烟 + 暖闪 | `boom` | 慢动作 0.5× / 0.12s | 震屏 7 |
| L4 | 入赏 / 听牌 | 液晶闪光、"入赏!"、"就差一个!" 横幅、保留灯 | `start` / `reach` | 听牌慢动作 0.6× | 震屏 5 |
| L5 | FEVER / 777 | 满屏金/红闪、3 道巨环、60 火星、"大当 FEVER!!" 弹跳横幅、背景变金、钉子彩虹 | `fever` + BGM 切换 | 慢动作 0.25× / 0.35s | 震屏 12 |
| L6 | 一发过关 | 分数板着火、得分金色滚动放大、暖白闪 | `bigwin` | — | 震屏 10 |

**节制规则**：
- 同时只允许一个慢动作（取最长、取最慢），震屏幅度取最大值不叠加，闪白 alpha 取最大值。
- 普通钉飘字随机抽样（55%），否则满屏数字会糊。
- 粒子池 520、飘字池 64、环 40，满了覆盖最旧的 —— 永不掉帧也永不报错。

### 5.2 数字膨胀曲线

- 第 1 层单发中位 ~2.4 万，第 8 层中位 ~153 万，顶级构筑单发可达**数千万到数亿**（模拟器实测最大 3880 万）。
- 显示统一走 `Skin.Num`：`≥1万 → 1.75万`，`≥10万 → 17.5万`，`≥1亿 → 1.23亿`，`≥1万亿 → 1.2万亿`，窄标签永不溢出。

### 5.3 "天意"与"奇迹"

| 天意（随机，但看得见） | 奇迹（构筑带来的必然爆发） |
|---|---|
| 出射角度/速度随机，玩家看得到珠子从不同位置落下 | 千手观音：首颗珠首撞分裂 6 颗 |
| 撞钉随机偏转 | 鞭炮串 + 火珠：爆炸连锁清半屏 |
| 特殊钉每发重新布置 | 确变之魂 + 幸运珠：大当率翻倍、必中 |
| 老虎机听牌（30%+ 的"差一点"） | 背水一战：最后一发 ×3 |

### 5.4 节奏（一发 8–15 秒的情绪曲线）

```
期待 ─ 释放 ─── 连锁 ──── 悬念 ─────── 爆发 ── 收束
按钮   珠流入   特殊钉/爆炸  入赏→听牌     FEVER   结算大字
0s     0.5s     2-6s        3-8s          5-12s   +1.5s
```

### 5.5 静音可玩

所有关键信息都有独立视觉：听牌 = 红黄闪边框 + 横幅；FEVER = 满屏颜色；过关 = 着火分数板；护符触发 = 护符栏对应格子弹跳旋转。

---

## 6. 局外决策系统

### 6.1 珠子（Demo 已实现 9 种）

| 珠子 | 价格 | 稀有 | 效果 | 设计意图 |
|---|---|---|---|---|
| 钢珠 | $2 | 普通 | 无 | 填充物；后期要"熔掉" |
| 金珠 | $5 | 普通 | 每次命中 +3 珠分；落袋 +$1 | 经济流起点 |
| 火珠 | $6 | 稀有 | 前 3 次命中引发小爆炸（半径 38） | 爆破流核心 |
| 分裂珠 | $5 | 普通 | 首次命中分裂出 2 颗钢珠 | 人海流 |
| 重珠 | $5 | 稀有 | 半径 9，命中珠分 ×2，进不了启动口 | 珠分流，与老虎机流互斥 |
| 幽灵珠 | $6 | 稀有 | 前 1.4 秒穿透钉子（每钉计一次） | 一口气刷满上半区 |
| 彩虹珠 | $6 | 稀有 | 每命中 5 钉 +1 倍率 | 倍率流 |
| 弹力珠 | $3 | 普通 | 弹性 0.88，撞墙 +5 珠分 | 便宜的混乱制造者 |
| 幸运珠 | $7 | 传说 | 进启动口必中大当 | 老虎机流核心 |

**完整版规划新增 9 种**：冰珠（冻住钉子使其可被命中两次）、磁珠（吸附金钉）、陀螺珠（贴钉旋转多次命中）、种子珠（落袋处长出新钉）、炸弹珠（落袋爆炸）、镜面珠（命中复制最近一次特殊钉效果）、钱袋珠（命中 10% 掉 $1）、雷珠（每 10 命中劈下闪电打一列）、彗星珠（极速 + 拖尾持续伤害）。

### 6.2 护符（= 小丑牌，Demo 已实现 16 个，上限 5 个槽）

| 护符 | 价格 | 稀有 | 效果 | 钩子 |
|---|---|---|---|---|
| 红灯笼 | 5 | 普 | 红钉额外 +2 倍率 | onPegHit |
| 招财猫 | 6 | 普 | 结算时每 $5 存款 +1 倍率 | onLaunchEnd |
| 鞭炮串 | 6 | 普 | 炸弹钉 +2，爆炸范围 +40% | stats |
| 七彩风车 | 5 | 普 | 老虎机每转一次 +3 倍率 | onSlotSpin |
| 确变之魂 | 7 | 稀 | 大当概率 +12% | stats |
| 狂热太鼓 | 7 | 稀 | FEVER 中钉子珠分再 ×2 | stats |
| 千手观音 | 8 | 传 | 每发首颗珠首撞分裂 6 颗 | onPegHit |
| 弹簧鞋 | 4 | 普 | 弹力柱 +3，命中 +1 倍率 | stats + onPegHit |
| 轻羽 | 5 | 普 | 重力 -25% | stats |
| 守财奴 | 4 | 普 | 利息上限 +$5，过关 +$1 | stats |
| 连击鬼 | 6 | 稀 | 每发首个达成 15 连击的珠 ×2 倍率 | onPegHit |
| 黄金律 | 5 | 普 | 金钉 +4，金钉必掉 $1 | stats |
| 背水一战 | 6 | 稀 | 最后一发 倍率 ×3 | onLaunchEnd |
| 棱镜 | 8 | 传 | 紫钉 +2 | stats |
| 回旋镖 | 5 | 稀 | 回收口每珠可用 3 次 | stats |
| 天降甘霖 | 7 | 稀 | 每发开局额外降 6 颗钢珠 | onLaunchStart |

**完整版规划新增 24 个**（总计 40）：磁铁（珠子被金钉轻微吸引）、双响炮（炸弹钉爆两次）、雷神（每第 50 次命中劈闪电）、老千骰子（老虎机符号种类 -1）、招福达摩（失败时保留 1 次，之后碎裂）、储钱罐（每发存 $1，卖出全得）、涟漪（普通钉 20% 连带相邻钉）、黑洞（中央口袋吸附邻近珠，每颗 +1 倍率）、樱吹雪（FEVER 时降花瓣，每片 +5 珠分）、不动明王（弹力柱命中 ×1.1 倍率）、打铁匠（每过一台钢珠永久 +1 命中珠分）、赌徒（倍率 ×2 但弹匣 -3）、回声（每发最后一颗珠落袋时重发一次）、霓虹招牌（每持有 1 个护符 +2 倍率）、金蟾（每 $10 存款结算 ×1.1，上限 ×2）、爆竹王（所有珠子首撞小爆炸）、双倍保留（保留上限 +4）、确率机（听牌落空 50% 改判中奖）、量子珠（穿过启动口判定两次）、铁人（重珠体积 +50%）、彩虹桥（弹匣内每种不同珠子 +1 倍率）、狐狸面具（商店物品 -$1）、大胃王（弹匣 +4，发射 -1）、复制猫（复制右侧护符效果）。

### 6.3 改造（永久修改本局台面）与服务

| 改造 | 价格 | 效果 |
|---|---|---|
| 弹匣扩容 | 6 | 每发 +2 颗 |
| 加一发（稀有） | 9 | 每台发射次数 +1 |
| 红钉+2 / 金钉+3 / 紫钉+1 / 炸弹钉+1 / 分裂钉+2 | 4–7 | 每发对应特殊钉数量增加 |
| 熔掉一颗（固定服务位） | 3 起，每次 +1 | 从珠袋移除 1 颗钢珠（珠袋 ≤4 颗不可） |

### 6.4 商店与经济

- **货架**：2 珠子 + 2 护符 + 1 改造 + 1 固定"熔珠"服务 = 6 格（3×2 网格）。护符不会刷出已拥有的。
- **稀有度权重**：普通 60 / 稀有 30 / 传说 10；改造中"加一发"权重 12，其余 40。
- **刷新**：$2 起，每次 +1，进新商店重置。
- **过关奖励**：小台 $3 / 大台 $4 / 头目 $5 + 剩余发射 $1/次 + 利息（每 $5 得 $1，上限 $5）+ 护符额外。
- **出售护符**：半价（向下取整，至少 $1）。局内飞珠时不可卖。

### 6.5 珠袋与弹匣

- 每台开始把珠袋洗成**抽牌堆**；每发从抽牌堆抽"弹匣容量"颗，抽完再洗。
- 珠袋 > 弹匣 × 发射次数时，有些珠子本台用不上 → **瘦身珠袋**（熔钢珠）让核心珠更频繁出场 —— 小丑牌的"删牌"在这里的映射。

### 6.6 构筑流派（给玩家的"梦想"）

| 流派 | 核心 | 关键护符 | 爆点 |
|---|---|---|---|
| 爆破流 | 火珠 + 炸弹钉 | 鞭炮串、双响炮、爆竹王 | 连锁爆炸清屏，单发上万次命中 |
| 大当流 | 幸运珠 + 普通珠多入赏 | 确变之魂、七彩风车、狂热太鼓 | 连庄 FEVER，珠雨不停 |
| 人海流 | 分裂珠 + 分裂钉 | 千手观音、天降甘霖、弹匣扩容 | 同屏 200 颗珠 |
| 倍率流 | 彩虹珠 + 红/紫钉 | 红灯笼、棱镜、连击鬼 | 倍率四位数 |
| 金币流 | 金珠 + 金钉 | 黄金律、招财猫、守财奴 | 前期滚雪球买满传说 |
| 收割流 | 任意 | 背水一战、回旋镖 | 前两发铺垫，最后一发 ×3 |

---

## 7. 关卡结构与头目

### 7.1 层与台

| 层 | 小台（×1） | 大台（×1.5） | 头目台（×2） |
|---|---|---|---|
| 1 | 11,000 | 16,500 | 22,000 |
| 2 | 30,000 | 45,000 | 60,000 |
| 3 | 75,000 | 112,500 | 150,000 |
| 4 | 190,000 | 285,000 | 380,000 |
| 5 | 380,000 | 570,000 | 760,000 |
| 6 | 800,000 | 1,200,000 | 1,600,000 |
| 7 | 1,800,000 | 2,700,000 | 3,600,000 |
| 8 | 4,000,000 | 6,000,000 | 8,000,000 |

### 7.2 头目规则（Demo 7 个，第 1 层只抽温和规则）

| 头目 | 规则 | 温和 |
|---|---|---|
| 铁壁 | 启动口被封死（老虎机不转） | |
| 吝啬鬼 | 本台不出现金钉 | ✓ |
| 浓雾 | 特殊钉数量减半 | |
| 逆风 | 重力 +40% | |
| 钝钉 | 普通钉 0 珠分 | |
| 锁链 | 红钉无效 | |
| 窄门 | 底部 +3 倍率口袋失效 | ✓ |

**规划新增**：镜像、漏斗、冰冻、饥饿、静电、黑幕、倒计时、天平（规则与实现见 19.4）。**终局头目 8-3「弹珠之王」**：双液晶双启动口，每 3 秒随机切换一条头目规则。

### 7.3 台面主题

樱花台 / 霓虹台 / 黄金台 / 深海台，按台序轮换；头目台使用固定主题偏移以示区别，并在待机时显示红色"头目 · 规则"告示牌。

---

## 8. 局外成长（Meta）

**原则：局外只解锁"可能性"，不解锁"数值"**（公平、可分享种子）。

| 系统 | Demo | 完整版 |
|---|---|---|
| 台主（起始角色） | 阿铁（12 钢珠）/ 火花（到达第 2 层解锁：9 钢 3 火 + 鞭炮串）/ 金喵（到达第 4 层：10 钢 2 金 + 招财猫 + $8） | +幽幽（幽灵流）、七七（大当流）、铁塔（重珠流），共 6 位 |
| 图鉴 | 珠子 / 护符（买过即发现） | +钉子、头目、台面主题；集齐奖励头像框 |
| 纪录 | 最佳层数、最高单发、通关次数 | +单局最高连击、最多大当 |
| 难度星 | — | 通关后解锁 ★1–★8：目标 +15%/级、商店 -1 格、头目双规则… |
| 每日挑战 | — | 全服同种子 + 固定台主，排行榜比单发最高 |
| 成就 | — | 30 个（"一发入魂""777 连庄""200 颗同屏"…） |

---

## 9. 数值体系

### 9.1 核心参数（`scripts/Game/Config.lua`）

| 参数 | 值 | 说明 |
|---|---|---|
| 重力 | 760 BU/s² | 轻羽 ×0.75，逆风 ×1.4 |
| 子步 | 4 | 限速 980 BU/s 防穿钉 |
| 撞钉弹性 / 偏转 | 0.52 / ±0.10 rad | |
| 弹匣 / 发射 | 10 / 3 | |
| 大当率 / 777 占比 / 听牌落空 | 16% / 25% / 32% | |
| FEVER | 7s（777 10s），珠雨 10（18），钉分 ×3 | |

### 9.2 模拟校准（`tests/sim_balance.lua`，贪心 AI，100 局）

| 层 | 小台目标 | 单发 p25 | 单发中位 | 单发 p75 | 止步于此 |
|---|---|---|---|---|---|
| 1 | 11,000 | 15,742 | 23,610 | 36,700 | 0 |
| 2 | 30,000 | 32,718 | 54,831 | 94,256 | 7 |
| 3 | 75,000 | 72,267 | 12.5 万 | 22.4 万 | 5 |
| 4 | 190,000 | 12.1 万 | 18.9 万 | 36.8 万 | 16 |
| 5 | 380,000 | 20.4 万 | 33.4 万 | 59.5 万 | 13 |
| 6 | 800,000 | 31.9 万 | 53.4 万 | 107.5 万 | 20 |
| 7 | 1,800,000 | 53.7 万 | 88.4 万 | 170.9 万 | 17 |
| 8 | 4,000,000 | 91.3 万 | 153.2 万 | 329.2 万 | 22（含 12 次通关） |

- 单台平均时长 **43 秒**（含 FEVER）。
- 贪心 AI 通关率 **12%**：人类玩家有流派意识后预期 30–50%（与小丑牌白注相近），后续由难度星拉开上限。
- **第 1 层 100 局 0 次失败**，满足"前 3 关基本不会失败"。

### 9.3 调参守则

1. 改任何数值后跑 `lua5.4 tests/sim_balance.lua 100`，对照上表：第 1 层止步 ≤ 2/100；贪心 AI 通关 3%–15%。
2. **乘法倍率要稀缺**：每发可触发的 ×倍率来源 ≤ 3 个（紫钉、777、护符）。早期版本把中央口袋设成"每颗珠 ×2"，结果单发 1900 亿 —— 已改为 +3。
3. 新护符若是"每颗珠/每次命中 ×N"，必须加"每发一次"限制（参考连击鬼）。
4. **改钉阵 / 出射 / 物理参数后必须跑 `tests/test_all.lua`**：其中「局内落点左右均衡且无卡珠刷分」会检查 4 种钉阵的左右比（40%–60%）与单珠命中上限（< 300）。历史上出现过两次卡珠刷分（墙边补钉夹缝 7159 次、命钉夹缝 300+ 次），都会让数值模拟严重失真。

---

## 10. UI / UX

### 10.1 页面与弹窗清单（Demo 全部已实现）

| 名称 | 类型 | 内容 |
|---|---|---|
| 标题页 | 页面 | 动态 Logo、选台主（3 张大立绘卡）、图鉴 / 开局 / 继续、最佳纪录 |
| 局内页 | 页面 | 顶栏（设置·关卡名·金币）、分数板、弹珠台、护符栏、底栏（珠袋·发射灯·大力干!·倍速） |
| 商店页 | 页面 | 顶栏、下一台预告、3×2 货架网格、固定高度详情区、护符栏、底栏（珠袋·刷新·出发） |
| 过关 | 弹窗 | 奖励明细 + 合计金币，"去商店" |
| 结局 | 弹窗 | 到达层数 / 最高单发 / 大当次数 / 最高连击，"回主页"/"再来" |
| 护符详情 | 弹窗 | 左大图 + 右名称说明，"卖出 $x"/"知道了" |
| 珠袋 | 弹窗 | 3×3 珠子网格（数量角标）+ 固定详情 |
| 设置 | 弹窗 | 音乐 / 音效开关、本地与云端保存时间（失败红字）、保存游戏、放弃本局 |
| 放弃确认 | 弹窗 | 不可逆操作二次确认 |
| 图鉴 | 弹窗 | 珠子/护符页签，4 列网格固定 16 格（页签切换 0 抖动） |
| 云存档读取失败 | 弹窗 | "重试读取"/"开始新档"，点遮罩不关闭 |

### 10.2 局内页线框（390 × 844 基准）

```
┌──────────────────────────────────────┐
│[⚙] 1-3 头目台·铁壁          [$ 12]   │← 顶栏 44，右侧 112px 留给平台胶囊
├──────────────────────────────────────┤
│ 目标 1.2万      ┌────────┐ ┌────────┐│← 分数板 64（预计过关时着火）
│ ▓▓▓▓▓░░░        │  1,234 │×│   56   ││
│ 8,400           └────────┘ └────────┘│
├──────────────────────────────────────┤
│                                      │
│          弹 珠 台（等比铺满）          │← flexGrow 1，盘面 360×640 等比缩放居中
│                                      │
├──────────────────────────────────────┤
│ [护符][护符][护符][ ··· ][ ··· ]     │← 护符栏 48，点开看详情/卖出
├──────────────────────────────────────┤
│[珠袋12] ●●○  [   大 力 干 !   ] [×1] │← 底栏 60，拇指热区
└──────────────────────────────────────┘
```

### 10.3 规范落实（对应 minigame-ui-spec）

- 控件树一次创建；状态变化只 `SetText / SetStyle / SetVisible`，并做脏检查（`shown` 缓存）。
- 所有多子容器显式 `flexDirection`；按钮组横排、次左主右；单主按钮居中 50–58% 宽。
- 网格格子只放「大图（≥60%）+ 短名 + 1 个数字」，详情走固定高度详情区（头部 + ScrollView + 动作栏三段隔离）。
- 弹窗：卡体阻止冒泡、遮罩 Alpha 120（≈47%）、固定高度、切页签 0 抖动；花费/不可逆弹窗点遮罩不关。
- 顶栏右侧 112px 避让平台胶囊；高频操作全部在底部 40%。
- 防连点：发射、购买点击后立即 `SetDisabled(true)`。
- 大数字统一紧凑格式；所有按钮 ≤ 4 字（"大力干!"为品牌口号例外，单独一行大按钮）。

---

## 11. 美术方案与贴图替换提示词

### 11.1 Style Bible（所有提示词共用）

| 维度 | 规范 |
|---|---|
| 画风 | 日式霓虹街机 × 和风祭典 × 糖果玩具质感；2.5D Q 版半厚涂，赛璐璐硬高光 |
| 外描边 | 深紫 `#2A1240`，3–4px 等宽描边，小尺寸依然轮廓清晰 |
| 主色 | 霓虹品红 `#FF4FA3`、电光青 `#3FD8FF` |
| 辅色 | 祭典金 `#FFC23C`、深夜紫 `#1A0B2E` |
| 语义色 | 珠分蓝 `#46AAFF`、倍率红 `#FF4658`、乘倍紫 `#C86EFF`、金币金 `#FFC83C`、增益绿 `#5AE682` |
| 光照 | 左上主光 + 强烈霓虹环境反光；金属珠镜面高光（左上椭圆白斑） |
| 质感 | 珠子：玻璃 / 抛光金属；钉子：黄铜；液晶：扫描线 + 发光 |
| 参考图 | **以 Demo 程序化画面为构图与配色参考**（截取局内页、商店页），新贴图须与程序化版本"形状一致、更精致"，确保替换前后玩家认知不变 |
| 禁止 | 写实赌场、真实老虎机品牌、现金/筹码实物、文字与数字（UI 文本由程序绘制） |

### 11.2 贴图替换机制（程序已就绪）

`scripts/Render/Art.lua` 在绘制每个图标前会查找 `Textures/<目录>/<id>.png`（即仓库 `assets/Textures/...`），存在即用贴图，缺失自动回退程序化绘制。**切好图放进对应路径即可生效，无需改代码。**

| key | 路径约定 | 数量 |
|---|---|---|
| `ball:<id>` | `assets/Textures/balls/<id>.png` | 9 |
| `charm:<id>` | `assets/Textures/charms/<id>.png` | 16（+2 规划） |
| `mod:<id>` | `assets/Textures/mods/<id>.png` | 8 |
| `peg:<type>` | `assets/Textures/pegs/<type>.png` | 6 特殊钉 |
| `slot:<symbol>` | `assets/Textures/slots/<symbol>.png` | 5 |
| `portrait:<key>` | `assets/Textures/portraits/<key>.png` | 3（+1 规划） |
| `boss:<id>` | `assets/Textures/bosses/<id>.png` | 7（+2 规划，接入待做） |

切图流程：生成 1:1 `1024×1024`（或 3:2 `1536×1024`）合图 → 按行列等分 → 去白底转透明 PNG → 裁到 `256×256` → 按映射表命名放入路径。

### 11.3 宣发三件套

#### ① 1:1 九宫格游戏头像

**中文提示词**
```
游戏图标九宫格设计稿，1:1 正方形画布，严格 3×3 网格排列 9 个独立方形游戏图标，主题为"弹珠物语"——日式霓虹弹珠台 Roguelike。
统一画风：日式霓虹街机 × 和风祭典 × 糖果玩具质感，2.5D Q版半厚涂，赛璐璐硬高光，深紫色(#2A1240)粗外描边，霓虹品红(#FF4FA3)与电光青(#3FD8FF)为主色，祭典金(#FFC23C)点缀，高饱和高对比。
每格主体放大居中，占单格 70%~78%，轮廓清晰，缩小到 48px 仍一眼可辨，每格背景为不同纯色圆角方块以区分。
第1行：①闪亮银色钢珠戴白色头带、自信笑脸，背景品红；②金色招财猫高举一颗发光弹珠，背景深紫；③爆炸中的火焰弹珠拖着火星尾迹，背景橙红。
第2行：④三轴老虎机显示三个红色"7"形状（只有图形不要文字）喷出金币，背景电光青；⑤弹珠台俯视：钉阵中数十颗彩色弹珠倾泻而下，背景夜空蓝；⑥Q版烟火师少女，火焰发髻，手托火珠，背景樱花粉。
第3行：⑦彩虹弹珠被紫色星形钉击中迸发光环，背景紫色；⑧红灯笼与鞭炮串交叉，火花四溅，背景金色；⑨大号"FEVER"能量球——金色光球外圈环绕弹珠，背景红金渐变。
无任何文字、字母、数字、水印、边框乱码。
```
**English prompt**
```
A 3x3 grid sheet of 9 separate square mobile game app icons on a 1:1 canvas, theme "Marble Story" — a Japanese neon pachinko roguelike.
Unified style: Japanese neon arcade x festival matsuri x candy-toy material, 2.5D chibi semi-painterly, crisp cel-shaded highlights, thick dark purple (#2A1240) outline, main colors neon magenta (#FF4FA3) and electric cyan (#3FD8FF), festival gold (#FFC23C) accents, high saturation, high contrast.
Each icon's subject is centered and large, filling 70-78% of its cell, bold silhouette readable at 48px, each cell on a different solid-color rounded-square background.
Row 1: (1) shiny silver steel ball wearing a white headband with a confident grin, magenta bg; (2) golden lucky cat raising a glowing marble, deep purple bg; (3) exploding fire marble with spark trail, orange-red bg.
Row 2: (4) three-reel slot machine showing three red seven shapes (pure graphics, no text) spewing gold coins, cyan bg; (5) top-down pachinko board with dozens of colorful marbles cascading through pins, night-blue bg; (6) chibi firework girl with flame hair bun holding a fire marble, sakura-pink bg.
Row 3: (7) rainbow marble hitting a purple star pin with a burst ring, purple bg; (8) red paper lantern crossed with a firecracker string, sparks flying, gold bg; (9) giant golden FEVER energy orb ringed by marbles, red-to-gold gradient bg.
No text, no letters, no numbers, no watermark, no garbled borders.
```
**9 格创意分工**

| 格 | 主体 | 用途建议 |
|---|---|---|
| 1 | 头带钢珠（主角化身） | **主图标首选** |
| 2 | 招财猫 + 弹珠 | 节日/运营活动图标 |
| 3 | 火焰爆炸珠 | 爆破流主题 |
| 4 | 777 老虎机 | 大当/FEVER 卖点 |
| 5 | 弹珠倾泻俯视 | 玩法直给型 |
| 6 | 烟火师少女 | 角色向用户 |
| 7 | 彩虹珠撞紫钉 | 倍率爆分卖点 |
| 8 | 灯笼 + 鞭炮 | 和风祭典氛围 |
| 9 | FEVER 能量球 | 买量素材 A/B 测试 |

#### ② 16:9 游戏宣传图（Key Art）

**中文提示词**
```
16:9 横版游戏主视觉 Key Art，日式霓虹弹珠台 Roguelike《弹珠物语》。
画面定格在"大当 FEVER"爆发的瞬间：
前景（画面右下）：Q版烟火师少女与头带钢珠少年一起跃起，举手欢呼，身前一颗巨大的金色弹珠反射霓虹光，三四颗火焰弹珠擦着镜头飞过，带运动模糊与火星。
中景（画面中央偏右）：一台竖立的华丽弹珠台，圆弧顶部霓虹灯管品红-青色流动，中央液晶屏三轴老虎机停在三个红色"7"图形（纯图形无文字），钉阵中数十颗彩色弹珠倾泻、金钉炸开金色光环、紫色星形钉迸发紫光、炸弹钉爆炸形成连锁火球，底部口袋喷出光柱。
远景：夜晚的和风祭典街道，灯笼串、樱花飘落、霓虹招牌虚化成光斑，天空有金色珠雨从上而下。
构图：主体集中在右侧 2/3，**画面左侧 1/3 留出干净的深紫夜空与柔和光斑作为标题安全区**，不放任何主体。
风格：日式霓虹街机 × 和风祭典 × 糖果玩具质感，2.5D 半厚涂，赛璐璐硬高光，深紫粗描边，品红/电光青/祭典金配色，强烈体积光与辉光，电影级景深，8K 细节。
no text, no logo, no letters, no numbers, no watermark.
```
**English prompt**
```
16:9 key art for a Japanese neon pachinko roguelike "Marble Story", frozen at the instant of a jackpot FEVER explosion.
Foreground (lower right): a chibi firework girl and a headband steel-ball boy leaping and cheering, a giant golden marble in front of them reflecting neon light, three or four fire marbles flying past the camera with motion blur and sparks.
Midground (center right): an ornate upright pachinko machine, arched top with flowing magenta-cyan neon tubes, central LCD slot showing three red seven shapes (pure graphics, no text), dozens of colorful marbles cascading through the pin field, golden pins bursting into gold rings, purple star pins flashing, bomb pins chaining into fireballs, light pillars shooting from the bottom pockets.
Background: a night-time Japanese festival street, lantern strings, falling sakura petals, neon signs blurred into bokeh, golden marble rain falling from the sky.
Composition: subjects concentrated in the right two-thirds; keep the left third as a clean dark-purple night sky with soft bokeh as a title safe area, no subjects there.
Style: Japanese neon arcade x festival matsuri x candy-toy material, 2.5D semi-painterly, crisp cel highlights, thick dark purple outline, magenta/electric cyan/festival gold palette, strong volumetric light and bloom, cinematic depth of field, 8K detail.
no text, no logo, no letters, no numbers, no watermark.
```
**标题安全区建议**：左侧 1/3（x 0–33%，y 15%–75%）放 Logo「弹珠物语」+ Slogan「局外运筹，局内交给天意」；右上角 10% 内可放平台角标；底部 12% 留给商店截图拼接条。

#### ③ 16:9 · 15 秒宣传视频

**整段 15 秒统一英文提示词**
```
15-second 16:9 vertical-to-horizontal game trailer for "Marble Story", a Japanese neon pachinko roguelike, chibi 2.5D candy-neon style with thick purple outlines and magenta/cyan/gold palette.
0-3s: extreme close-up of a giant glowing "launch" button being slammed by a chibi hand, screen shakes, a stream of silver marbles shoots up a curved rail and arcs over the top of an ornate neon pachinko board.
3-9s: camera tracks down the pin field as marbles bounce wildly, pins flash white, golden pins burst into coins, a fire marble triggers a chain of bomb pins exploding across the board, numbers pop and the score multiplies, a marble drops into the center start pocket and the LCD slot reels spin, two red sevens stop and the third reel slows down dramatically with the frame flashing red and gold.
9-13s: the third seven lands — full-screen gold flash, slow motion, the board turns gold, rainbow pins pulse, a torrential rain of marbles pours from the top, hundreds of marbles on screen, a giant score counter rockets from thousands to hundreds of millions while a flame bursts over the score bar.
13-15s: freeze on hero shot of the firework girl and the headband steel-ball boy cheering in front of the glowing machine, festival lanterns and sakura in the background, clean space on the left for the logo.
Fast rhythmic editing synced to taiko drums and arcade jingles, energetic, high saturation, bloom, no on-screen text.
```

**4 段逐秒分镜表**

| 时段 | 画面（中文提示词） | English prompt | 运镜 | 音效 | 后期花字 |
|---|---|---|---|---|---|
| 0–3s 强钩子 | Q版手掌狠狠拍下发光的「大力干」大按钮，屏幕震动，一串银色钢珠沿弯轨飞速上行、越过霓虹弹珠台圆弧顶 | A chibi hand slams a giant glowing launch button, screen shakes, a stream of silver marbles races up a curved rail and arcs over the neon pachinko arch | 特写→快速上摇 | 按钮"咚"+钢珠连发"哒哒哒" | 「只需要按一下」 |
| 3–9s 玩法递进 | 镜头沿钉阵下移：钉子闪白、金钉爆金币、火珠引爆炸弹钉连锁、数字飘起翻倍；珠子掉入中央启动口，老虎机转动，两个红7停下，第三轴减速、边框红金闪烁 | Camera tracks down the pin field, pins flash, gold pins burst coins, a fire marble chains bomb pins, numbers pop and multiply, a marble drops into the start pocket, slot reels spin, two red sevens stop, the third reel slows with red-gold flashing frame | 下摇 + 推近液晶 | 叮叮连击、爆炸、转轮"哗啦"、心跳鼓点 | 「连锁！」「就差一个!」 |
| 9–13s 高潮爆发 | 第三个7落定，全屏金闪慢动作，盘面变金、钉子彩虹脉动，顶部珠雨倾盆，数百颗珠满屏，分数从几千飙升到几亿，分数板喷火 | The third seven lands, full-screen gold flash in slow motion, board turns gold, rainbow pins pulse, torrential marble rain, hundreds of marbles, score rockets from thousands to hundreds of millions, flames burst over the score bar | 慢动作 → 急速拉远全景 | 大当音效 + 太鼓连打 + 金币瀑布 | 「FEVER!!」「×1000000」 |
| 13–15s 定帧收尾 | 烟火师少女与头带钢珠少年在发光弹珠台前欢呼定格，背景祭典灯笼与樱花，左侧留 Logo 位 | Freeze on the firework girl and headband steel-ball boy cheering before the glowing machine, festival lanterns and sakura behind, clean left space for logo | 定帧 + 轻微推近 | 收束和弦 | Logo「弹珠物语」+「TapTap 搜索」 |

### 11.4 局内小件合图提示词（全部按网格打包，0 单张散出）

**所有合图通用强制条款**（每张提示词末尾已附）：
```
严格按行列定格摆放，从第一行左到右逐一绘制指定主体，不得乱排或漏画；每个主体居中独立、占单格约 72%–78%，四周留足均匀白边，彼此不重叠、不跨格；
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```

#### 合图 A · 珠子（9 件 → 1:1 3×3）

**中文**
```
1:1 正方形画布，3×3 规整九宫格排列 9 颗游戏弹珠道具图标，日式霓虹街机 × 糖果玩具质感，2.5D 半厚涂，赛璐璐硬高光，深紫色(#2A1240) 3px 外描边，球体左上椭圆白色高光，玻璃/金属镜面反射。
第1行：①抛光银色钢珠，冷色金属反射；②金色金珠，表面浮雕铜钱纹，暖金辉光；③火珠，橙红熔岩球体包裹跳动火焰。
第2行：④分裂珠，青绿色球体有十字裂缝透出白光；⑤重珠，深灰铁球表面一圈六颗铆钉，体积感厚重；⑥幽灵珠，半透明淡紫色球体内有两只呆萌小眼睛，周围轻雾。
第3行：⑦彩虹珠，球面流动的七彩渐变如肥皂泡；⑧弹力珠，亮粉色橡胶球带一道白色弧形条纹；⑨幸运珠，翠绿球体中央嵌四叶草图案，淡绿辉光。
严格按行列定格摆放，从第一行左到右逐一绘制指定主体，不得乱排或漏画；每个主体居中独立、占单格约 72%–78%，四周留足均匀白边，彼此不重叠、不跨格；
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
**English**
```
1:1 square canvas, a clean 3x3 grid of 9 game marble item icons, Japanese neon arcade x candy-toy material, 2.5D semi-painterly, crisp cel highlights, 3px dark purple (#2A1240) outline, elliptical white highlight at upper-left of each sphere, glass/metal specular reflections.
Row 1: (1) polished silver steel ball with cool metallic reflections; (2) golden marble embossed with an ancient coin pattern, warm gold glow; (3) fire marble, orange-red molten sphere wrapped in flickering flames.
Row 2: (4) split marble, teal sphere with a cross-shaped crack leaking white light; (5) heavy marble, dark grey iron ball with a ring of six rivets, massive feel; (6) ghost marble, translucent lavender sphere with two cute derpy eyes inside, light mist around.
Row 3: (7) prism marble, flowing rainbow gradient like a soap bubble; (8) rubber marble, bright pink rubber ball with one white curved stripe; (9) lucky marble, emerald sphere with an inlaid four-leaf clover, soft green glow.
Strictly place by rows and columns, drawing each specified subject from left to right starting at row 1, no random arrangement or omissions; each subject centered and isolated, filling about 72-78% of its cell with even white margins, no overlap, no crossing cells;
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
| 格位 | 文件 |
|---|---|
| 第1行第1格 | `assets/Textures/balls/steel.png` |
| 第1行第2格 | `assets/Textures/balls/gold.png` |
| 第1行第3格 | `assets/Textures/balls/fire.png` |
| 第2行第1格 | `assets/Textures/balls/split.png` |
| 第2行第2格 | `assets/Textures/balls/heavy.png` |
| 第2行第3格 | `assets/Textures/balls/ghost.png` |
| 第3行第1格 | `assets/Textures/balls/prism.png` |
| 第3行第2格 | `assets/Textures/balls/rubber.png` |
| 第3行第3格 | `assets/Textures/balls/lucky.png` |

#### 合图 B · 护符 第 1 盘（9 件 → 1:1 3×3）

**中文**
```
1:1 正方形画布，3×3 规整九宫格排列 9 个护符道具图标（和风祭典小物件），日式霓虹街机 × 糖果玩具质感，2.5D 半厚涂，赛璐璐硬高光，深紫色(#2A1240) 3px 外描边，高饱和。
第1行：①红灯笼，圆鼓红纸灯笼金色上下盖、竖骨线、金色流苏，内透暖光；②招财猫，白色招财猫高举右爪、红项圈金铃铛、眯眼笑；③鞭炮串，三根红色爆竹金色腰带绑在一起，引线末端火花星。
第2行：④七彩风车，四片红黄蓝绿风车叶插在木棍上；⑤确变之魂，蓝色水滴形魂火，内白外蓝渐变，两只小黑眼；⑥狂热太鼓，木纹太鼓侧视，米白鼓面、红色鼓心圆环，两根鼓槌交叉。
第3行：⑦千手观音，金色光环中心一颗金珠，十二只手臂放射状各托一颗银珠；⑧弹簧鞋，青色螺旋弹簧下接红色鞋底，顶端一颗蓝色弹珠；⑨轻羽，白到浅蓝渐变的羽毛，斜向飘动，羽轴清晰。
严格按行列定格摆放，从第一行左到右逐一绘制指定主体，不得乱排或漏画；每个主体居中独立、占单格约 72%–78%，四周留足均匀白边，彼此不重叠、不跨格；
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
**English**
```
1:1 square canvas, clean 3x3 grid of 9 charm item icons (Japanese festival trinkets), Japanese neon arcade x candy-toy material, 2.5D semi-painterly, crisp cel highlights, 3px dark purple (#2A1240) outline, high saturation.
Row 1: (1) red paper lantern, round with gold top and bottom caps, vertical ribs, gold tassel, warm inner glow; (2) white lucky cat raising its right paw, red collar with gold bell, smiling closed eyes; (3) firecracker bundle, three red crackers tied with gold bands, fuse tip with a spark star.
Row 2: (4) pinwheel with red, yellow, blue and green blades on a wooden stick; (5) blue teardrop spirit flame, white core to blue edge gradient, two small black eyes; (6) taiko drum side view, wood grain body, cream drumhead with red ring, two crossed drumsticks.
Row 3: (7) thousand-armed guardian emblem: a golden halo with a gold marble at center and twelve radiating arms each holding a silver marble; (8) spring shoe: cyan coil spring on a red sole with a blue marble on top; (9) light feather with white to pale blue gradient, floating diagonally, clear quill.
Strictly place by rows and columns, drawing each specified subject from left to right starting at row 1, no random arrangement or omissions; each subject centered and isolated, filling about 72-78% of its cell with even white margins, no overlap, no crossing cells;
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
| 格位 | 文件 |
|---|---|
| 第1行第1格 | `assets/Textures/charms/lantern.png` |
| 第1行第2格 | `assets/Textures/charms/cat.png` |
| 第1行第3格 | `assets/Textures/charms/cracker.png` |
| 第2行第1格 | `assets/Textures/charms/pinwheel.png` |
| 第2行第2格 | `assets/Textures/charms/soul.png` |
| 第2行第3格 | `assets/Textures/charms/drum.png` |
| 第3行第1格 | `assets/Textures/charms/kannon.png` |
| 第3行第2格 | `assets/Textures/charms/spring.png` |
| 第3行第3格 | `assets/Textures/charms/feather.png` |

#### 合图 C · 护符 第 2 盘（7 件 + 2 件规划护符 → 1:1 3×3，0 废格）

**中文**
```
1:1 正方形画布，3×3 规整九宫格排列 9 个护符道具图标（和风祭典小物件），日式霓虹街机 × 糖果玩具质感，2.5D 半厚涂，赛璐璐硬高光，深紫色(#2A1240) 3px 外描边，高饱和。
第1行：①守财奴，鼓鼓的棕色布钱袋，红色束口绳，袋身金色元宝纹，旁边一枚金币；②连击鬼，一道明黄色闪电，闪电旁一个红色小鬼面具；③黄金律，一块闪亮的梯形金锭，表面星光反射。
第2行：④背水一战，红白同心圆靶心，中心插着一颗冒火的弹珠；⑤棱镜，半透明三角棱镜，一侧射出六色彩虹光束；⑥回旋镖，橙色木质回旋镖带旋转动态弧线。
第3行：⑦天降甘霖，一朵白色云朵下方落下五颗银色弹珠；⑧磁铁，红蓝 U 形马蹄磁铁吸着两颗金色弹珠；⑨雷神，金色雷鼓环绕一圈小鼓，中央一道蓝白闪电。
严格按行列定格摆放，从第一行左到右逐一绘制指定主体，不得乱排或漏画；每个主体居中独立、占单格约 72%–78%，四周留足均匀白边，彼此不重叠、不跨格；
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
**English**
```
1:1 square canvas, clean 3x3 grid of 9 charm item icons (Japanese festival trinkets), Japanese neon arcade x candy-toy material, 2.5D semi-painterly, crisp cel highlights, 3px dark purple (#2A1240) outline, high saturation.
Row 1: (1) bulging brown cloth money pouch with red drawstring and gold ingot pattern, one gold coin beside it; (2) bright yellow lightning bolt with a small red oni mask beside it; (3) shiny trapezoid gold ingot with star glints.
Row 2: (4) red and white concentric bullseye target with a flaming marble stuck in the center; (5) translucent triangular prism emitting a six-color rainbow beam from one side; (6) orange wooden boomerang with spinning motion arcs.
Row 3: (7) white fluffy cloud with five silver marbles falling below; (8) red and blue U-shaped horseshoe magnet attracting two golden marbles; (9) thunder god drum ring: golden ring of small drums around a blue-white lightning bolt.
Strictly place by rows and columns, drawing each specified subject from left to right starting at row 1, no random arrangement or omissions; each subject centered and isolated, filling about 72-78% of its cell with even white margins, no overlap, no crossing cells;
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
| 格位 | 文件 |
|---|---|
| 第1行第1格 | `assets/Textures/charms/miser.png` |
| 第1行第2格 | `assets/Textures/charms/combo.png` |
| 第1行第3格 | `assets/Textures/charms/goldrule.png` |
| 第2行第1格 | `assets/Textures/charms/lastshot.png` |
| 第2行第2格 | `assets/Textures/charms/prismlens.png` |
| 第2行第3格 | `assets/Textures/charms/boomer.png` |
| 第3行第1格 | `assets/Textures/charms/rain.png` |
| 第3行第2格 | `assets/Textures/charms/magnet.png`（规划护符"磁铁"） |
| 第3行第3格 | `assets/Textures/charms/thunder.png`（规划护符"雷神"） |

#### 合图 D · 改造与服务（8 件 + UI 金币 → 1:1 3×3）

**中文**
```
1:1 正方形画布，3×3 规整九宫格排列 9 个弹珠台改造道具图标，日式霓虹街机 × 糖果玩具质感，2.5D 半厚涂，赛璐璐硬高光，深紫色(#2A1240) 3px 外描边。
第1行：①弹匣扩容，竖直透明胶囊弹匣内装五颗银色弹珠，侧面绿色向上箭头；②加一发，一颗银色弹珠上方金色大三角箭头，尾部冲击线；③红钉强化，一颗发红光的黄铜钉帽，周围红色光点。
第2行：④金钉强化，一颗发金光的黄铜钉帽，周围金币火花；⑤紫钉强化，紫色四角星形钉，迸发紫色光芒；⑥炸弹钉强化，黑色圆形炸弹钉，导火索火花星。
第3行：⑦分裂钉强化，青绿色钉帽中间一道横线，两侧各弹出一颗小珠；⑧熔掉一颗，银色弹珠被红色大叉覆盖，底部橙色熔融火光；⑨金币，正面浮雕钱袋纹的圆形金币，厚边缘。
严格按行列定格摆放，从第一行左到右逐一绘制指定主体，不得乱排或漏画；每个主体居中独立、占单格约 72%–78%，四周留足均匀白边，彼此不重叠、不跨格；
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
**English**
```
1:1 square canvas, clean 3x3 grid of 9 pachinko machine upgrade item icons, Japanese neon arcade x candy-toy material, 2.5D semi-painterly, crisp cel highlights, 3px dark purple (#2A1240) outline.
Row 1: (1) vertical transparent capsule magazine holding five silver marbles with a green upward arrow on its side; (2) a silver marble under a big golden triangle arrow with impact lines; (3) brass pin head glowing red with red light motes.
Row 2: (4) brass pin head glowing gold with coin sparks; (5) purple four-pointed star pin bursting with purple light; (6) black round bomb pin with a sparking fuse.
Row 3: (7) teal pin head with a horizontal line, a small marble popping out on each side; (8) silver marble covered by a big red X with orange molten glow beneath; (9) round gold coin with an embossed money-pouch emblem and thick rim.
Strictly place by rows and columns, drawing each specified subject from left to right starting at row 1, no random arrangement or omissions; each subject centered and isolated, filling about 72-78% of its cell with even white margins, no overlap, no crossing cells;
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
| 格位 | 文件 |
|---|---|
| 第1行第1格 | `assets/Textures/mods/mag.png` |
| 第1行第2格 | `assets/Textures/mods/launch.png` |
| 第1行第3格 | `assets/Textures/mods/redpeg.png` |
| 第2行第1格 | `assets/Textures/mods/goldpeg.png` |
| 第2行第2格 | `assets/Textures/mods/purppeg.png` |
| 第2行第3格 | `assets/Textures/mods/bombpeg.png` |
| 第3行第1格 | `assets/Textures/mods/splitpeg.png` |
| 第3行第2格 | `assets/Textures/mods/remove.png` |
| 第3行第3格 | `assets/Textures/ui/coin.png`（UI 金币，接入待做） |

#### 合图 E · 钉子与盘面小件（9 件 → 1:1 3×3）

**中文**
```
1:1 正方形画布，3×3 规整九宫格排列 9 个弹珠台盘面小部件，俯视略带 3/4 角度，日式霓虹街机 × 糖果玩具质感，2.5D 半厚涂，赛璐璐硬高光，深紫色(#2A1240) 3px 外描边。
第1行：①普通钉，抛光黄铜圆钉帽，顶部白色高光；②金钉，金色发光钉帽外圈暖光；③红钉，红宝石质感钉帽外圈红光。
第2行：④紫钉，紫色四角星钉帽，中心白点；⑤炸弹钉，黑色小炸弹钉帽，右上导火索火花；⑥分裂钉，青绿色钉帽中间白色横纹。
第3行：⑦弹力柱，蓝色发光圆柱头部带白色光环；⑧启动口，金色U形小杯口，两侧黄铜沿钉，内部发光；⑨封锁锁头，灰紫色挂锁，锁孔深色。
严格按行列定格摆放，从第一行左到右逐一绘制指定主体，不得乱排或漏画；每个主体居中独立、占单格约 72%–78%，四周留足均匀白边，彼此不重叠、不跨格；
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
**English**
```
1:1 square canvas, clean 3x3 grid of 9 pachinko board parts, top-down with slight 3/4 angle, Japanese neon arcade x candy-toy material, 2.5D semi-painterly, crisp cel highlights, 3px dark purple (#2A1240) outline.
Row 1: (1) polished brass round pin head with white top highlight; (2) glowing gold pin head with warm halo; (3) ruby-red pin head with red halo.
Row 2: (4) purple four-pointed star pin head with a white center dot; (5) small black bomb pin head with a sparking fuse at upper right; (6) teal pin head with a white horizontal stripe.
Row 3: (7) glowing blue bumper post with a white light ring on top; (8) golden U-shaped start pocket cup with brass rim pins on both sides, glowing inside; (9) grey-purple padlock with a dark keyhole.
Strictly place by rows and columns, drawing each specified subject from left to right starting at row 1, no random arrangement or omissions; each subject centered and isolated, filling about 72-78% of its cell with even white margins, no overlap, no crossing cells;
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
| 格位 | 文件 |
|---|---|
| 第1行第1格 | `assets/Textures/pegs/normal.png` |
| 第1行第2格 | `assets/Textures/pegs/gold.png` |
| 第1行第3格 | `assets/Textures/pegs/red.png` |
| 第2行第1格 | `assets/Textures/pegs/purple.png` |
| 第2行第2格 | `assets/Textures/pegs/bomb.png` |
| 第2行第3格 | `assets/Textures/pegs/split.png` |
| 第3行第1格 | `assets/Textures/pegs/bumper.png` |
| 第3行第2格 | `assets/Textures/ui/start_cup.png`（接入待做） |
| 第3行第3格 | `assets/Textures/ui/lock.png`（接入待做） |

#### 合图 F · 老虎机符号（6 件 → 3:2 横版 3×2）

**中文**
```
3:2 横版画布，3 列 × 2 行规整排列 6 个等大正方形格子的老虎机转轮符号，日式霓虹街机风，2.5D 半厚涂，赛璐璐硬高光，深紫色(#2A1240) 3px 外描边，高饱和。
第1行：①幸运七，红色粗体"7"形状的立体徽章（作为图形造型，金色描边，不要额外文字）；②金色五角星，内层浅黄高光星；③两颗相连的红樱桃，绿色细梗。
第2行：④金色铃铛，底部铃舌，暖金渐变；⑤蓝色发光弹珠；⑥保留灯，圆形琥珀色指示灯泡带金属底座，内部发光。
严格按行列定格摆放，从第一行左到右逐一绘制指定主体，不得乱排或漏画；每个主体居中独立、占单格约 72%–78%，四周留足均匀白边，彼此不重叠、不跨格；
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers (the seven is a graphic shape only).
```
**English**
```
3:2 landscape canvas, a 3-column by 2-row grid of 6 equal square cells containing slot machine reel symbols, Japanese neon arcade style, 2.5D semi-painterly, crisp cel highlights, 3px dark purple (#2A1240) outline, high saturation.
Row 1: (1) lucky seven: a bold red 3D "7" shaped badge with gold outline (as a graphic emblem, no other text); (2) golden five-pointed star with a pale yellow inner star highlight; (3) two connected red cherries with thin green stems.
Row 2: (4) golden bell with clapper, warm gold gradient; (5) glowing blue marble; (6) hold lamp: round amber indicator bulb on a metal base, glowing inside.
Strictly place by rows and columns, drawing each specified subject from left to right starting at row 1, no random arrangement or omissions; each subject centered and isolated, filling about 72-78% of its cell with even white margins, no overlap, no crossing cells;
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers (the seven is a graphic shape only).
```
| 格位 | 文件 |
|---|---|
| 第1行第1格 | `assets/Textures/slots/seven.png` |
| 第1行第2格 | `assets/Textures/slots/star.png` |
| 第1行第3格 | `assets/Textures/slots/cherry.png` |
| 第2行第1格 | `assets/Textures/slots/bell.png` |
| 第2行第2格 | `assets/Textures/slots/marble.png` |
| 第2行第3格 | `assets/Textures/ui/hold_lamp.png`（接入待做） |

#### 合图 G · 台主 Q 版头像（3 件 + 1 规划 → 1:1 2×2）

**中文**
```
1:1 正方形画布，2×2 规整四宫格排列 4 个 Q 版角色半身头像，二头身，日式霓虹街机 × 和风祭典，2.5D 半厚涂，赛璐璐硬高光，深紫色(#2A1240) 4px 外描边，大眼睛，表情鲜明。
第1行：①阿铁·钢珠少年，黑短发系白色头带（中间红点），蓝色上衣，手托一颗银色钢珠，自信咧嘴笑；②火花·烟火师，火焰形红橙发髻，红色和风短上衣，手托一颗燃烧的火珠，俏皮眨眼。
第2行：③金喵·招财喵，白色招财猫举右爪，红项圈金铃铛，抱着一枚大金币，眯眼笑；④幽幽·幽灵少女，淡紫色半透明长发，白色浴衣，身边漂浮一颗带小眼睛的幽灵珠，害羞微笑。
严格按行列定格摆放，从第一行左到右逐一绘制指定主体，不得乱排或漏画；每个主体居中独立、占单格约 72%–78%，四周留足均匀白边，彼此不重叠、不跨格；
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
**English**
```
1:1 square canvas, clean 2x2 grid of 4 chibi character bust portraits, two-head-tall proportions, Japanese neon arcade x festival matsuri, 2.5D semi-painterly, crisp cel highlights, 4px dark purple (#2A1240) outline, big eyes, vivid expressions.
Row 1: (1) Tie, the steel-ball boy: short black hair with a white headband (red dot in the middle), blue top, holding a silver steel marble, confident toothy grin; (2) Huo, the firework girl: flame-shaped red-orange hair bun, red Japanese short jacket, holding a burning fire marble, playful wink.
Row 2: (3) Miao, the lucky cat: white beckoning cat raising its right paw, red collar with gold bell, hugging a big gold coin, smiling closed eyes; (4) Youyou, the ghost girl: translucent lavender long hair, white yukata, a ghost marble with tiny eyes floating beside her, shy smile.
Strictly place by rows and columns, drawing each specified subject from left to right starting at row 1, no random arrangement or omissions; each subject centered and isolated, filling about 72-78% of its cell with even white margins, no overlap, no crossing cells;
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
| 格位 | 文件 |
|---|---|
| 第1行第1格 | `assets/Textures/portraits/tie.png` |
| 第1行第2格 | `assets/Textures/portraits/huo.png` |
| 第2行第1格 | `assets/Textures/portraits/miao.png` |
| 第2行第2格 | `assets/Textures/portraits/youyou.png`（规划台主） |

#### 合图 H · 头目徽章（7 件 + 2 规划 → 1:1 3×3）

**中文**
```
1:1 正方形画布，3×3 规整九宫格排列 9 个头目徽章图标，圆形徽章底座 + 中心图形，日式霓虹街机 × 和风妖怪，2.5D 半厚涂，赛璐璐硬高光，深紫色(#2A1240) 3px 外描边，暗红与紫色为主带霓虹描边。
第1行：①铁壁，灰色铁门紧闭的盾牌徽章；②吝啬鬼，抱着金币袋的绿色小鬼；③浓雾，灰白雾团中露出一只眼睛。
第2行：④逆风，蓝色狂风漩涡压向下方箭头；⑤钝钉，一颗弯折变钝的灰色钉子；⑥锁链，红色钉子被铁链缠绕上锁。
第3行：⑦窄门，两扇窄木门之间一道细缝；⑧镜像，对称的两面镜子映出反向弹珠；⑨弹珠之王，戴金冠的巨大弹珠，王座光环。
严格按行列定格摆放，从第一行左到右逐一绘制指定主体，不得乱排或漏画；每个主体居中独立、占单格约 72%–78%，四周留足均匀白边，彼此不重叠、不跨格；
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
**English**
```
1:1 square canvas, clean 3x3 grid of 9 boss emblem icons, round badge base with a central symbol, Japanese neon arcade x yokai, 2.5D semi-painterly, crisp cel highlights, 3px dark purple (#2A1240) outline, dark red and purple dominant with neon rims.
Row 1: (1) iron wall: shield badge with a shut grey iron gate; (2) miser: small green goblin hugging a coin sack; (3) fog: grey-white fog cloud with a single eye peeking out.
Row 2: (4) headwind: blue gale vortex pressing a downward arrow; (5) dull pin: a bent, blunted grey pin; (6) chains: a red pin wrapped in iron chains with a padlock.
Row 3: (7) narrow gate: two narrow wooden doors with a thin gap between; (8) mirror: two symmetric mirrors reflecting mirrored marbles; (9) marble king: a giant marble wearing a golden crown with a throne halo.
Strictly place by rows and columns, drawing each specified subject from left to right starting at row 1, no random arrangement or omissions; each subject centered and isolated, filling about 72-78% of its cell with even white margins, no overlap, no crossing cells;
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
| 格位 | 文件 |
|---|---|
| 第1行第1格 | `assets/Textures/bosses/wall.png` |
| 第1行第2格 | `assets/Textures/bosses/stingy.png` |
| 第1行第3格 | `assets/Textures/bosses/fog.png` |
| 第2行第1格 | `assets/Textures/bosses/storm.png` |
| 第2行第2格 | `assets/Textures/bosses/dull.png` |
| 第2行第3格 | `assets/Textures/bosses/lock.png` |
| 第3行第1格 | `assets/Textures/bosses/narrow.png` |
| 第3行第2格 | `assets/Textures/bosses/mirror.png`（规划） |
| 第3行第3格 | `assets/Textures/bosses/king.png`（规划终局头目） |

> 合计 **8 张合图覆盖 69 个小件**（9+9+9+9+9+6+4+9），按单张出图需要 69 次抽卡。

### 11.5 单张大图提示词（允许单张：全屏背景 / 复杂 UI 底框 / Logo）

#### 台面背景 ×4（9:16 竖版，路径 `assets/Textures/boards/<theme>.png`，接入待做）

通用前缀：`9:16 竖版弹珠台盘面背景图，纯背景无钉子无弹珠，中央上方预留圆角矩形液晶屏位置（暗色），顶部为半圆拱形霓虹灯管边框，下部 12% 区域为 7 格口袋底座，日式霓虹街机 × 和风祭典，2.5D 半厚涂，柔和光斑，低对比度以免干扰前景钉子，no text, no numbers, no watermark.`

| 主题 | 追加描述（中文） | English addition |
|---|---|---|
| 樱花台 `sakura` | 深紫红夜色，樱花枝从两侧伸入，花瓣飘落，粉色霓虹边框 | deep plum night, sakura branches reaching in from both sides, falling petals, pink neon frame |
| 霓虹台 `neon` | 深蓝赛博街巷，青色霓虹招牌光斑，雨后反光地面意象 | deep blue cyber alley, cyan neon sign bokeh, wet reflective street mood |
| 黄金台 `gold` | 暗金漆器纹理，金色祥云与鲤鱼纹样，琥珀辉光 | dark gold lacquer texture, golden auspicious clouds and koi motifs, amber glow |
| 深海台 `abyss` | 深青海底，水母与气泡光点，青绿霓虹边框 | deep teal undersea, jellyfish and bubble light dots, teal-green neon frame |

#### 标题 Logo（单张，透明底，`assets/Textures/ui/logo.png`）
```
游戏标题字标设计"弹珠物语"四个汉字，日式霓虹招牌 × 祭典灯笼字体，粗圆体带立体厚度，品红到金色渐变填充，深紫粗描边，外层电光青霓虹灯管发光，"珠"字的点画替换为一颗银色弹珠，字下方一行小号英文 MARBLE STORY，纯白背景，居中，无其他元素。
Game title logotype of the four Chinese characters "弹珠物语", Japanese neon sign x festival lantern lettering, chunky rounded 3D letters, magenta-to-gold gradient fill, thick dark purple outline, outer electric-cyan neon tube glow, the dot stroke of "珠" replaced by a silver marble, small "MARBLE STORY" line beneath, pure white background, centered, nothing else.
```
> Logo 是唯一允许出现文字的素材；若模型写错字，改用程序/设计软件排字，仅生成装饰底板。

#### UI 控件合图（替换当前默认蓝色按钮 / 纯色面板）

三张合图覆盖全部界面控件。底框类素材按**九宫格拉伸（9-slice）**设计：圆角方块 tile、四边等宽边框、中心大面积干净纯色，装饰只放在四角与边框内。生成 1:1 用 `1024×1024`，3:2 用 `1536×1024`，纯白底，切图时由程序去底并设置九宫格切线。

**合图 UI-A · 控件底框（9 件 → 1:1 3×3）**

中文：
```
1:1 正方形画布，3×3 规整九宫格排列 9 个手机游戏 UI 底框素材，用于九宫格拉伸（9-slice），正面平视无透视，日式霓虹街机 × 和风祭典 × 糖果玩具质感，2.5D 轻厚涂，赛璐璐硬高光，深紫色(#2A1240) 3px 外描边。
每个素材都是圆角方块 tile：四角装饰、四边等宽边框、中间大面积为干净的纯色或极简渐变（便于拉伸），装饰只放在四角与边框上，不得占用中心区域。
第1行：①主按钮：品红(#FF4FA3)到亮粉渐变，顶部一条白色高光带，底部加厚的深品红立体厚底，像糖果按键；②次按钮：深紫(#3A2466)渐变，淡紫细描边，底部加厚深紫厚底；③危险按钮：朱红(#FF4658)渐变，底部深红厚底。
第2行：④弹窗大框：深夜紫(#1A0B2E)面板，金色(#FFC23C)细双线边框，四角和风祥云金饰，底边加厚；⑤次级面板：比④更暗更简洁的深紫底板，淡紫细边，小圆角；⑥商品格子（普通）：深紫底，紫色细边，内侧微弱暗角。
第3行：⑦商品格子（选中）：同⑥但边框换成发光的金色粗描边并带外发光；⑧护符空槽：半透明黑紫底，虚线圆角内框；⑨胶囊底：金色描边的深色胶囊形 tile，用作金币/价签底。
严格按行列定格摆放，从第一行左到右逐一绘制指定主体，不得乱排或漏画；每个主体居中独立、占单格约 72%–78%，四周留足均匀白边，彼此不重叠、不跨格；
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
English：
```
1:1 square canvas, a clean 3x3 grid of 9 mobile game UI frame assets designed for 9-slice stretching, flat front view with no perspective, Japanese neon arcade x festival matsuri x candy-toy material, 2.5D light painterly, crisp cel highlights, 3px dark purple (#2A1240) outline.
Every asset is a rounded-square tile: decorated corners, equal-width borders on all four sides, and a large clean center of flat color or a very subtle gradient so it can stretch; decorations only on corners and borders, never in the center.
Row 1: (1) primary button: magenta (#FF4FA3) to bright pink gradient, white highlight band on top, thick deep-magenta 3D base at the bottom like a candy key; (2) secondary button: deep purple (#3A2466) gradient, thin lavender outline, thick dark purple base; (3) danger button: vermilion (#FF4658) gradient with a thick dark red base.
Row 2: (4) large dialog frame: midnight purple (#1A0B2E) panel, thin gold (#FFC23C) double-line border, golden auspicious-cloud ornaments on the four corners, thicker bottom edge; (5) secondary panel: darker and simpler purple plate with thin lavender border and small corner radius; (6) item card (normal): dark purple fill, thin purple border, faint inner vignette.
Row 3: (7) item card (selected): same as (6) but with a thick glowing gold border and outer glow; (8) empty charm slot: translucent black-purple fill with a dashed rounded inner frame; (9) pill base: dark capsule-shaped tile with gold outline, used behind coin counters and price tags.
Strictly place by rows and columns, drawing each specified subject from left to right starting at row 1, no random arrangement or omissions; each subject centered and isolated, filling about 72-78% of its cell with even white margins, no overlap, no crossing cells;
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```

| 格位 | 文件 | 用途 |
|---|---|---|
| 第1行第1格 | `assets/Textures/ui/btn_primary.png` | 开局 / 出发 / 购买 等主按钮 |
| 第1行第2格 | `assets/Textures/ui/btn_secondary.png` | 图鉴 / 珠袋 / 刷新 等次按钮 |
| 第1行第3格 | `assets/Textures/ui/btn_danger.png` | 卖出 / 放弃 |
| 第2行第1格 | `assets/Textures/ui/dialog.png` | 所有弹窗卡体 |
| 第2行第2格 | `assets/Textures/ui/panel.png` | 分数板、详情区、顶栏底 |
| 第2行第3格 | `assets/Textures/ui/card.png` | 商店 / 珠袋 / 图鉴格子 |
| 第3行第1格 | `assets/Textures/ui/card_selected.png` | 选中格子 |
| 第3行第2格 | `assets/Textures/ui/slot_empty.png` | 护符空槽 |
| 第3行第3格 | `assets/Textures/ui/pill.png` | 金币 / 价签胶囊 |

**合图 UI-B · HUD 小图标（9 件 → 1:1 3×3）**

中文：
```
1:1 正方形画布，3×3 规整九宫格排列 9 个手机游戏 HUD 按钮图标，日式霓虹街机 × 糖果玩具质感，2.5D 半厚涂，赛璐璐硬高光，深紫色(#2A1240) 3px 外描边，小尺寸（32px）依然清晰。
第1行：①设置：圆形深紫底座上一个银色齿轮；②关闭：圆形深紫底座上一个白色粗圆角叉号；③主页：圆形深紫底座上一座金色小房子。
第2行：④珠袋：棕色布袋口敞开，露出三颗银色弹珠；⑤倍速：两个并排向右的品红色粗箭头；⑥发射灯（亮）：金色发光圆形灯泡，外圈暖光。
第3行：⑦发射灯（灭）：同⑥造型但暗灰色无光；⑧刷新：两个首尾相接的青色环形箭头；⑨乘号徽章：金色立体粗乘号"×"形状的小徽章（纯图形）。
严格按行列定格摆放，从第一行左到右逐一绘制指定主体，不得乱排或漏画；每个主体居中独立、占单格约 72%–78%，四周留足均匀白边，彼此不重叠、不跨格；
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
English：
```
1:1 square canvas, a clean 3x3 grid of 9 mobile game HUD button icons, Japanese neon arcade x candy-toy material, 2.5D semi-painterly, crisp cel highlights, 3px dark purple (#2A1240) outline, still readable at 32px.
Row 1: (1) settings: a silver gear on a round deep purple base; (2) close: a bold white rounded X on a round deep purple base; (3) home: a small golden house on a round deep purple base.
Row 2: (4) marble bag: an open brown cloth pouch with three silver marbles peeking out; (5) speed-up: two bold magenta arrows pointing right side by side; (6) launch lamp (on): a glowing golden round bulb with a warm halo.
Row 3: (7) launch lamp (off): same shape as (6) but dull grey and unlit; (8) refresh: two cyan circular arrows chasing each other; (9) multiply badge: a small golden 3D bold multiplication-cross shaped emblem (graphic only).
Strictly place by rows and columns, drawing each specified subject from left to right starting at row 1, no random arrangement or omissions; each subject centered and isolated, filling about 72-78% of its cell with even white margins, no overlap, no crossing cells;
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```

| 格位 | 文件 |
|---|---|
| 第1行第1格 | `assets/Textures/ui/icon_settings.png` |
| 第1行第2格 | `assets/Textures/ui/icon_close.png` |
| 第1行第3格 | `assets/Textures/ui/icon_home.png` |
| 第2行第1格 | `assets/Textures/ui/icon_bag.png` |
| 第2行第2格 | `assets/Textures/ui/icon_speed.png` |
| 第2行第3格 | `assets/Textures/ui/lamp_on.png` |
| 第3行第1格 | `assets/Textures/ui/lamp_off.png` |
| 第3行第2格 | `assets/Textures/ui/icon_refresh.png` |
| 第3行第3格 | `assets/Textures/ui/icon_times.png` |

**合图 UI-C · 局内核心控件（6 件 → 3:2 横版 3×2）**

中文：
```
3:2 横版画布，3 列 × 2 行规整排列 6 个等大正方形格子的手机弹珠游戏核心控件素材，正面平视无透视，日式霓虹街机 × 柏青哥机台 × 糖果玩具质感，2.5D 轻厚涂，赛璐璐硬高光，深紫色(#2A1240) 3px 外描边。①–⑤ 为可九宫格拉伸的圆角方块 tile，中心区域干净纯色。
第1行：①发射大按钮（常态）：品红到橙色渐变，边框嵌一圈金色小灯泡点阵（像柏青哥机台按钮），顶部白色高光，底部加厚立体厚底；②发射大按钮（按下）：同①但整体下沉、厚底变薄、颜色更亮、灯泡全亮；③发射大按钮（禁用）：同①造型去饱和成灰紫色，灯泡熄灭。
第2行：④珠分框：电光蓝(#46AAFF)发光圆角 tile，内阴影，细白描边；⑤倍率框：倍率红(#FF4658)发光圆角 tile，内阴影，细白描边；⑥火焰条：一排横向并列的橙黄卡通火苗，底边平直，可左右平铺。
严格按行列定格摆放，从第一行左到右逐一绘制指定主体，不得乱排或漏画；每个主体居中独立、占单格约 72%–78%，四周留足均匀白边，彼此不重叠、不跨格；
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```
English：
```
3:2 landscape canvas, a 3-column by 2-row grid of 6 equal square cells containing core in-game controls for a mobile pachinko game, flat front view with no perspective, Japanese neon arcade x pachinko cabinet x candy-toy material, 2.5D light painterly, crisp cel highlights, 3px dark purple (#2A1240) outline. Items 1-5 are rounded-square tiles for 9-slice stretching with a clean flat-color center.
Row 1: (1) big launch button (normal): magenta to orange gradient, border studded with a ring of tiny golden light bulbs like a pachinko cabinet button, white highlight on top, thick 3D base; (2) big launch button (pressed): same as (1) but sunk down, thinner base, brighter colors, all bulbs lit; (3) big launch button (disabled): same shape as (1) desaturated to grey-purple, bulbs off.
Row 2: (4) chips box: glowing electric blue (#46AAFF) rounded tile with inner shadow and thin white outline; (5) mult box: glowing red (#FF4658) rounded tile with inner shadow and thin white outline; (6) flame strip: a horizontal row of orange-yellow cartoon flames with a flat bottom edge, tileable left to right.
Strictly place by rows and columns, drawing each specified subject from left to right starting at row 1, no random arrangement or omissions; each subject centered and isolated, filling about 72-78% of its cell with even white margins, no overlap, no crossing cells;
no grid lines, no dividing boxes, no borders, no frames around cells, pure flat solid white background (#FFFFFF), no drop shadow, no cast shadow, no text, no numbers.
```

| 格位 | 文件 |
|---|---|
| 第1行第1格 | `assets/Textures/ui/launch_normal.png` |
| 第1行第2格 | `assets/Textures/ui/launch_pressed.png` |
| 第1行第3格 | `assets/Textures/ui/launch_disabled.png` |
| 第2行第1格 | `assets/Textures/ui/box_chips.png` |
| 第2行第2格 | `assets/Textures/ui/box_mult.png` |
| 第2行第3格 | `assets/Textures/ui/flame_strip.png` |

> UI 文字（按钮字、数字）始终由程序绘制，素材里一律不出现文字。接入方式：底框用 `backgroundImage + backgroundFit = "sliced" + backgroundSlice`，图标走 `ArtIcon`。

---

## 12. 音频

| 文件（`assets/Sounds/`） | 用途 | 风格 |
|---|---|---|
| `bgm_title.ogg` | 标题 | 祭典三味线 + 合成器 Lo-fi，90 BPM |
| `bgm_game.ogg` | 局内 | 街机 chiptune × 太鼓，120 BPM，可循环 |
| `bgm_fever.ogg` | FEVER | 同曲提速变调 + 欢呼，150 BPM |
| `sfx_launch` | 发射 | 机械"咔哒" + 钢珠连发 |
| `sfx_peg` | 普通钉 | 清脆"叮"（引擎按单珠连击抬音高） |
| `sfx_bumper` / `sfx_coin` / `sfx_mult` / `sfx_xmult` | 特殊钉 | 弹簧 / 金币 / 上扬 / 重低音"轰" |
| `sfx_pop` / `sfx_boom` | 小/大爆炸 | |
| `sfx_pocket` / `sfx_start` | 落袋 / 入赏 | |
| `sfx_spin` / `sfx_reel` / `sfx_reach` | 转轮 / 停轮 / 听牌 | 听牌 = 心跳 + 鼓点渐强 |
| `sfx_fever` / `sfx_settle` / `sfx_bigwin` / `sfx_fail` | 大当 / 结算 / 过关 / 失败 | |
| `sfx_charm` / `sfx_click` / `sfx_buy` | 护符触发 / 点击 / 购买 | |

- 缺文件时静默跳过（Demo 无音频也可运行）。首次点击后解锁音频；同名音效 50ms 节流；音乐/音效开关独立持久化。

---

## 13. 技术架构

### 13.1 模块

```
scripts/
├── main.lua              引擎初始化、事件订阅、dt 钳制、切后台
├── Game/                 纯逻辑（无引擎依赖，可在 lua5.4 直接跑）
│   ├── Config.lua        全部数值与内容表 ← 加内容从这里开始
│   ├── RNG.lua           可存档 LCG 随机
│   ├── Physics.lua       自写 2D 物理：圆 vs 钉/线段/圆角矩形 + 珠珠碰撞，空间哈希
│   ├── Board.lua         钉阵模板、墙、口袋、启动口、特殊钉布置
│   ├── Stage.lua         一台的局内状态机：发射→物理→计分→老虎机→FEVER→结算
│   ├── Charms.lua        护符钩子实现
│   ├── Run.lua           一局：层/台/金币/珠袋/护符/改造/商店/序列化
│   ├── Save.lua          双端存档
│   └── Audio.lua         音效/BGM（缺文件静默）
├── Render/
│   ├── Art.lua           程序化美术 + 贴图自动替换
│   ├── FX.lua            粒子/飘字/冲击环/横幅/震屏/闪白（Stage 事件监听者）
│   └── Widgets.lua       BoardView / ScoreBar / ArtIcon / LogoArt（UI.Widget 子类）
└── UIx/
    ├── Skin.lua          颜色/字号/数字格式化
    └── App.lua           页面、弹窗、流程状态机
```

### 13.2 数据流

```
[大力干!] → App.Launch → Stage:Launch
每帧 main.HandleUpdate(dt≤0.05) → App.Update
   → Stage:Update(dt)（×倍速次） → Physics:Step（4 子步）→ 回调 Stage:HitPeg …
                                  → self.fx:PegHit / Popup / Explode …（只发事件）
   → FX:Update → App.RefreshHUD（脏检查）
   → Save.Update（30s 本地 / 120s 云端）
UI 渲染 → BoardView:Render(nvg) 读 Stage/FX 状态绘制（逻辑与表现完全解耦）
```

### 13.3 关键决策

| 决策 | 理由 |
|---|---|
| 自写物理而非 Box2D | 只需圆/线段/圆角矩形；可控手感（偏转=天意、弹力柱补速）；**纯 Lua 可跑数值模拟**；200 颗珠 1.1ms/帧（桌面 Lua） |
| 全 NanoVG 绘制盘面 | 程序化美术零资源即可玩；与 UI 同一渲染管线；贴图后期可逐个替换 |
| 逻辑层零引擎依赖 | `tests/` 可直接跑完整局、校准数值、回归测试 |
| 事件监听者模式（Stage → FX） | 换表现层/加音效不碰逻辑 |
| 对象池（粒子 520 / 飘字 64 / 环 40）+ 飘字字符串缓存 | 每帧零分配 |

### 13.4 存档

- 本地：`danzhu_save.json`（信封 `{version, savedAt, saveSeq, summary, body={meta, run}}`）；偏好 `danzhu_prefs.json`。
- 云端（clientCloud）：`has_save`（iscore）+ `save_meta` + `save_body`（JSON 字符串）。
- 启动：比较 `savedAt → saveSeq → 进度` 取领先；无本地且云读取失败/超时（10s 看门狗）→ 「云存档读取失败」弹窗（重试 / 开始新档），**绝不静默覆盖**。
- 断点：每发结算回到待机时写 `stageSave`，商店购买即存；可在任意台间/台内发射间续玩。

### 13.5 测试

| 命令 | 内容 |
|---|---|
| `lua5.4 tests/test_all.lua` | 12 项：全图标绘制、标题 Logo 物理、局内左右均衡与防卡珠、完整一局（每 3 帧渲染整棵 UI 树，约 570 万次严格 NanoVG 调用）、弹窗、极值态（1.2e13 珠分、777、听牌、头目）、存档往返、云领先/失败/超时 |
| `lua5.4 tests/sim_balance.lua 100` | 100 局数值模拟 |
| `TEST_VERBOSE=1 ...` | 打开游戏内日志 |

> 测试桩严格模式：NanoVG 参数出现 nil/NaN/越界颜色立即报错；UI 桩只允许文档中出现的控件方法，调用未知方法即报错。

---

## 14. 商业化与轻社交

| 点位 | 形式 | 规则 |
|---|---|---|
| 台崩了 → **再来一发** | 激励视频 | 每局 1 次，+1 次发射继续本台 |
| 过关奖励 **×2** | 激励视频 | 结算弹窗次按钮，每台 1 次 |
| 商店 **免费刷新** | 激励视频 | 每店 1 次 |
| 每日挑战排行 | clientCloud 排行榜 | 只比单发最高分 |
| 战绩分享卡 | 截图 + 构筑展示 | 结局弹窗"晒一晒"，不强制 |

- 广告未就绪时按钮置灰"加载中"；完整观看回调后发奖，状态锁防重复。
- **绝不**在发射中插屏、绝不强制分享。

---

## 15. 埋点

`launch_app → title_ready → run_start(starter) → first_launch → first_fever → stage_clear(ante, idx, score, launches_left) → shop_buy(type, id, price) → stage_fail(ante, idx) → run_end(result, ante, best_launch)`，以及 `lua_error`、`cloud_fail(code)`、`ad_reward(placement)`。

---

## 16. Demo 现状与路线图

### 16.1 Demo 已实现 ✅

- 完整局内：轨道发射、自写物理、7 种钉子、7 口袋、启动口 + 老虎机（保留/听牌/大当/777）、FEVER 珠雨、计分与结算演出、慢动作/震屏/闪白/粒子。
- 9 珠子、16 护符、8 改造、7 头目、4 主题 × 4 钉阵、8 层 24 台。
- 商店（刷新/购买/熔珠/出售）、经济（奖励/利息）、珠袋/弹匣抽取。
- 3 台主 + 解锁、图鉴、纪录。
- 双端存档（本地 30s / 云 120s / 手动保存 / 启动领先对比 / 云失败防覆盖弹窗 / 断点续玩）、设置（音乐/音效）。
- 全部程序化美术 + 贴图自动替换钩子；音频钩子。
- 纯 Lua 测试与数值模拟。

### 16.2 路线图（任务拆解见第 24 章）

| 里程碑 | 内容 | 验收 |
|---|---|---|
| M1 真机验证（1 周） | 真机跑通、修 UI 适配与性能、接入首批贴图（合图 A/B/C/E） | 360×667 与 412×915 无裁剪；中端机 60 帧 |
| M2 内容扩充（2 周） | 珠子 18、护符 40、头目 15 + 终局头目、台主 6 | 模拟器通关率 3–15% |
| M3 局外（1 周） | 难度星、成就、每日挑战、图鉴扩展 | |
| M4 音频与演出（1 周） | 全部 BGM/SFX、FEVER 专属演出、过关转场 | 静音/有声两套体验评审 |
| M5 商业化与上线（1 周） | 激励视频、分享卡、埋点、合规 | 冷启动 ≤ 3 秒 |

---

## 17. 给后续 AI 的落地指引

> 先读：`docs/GDD.md`（本文）→ `scripts/Game/Config.lua` → `scripts/Game/Stage.lua`。遵守 minigame-ui-spec（UI 只建一次、横排优先、网格+详情区、弹窗规范、B1–B6 防裁剪）。

### 17.1 加一颗新珠子
1. `Config.BALLS` 加表项（`name/price/rarity/r/rest/desc` + 自定义字段），并加入 `BALL_ORDER`。
2. 在 `Stage:HitPeg` 的「珠子特性」段或 `_onPocket` 里实现自定义字段逻辑。
3. `Art.BALL_COLORS` 加颜色，`Art.Ball` 加特征绘制。
4. 跑测试：`lua5.4 tests/test_all.lua`（会自动绘制所有珠子图标）。

### 17.2 加一个新护符
1. `Config.CHARMS` + `CHARM_ORDER` 加表项（描述 ≤ 20 字）。
2. `Game/Charms.lua` 加钩子表（`stats / onLaunchStart / onPegHit / onPocket / onSlotSpin / onFever / onLaunchEnd`）。
3. `Render/Art.lua` 的 `CHARM.<id>` 加程序化图标（单位 `u = s/100`，在 ±50u 内绘制）。
4. 乘法类效果必须"每发一次"；跑 `sim_balance.lua` 确认没有破坏曲线。

### 17.3 加一个头目
`Config.BOSSES` + `BOSS_ORDER` 加表项；在 `Stage.new` 的规则段（`self.rules.<id>`）实现；需要盘面变化的在 `Board` 增加参数。温和规则标 `mild = true` 才可能出现在第 1 层。

### 17.4 加钉子类型 / 口袋类型
`Config.PEGS` + `PEG_ORDER`；`Stage:HitPeg` 增加分支；`Art.Peg` 增加绘制；`FX.PEG_COL` 增加颜色。

### 17.5 接入贴图
放 PNG 到 `assets/Textures/<目录>/<id>.png` 即自动生效（见 11.2）；切图与 UI 底框接入按第 22 章执行。`boss/ui/boards` 目录尚未在绘制代码里调用，需要在对应位置调用 `Art.TryImage(vg, "boss:<id>")`。

### 17.6 禁止事项
- 不在 `onClick / Update / refresh` 里重建控件；不在每帧分配表或拼字符串。
- 不改 `Physics` 子步/限速前不跑模拟（会穿钉）。
- 未经用户明确指令不操作 GitHub 远端；Maker 构建/同步走 Maker 流程。

---

## 18. 风险与对策

| 风险 | 对策 |
|---|---|
| "零操作"被认为无聊 | 局内演出密度（5 章）+ 局外决策深度（6 章）；倍速按钮缩短等待；后续可加"一次性主动技"作为护符（仍不加瞄准） |
| 随机性过强导致挫败 | 第 1 层温和头目；"差一点"演出转化挫败为期待；剩余发射给钱 |
| 数值爆炸失控 | 乘法来源受限 + 模拟器回归（9.3 守则） |
| 低端机性能 | 粒子/珠子上限（520/220）、飘字抽样、可在设置加"省电模式"关闭拖尾与辉光 |
| 柏青哥题材合规 | 去赌博化：无兑换、无真实货币、无"押注"；商店货币为游戏内金币；老虎机仅作演出 |

---

## 19. 完整版内容规格（可直接实现）

> 本章是第 6–8 章"规划内容"的**实现规格**：每条都给出数值、触发钩子与改动位置。数值为初值，实现后必须跑 `tests/sim_balance.lua 100` 回归（见 9.3）。

### 19.1 需要先补的框架能力（实现下列内容的前置）

| 能力 | 位置 | 说明 | 被谁依赖 |
|---|---|---|---|
| `Stage:Delay(t, fn)` | Stage | 延时回调队列（按局内时间推进，受慢动作影响） | 双响炮、陀螺珠 |
| 护符实例数据 `run.charmData[id]` | Run（随存档序列化） | 每个护符可存自己的计数/金额 | 储钱罐、打铁匠 |
| 钩子 `onStageFail(st)` → 返回 `true` 取消失败 | Stage `_finishSettle` | 失败前询问护符 | 招福达摩 |
| 钩子 `onStageClear(st)` | Stage | 过关时 | 打铁匠 |
| 钩子 `onBallUpdate(st, ball, dt)` | Stage 珠子循环 | 每颗珠每帧（**禁止分配表**） | 磁铁、磁珠 |
| `stats.holdMax` / `stats.slotSymbols` / `stats.ballBallRest` / `stats.multCap` | Stage 静态参数 | 取代直接读 `C.SLOT.maxHold` 等常量 | 双倍保留、老千骰子、静电、天平 |
| `Run:PriceOf(item)` | Run 商店 | 统一计价入口（折扣/涨价） | 狐狸面具、难度星 |
| 护符派发支持"复制" | `Stage:_hook` | 复制猫调用右侧护符的同名钩子 | 复制猫 |

### 19.2 新增珠子（9 种 → 总计 18）

| id | 名称 | 价格 | 稀有 | 效果（描述 ≤20 字） | 参数 | 实现位置 |
|---|---|---|---|---|---|---|
| `ice` | 冰珠 | 6 | 稀 | 特殊钉被它撞后不熄灭一次 | — | `HitPeg` 熄灭分支：`peg.frozenUsed` |
| `magnet` | 磁珠 | 5 | 普 | 被 60 内的金钉吸引 | 引力 300 | `onBallUpdate` |
| `top` | 陀螺珠 | 6 | 稀 | 撞钉后贴钉连撞 3 次 | 间隔 0.1s | `Delay` + `HitPeg` |
| `seed` | 种子珠 | 5 | 普 | 落袋处上方长出 1 颗金钉 | 本台有效 | `_onPocket` → `Board:AddPeg` |
| `bombb` | 炸弹珠 | 6 | 稀 | 落袋时爆炸 | 半径 60 | `_onPocket` → `Explode` |
| `mirror` | 镜面珠 | 7 | 传 | 撞普通钉 25% 复制上次特殊钉 | — | `HitPeg` 记录 `st.lastSpecial` |
| `purse` | 钱袋珠 | 4 | 普 | 每次命中 8% 掉 $1 | 每发上限 $3 | `HitPeg` 珠子特性段 |
| `thunder` | 雷珠 | 7 | 稀 | 每 10 次命中劈一道闪电 | 同列 x±10 全触发 | `HitPeg` + `Physics:QueryPegs` |
| `comet` | 彗星珠 | 6 | 稀 | 极速，路径上的钉都算命中 | 速度 ×2，重力 ×0.6 | `SpawnBall` 设 `gravityMul`；`ghost` 0.3s |

### 19.3 新增护符（24 个 → 总计 40）

| id | 名称 | 价格 | 稀有 | 描述（≤20 字） | 钩子 / 实现 |
|---|---|---|---|---|---|
| `magnet` | 磁铁 | 5 | 普 | 所有珠子被金钉轻微吸引 | `onBallUpdate`：半径 50，引力 200 |
| `double` | 双响炮 | 7 | 稀 | 炸弹钉 0.3 秒后再爆一次 | `onPegHit`(bomb) → `Delay(0.3, Explode)` |
| `thunder` | 雷神 | 7 | 稀 | 每发每 50 次命中劈闪电 | `onPegHit` 计 `st.result.hits % 50` |
| `dice` | 老千骰子 | 6 | 稀 | 老虎机符号少一种 | `stats.slotSymbols = 4` |
| `daruma` | 招福达摩 | 8 | 传 | 失败时多给 1 发，然后碎裂 | `onStageFail`：`launchesLeft = 1`，移除自身 |
| `piggy` | 储钱罐 | 4 | 普 | 每发存 $1，卖出全拿 | `onLaunchEnd` 累加 `charmData.piggy`；`SellPrice` 加上 |
| `ripple` | 涟漪 | 6 | 稀 | 普通钉 20% 连带邻钉 | `onPegHit`：`QueryPegs` 半径 30 取 1 颗 |
| `blackhole` | 黑洞 | 8 | 传 | +3 口袋吸珠，每颗 +1 倍率 | `onBallUpdate`：口袋上方 50 内吸引 |
| `sakura` | 樱吹雪 | 5 | 普 | FEVER 中花瓣每片 +5 珠分 | `onFever` 启动定时；FX 花瓣粒子 |
| `fudo` | 不动明王 | 6 | 稀 | 弹力柱命中 ×1.1 倍率 | `onPegHit`(bumper)，每发上限 ×3 |
| `smith` | 打铁匠 | 5 | 普 | 每过一台钢珠命中 +1 珠分 | `onStageClear` 累加；`HitPeg` 读取 |
| `gambler` | 赌徒 | 6 | 稀 | 结算倍率 ×2，弹匣 -3 | `stats.magazine -= 3`；`onLaunchEnd` ×2 |
| `echo` | 回声 | 6 | 稀 | 每发最后一颗珠重发一次 | `_onPocket` 时若轨道/场上无其他珠 → 再入轨 |
| `neon` | 霓虹招牌 | 5 | 普 | 每个护符结算 +2 倍率 | `onLaunchEnd`：`#run.charms × 2` |
| `toad` | 金蟾 | 7 | 稀 | 每 $10 存款结算 ×1.1 | `onLaunchEnd`，上限 ×2 |
| `firework` | 爆竹王 | 8 | 传 | 所有珠首撞小爆炸 | `onPegHit`：`ball.hits == 1` → `Explode(r=30)` |
| `hold2` | 双倍保留 | 5 | 普 | 保留上限 4 → 8 | `stats.holdMax = 8`（液晶画 8 盏灯） |
| `rigged` | 确率机 | 7 | 稀 | 听牌落空 50% 改判大当 | `_startSpin` 结果生成后改写 |
| `quantum` | 量子珠 | 6 | 稀 | 入赏一次得 2 个保留 | `_onStartPocket` |
| `ironman` | 铁人 | 5 | 普 | 重珠变 1.5 倍大，珠分 ×3 | `SpawnBall` 改半径；`HitPeg` 改倍数 |
| `rainbow` | 彩虹桥 | 6 | 稀 | 弹匣每种不同珠 +2 倍率 | `onLaunchStart` 统计弹匣种类 |
| `fox` | 狐狸面具 | 6 | 稀 | 商店商品 -$1 | `Run:PriceOf` 读护符 |
| `glutton` | 大胃王 | 5 | 普 | 弹匣 +4，发射次数 -1 | `stats.magazine += 4; stats.launches -= 1`（最低 1） |
| `copycat` | 复制猫 | 9 | 传 | 复制右侧护符效果 | `_hook` 遇到 copycat 时调用 `charms[i+1]` 的钩子 |

> 护符 id 与贴图文件名一致（`assets/Textures/charms/<id>.png`）。护符 `magnet` / `thunder` 与珠子 `magnet` / `thunder` 同名但分属 `C.CHARMS` / `C.BALLS` 与不同贴图目录，互不冲突。

### 19.4 新增头目（8 个 + 终局）

| id | 名称 | 规则 | 温和 | 实现 |
|---|---|---|---|---|
| `mirror` | 镜像 | 钉阵左右翻转，每种特殊钉 -1 | | `Board` 生成后 `x = W - x`；`stats.peg[k] - 1` |
| `funnel` | 漏斗 | 两侧回收口变成吞珠口 | ✓ | `pk.kind = "void"`（无奖励） |
| `freeze` | 冰冻 | 特殊钉要撞两次才生效 | | `peg.hp = 2` |
| `hunger` | 饥饿 | 每发弹匣 -2 | ✓ | `stats.magazine -= 2` |
| `static` | 静电 | 珠子互相强烈弹开 | | `stats.ballBallRest = 1.25` |
| `blackout` | 黑幕 | 液晶关闭，大当率 -5% | | 液晶画"？？？"，不演听牌 |
| `countdown` | 倒计时 | 每发 8 秒后珠子消失 | | `launchClock > 8` → 全部回收 |
| `balance` | 天平 | 倍率上限 50 | | `stats.multCap = 50`，`AddMult/MulMult` 截断 |
| `king` | 弹珠之王 | **终局 8-3 固定**：每 3 秒随机切换一条规则，目标 ×2.5 | — | `Run.bosses[8] = "king"`；Stage 内定时切 `rules` |

### 19.5 新增台主（3 位 → 总计 6）

| key | 名称 | 起始 | 解锁 |
|---|---|---|---|
| `youyou` | 幽幽 · 幽灵少女 | 8 钢珠 4 幽灵珠 + 轻羽，$4 | 通关 1 次 |
| `qiqi` | 七七 · 老虎机少女 | 10 钢珠 1 幸运珠 + 确变之魂，$4 | 累计大当 20 次 |
| `tieta` | 铁塔 · 重珠大叔 | 8 钢珠 3 重珠 + 铁人，$5 | 到达第 6 层 |

---

## 20. 局外系统细则

### 20.1 难度星（通关后解锁，逐级叠加）

| 星级 | 新增规则 |
|---|---|
| ★1 | 小台不再给过关基础奖励（$0） |
| ★2 | 所有目标分 ×1.15 |
| ★3 | 商店少 1 个珠子格 |
| ★4 | 利息上限 $3 |
| ★5 | 所有目标分再 ×1.15（累计 ×1.32） |
| ★6 | 第 4 层起头目台叠加两条规则 |
| ★7 | 每台发射次数 -1（最低 2） |
| ★8 | 起始金币 $0，刷新起价 $3 |

实现：`Run.new(starter, seed, stars)`，规则写成 `C.STARS[1..8]` 表，在 `CurrentStageInfo / GenerateShop / OnStageCleared / Stage.new` 读取。图鉴与纪录按星级分开记录最佳成绩。

### 20.2 成就（30 个，奖励只给外观：头像框 / 台面皮肤 / 珠子拖尾色）

| 类 | 示例（条件 → 奖励） |
|---|---|
| 爆分 | 一发入魂：单发 ≥ 100 万 → 金色拖尾；亿万富翁：单发 ≥ 1 亿 → "亿"头像框 |
| 老虎机 | 首次大当；777：首次超级大当 → 777 台面皮肤；连庄：一发内 3 次大当 |
| 物理 | 人海战术：同屏 ≥ 150 颗珠；连锁反应：一次爆炸连带 ≥ 30 颗钉 |
| 构筑 | 五福临门：同时持有 5 个护符；纯钢：只用钢珠通过第 4 层 |
| 进度 | 每位台主各通关 1 次（6 个）；★1–★8 各通关 1 次（8 个） |
| 趣味 | 差一点：一局听牌落空 10 次；守财奴：持有 $50 |

存储：`meta.achievements = { [id] = os.time() }`。成就弹出用 Toast 级横幅，**不打断局内**（排队到结算后显示）。

### 20.3 每日挑战

- 种子 = `tonumber(os.date("%Y%m%d"))`，台主按星期轮换，难度固定 ★2。
- 每天只有**第一次**完整挑战计入排行榜，比"最高单发"。
- 云端：`clientCloud:SetInt("daily_" .. yyyymmdd, bestLaunch)`，排行用 `GetRankList("daily_" .. yyyymmdd, 0, 50)`；弱网失败时本地缓存待下次上传，不阻塞游戏。

### 20.4 无尽模式

全台通关后可选"继续"：第 9 层起目标每层 ×2.2，头目每台都是（随机双规则）。纪录"无尽最高层"。

---

## 21. 新手引导

**原则**：做给玩家看，不写给玩家读；每步 ≤ 12 字；全部可跳过；只在首局触发（`meta.tutorialDone`）。

| 步 | 时机 | 表现 | 文案 |
|---|---|---|---|
| 1 | 首局进入局内 | "大力干!"按钮呼吸放大 + 手指点击动画，其余区域压暗 40% | 点这里，大力干! |
| 2 | 第 1 颗珠撞到特殊钉 | 慢动作 0.3×，该钉圈出高亮 | 金钉=珠分 红钉=倍率 |
| 3 | 第 1 次入赏 | 镜头不动，液晶边框闪烁 + 箭头指向启动口 | 掉进这里抽大奖 |
| 4 | 第 1 次结算 | 分数板珠分框、倍率框依次高亮 | 珠分 × 倍率 |
| 5 | 第 1 次进商店 | 最便宜的护符格子呼吸高亮 | 买个护符试试 |

**首局保底**：首局第 1 发的第 1 次老虎机必中大当（`run.tutorial = true` 时 `jackpot = true`），保证 30 秒内看到 FEVER（3-10-30 漏斗的"30 秒首次爽感"）。

---

## 22. 切图与 UI 贴图接入规范（交给切图 AI / 接入 AI）

### 22.1 切图规则

| 项 | 规范 |
|---|---|
| 等分 | 1:1 合图按 3×3（或 2×2）等分；3:2 合图按 3×2 等分（每格正方形） |
| 去底 | 只去掉**与画布边缘连通**的白色区域（从四边做洪水填充，容差 ~12），**不要全局抠白**，否则珠子高光、眼白会被挖空 |
| 修边 | 去底后做 1px 收缩 + 1px 羽化，消除白边 |
| 输出尺寸 | 道具/图标/钉子/符号/头像：`256×256` 透明 PNG，主体居中，四周留 8px；UI 底框（UI-A、UI-C ①–⑤）：`192×192`；火焰条 `flame_strip`：裁成 `256×96` |
| 命名 | 严格按第 11 章各合图的"格位 → 文件"映射表 |
| 规划格 | 合图里"规划"的格子照常切出，放入对应路径即可，代码接入时自动生效 |

### 22.2 九宫格切线清单（切图 AI 必须一起输出）

UI 底框需要告诉程序"四角不拉伸的范围"。切图 AI 量好每张图后写入 `assets/Textures/ui/slices.json`：

```json
{
  "btn_primary.png":   { "top": 48, "right": 48, "bottom": 60, "left": 48 },
  "btn_secondary.png": { "top": 48, "right": 48, "bottom": 60, "left": 48 },
  "btn_danger.png":    { "top": 48, "right": 48, "bottom": 60, "left": 48 },
  "dialog.png":        { "top": 56, "right": 56, "bottom": 64, "left": 56 },
  "panel.png":         { "top": 32, "right": 32, "bottom": 32, "left": 32 },
  "card.png":          { "top": 36, "right": 36, "bottom": 36, "left": 36 },
  "card_selected.png": { "top": 40, "right": 40, "bottom": 40, "left": 40 },
  "slot_empty.png":    { "top": 36, "right": 36, "bottom": 36, "left": 36 },
  "pill.png":          { "top": 40, "right": 56, "bottom": 40, "left": 56 },
  "launch_normal.png": { "top": 52, "right": 56, "bottom": 64, "left": 56 },
  "launch_pressed.png":{ "top": 52, "right": 56, "bottom": 56, "left": 56 },
  "launch_disabled.png":{ "top": 52, "right": 56, "bottom": 64, "left": 56 },
  "box_chips.png":     { "top": 40, "right": 40, "bottom": 40, "left": 40 },
  "box_mult.png":      { "top": 40, "right": 40, "bottom": 40, "left": 40 }
}
```

> 上面是 192×192 素材的初值，按实际装饰大小量取：切线必须完全包住四角装饰和加厚底边，中间可拉伸区域只能是纯色。

### 22.3 程序接入（接入 AI 照做）

1. `UIx/Skin.lua` 新增 `Skin.IMG`（文件路径）与 `Skin.SLICE`（读取 `slices.json`，用 `cjson` + `pcall`，缺文件时为空表 → 继续用当前纯色样式）。
2. 新建 `UIx/SkinButton.lua`：`Panel + Label` 组合按钮，`variant` 决定三张底图（normal / pressed / disabled），按下时换 pressed 图 + 缩放 0.94；**文字仍由程序绘制**，`minHeight = 44`，接口保持 `SetText / SetDisabled`，用它替换 `App.lua` 里的 `UI.Button`。
3. 面板：`UI.Panel { backgroundImage = "Textures/ui/dialog.png", backgroundFit = "sliced", backgroundSlice = Skin.SLICE["dialog.png"] }`（参见 `recipes/ui.md` 图片渲染一节）。
4. 对应关系：

| 素材 | 用在 |
|---|---|
| `dialog` | 所有 Dialog 卡体 |
| `panel` | 分数板底、商店详情区、顶栏金币底以外的面板 |
| `card` / `card_selected` | `ItemCell`、台主卡（`setCellSelected` 切换） |
| `slot_empty` | 护符栏空槽（有护符时仍显示底框，图标叠在上面） |
| `pill` | `CoinTag`、价格标签 |
| `launch_*` | "大力干!"按钮三态 |
| `box_chips` / `box_mult` / `flame_strip` | `ScoreBar:Render` 内用 `nvgImagePattern` 替代渐变矩形与程序火焰 |
| `icon_*`、`lamp_*` | `ArtIcon` 新增 `kind = "ui"`，走 `Art.TryImage("ui:<name>")`（需在 `Art.AUTO_DIRS` 加 `ui = "ui"`） |

5. 接入后验收：360×667 与 412×915 两种分辨率下按钮文字不被裁剪、弹窗切页签 0 抖动、九宫格四角不变形。

---

## 23. 存档数据结构（version = 1）

```text
danzhu_save.json（信封）
├─ version      int      存档结构版本，结构变化时 +1 并在 Save 里写迁移函数
├─ savedAt      int      os.time()
├─ saveSeq      int      单调递增（同秒多次保存时比较用）
├─ summary      { bestAnte, inRun }        云端轻量摘要
└─ body
   ├─ meta
   │  ├─ bestAnte / wins / runs / bestLaunch     int
   │  ├─ discovered   { ["ball:fire"]=true, ["charm:cat"]=true, ... }
   │  ├─ (规划) achievements { [id]=time }、tutorialDone bool、stars { [starter]=maxStar }
   └─ run  （无进行中对局时为 nil）
      ├─ version, seed, rngState              随机数可续
      ├─ starter, ante, stageIdx, coins, rerollCost, phase("stage"|"shop")
      ├─ bag        ["steel","steel","fire",...]
      ├─ charms     ["cat","lantern",...]
      ├─ mods       { magazine, launches, peg = { red=2, ... } }
      ├─ bosses     [8 个头目 id]
      ├─ shop       [{ type, id, price, sold }] | nil
      ├─ stageSave  { score, left, index } | nil   台内断点（发射间）
      ├─ stats      { bestLaunch, totalScore, jackpots, maxCombo, stagesCleared }
      └─ (规划) charmData { [id] = any }、stars
danzhu_prefs.json   { music, sfx, (规划) vibrate, lowPower }
云端：has_save(iscore=1) / save_meta(summary) / save_body(整份信封 JSON 字符串)
```

**迁移规则**：读取时 `env.version < C.VERSION` → 依次调用 `Save.migrate[v](env)` 升级到当前版本后再使用；不能识别的高版本存档**只读不写**并提示更新。

---

## 24. 开发任务清单（Backlog）

> 优先级：P0 = 上线必须，P1 = 首版内容，P2 = 长线。每个任务完成后都要跑 `tests/test_all.lua`；动数值的再跑 `sim_balance.lua 100`。

| ID | 任务 | 优先 | 依赖 | 验收 |
|---|---|---|---|---|
| T01 | 真机跑通 Demo，修所有报错与适配问题 | P0 | — | 25 节「待验证项」逐条确认；`runtime.log` 0 条 Layout Warning |
| T02 | 接入 UI-A/B/C 贴图（22 章） | P0 | 切图 | 22.3 第 5 条 |
| T03 | 接入珠子/护符/改造/钉子/符号/头像合图 | P0 | 切图 | 放入路径即生效；缺图自动回退 |
| T04 | 音频接入（12 章清单） | P0 | 音频素材 | 静音开关持久化；同名音效 50ms 节流 |
| T05 | 新手引导 + 首局保底大当（21 章） | P0 | — | 新号 30 秒内看到 FEVER |
| T06 | 框架能力（19.1 全部） | P1 | — | 新增单测覆盖 Delay / onStageFail / charmData 存档往返 |
| T07 | 新珠子 ×9（19.2） | P1 | T06 | 图鉴自动出现；全部图标可程序化绘制 |
| T08 | 新护符 ×24（19.3） | P1 | T06 | 模拟器通关率仍在 3–15% |
| T09 | 新头目 ×8 + 终局弹珠之王（19.4） | P1 | T06 | 每个头目单测：规则生效 |
| T10 | 新台主 ×3（19.5） | P1 | T07 T08 | 解锁条件正确写入 meta |
| T11 | 头目徽章 / 台面背景 / Logo 贴图接入 | P1 | 切图 | `Art.TryImage("boss:<id>")` 用于待机告示牌 |
| T12 | 难度星 ★1–★8（20.1） | P1 | — | 每级规则单测 |
| T13 | 成就 30 个（20.2） | P2 | — | 结算后排队弹出，不打断局内 |
| T14 | 每日挑战 + 排行榜（20.3） | P2 | 云 | 弱网降级不阻塞 |
| T15 | 无尽模式（20.4） | P2 | — | |
| T16 | 激励视频 3 个点位（14 章） | P1 | 平台 SDK | 未就绪置灰；完整观看才发奖；防重复 |
| T17 | 埋点（15 章） | P1 | — | 漏斗事件齐全 |
| T18 | 设置：震动、省电模式（关拖尾/辉光/粒子减半） | P2 | — | 低端机 ≥ 50 帧 |
| T19 | `App.lua` 拆分为 `UIx/Pages/*.lua` + `UIx/Dialogs/*.lua` | P1 | — | 行为不变，测试全绿 |
| T20 | 存档迁移框架（23 章） | P1 | — | v1→v2 迁移单测 |

---

## 25. Demo 已知限制与待真机验证项

### 25.1 未在真机/引擎中运行过

Demo 只通过了纯 Lua 测试（严格 NanoVG / UI 测试桩）。以下接口按官方文档写成，但**必须在真机上确认**：

| 项 | 位置 | 若不符合怎么改 |
|---|---|---|
| 粗体字体 `Fonts/MiSans-Bold.ttf` 是否存在 | `main.lua` `UI.Init` | 去掉 bold 项，`Art.FONT_BOLD = Art.FONT` |
| `UI.Theme.FontFace("sans","bold")` 返回值能否直接给 `nvgFontFace` | `main.lua` | 改为 UI 注册字体时的真实名字 |
| 自定义控件 `Render(nvg)` 坐标系与 UI 缩放 | `Render/Widgets.lua` | 若错位，乘以 `UI.Scale` 或改用 `GetAbsoluteLayout` 的物理像素 |
| `nvgIntersectScissor` 在 UI 渲染中的表现 | `BoardView:Render` | 若裁剪异常改为 `nvgScissor` |
| `nvgCreateImage(vg, path, 0)` 能否按资源路径加载 | `Art.TryImage` | 改用 UI 库的 ImageCache 接口 |
| `InputFocus` 事件与 `Focus` 字段 | `main.lua` | 改订阅引擎实际的切后台事件 |
| `Hide()` 是否让出布局空间（"继续"按钮隐藏时） | 标题页按钮行 | 改用 `SetStyle({ display = "none" })` 或宽度 0 |
| `Widget:Animate` 支持 `rotate` 关键帧 | 护符栏弹跳 | 去掉 rotate 只留 scale |
| `UI.Toggle:SetChecked` | 设置弹窗 | 以 `UI.Toggle` 实际方法名为准 |
| 新增 `.lua` 没有 `.meta` 文件 | `scripts/**` | 由 Maker 同步时生成；若不生成需手动补 |

### 25.2 设计/实现上的已知取舍

- **两侧回收口进珠偏多**（约占落袋 40%）：钉阵左右对称后两侧各有一条边道，回收口会把珠子重发一次，不算浪费。若觉得太多，可缩窄边道（注意不要形成 V 形夹缝，见 9.3 第 4 条）。
- **音频文件缺失**：Demo 静音运行，`Game/Audio.lua` 会自动跳过缺失文件。
- **头目徽章 / 台面背景 / UI 底框贴图尚未接入**（见 T02、T11）。
- **局内飞珠时不能卖护符**（避免中途改规则的边界问题）；改造只能在商店买。
- **单个 `App.lua` 约 1000 行**：扩建前建议先做 T19 拆分。
- **数值模拟用的是贪心 AI**：只能代表"不懂流派的玩家"下限，人类实测数据回来后要重调第 6–8 层。

---

## 附录 · 名词表

| 名词 | 含义 |
|---|---|
| 台 / Stage | 一个关卡（一台弹珠机） |
| 层 / Ante | 3 台为一层，共 8 层 |
| 一发 | 按一次「大力干!」射出一个弹匣 |
| 弹匣 | 每发射出的珠子数量 |
| 珠袋 | 本局拥有的全部珠子 |
| 珠分 / 倍率 | 计分两项，得分 = 珠分 × 倍率 |
| 启动口 / 入赏 | 中央小口，入珠后获得保留 |
| 保留 | 待转的老虎机次数（最多 4） |
| 听牌 | 前两轴相同，第三轴减速悬念 |
| 大当 / FEVER | 三连中奖，进入狂热模式 |
| 护符 | 被动改写规则的道具（≈ 小丑牌） |
| 改造 | 永久修改本局台面的道具 |
| 台主 | 起始角色 |
