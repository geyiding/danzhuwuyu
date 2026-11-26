-- ============================================================================
-- 纯 Lua 冒烟测试：lua5.4 tests/test_all.lua
--   1. 语法/加载    2. 程序化美术全图标（严格 NanoVG）
--   3. 完整流程：标题→开局→发射→过关→商店→购买→…→结局（每 3 帧渲染整棵 UI 树）
--   4. 极值态渲染（超大数字 / 777 FEVER / 听牌 / 头目）
--   5. 存档：序列化往返、本地续玩、云端领先/失败/超时
-- ============================================================================
package.path = "scripts/?.lua;tests/?.lua;" .. package.path
local Stubs = require("stubs")
Stubs.InstallNVG()
Stubs.InstallJSON()
Stubs.InstallFiles()
local UI = Stubs.MakeUI()
package.preload["urhox-libs/UI"] = function() return UI end

local VERBOSE = os.getenv("TEST_VERBOSE") == "1"
local realPrint = print
if not VERBOSE then _G.print = function() end end
local function log(...) realPrint(...) end

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then passed = passed + 1; log("  ✅ " .. name)
  else failed = failed + 1; log("  ❌ " .. name .. "\n" .. tostring(err)) end
end

local C = require("Game/Config")
local Art = require("Render/Art")
local VG = {}

log("== 1. 程序化美术 ==")
test("所有图标 / 钉子 / 符号 / 立绘 可绘制（待机态 + 动画态）", function()
  for _, t in ipairs({ 0, 12.37 }) do
    for _, id in ipairs(C.BALL_ORDER) do Art.BallIcon(VG, id, 50, 50, 80, t); Art.Ball(VG, id, 10, 10, 6, t) end
    for _, id in ipairs(C.CHARM_ORDER) do Art.CharmIcon(VG, id, 50, 50, 80, t) end
    for _, id in ipairs(C.MOD_ORDER) do Art.ModIcon(VG, id, 50, 50, 80, t) end
    for _, st in ipairs(C.STARTERS) do Art.Portrait(VG, st.key, 50, 50, 80, t) end
    for _, sym in ipairs(C.SLOT.symbols) do Art.SlotSymbol(VG, sym, 50, 50, 40, t) end
    for _, tp in ipairs({ "normal", "gold", "red", "purple", "bomb", "split", "bumper" }) do
      Art.Peg(VG, { x = 5, y = 5, r = 4, type = tp, alive = true, flash = 1 }, t, false)
      Art.Peg(VG, { x = 5, y = 5, r = 4, type = tp, alive = true, flash = 0 }, t, true)
      Art.Peg(VG, { x = 5, y = 5, r = 4, type = tp, alive = false, pop = 0.5 }, t, false)
    end
    Art.Icon(VG, "lock", nil, 10, 10, 20, t); Art.Icon(VG, "coin", nil, 10, 10, 20, t); Art.Icon(VG, "gear", nil, 10, 10, 20, t)
  end
  -- 每个配置条目都必须有对应的程序化图标（防新增内容忘记画图）
  for _, id in ipairs(C.CHARM_ORDER) do assert(C.CHARMS[id].name and C.CHARMS[id].desc, id) end
end)

