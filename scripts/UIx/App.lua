-- ============================================================================
-- App.lua · 界面与流程总控
--
-- 状态机：title（标题/选台主）→ game（局内）→ shop（商店）→ game ... → 结算弹窗 → title
-- UI 铁律：整棵控件树在 Build() 时一次性创建；之后只 Show/Hide + SetText/SetStyle。
-- 弹窗为自建 Dialog（半透明微暗遮罩 Alpha 120，卡体阻止冒泡，固定高度 0 抖动）。
-- ============================================================================

local UI = require("urhox-libs/UI")
local C = require("Game/Config")
local Run = require("Game/Run")
local Stage = require("Game/Stage")
local Save = require("Game/Save")
local Skin = require("UIx/Skin")
local FX = require("Render/FX")
local W = require("Render/Widgets")

local App = {}

local S = Skin.C
local FS = Skin.FS

-- 运行状态
App.page = "title"
App.run = nil
App.stage = nil
App.fx = nil
App.audio = nil
App.speed = 1
App.paused = false
App.meta = { bestAnte = 0, wins = 0, runs = 0, bestLaunch = 0, discovered = {} }
App.selectedStarter = 1
App.pendingResult = nil   -- { kind = "cleared"|"failed", t = delay }

local refs = {}           -- 控件引用
local shown = {}          -- 上次显示的值（脏检查）

-- ---------------------------------------------------------------------------
-- 小工具
-- ---------------------------------------------------------------------------
local function setText(key, label, text)
    if shown[key] ~= text then
        shown[key] = text
        label:SetText(text)
    end
end

local function Lbl(text, size, color, extra)
    local p = { text = text, fontSize = size or FS.body, fontColor = color or S.text }
    if extra then for k, v in pairs(extra) do p[k] = v end end
    return UI.Label(p)
end

local function stopProp(w, e)
    if e and e.StopPropagation then e:StopPropagation() end
end

local function pressFx(props)
    props.transition = "scale 0.1s easeOut"
    props.onPointerDown = function(e, w) w:SetStyle({ scale = 0.94 }) end
    props.onPointerUp = function(e, w) w:SetStyle({ scale = 1.0 }) end
    props.onPointerLeave = function(e, w) w:SetStyle({ scale = 1.0 }) end
    return props
end

local function Btn(text, variant, onClick, extra)
    local p = pressFx({
        text = text, variant = variant or "secondary", fontSize = FS.button, minHeight = 44,
        paddingHorizontal = 12,
        onClick = function(w, e)
            if App.audio then App.audio:Unlock(); App.audio:Play("click") end
            onClick(w, e)
        end,
    })
    if extra then for k, v in pairs(extra) do p[k] = v end end
    return UI.Button(p)
end

local function GearButton(onClick)
    return UI.Panel(pressFx({
        width = 44, height = 44, borderRadius = 22, backgroundColor = S.panelHi,
        justifyContent = "center", alignItems = "center",
        onClick = function() if App.audio then App.audio:Unlock() end onClick() end,
        children = { W.ArtIcon { icon = "gear", width = 26, height = 26 } },
    }))
end

local function CoinTag()
    local label = Lbl("0", 18, S.gold, { fontWeight = "bold" })
    local row = UI.Row {
        alignItems = "center", gap = 4, height = 36, paddingHorizontal = 10, borderRadius = 18,
        backgroundColor = { 0, 0, 0, 120 },
        children = { W.ArtIcon { icon = "coin", width = 22, height = 22 }, label },
    }
    return row, label
end

-- ---------------------------------------------------------------------------
-- Dialog：自建弹窗
-- ---------------------------------------------------------------------------
local Dialog = {}
Dialog.__index = Dialog

