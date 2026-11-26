# 弹珠物语 · Marble Story

手机竖屏 Roguelike 弹珠台：**局外运筹帷幄，局内一拳「大力干!」，剩下交给天意与奇迹。**
参考柏青哥（启动口 / 液晶老虎机 / 听牌 / 大当 FEVER）、小丑牌（珠分 × 倍率、护符、商店、头目）、哥布林弹珠（珠子技能、特殊钉）。

- 引擎：UrhoX · Lua 5.4 · `urhox-libs/UI`（Yoga + NanoVG）
- 入口：`scripts/main.lua`
- 完整方案（玩法 / 数值 / UI / 美术提示词 / 技术 / 路线图）：[`docs/GDD.md`](docs/GDD.md)
  - 扩建入口：第 19 章完整版内容规格、第 22 章切图与接入规范、第 24 章开发任务清单、第 25 章待真机验证项

## Demo 内容

- 自写 2D 弹珠物理，轨道发射、7 种钉子、7 个口袋、启动口 + 三轴老虎机（保留 / 听牌 / 大当 / 777）、FEVER 珠雨
- 9 种珠子、16 个护符、8 种改造、7 个头目、4 套台面主题 × 4 种钉阵、8 层 24 台
- 商店（买 / 卖 / 刷新 / 熔珠）、利息经济、3 位台主与解锁、图鉴
- 双端存档（本地 30s / 云端 120s / 手动保存 / 云读取失败防覆盖 / 断点续玩）
- **全部程序化美术**，零贴图零音频即可运行；把 PNG 放进 `assets/Textures/<目录>/<id>.png` 自动替换（提示词与映射表见 GDD 第 11 章）

## 目录

```
scripts/
  main.lua        入口
  Game/           纯逻辑（Config 数值表、Physics、Board、Stage、Charms、Run、Save、Audio、RNG）
  Render/         程序化美术 Art、特效 FX、自定义控件 Widgets
  UIx/            界面与流程 App、样式 Skin
tests/
  test_all.lua    纯 Lua 冒烟测试（严格 NanoVG / UI 桩）
  sim_balance.lua 数值模拟（贪心 AI 跑整局）
docs/
  GDD.md          完整游戏方案
```

## 本地测试（不需要引擎）

```bash
lua5.4 tests/test_all.lua
```

```bash
lua5.4 tests/sim_balance.lua 60
```

## 扩展内容

见 [`docs/GDD.md` 第 17 章](docs/GDD.md#17-给后续-ai-的落地指引)：加珠子 / 护符 / 头目 / 钉子 / 接入贴图的步骤。