test("标题 Logo：珠子真实撞钉、不穿钉、从底部出口回收", function()
  local W = require("Render/Widgets")
  local logo = W.LogoArt { width = 300, height = 300 }
  local maxPen, maxBalls = 0, 0
  for _ = 1, 60 * 20 do
    logo:_step(1 / 60)
    maxBalls = math.max(maxBalls, #logo.phys.balls)
    for _, b in ipairs(logo.phys.balls) do
      for _, p in ipairs(logo.pegs) do
        local d = math.sqrt((b.x - p.x) ^ 2 + (b.y - p.y) ^ 2)
        maxPen = math.max(maxPen, (b.r + p.r) - d)
      end
      assert(b.x * b.x + b.y * b.y < 104 * 104 or b.y > 80, "ball escaped through the frame")
    end
  end
  log(string.format("     logo pegHits=%d spawned=%d maxBalls=%d maxPenetration=%.2f", logo.hits, logo.nextId, maxBalls, maxPen))
  assert(logo.hits > 100, "balls are not hitting pegs")
  assert(logo.nextId > 20, "balls are not exiting/recycling")
  assert(maxPen < 2.0, "balls penetrate pegs")
  logo.layout = { x = 0, y = 0, w = 300, h = 300 }
  W.time = 1; logo:Render(VG); W.time = 1.016; logo:Render(VG)
end)

test("局内落点左右均衡（4 种钉阵）且无卡珠刷分", function()
  local Run = require("Game/Run")
  local Stage = require("Game/Stage")
  for _, layout in ipairs(C.LAYOUTS) do
    local left, right, worst = 0, 0, 0
    for seed = 1, 12 do
      local run = Run.new("tie", seed)
      local info = run:CurrentStageInfo(); info.layout = layout
      local st = Stage.new(run, info)
      st:Launch()
      local seen = {}
      for _ = 1, 60 * 40 do
        st:Update(1 / 60)
        for _, b in ipairs(st.phys.balls) do
          if not seen[b] and b.y > 260 then seen[b] = true; if b.x < 180 then left = left + 1 else right = right + 1 end end
          if b.hits > worst then worst = b.hits end
        end
        if st.phase ~= "launch" then break end
      end
    end
    local ratio = right / (left + right)
    log(string.format("     %-7s 右侧占比 %.0f%%  单珠最多命中 %d", layout, ratio * 100, worst))
    assert(ratio > 0.40 and ratio < 0.60, layout .. " 左右失衡")
    assert(worst < 300, layout .. " 有珠子卡住刷分")
  end
end)

log("== 2. 完整流程 ==")
local App = require("UIx/App")
local Save = require("Game/Save")
local frames, renders = 0, 0

local function frame(n)
  for _ = 1, n or 1 do
    App.Update(1 / 60)
    frames = frames + 1
    if frames % 3 == 0 then renders = renders + Stubs.RenderTree(UI.root, VG) end
  end
end

test("构建 UI + 读取存档（无云）", function()
  App.Build(nil)
  assert(UI.root, "root not set")
  App.Boot()
  assert(App.profileReady, "profile not ready")
  assert(Save.cloudState == "off")
  frame(10)
end)

local stagesPlayed, shopsVisited, ended = 0, 0, false
test("完整一局：发射→过关→商店→…→结局", function()
  local R = App._refs
  App.selectedStarter = 1
  App.StartRun()
  assert(App.page == "game")
  local guard = 0
  while not ended do
    guard = guard + 1
    assert(guard < 60 * 60 * 120, "run never ended")
    local st = App.stage
    if App.page == "game" and st and st.phase == "idle" and not App.pendingResult then
      App.Launch()
      if stagesPlayed % 2 == 0 then App.ToggleSpeed() end
    end
    frame(1)
    if R.dlgClear.isOpen then
      stagesPlayed = stagesPlayed + 1
      App.GoShop()
      shopsVisited = shopsVisited + 1
      assert(App.page == "shop")
      frame(3)
      for i = 1, 6 do App.SelectShop(i); App.BuyShop(); frame(1) end
      App.OpenBag(); App.SelectBag(3); frame(2); R.dlgBag:Close()
      if #App.run.charms > 0 then App.OpenCharm(1); frame(2); R.dlgCharm:Close() end
      App.RerollShop(); frame(1)
      App.LeaveShop()
      frame(2)
    elseif R.dlgEnd.isOpen then
      stagesPlayed = stagesPlayed + 1
      ended = true
    end
    if stagesPlayed >= 7 and not ended then
      -- 只跑前若干台，强制失败收尾，节省时间
      App.stage.launchesLeft = 1
      App.stage.target = 1e15
    end
  end
  log(string.format("     stages=%d shops=%d frames=%d customRenders=%d nvgCalls=%d", stagesPlayed, shopsVisited, frames, renders, Stubs.calls))
  App.GoTitle()
  assert(App.page == "title")
  frame(5)
end)

test("弹窗：设置 / 手动保存 / 图鉴 / 放弃", function()
  local R = App._refs
  App.OpenSettings(); App.ManualSave(); frame(2); R.dlgSettings:Close()
  App.OpenCodex(); App.SetCodexTab("charm"); App.SelectCodex(5); frame(2); App.SetCodexTab("ball"); R.dlgCodex:Close()
  App.StartRun(); frame(30)
  App.OpenSettings(); R.dlgSettings:Close()
  App.AbandonRun()
  assert(App.page == "title" and App.run == nil)
end)

log("== 3. 极值态渲染 ==")
test("超大数字 / 777 FEVER / 听牌 / 头目铁壁", function()
  App.StartRun()
  local st = App.stage
  App.Launch(); frame(40)
  st.chips, st.mult = 12345678901234, 98765.4
  st:_startFever(true)
  st.slot.holds = { { lucky = false }, { lucky = true } }
  frame(20)
  st.slot.spin = { t = 0.9, res = { "seven", "seven", "bell" }, reach = true, jackpot = false, super = false,
    stop = { 0.45, 0.75, 2.05 }, stopped = 2, reachAnnounced = true }
  App.fx.reachT = 1.5
  App.fx:Settle(1e9, 1e5, 1e14, true)
  frame(30)
  -- 头目台
  App.run.ante, App.run.stageIdx = 3, 3
  App.run.bosses[3] = "wall"
  App.EnterStage()
  assert(App.stage.startBlocked)
  frame(10)
  App.Launch(); frame(200)
  App.AbandonRun()
end)

log("== 4. 存档 ==")
test("Run 序列化往返 + 断点续玩", function()
  App.StartRun()
  App.Launch(); frame(60 * 25)
  App.SaveLocal()
  local env = Save.LoadLocal()
  assert(env and env.body and env.body.run, "no run in local save")
  local Run = require("Game/Run")
  local r2 = Run.Deserialize(env.body.run)
  assert(r2 and #r2.bag == #App.run.bag and r2.ante == App.run.ante)
  App.savedRun = env.body.run
  App.run = nil
  App.ContinueRun()
  assert(App.run and (App.page == "game" or App.page == "shop"))
  frame(30)
  App.AbandonRun()
end)

test("云端领先 → 采用云档并写回本地", function()
  local cjson = require("cjson")
  Stubs.files = {}
  local cloudEnv = { version = 1, savedAt = os.time() + 100, saveSeq = 9, body = { meta = { bestAnte = 5, runs = 3, discovered = {} } } }
  Stubs.InstallCloud("ok", { values = { save_body = cjson.encode(cloudEnv) }, iscores = { has_save = 1 } })
  local picked
  Save.Startup({ onReady = function(e) picked = e end, onCloudFail = function() error("should not fail") end })
  assert(picked and picked.body.meta.bestAnte == 5, "cloud not adopted")
  assert(Save.cloudState == "ready")
  assert(Stubs.files[C.SAVE.localFile], "not written back to local")
end)

test("无本地档 + 云读取失败 → 弹窗，不建新号", function()
  Stubs.files = {}
  Stubs.InstallCloud("error")
  local failedCalled, readyCalled = false, false
  Save.Startup({ onReady = function() readyCalled = true end, onCloudFail = function() failedCalled = true end })
  assert(failedCalled and not readyCalled)
  assert(Save.cloudState == "failed")
  assert(not Stubs.files[C.SAVE.localFile], "must not write a new profile")
end)

test("云请求超时 10 秒看门狗", function()
  Stubs.files = {}
  Stubs.InstallCloud("hang")
  local failedCalled = false
  Save.Startup({ onReady = function() end, onCloudFail = function() failedCalled = true end })
  for _ = 1, 60 * 11 do Save.Update(1 / 60, false, App.CollectSave) end
  assert(failedCalled, "timeout not fired")
end)

test("UI 流程中云读取失败弹窗可见", function()
  Stubs.files = {}
  Stubs.InstallCloud("error")
  App.Boot()
  assert(App._refs.dlgCloudFail.isOpen)
  App._refs.dlgCloudFail:Close()
  _G.clientCloud = nil
end)

realPrint(string.format("\n结果：%d 通过，%d 失败", passed, failed))
os.exit(failed == 0 and 0 or 1)