--- opts: title, height, body, footer, closeOnOverlay, showClose
local function NewDialog(opts)
    local d = setmetatable({}, Dialog)
    d.titleLabel = Lbl(opts.title or "", FS.title, S.text, { fontWeight = "bold", flexGrow = 1, flexShrink = 1, maxLines = 1 })
    local header = UI.Row {
        width = "100%", height = 44, alignItems = "center", gap = 8, flexShrink = 0,
        children = { d.titleLabel },
    }
    if opts.showClose ~= false then
        header:AddChild(UI.Panel(pressFx({
            width = 44, height = 44, borderRadius = 22, backgroundColor = S.panelHi,
            justifyContent = "center", alignItems = "center",
            onClick = function(w, e) stopProp(w, e); d:Close() end,
            children = { Lbl("×", 22, S.text, { fontWeight = "bold" }) },
        })))
    end
    local children = { header }
    if opts.body then
        opts.body:SetStyle({ flexGrow = 1, flexBasis = 0, flexShrink = 1, minHeight = 0, width = "100%" })
        children[#children + 1] = opts.body
    end
    if opts.footer then
        opts.footer:SetStyle({ flexShrink = 0, width = "100%" })
        children[#children + 1] = opts.footer
    end
    d.card = UI.Panel {
        width = "90%", height = opts.height or 420,
        backgroundColor = { 30, 22, 52, 250 }, borderRadius = 18,
        borderTopWidth = 2, borderLeftWidth = 2, borderRightWidth = 2, borderBottomWidth = 4,
        borderColor = S.line,
        padding = 14, flexDirection = "column", gap = 10,
        onClick = stopProp,
        children = children,
    }
    d.overlay = UI.Panel {
        position = "absolute", top = 0, left = 0, width = "100%", height = "100%",
        backgroundColor = S.overlay, justifyContent = "center", alignItems = "center",
        onClick = function()
            if opts.closeOnOverlay then d:Close() end
        end,
        children = { d.card },
    }
    d.overlay:Hide()
    d.onClose = opts.onClose
    return d
end

function Dialog:Open()
    self.overlay:Show()
    self.card:Animate({
        keyframes = { [0] = { scale = 0.86, opacity = 0 }, [1] = { scale = 1, opacity = 1 } },
        duration = 0.22, easing = "easeOutBack", fillMode = "forwards",
    })
    self.isOpen = true
end

function Dialog:Close()
    if not self.isOpen then return end
    self.isOpen = false
    self.overlay:Hide()
    if self.onClose then self.onClose() end
end

function Dialog:SetTitle(t) self.titleLabel:SetText(t) end

-- ---------------------------------------------------------------------------
-- 网格（手写 row + flexGrow，避免依赖 SimpleGrid 细节）
-- ---------------------------------------------------------------------------
local function Grid(cells, cols, gap)
    local rows = {}
    local i = 1
    while i <= #cells do
        local row = UI.Row { width = "100%", gap = gap, children = {} }
        for c = 1, cols do
            local cell = cells[i]
            if cell then
                row:AddChild(cell)
            else
                row:AddChild(UI.Panel { flexGrow = 1, flexBasis = 0 })   -- 占位，保持等宽
            end
            i = i + 1
        end
        rows[#rows + 1] = row
    end
    return UI.Column { width = "100%", gap = gap, children = rows }
end

--- 通用"大图 + 短名 + 一个数字"格子
local function ItemCell(onClick)
    local icon = W.ArtIcon { flexGrow = 1, flexBasis = 0, width = "100%" }
    local name = Lbl("", 13, S.text, { fontWeight = "bold", flexShrink = 1, maxLines = 1 })
    local value = Lbl("", 13, S.gold, { fontWeight = "bold" })
    local cell = UI.Panel(pressFx({
        flexGrow = 1, flexBasis = 0, aspectRatio = 1, borderRadius = 12, padding = 6,
        backgroundColor = { 44, 34, 76, 255 },
        borderTopWidth = 2, borderLeftWidth = 2, borderRightWidth = 2, borderBottomWidth = 2,
        borderColor = { 70, 56, 120, 255 },
        flexDirection = "column", alignItems = "center",
        onClick = onClick,
        children = {
            icon,
            UI.Row { width = "100%", height = 18, alignItems = "center", gap = 2,
                children = { name, UI.Spacer(), value } },
        },
    }))
    return { cell = cell, icon = icon, name = name, value = value }
end

local function setCellSelected(c, on)
    if c.selected == on then return end
    c.selected = on
    c.cell:SetStyle({ borderColor = on and { 255, 210, 80, 255 } or { 70, 56, 120, 255 },
        backgroundColor = on and { 62, 48, 104, 255 } or { 44, 34, 76, 255 } })
end

-- ---------------------------------------------------------------------------
-- 护符栏（局内 / 商店各一份，预建 5 格）
-- ---------------------------------------------------------------------------
local function CharmBar(key)
    local slots = {}
    local cells = {}
    for i = 1, C.MAX_CHARMS do
        local icon = W.ArtIcon { width = "100%", height = "100%" }
        local cell = UI.Panel(pressFx({
            flexGrow = 1, flexBasis = 0, height = 48, borderRadius = 10, padding = 3,
            backgroundColor = { 0, 0, 0, 90 },
            borderTopWidth = 1, borderLeftWidth = 1, borderRightWidth = 1, borderBottomWidth = 1,
            borderColor = { 90, 70, 150, 200 },
            onClick = function() App.OpenCharm(i) end,
            children = { icon },
        }))
        slots[i] = { cell = cell, icon = icon, id = nil }
        cells[i] = cell
    end
    refs[key] = slots
    return UI.Row { width = "100%", gap = 6, height = 48, flexShrink = 0, children = cells }
end

local function RefreshCharmBar(key)
    local slots = refs[key]
    if not slots or not App.run then return end
    for i, s in ipairs(slots) do
        local id = App.run.charms[i]
        if s.id ~= id then
            s.id = id
            s.icon:SetIcon(id and "charm" or nil, id)
            s.cell:SetStyle({ opacity = id and 1 or 0.45 })
        end
    end
end

local lastPulse = {}
local function PulseCharm(id)
    for _, key in ipairs({ "charmsGame", "charmsShop" }) do
        local slots = refs[key]
        if slots then
            for _, s in ipairs(slots) do
                if s.id == id then
                    local now = W.time
                    if not lastPulse[id] or now - lastPulse[id] > 0.15 then
                        lastPulse[id] = now
                        s.cell:Animate({
                            keyframes = { [0] = { scale = 1, rotate = 0 }, [0.35] = { scale = 1.22, rotate = -8 }, [1] = { scale = 1, rotate = 0 } },
                            duration = 0.32, easing = "easeOut",
                        })
                    end
                end
            end
        end
    end
end

-- ===========================================================================
-- 标题页
-- ===========================================================================
local function starterUnlocked(st)
    if not st.unlock then return true end
    return (App.meta.bestAnte or 0) >= (st.unlock.bestAnte or 0)
end

local function BuildTitle()
    local cards = {}
    refs.starters = {}
    for i, st in ipairs(C.STARTERS) do
        local icon = W.ArtIcon { icon = "portrait", iconId = st.key, flexGrow = 1, flexBasis = 0, width = "100%" }
        local name = Lbl(st.name, FS.button, S.text, { fontWeight = "bold" })
        local card = UI.Panel(pressFx({
            flexGrow = 1, flexBasis = 0, aspectRatio = 0.82, borderRadius = 14, padding = 6,
            backgroundColor = { 44, 34, 76, 255 },
            borderTopWidth = 2, borderLeftWidth = 2, borderRightWidth = 2, borderBottomWidth = 2,
            borderColor = { 70, 56, 120, 255 },
            flexDirection = "column", alignItems = "center", gap = 2,
            onClick = function() App.SelectStarter(i) end,
            children = { icon, name },
        }))
        refs.starters[i] = { cell = card, icon = icon, name = name }
        cards[i] = card
    end
    refs.starterDesc = Lbl("", FS.body, S.textDim, { width = "100%", textAlign = "center", whiteSpace = "normal", maxLines = 2 })
    refs.bestLabel = Lbl("", FS.caption, S.textDim, { width = "100%", textAlign = "center", maxLines = 1 })
    refs.btnContinue = Btn("继续", "primary", function() App.ContinueRun() end, { flexGrow = 2, flexBasis = 0 })
    refs.btnNew = Btn("开局", "primary", function() App.StartRun() end, { flexGrow = 2, flexBasis = 0 })

    return UI.Panel {
        position = "absolute", top = 0, left = 0, width = "100%", height = "100%",
        flexDirection = "column", padding = 16, gap = 12, alignItems = "center",
        children = {
            UI.Row { width = "100%", height = 44, alignItems = "center", paddingRight = 112, flexShrink = 0,
                children = { GearButton(function() App.OpenSettings() end), UI.Spacer() } },
            W.LogoArt { width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 180 },
            Lbl("选择台主", FS.title, S.text, { fontWeight = "bold" }),
            UI.Row { width = "100%", gap = 10, flexShrink = 0, children = cards },
            UI.Panel { width = "100%", height = 44, justifyContent = "center", flexShrink = 0, children = { refs.starterDesc } },
            UI.Row { width = "100%", gap = 12, flexShrink = 0, children = {
                Btn("图鉴", "secondary", function() App.OpenCodex() end, { flexGrow = 1, flexBasis = 0 }),
                refs.btnNew, refs.btnContinue,
            } },
            refs.bestLabel,
        },
    }
end

function App.SelectStarter(i)
    App.selectedStarter = i
    App.RefreshTitle()
end

function App.RefreshTitle()
    for i, r in ipairs(refs.starters) do
        local st = C.STARTERS[i]
        local unlocked = starterUnlocked(st)
        r.icon:SetIcon("portrait", st.key, not unlocked)
        local sel = (i == App.selectedStarter)
        r.cell:SetStyle({ borderColor = sel and { 255, 210, 80, 255 } or { 70, 56, 120, 255 },
            backgroundColor = sel and { 62, 48, 104, 255 } or { 44, 34, 76, 255 } })
    end
    local st = C.STARTERS[App.selectedStarter]
    if starterUnlocked(st) then
        setText("starterDesc", refs.starterDesc, st.title .. " · " .. st.desc)
        refs.btnNew:SetDisabled(false)
    else
        setText("starterDesc", refs.starterDesc, "到达第 " .. st.unlock.bestAnte .. " 层解锁")
        refs.btnNew:SetDisabled(true)
    end
    local hasRun = App.savedRun ~= nil
    refs.btnContinue:SetVisible(hasRun)
    refs.btnNew:SetText(hasRun and "新局" or "开局")
    local m = App.meta
    setText("best", refs.bestLabel, string.format("最佳 第%d层 · 最高单发 %s · 通关 %d", m.bestAnte or 0, Skin.Num(m.bestLaunch or 0), m.wins or 0))
end

-- ===========================================================================
-- 局内页
-- ===========================================================================
local function BuildGame()
    refs.stageLabel = Lbl("", FS.button, S.text, { fontWeight = "bold", flexShrink = 1, maxLines = 1 })
    local coinRow
    coinRow, refs.coinGame = CoinTag()
    refs.scoreBar = W.ScoreBar { width = "100%", height = 64, flexShrink = 0 }
    refs.board = W.BoardView { width = "100%", flexGrow = 1, flexBasis = 0 }

    -- 发射次数灯
    refs.dots = {}
    local dots = {}
    for i = 1, 6 do
        local d = UI.Panel { width = 12, height = 12, borderRadius = 6, backgroundColor = S.gold }
        refs.dots[i] = d
        dots[i] = d
    end
    refs.bagCount = Lbl("12", 13, S.text, { fontWeight = "bold" })
    refs.btnLaunch = UI.Button(pressFx({
        text = "大力干!", variant = "primary", fontSize = 22, minHeight = 56, flexGrow = 1, flexBasis = 0,
        onClick = function() App.Launch() end,
    }))
    refs.btnSpeed = Btn("×1", "secondary", function() App.ToggleSpeed() end, { width = 60 })

    return UI.Panel {
        position = "absolute", top = 0, left = 0, width = "100%", height = "100%",
        flexDirection = "column", padding = 8, gap = 6,
        children = {
            UI.Row { width = "100%", height = 44, alignItems = "center", gap = 8, paddingRight = 112, flexShrink = 0,
                children = { GearButton(function() App.OpenSettings() end), refs.stageLabel, UI.Spacer(), coinRow } },
            refs.scoreBar,
            refs.board,
            CharmBar("charmsGame"),
            UI.Row { width = "100%", height = 60, gap = 8, alignItems = "center", flexShrink = 0, children = {
                UI.Panel(pressFx({
                    width = 60, height = 56, borderRadius = 12, backgroundColor = S.panelHi,
                    alignItems = "center", justifyContent = "center",
                    onClick = function() App.OpenBag() end,
                    children = { W.ArtIcon { icon = "ball", iconId = "steel", width = 34, height = 34 }, refs.bagCount },
                })),
                UI.Column { width = 44, gap = 4, alignItems = "center", justifyContent = "center", children = {
                    UI.Row { gap = 4, children = { dots[1], dots[2], dots[3] } },
                    UI.Row { gap = 4, children = { dots[4], dots[5], dots[6] } },
                } },
                refs.btnLaunch,
                refs.btnSpeed,
            } },
        },
    }
end

function App.RefreshHUD()
    local run, st = App.run, App.stage
    if not run then return end
    if shown.coinsN ~= run.coins then
        shown.coinsN = run.coins
        local txt = tostring(run.coins)
        refs.coinGame:SetText(txt)
        refs.coinShop:SetText(txt)
    end
    if st then
        local info = st.info
        if shown.stageObj ~= st then
            shown.stageObj = st
            refs.stageLabel:SetText(info.ante .. "-" .. info.idx .. " " .. info.kindName .. (info.boss and (" · " .. C.BOSSES[info.boss].name) or ""))
        end
        local total = st.stats.launches
        if shown.dotsLeft ~= st.launchesLeft or shown.dotsTotal ~= total then
            shown.dotsLeft, shown.dotsTotal = st.launchesLeft, total
            for i, d in ipairs(refs.dots) do
                d:SetVisible(i <= total)
                d:SetStyle({ backgroundColor = (i <= st.launchesLeft) and S.gold or S.disabled })
            end
        end
        local can = st:CanLaunch() and not App.pendingResult
        if shown.canLaunch ~= can then
            shown.canLaunch = can
            refs.btnLaunch:SetDisabled(not can)
            refs.btnLaunch:SetText(can and "大力干!" or "天意中…")
        end
    end
    if shown.bagN ~= #run.bag then
        shown.bagN = #run.bag
        refs.bagCount:SetText(tostring(#run.bag))
    end
    RefreshCharmBar("charmsGame")
end

-- ===========================================================================
-- 商店页
-- ===========================================================================
local function BuildShop()
    local coinRow
    coinRow, refs.coinShop = CoinTag()
    refs.shopNext = Lbl("", FS.body, S.textDim, { width = "100%", maxLines = 1 })
    refs.shopCells = {}
    local cells = {}
    for i = 1, 6 do
        local c = ItemCell(function() App.SelectShop(i) end)
        refs.shopCells[i] = c
        cells[i] = c.cell
    end
    -- 详情区（固定高度：头 + 滚动说明 + 底部动作）
    refs.detIcon = W.ArtIcon { width = "100%", height = "100%" }
    refs.detName = Lbl("", 18, S.text, { fontWeight = "bold", flexShrink = 1, maxLines = 1 })
    refs.detType = Lbl("", 12, S.textDim, {})
    refs.detDesc = Lbl("", FS.body, S.text, { width = "100%", whiteSpace = "normal", lineHeight = 1.4 })
    refs.btnBuy = Btn("购买", "primary", function() App.BuyShop() end, { width = "100%" })
    local detail = UI.Row {
        width = "100%", height = 156, gap = 10, padding = 10, borderRadius = 14, flexShrink = 0,
        backgroundColor = { 0, 0, 0, 90 },
        children = {
            UI.Panel { width = "40%", height = "100%", borderRadius = 12, backgroundColor = { 60, 46, 100, 180 },
                children = { refs.detIcon } },
            UI.Column { flexGrow = 1, flexBasis = 0, height = "100%", gap = 4, children = {
                UI.Row { width = "100%", height = 24, alignItems = "center", gap = 6, flexShrink = 0,
                    children = { refs.detName, UI.Spacer(), refs.detType } },
                UI.ScrollView { width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 0, scrollY = true,
                    children = { refs.detDesc } },
                refs.btnBuy,
            } },
        },
    }
    refs.btnReroll = Btn("刷新", "secondary", function() App.RerollShop() end, { flexGrow = 1, flexBasis = 0 })
    return UI.Panel {
        position = "absolute", top = 0, left = 0, width = "100%", height = "100%",
        flexDirection = "column", padding = 12, gap = 8,
        children = {
            UI.Row { width = "100%", height = 44, alignItems = "center", gap = 8, paddingRight = 112, flexShrink = 0,
                children = { GearButton(function() App.OpenSettings() end),
                    Lbl("弹珠商店", FS.title, S.text, { fontWeight = "bold" }), UI.Spacer(), coinRow } },
            refs.shopNext,
            Grid(cells, 3, 8),
            detail,
            CharmBar("charmsShop"),
            UI.Spacer(),
            UI.Row { width = "100%", gap = 8, flexShrink = 0, children = {
                Btn("珠袋", "secondary", function() App.OpenBag() end, { flexGrow = 1, flexBasis = 0 }),
                refs.btnReroll,
                Btn("出发", "primary", function() App.LeaveShop() end, { flexGrow = 2, flexBasis = 0 }),
            } },
        },
    }
end

local function itemDef(it)
    if it.type == "ball" then return C.BALLS[it.id] elseif it.type == "charm" then return C.CHARMS[it.id] end
    return C.MODS[it.id]
end

local TYPE_NAME = { ball = "珠子", charm = "护符", mod = "改造" }

function App.RefreshShop()
    local run = App.run
    if not run or not run.shop then return end
    -- 下一台信息（商店时 stageIdx 尚未推进，预览下一台）
    local na, ni = run.ante, run.stageIdx + 1
    if ni > 3 then na, ni = na + 1, 1 end
    local target = math.floor((C.ANTE_TARGETS[na] or 0) * C.STAGE_KINDS[ni].mul)
    setText("shopNext", refs.shopNext, string.format("下一台 %d-%d %s · 目标 %s", na, ni, C.STAGE_KINDS[ni].name, Skin.Num(target)))
    for i, c in ipairs(refs.shopCells) do
        local it = run.shop[i]
        if it then
            c.cell:SetVisible(true)
            local def = itemDef(it)
            c.icon:SetIcon(it.type, it.id, false)
            c.name:SetText(def.name)
            c.value:SetText(it.sold and "已售" or ("$" .. it.price))
            c.cell:SetStyle({ opacity = it.sold and 0.45 or 1 })
            setCellSelected(c, i == App.shopSel)
        else
            c.cell:SetStyle({ opacity = 0 })
        end
    end
    local it = run.shop[App.shopSel]
    if it then
        local def = itemDef(it)
        refs.detIcon:SetIcon(it.type, it.id, false)
        refs.detName:SetText(def.name)
        refs.detType:SetText(TYPE_NAME[it.type] .. (def.rarity and ({ " · 普通", " · 稀有", " · 传说" })[def.rarity] or ""))
        local extra = ""
        if it.type == "ball" then extra = "\n珠袋内已有 " .. run:CountBag(it.id) .. " 颗" end
        refs.detDesc:SetText(def.desc .. extra)
        local ok, why = run:CanBuy(App.shopSel)
        refs.btnBuy:SetDisabled(not ok)
        refs.btnBuy:SetText(ok and ("购买 $" .. it.price) or why)
    end
    refs.btnReroll:SetText("刷新 $" .. run.rerollCost)
    refs.btnReroll:SetDisabled(run.coins < run.rerollCost)
    if shown.coinsN ~= run.coins then
        shown.coinsN = run.coins
        local txt = tostring(run.coins)
        refs.coinShop:SetText(txt)
        refs.coinGame:SetText(txt)
    end
    RefreshCharmBar("charmsShop")
end

function App.SelectShop(i)
    App.shopSel = i
    App.RefreshShop()
end

function App.BuyShop()
    local run = App.run
    refs.btnBuy:SetDisabled(true)   -- 防连点
    local it = run.shop[App.shopSel]
    if run:Buy(App.shopSel) then
        if App.audio then App.audio:Play("buy") end
        App.meta.discovered[it.type .. ":" .. it.id] = true
        local c = refs.shopCells[App.shopSel]
        c.cell:Animate({ keyframes = { [0] = { scale = 1 }, [0.4] = { scale = 1.12 }, [1] = { scale = 1 } }, duration = 0.25 })
        App.SaveLocal()
    end
    App.RefreshShop()
end

function App.RerollShop()
    if App.run:Reroll() then
        App.shopSel = 1
        App.RefreshShop()
    end
end

function App.LeaveShop()
    App.run:NextStage()
    App.EnterStage()
end

-- ===========================================================================
-- 弹窗们
-- ===========================================================================
local function BuildDialogs(root)
    -- 过关结算
    refs.clearRows = {}
    local rows = {}
    local names = { "过关奖励", "剩余发射", "利息", "额外" }
    for i = 1, 4 do
        local v = Lbl("", 18, S.gold, { fontWeight = "bold" })
        local r = UI.Row { width = "100%", height = 32, alignItems = "center", children = {
            Lbl(names[i], FS.button, S.textDim), UI.Spacer(), v } }
        refs.clearRows[i] = { row = r, value = v }
        rows[i] = r
    end
    refs.clearTotal = Lbl("", 36, S.gold, { fontWeight = "bold", textStroke = { width = 2, color = "#3A1A00" } })
    refs.clearScore = Lbl("", FS.body, S.textDim, { width = "100%", textAlign = "center" })
    rows[#rows + 1] = UI.Panel { width = "100%", height = 2, backgroundColor = S.line }
    rows[#rows + 1] = UI.Row { width = "100%", justifyContent = "center", alignItems = "center", gap = 8, children = {
        W.ArtIcon { icon = "coin", width = 36, height = 36 }, refs.clearTotal } }
    rows[#rows + 1] = refs.clearScore
    refs.dlgClear = NewDialog({
        title = "过关!", height = 400, showClose = false,
        body = UI.Column { gap = 6, children = rows },
        footer = UI.Row { justifyContent = "center", children = {
            Btn("去商店", "primary", function() App.GoShop() end, { width = "58%", minWidth = 148 }) } },
    })

    -- 结局（失败 / 通关）
    refs.endStats = {}
    local statCells = {}
    local statNames = { "到达", "最高单发", "大当次数", "最高连击" }
    for i = 1, 4 do
        local v = Lbl("", 24, S.text, { fontWeight = "bold" })
        statCells[i] = UI.Panel { flexGrow = 1, flexBasis = 0, height = 76, borderRadius = 12, backgroundColor = { 0, 0, 0, 90 },
            alignItems = "center", justifyContent = "center", gap = 2, children = { v, Lbl(statNames[i], FS.caption, S.textDim) } }
        refs.endStats[i] = v
    end
    refs.endSub = Lbl("", FS.body, S.textDim, { width = "100%", textAlign = "center", whiteSpace = "normal", maxLines = 2 })
    refs.dlgEnd = NewDialog({
        title = "", height = 420, showClose = false,
        body = UI.Column { gap = 10, children = { refs.endSub, Grid(statCells, 2, 8) } },
        footer = UI.Row { gap = 12, children = {
            Btn("回主页", "secondary", function() App.GoTitle() end, { flexGrow = 1, flexBasis = 0 }),
            Btn("再来", "primary", function() refs.dlgEnd:Close(); App.StartRun() end, { flexGrow = 2, flexBasis = 0 }),
        } },
    })

    -- 护符详情
    refs.charmIcon = W.ArtIcon { width = "100%", height = "100%" }
    refs.charmName = Lbl("", FS.title, S.text, { fontWeight = "bold", maxLines = 1 })
    refs.charmDesc = Lbl("", FS.button, S.text, { width = "100%", whiteSpace = "normal", lineHeight = 1.4 })
    refs.btnSell = Btn("卖出", "danger", function() App.SellCharm() end, { flexGrow = 1, flexBasis = 0 })
    refs.dlgCharm = NewDialog({
        title = "护符", height = 330, closeOnOverlay = true,
        body = UI.Row { gap = 12, children = {
            UI.Panel { width = "42%", height = "100%", borderRadius = 14, backgroundColor = { 60, 46, 100, 180 }, children = { refs.charmIcon } },
            UI.Column { flexGrow = 1, flexBasis = 0, gap = 8, children = { refs.charmName, refs.charmDesc } },
        } },
        footer = UI.Row { gap = 12, children = {
            refs.btnSell,
            Btn("知道了", "primary", function() refs.dlgCharm:Close() end, { flexGrow = 1, flexBasis = 0 }),
        } },
    })

    -- 珠袋
    refs.bagCells = {}
    local bagCells = {}
    for i, kind in ipairs(C.BALL_ORDER) do
        local c = ItemCell(function() App.SelectBag(i) end)
        refs.bagCells[i] = c
        bagCells[i] = c.cell
        c.icon:SetIcon("ball", kind, false)
        c.name:SetText(C.BALLS[kind].name)
    end
    refs.bagInfo = Lbl("", FS.body, S.textDim, { width = "100%", maxLines = 1 })
    refs.bagDet = Lbl("", FS.body, S.text, { width = "100%", whiteSpace = "normal", maxLines = 3 })
    refs.dlgBag = NewDialog({
        title = "珠袋", height = "84%", closeOnOverlay = true,
        body = UI.Column { gap = 8, children = {
            refs.bagInfo,
            UI.ScrollView { width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 0, scrollY = true, children = { Grid(bagCells, 3, 8) } },
            UI.Panel { width = "100%", height = 72, padding = 8, borderRadius = 12, backgroundColor = { 0, 0, 0, 90 }, flexShrink = 0,
                children = { refs.bagDet } },
        } },
        footer = UI.Row { justifyContent = "center", children = {
            Btn("关闭", "primary", function() refs.dlgBag:Close() end, { width = "50%", minWidth = 148 }) } },
    })

    -- 设置
    refs.togMusic = UI.Toggle { checked = Save.prefs.music, onChange = function(_, v) App.SetMusic(v) end }
    refs.togSfx = UI.Toggle { checked = Save.prefs.sfx, onChange = function(_, v) App.SetSfx(v) end }
    refs.saveLocal = Lbl("", FS.body, S.textDim)
    refs.saveCloud = Lbl("", FS.body, S.textDim)
    refs.btnAbandon = Btn("放弃本局", "danger", function() refs.dlgSettings:Close(); refs.dlgConfirm:Open() end, { flexGrow = 1, flexBasis = 0 })
    local function settingRow(name, right)
        return UI.Row { width = "100%", height = 48, alignItems = "center", paddingHorizontal = 4, children = {
            Lbl(name, FS.button, S.text), UI.Spacer(), right } }
    end
    refs.dlgSettings = NewDialog({
        title = "设置", height = 440, closeOnOverlay = true,
        body = UI.Column { gap = 6, children = {
            settingRow("音乐", refs.togMusic),
            settingRow("音效", refs.togSfx),
            UI.Panel { width = "100%", height = 2, backgroundColor = S.line },
            UI.Row { width = "100%", height = 30, alignItems = "center", children = { Lbl("本地", FS.body, S.text), UI.Spacer(), refs.saveLocal } },
            UI.Row { width = "100%", height = 30, alignItems = "center", children = { Lbl("云端", FS.body, S.text), UI.Spacer(), refs.saveCloud } },
            Btn("保存游戏", "secondary", function() App.ManualSave() end, { width = "100%" }),
        } },
        footer = UI.Row { gap = 12, children = {
            refs.btnAbandon,
            Btn("关闭", "primary", function() refs.dlgSettings:Close() end, { flexGrow = 1, flexBasis = 0 }),
        } },
        onClose = function() App.SetPaused(false) end,
    })

    -- 放弃确认
    refs.dlgConfirm = NewDialog({
        title = "放弃本局？", height = 220, showClose = false,
        body = UI.Column { justifyContent = "center", children = { Lbl("进度不保存", FS.body, S.textDim, { width = "100%", textAlign = "center" }) } },
        footer = UI.Row { gap = 12, children = {
            Btn("取消", "secondary", function() refs.dlgConfirm:Close() end, { flexGrow = 1, flexBasis = 0 }),
            Btn("放弃", "danger", function() refs.dlgConfirm:Close(); App.AbandonRun() end, { flexGrow = 1, flexBasis = 0 }),
        } },
    })

    -- 图鉴
    refs.codexTab = "ball"
    refs.codexCells = {}
    local cdx = {}
    for i = 1, 16 do
        local c = ItemCell(function() App.SelectCodex(i) end)
        refs.codexCells[i] = c
        cdx[i] = c.cell
    end
    refs.codexTabs = {}
    local function tab(key, text)
        local lbl = Lbl(text, FS.button, S.text, { fontWeight = "bold" })
        local p = UI.Panel(pressFx({ flexGrow = 1, flexBasis = 0, height = 40, borderRadius = 20, alignItems = "center", justifyContent = "center",
            backgroundColor = S.panelHi, onClick = function() App.SetCodexTab(key) end, children = { lbl } }))
        refs.codexTabs[key] = p
        return p
    end
    refs.codexDet = Lbl("", FS.body, S.text, { width = "100%", whiteSpace = "normal", maxLines = 3 })
    refs.dlgCodex = NewDialog({
        title = "图鉴", height = "86%", closeOnOverlay = true,
        body = UI.Column { gap = 8, children = {
            UI.Row { width = "100%", gap = 8, flexShrink = 0, children = { tab("ball", "珠子"), tab("charm", "护符") } },
            UI.ScrollView { width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 0, scrollY = true, children = { Grid(cdx, 4, 6) } },
            UI.Panel { width = "100%", height = 72, padding = 8, borderRadius = 12, backgroundColor = { 0, 0, 0, 90 }, flexShrink = 0,
                children = { refs.codexDet } },
        } },
        footer = UI.Row { justifyContent = "center", children = {
            Btn("关闭", "primary", function() refs.dlgCodex:Close() end, { width = "50%", minWidth = 148 }) } },
    })

    -- 云存档读取失败（防覆盖）
    refs.dlgCloudFail = NewDialog({
        title = "云存档读取失败", height = 260, showClose = false,
        body = UI.Column { justifyContent = "center", children = {
            Lbl("可能已有云存档，直接开新档会覆盖它", FS.body, S.textDim, { width = "100%", textAlign = "center", whiteSpace = "normal" }) } },
        footer = UI.Row { gap = 12, children = {
            Btn("开始新档", "secondary", function() refs.dlgCloudFail:Close(); Save.ConfirmNewProfile(); App.OnProfileReady(nil) end, { flexGrow = 1, flexBasis = 0 }),
            Btn("重试读取", "primary", function() refs.dlgCloudFail:Close(); App.Boot() end, { flexGrow = 1, flexBasis = 0 }),
        } },
    })

    for _, d in ipairs({ refs.dlgClear, refs.dlgEnd, refs.dlgCharm, refs.dlgBag, refs.dlgSettings, refs.dlgConfirm, refs.dlgCodex, refs.dlgCloudFail }) do
        root:AddChild(d.overlay)
    end
end

-- 护符详情
function App.OpenCharm(i)
    local id = App.run and App.run.charms[i]
    if not id then return end
    App.charmSel = i
    local def = C.CHARMS[id]
    refs.charmIcon:SetIcon("charm", id)
    refs.charmName:SetText(def.name)
    refs.charmDesc:SetText(def.desc)
    refs.btnSell:SetText("卖出 $" .. App.run:SellPrice(id))
    -- 局内飞珠时不允许卖
    local busy = App.page == "game" and App.stage and App.stage.phase ~= "idle"
    refs.btnSell:SetDisabled(busy)
    refs.dlgCharm:Open()
end

function App.SellCharm()
    if App.run:SellCharm(App.charmSel) then
        refs.dlgCharm:Close()
        App.RefreshHUD()
        if App.page == "shop" then App.RefreshShop() end
    end
end

-- 珠袋
function App.OpenBag()
    local run = App.run
    if not run then return end
    local mag = C.BASE_MAGAZINE + (run.mods.magazine or 0)
    refs.bagInfo:SetText(string.format("珠袋 %d 颗 · 每发装 %d 颗", #run.bag, mag))
    App.bagSel = App.bagSel or 1
    App.SelectBag(App.bagSel)
    refs.dlgBag:Open()
end

function App.SelectBag(i)
    App.bagSel = i
    local run = App.run
    for k, c in ipairs(refs.bagCells) do
        local kind = C.BALL_ORDER[k]
        local n = run and run:CountBag(kind) or 0
        c.value:SetText("×" .. n)
        c.cell:SetStyle({ opacity = n > 0 and 1 or 0.4 })
        setCellSelected(c, k == i)
    end
    local def = C.BALLS[C.BALL_ORDER[i]]
    refs.bagDet:SetText(def.name .. "：" .. def.desc)
end

-- 设置
function App.OpenSettings()
    App.SetPaused(true)
    refs.togMusic:SetChecked(Save.prefs.music)
    refs.togSfx:SetChecked(Save.prefs.sfx)
    refs.btnAbandon:SetDisabled(App.run == nil or App.page == "title")
    App.RefreshSaveLabels()
    refs.dlgSettings:Open()
end

function App.RefreshSaveLabels()
    if Save.localFail then
        refs.saveLocal:SetText("保存失败"); refs.saveLocal:SetFontColor(S.bad)
    else
        refs.saveLocal:SetText(Save.FormatTime(Save.localTime) or "未保存"); refs.saveLocal:SetFontColor(S.textDim)
    end
    if Save.cloudState == "off" then
        refs.saveCloud:SetText("未连接"); refs.saveCloud:SetFontColor(S.textDim)
    elseif Save.cloudFail or Save.cloudState == "failed" then
        refs.saveCloud:SetText("保存失败"); refs.saveCloud:SetFontColor(S.bad)
    else
        refs.saveCloud:SetText(Save.FormatTime(Save.cloudTime) or "未保存"); refs.saveCloud:SetFontColor(S.textDim)
    end
end

function App.ManualSave()
    Save.Commit(App.CollectSave, true, function()
        App.RefreshSaveLabels()
    end)
    App.RefreshSaveLabels()
end

function App.SetMusic(v)
    Save.prefs.music = v
    Save.SavePrefs()
    if App.audio then App.audio:SetMusic(v) end
end

function App.SetSfx(v)
    Save.prefs.sfx = v
    Save.SavePrefs()
    if App.audio then App.audio:SetSfx(v) end
end

-- 图鉴
function App.OpenCodex()
    App.SetCodexTab(refs.codexTab or "ball")
    refs.dlgCodex:Open()
end

local function codexList()
    return refs.codexTab == "ball" and C.BALL_ORDER or C.CHARM_ORDER
end

local function isDiscovered(kind, id)
    if kind == "ball" and id == "steel" then return true end
    return App.meta.discovered[kind .. ":" .. id] == true
end

function App.SetCodexTab(key)
    refs.codexTab = key
    for k, p in pairs(refs.codexTabs) do
        p:SetStyle({ backgroundColor = (k == key) and { 255, 170, 60, 255 } or S.panelHi })
    end
    local list = codexList()
    local found = 0
    for i, c in ipairs(refs.codexCells) do
        local id = list[i]
        if id then
            local disc = isDiscovered(key, id)
            if disc then found = found + 1 end
            c.cell:SetStyle({ opacity = 1 })
            c.icon:SetIcon(key, id, not disc)
            c.name:SetText(disc and (key == "ball" and C.BALLS[id] or C.CHARMS[id]).name or "？？")
            c.value:SetText("")
        else
            c.cell:SetStyle({ opacity = 0 })   -- 占位：保持网格总高度恒定
            c.icon:SetIcon(nil)
            c.name:SetText("")
            c.value:SetText("")
        end
    end
    refs.dlgCodex:SetTitle(string.format("图鉴 %d/%d", found, #list))
    App.SelectCodex(1)
end

function App.SelectCodex(i)
    local list = codexList()
    local id = list[i]
    if not id then return end
    for k, c in ipairs(refs.codexCells) do setCellSelected(c, k == i) end
    local key = refs.codexTab
    if isDiscovered(key, id) then
        local def = key == "ball" and C.BALLS[id] or C.CHARMS[id]
        refs.codexDet:SetText(def.name .. "：" .. def.desc)
    else
        refs.codexDet:SetText("未发现：在商店购买后解锁")
    end
end

-- ===========================================================================
-- 构建
-- ===========================================================================
function App.Build(audio)
    App.audio = audio
    App.fx = FX.new(audio)
    App.fx.listener = App.OnFxEvent
    W.app = App

    refs.pageTitle = BuildTitle()
    refs.pageGame = BuildGame()
    refs.pageShop = BuildShop()

    local root = UI.Panel {
        width = "100%", height = "100%", backgroundColor = S.bg,
        children = {
            UI.SafeAreaView { width = "100%", height = "100%", children = { refs.pageTitle, refs.pageGame, refs.pageShop } },
        },
    }
    BuildDialogs(root)
    refs.root = root
    App._refs = refs   -- 供纯 Lua 测试访问
    UI.SetRoot(root)
    App.ShowPage("title")
    App.RefreshTitle()
    print("[App] UI built")
end

function App.ShowPage(name)
    App.page = name
    refs.pageTitle:SetVisible(name == "title")
    refs.pageGame:SetVisible(name == "game")
    refs.pageShop:SetVisible(name == "shop")
    if App.audio then
        App.audio:PlayBGM(name == "title" and "bgm_title" or "bgm_game")
    end
end

-- ===========================================================================
-- 存档
-- ===========================================================================
function App.CollectSave()
    return {
        meta = App.meta,
        run = (App.run and App.run.phase ~= "over" and App.run.phase ~= "win") and App.run:Serialize() or nil,
    }
end

function App.SaveLocal()
    Save.Commit(App.CollectSave, false)
end

function App.Boot()
    Save.Startup({
        onReady = function(env) App.OnProfileReady(env) end,
        onCloudFail = function() refs.dlgCloudFail:Open() end,
    })
end

function App.OnProfileReady(env)
    if env and env.body then
        local m = env.body.meta
        if type(m) == "table" then
            for k, v in pairs(m) do App.meta[k] = v end
            App.meta.discovered = App.meta.discovered or {}
        end
        App.savedRun = env.body.run
    else
        App.savedRun = nil
    end
    App.profileReady = true
    App.RefreshTitle()
    print("[App] profile ready, savedRun=" .. tostring(App.savedRun ~= nil))
end

-- ===========================================================================
-- 流程
-- ===========================================================================
function App.StartRun()
    local st = C.STARTERS[App.selectedStarter]
    if not starterUnlocked(st) then return end
    App.run = Run.new(st.key)
    App.meta.runs = (App.meta.runs or 0) + 1
    for _, k in ipairs(App.run.bag) do App.meta.discovered["ball:" .. k] = true end
    for _, k in ipairs(App.run.charms) do App.meta.discovered["charm:" .. k] = true end
    App.EnterStage()
end

function App.ContinueRun()
    local run = Run.Deserialize(App.savedRun)
    if not run then return end
    App.run = run
    if run.phase == "shop" then
        App.GoShop(true)
    else
        App.EnterStage()
    end
end

function App.EnterStage()
    local run = App.run
    App.fx:Reset()
    App.stage = Stage.new(run, run:CurrentStageInfo(), App.fx)
    if run.stageSave then
        App.stage.stageScore = run.stageSave.score or 0
        App.stage.launchesLeft = run.stageSave.left or App.stage.launchesLeft
        App.stage.launchIndex = run.stageSave.index or 0
    end
    App.pendingResult = nil
    shown = {}
    App.ShowPage("game")
    App.RefreshHUD()
    App.fx:Banner(run:CurrentStageInfo().theme.name, run:CurrentStageInfo().theme.accent)
    App.SaveLocal()
end

function App.Launch()
    local st = App.stage
    if not st or App.pendingResult then return end
    if App.audio then App.audio:Unlock() end
    refs.btnLaunch:SetDisabled(true)   -- 防连点
    if st:Launch() then
        App.RefreshHUD()
    end
end

function App.ToggleSpeed()
    App.speed = (App.speed == 1) and 2 or 1
    refs.btnSpeed:SetText("×" .. App.speed)
end

function App.SetPaused(p)
    App.paused = p
end

function App.OnFxEvent(name, a, b, c, d)
    if name == "charm" then
        PulseCharm(a)
    elseif name == "cleared" then
        App.pendingResult = { kind = "cleared", t = 0.9 }
    elseif name == "failed" then
        App.pendingResult = { kind = "failed", t = 1.1 }
        if App.audio then App.audio:Play("fail") end
    elseif name == "fever" then
        if App.audio then App.audio:PlayBGM("bgm_fever") end
    elseif name == "feverEnd" then
        if App.audio then App.audio:PlayBGM("bgm_game") end
    end
end

function App.ResolveResult()
    local pr = App.pendingResult
    local run, st = App.run, App.stage
    if pr.kind == "cleared" then
        local reward = run:OnStageCleared(st)
        App.meta.bestAnte = math.max(App.meta.bestAnte or 0, run.ante)
        App.meta.bestLaunch = math.max(App.meta.bestLaunch or 0, run.stats.bestLaunch)
        if run.phase == "win" then
            App.meta.wins = (App.meta.wins or 0) + 1
            App.ShowEnd(true)
        else
            local vals = { reward.base, reward.launches, reward.interest, reward.bonus }
            for i, r in ipairs(refs.clearRows) do
                r.value:SetText("+$" .. vals[i])
                r.row:SetVisible(i <= 2 or vals[i] > 0)
            end
            refs.clearTotal:SetText("+" .. reward.total)
            refs.clearScore:SetText("本台 " .. Skin.Num(st.stageScore) .. " / 目标 " .. Skin.Num(st.target))
            refs.dlgClear:SetTitle(st.info.boss and "击败头目!" or "过关!")
            refs.dlgClear:Open()
        end
    else
        run:OnStageFailed(st)
        App.meta.bestAnte = math.max(App.meta.bestAnte or 0, run.ante)
        App.meta.bestLaunch = math.max(App.meta.bestLaunch or 0, run.stats.bestLaunch)
        App.ShowEnd(false)
    end
    App.pendingResult = nil
    App.SaveLocal()
    App.RefreshHUD()
end

function App.ShowEnd(win)
    local run = App.run
    refs.dlgEnd:SetTitle(win and "全台通关!" or "台崩了…")
    refs.endSub:SetText(win and "天意站在你这边" or ("倒在 " .. run.ante .. "-" .. run.stageIdx .. "，差一点点"))
    refs.endStats[1]:SetText("第" .. run.ante .. "层")
    refs.endStats[2]:SetText(Skin.Num(run.stats.bestLaunch))
    refs.endStats[3]:SetText(tostring(run.stats.jackpots))
    refs.endStats[4]:SetText(tostring(run.stats.maxCombo))
    App.savedRun = nil
    refs.dlgEnd:Open()
end

function App.GoShop(fromContinue)
    refs.dlgClear:Close()
    App.stage = nil
    App.shopSel = 1
    shown = {}
    App.ShowPage("shop")
    App.RefreshShop()
    App.RefreshHUD()
    if not fromContinue then App.SaveLocal() end
end

function App.GoTitle()
    refs.dlgEnd:Close()
    App.run = nil
    App.stage = nil
    App.SaveLocal()
    App.ShowPage("title")
    App.RefreshTitle()
end

function App.AbandonRun()
    if not App.run then return end
    App.run.phase = "over"
    App.savedRun = nil
    App.run = nil
    App.stage = nil
    App.SaveLocal()
    App.ShowPage("title")
    App.RefreshTitle()
end

-- ===========================================================================
-- 每帧
-- ===========================================================================
local function decayBoard(st, dt)
    for _, p in ipairs(st.board.pegs) do
        if p.flash > 0 then p.flash = math.max(0, p.flash - dt * 4) end
        if p.pop and p.pop > 0 then p.pop = math.max(0, p.pop - dt * 3) end
    end
    for _, pk in ipairs(st.board.pockets) do
        if pk.flash > 0 then pk.flash = math.max(0, pk.flash - dt * 3) end
    end
end

function App.Update(dt)
    W.time = W.time + dt
    if App.audio then App.audio:Update(dt) end
    local active = false
    if App.page == "game" and App.stage and not App.paused then
        local st = App.stage
        local prevPhase = st.phase
        local simDt = dt
        for _ = 1, App.speed do simDt = st:Update(dt) end
        App.fx:Update(simDt * App.speed)
        decayBoard(st, dt)
        -- 一发结束回到 idle：记录断点
        if prevPhase == "settle" and st.phase == "idle" then
            App.run.stageSave = { score = st.stageScore, left = st.launchesLeft, index = st.launchIndex }
            App.SaveLocal()
        end
        if App.pendingResult then
            App.pendingResult.t = App.pendingResult.t - dt
            if App.pendingResult.t <= 0 then App.ResolveResult() end
        end
        App.RefreshHUD()
        active = true
    elseif App.page == "shop" then
        active = true
    end
    Save.Update(dt, active and not App.paused, App.CollectSave)
end

return App
