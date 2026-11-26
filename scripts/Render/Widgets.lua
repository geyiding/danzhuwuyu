-- ============================================================================
-- Widgets.lua · 自定义 NanoVG 控件（继承 UI.Widget）
--   BoardView  弹珠台主画面（盘面坐标 360x640 等比缩放居中）
--   ScoreBar   目标进度 + 珠分×倍率（会着火）
--   ArtIcon    程序化图标（珠子/护符/改造/台主/锁）
--   LogoArt    标题页动态 Logo
-- ============================================================================

local UI = require("urhox-libs/UI")
local Art = require("Render/Art")
local Skin = require("UIx/Skin")
local C = require("Game/Config")

local W = {}
W.time = 0          -- 由 App 每帧推进
W.app = nil         -- 由 App.Build 注入（不放进 props，避免 UI 库处理大表）

local B = C.BOARD
local FEVER_TIP = "钉子珠分 ×" .. C.FEVER.chipsMul
local pi, sin, cos, floor, min, max = math.pi, math.sin, math.cos, math.floor, math.min, math.max

-- ===========================================================================
-- BoardView
-- ===========================================================================
local BoardView = UI.Widget:Extend("BoardView")
W.BoardView = BoardView

function BoardView:Init(props)
    props = props or {}
    UI.Widget.Init(self, props)
    -- 预生成背景星点（只做一次）
    self.stars = {}
    for i = 1, 40 do
        self.stars[i] = { math.random() * B.W, math.random() * B.H, 0.5 + math.random() * 1.2, math.random() * 6 }
    end
end

local function drawBackground(self, vg, theme, fever, t)
    local bg1, bg2 = theme.bg1, theme.bg2
    if fever > 0 then
        local k = fever * (0.6 + 0.4 * sin(t * 6))
        bg1 = Art.mix(bg1, { 150, 90, 10 }, k)
        bg2 = Art.mix(bg2, { 60, 20, 0 }, k)
    end
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 0, 0, B.W, B.H, 22)
    nvgFillPaint(vg, nvgLinearGradient(vg, 0, 0, 0, B.H, Art.c(bg1), Art.c(bg2)))
    nvgFill(vg)
    -- 中心光
    Art.Glow(vg, B.W / 2, B.H * 0.45, 260, theme.frame, 40 + fever * 60)
    for i = 1, #self.stars do
        local s = self.stars[i]
        local a = 60 + 60 * sin(t * 1.5 + s[4])
        Art.Circle(vg, s[1], s[2], s[3], theme.accent, a)
    end
end

local function drawFrame(vg, theme, t, fever)
    local col = theme.frame
    if fever > 0 then col = Art.hsv(t * 0.4, 0.6, 1) end
    local function path()
        nvgBeginPath(vg)
        nvgMoveTo(vg, B.wallL, B.floor)
        nvgLineTo(vg, B.wallL, B.arcCy)
        nvgArc(vg, B.arcCx, B.arcCy, B.arcR, pi, 0, NVG_CW)
        nvgLineTo(vg, B.wallR, B.floor)
    end
    path()
    nvgStrokeWidth(vg, 9)
    nvgStrokeColor(vg, Art.c(col, 50))
    nvgStroke(vg)
    path()
    nvgStrokeWidth(vg, 2.5)
    nvgStrokeColor(vg, Art.c(col, 230))
    nvgStroke(vg)
    -- 发射轨道
    nvgBeginPath(vg)
    nvgMoveTo(vg, B.railX, B.railBottom)
    nvgLineTo(vg, B.railX, B.arcCy)
    nvgArc(vg, B.arcCx, B.arcCy, B.railR, pi, pi * 1.85, NVG_CW)
    nvgStrokeWidth(vg, 11)
    nvgStrokeColor(vg, Art.rgba(0, 0, 0, 90))
    nvgStroke(vg)
    nvgStrokeWidth(vg, 1.2)
    nvgStrokeColor(vg, Art.c(theme.accent, 120))
    nvgStroke(vg)
end

local function drawLCD(vg, st, fx, t)
    local L = B.lcd
    local spin = st.slot.spin
    local reach = fx.reachT > 0
    local fever = st.fever
    -- 外框
    local border = st.info.theme.frame
    if reach then border = (floor(t * 10) % 2 == 0) and { 255, 60, 60 } or { 255, 220, 80 } end
    if fever then border = Art.hsv(t * 0.8, 0.7, 1) end
    Art.Glow(vg, L.x + L.w / 2, L.y + L.h / 2, L.w * 0.8, border, 70 + fx.lcdFlash * 120)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, L.x - 3, L.y - 3, L.w + 6, L.h + 6, L.r + 3)
    nvgFillColor(vg, Art.c(border, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, L.x, L.y, L.w, L.h, L.r)
    nvgFillPaint(vg, nvgLinearGradient(vg, 0, L.y, 0, L.y + L.h, Art.rgba(20, 16, 44), Art.rgba(6, 4, 18)))
    nvgFill(vg)

    if fever then
        local k = fever.t / fever.dur
        Art.TextStroke(vg, L.x + L.w / 2, L.y + 30, fever.super and "777!!" or "FEVER", 26 + sin(t * 12) * 2,
            Art.hsv(t, 0.5, 1), { 40, 0, 0 }, 2)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, L.x + 12, L.y + L.h - 22, (L.w - 24) * max(0, 1 - k), 8, 4)
        nvgFillColor(vg, Art.rgba(255, 220, 80))
        nvgFill(vg)
        Art.Text(vg, L.x + L.w / 2, L.y + 56, FEVER_TIP, 11, { 255, 240, 200 }, 230, true)
        return
    end
    -- 三个转轮
    local rw, rh = 34, 50
    local gap = 6
    local x0 = L.x + (L.w - (rw * 3 + gap * 2)) / 2
    local y0 = L.y + 8
    for i = 1, 3 do
        local rx = x0 + (i - 1) * (rw + gap)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rx, y0, rw, rh, 6)
        nvgFillColor(vg, Art.rgba(250, 246, 236))
        nvgFill(vg)
        nvgSave(vg)
        nvgIntersectScissor(vg, rx, y0, rw, rh)
        local rolling = spin and spin.stopped < i
        if rolling then
            local syms = C.SLOT.symbols
            local speed = (spin.reach and i == 3) and 9 or 16
            local pos = t * speed + i * 1.7
            local base = floor(pos)
            local frac = pos - base
            for k = -1, 1 do
                local sym = syms[(base + k) % #syms + 1]
                Art.SlotSymbol(vg, sym, rx + rw / 2, y0 + rh / 2 + (k + frac - 0.5) * rh * 0.9 + rh * 0.45, rw * 0.9, t, 230)
            end
        else
            Art.SlotSymbol(vg, st.slot.reels[i], rx + rw / 2, y0 + rh / 2, rw * 0.9, t)
        end
        nvgRestore(vg)
    end
    -- 保留灯
    local holds = #st.slot.holds
    for i = 1, C.SLOT.maxHold do
        local cx = L.x + L.w / 2 + (i - 2.5) * 14
        local on = i <= holds
        Art.Circle(vg, cx, L.y + L.h - 12, 4, on and { 255, 210, 60 } or { 70, 60, 100 }, 255)
        if on then Art.Glow(vg, cx, L.y + L.h - 12, 10, { 255, 210, 60 }, 140) end
    end
end

local function drawStartPocket(vg, st, t)
    local S = B.start
    local col = st.startBlocked and { 120, 120, 140 } or { 255, 220, 90 }
    if not st.startBlocked then Art.Glow(vg, S.x, S.y + 6, 22, col, 90 + 40 * sin(t * 5)) end
    nvgBeginPath(vg)
    nvgArc(vg, S.x, S.y + 2, S.rimGap - 1, 0.1, pi - 0.1, NVG_CW)
    nvgStrokeWidth(vg, 3)
    nvgStrokeColor(vg, Art.c(col, 255))
    nvgStroke(vg)
    if st.startBlocked then
        Art.Lock(vg, S.x, S.y + 4, 18, 255)
    end
end

local POCKET_COL = {
    recycle = { 90, 220, 140 }, chips = { 70, 160, 255 }, mult = { 255, 80, 100 }, bigmult = { 255, 40, 80 },
}

local function drawPockets(vg, st, t)
    for _, pk in ipairs(st.board.pockets) do
        local col = pk.disabled and { 90, 90, 110 } or (POCKET_COL[pk.kind] or { 200, 200, 200 })
        local fl = pk.flash or 0
        nvgBeginPath(vg)
        nvgRect(vg, pk.x + 1, B.pocketTop, pk.w - 2, B.floor - B.pocketTop)
        nvgFillPaint(vg, nvgLinearGradient(vg, 0, B.pocketTop, 0, B.floor, Art.c(col, 30 + fl * 120), Art.c(col, 120 + fl * 135)))
        nvgFill(vg)
        if not pk.text then
            pk.text = (pk.kind == "mult" or pk.kind == "bigmult") and (pk.label .. "倍") or pk.label
        end
        local label = pk.disabled and "封" or pk.text
        Art.TextStroke(vg, pk.x + pk.w / 2, B.pocketTop + 40, label, (pk.kind == "bigmult") and 15 or 12,
            { 255, 255, 255 }, Art.mix(col, { 0, 0, 0 }, 0.6), 1.5, 255)
    end
    -- 隔板
    for _, s in ipairs(st.board.segs) do
        if s.tag == "divider" then
            nvgBeginPath(vg)
            nvgMoveTo(vg, s.x1, s.y1)
            nvgLineTo(vg, s.x2, s.y2)
            nvgStrokeWidth(vg, 2)
            nvgStrokeColor(vg, Art.rgba(220, 220, 255, 200))
            nvgStroke(vg)
        elseif s.tag == "wall" and s.y1 > B.fieldBottom then
            nvgBeginPath(vg)
            nvgMoveTo(vg, s.x1, s.y1)
            nvgLineTo(vg, s.x2, s.y2)
            nvgStrokeWidth(vg, 2.5)
            nvgStrokeColor(vg, Art.c(st.info.theme.frame, 220))
            nvgStroke(vg)
        end
    end
end

local function drawBalls(vg, st, t)
    local balls = st.phys.balls
    for i = 1, #balls do
        local b = balls[i]
        if b.alive then
            -- 拖尾：从最新采样往回连线
            local tr = b.trail
            local n = #tr
            if n >= 3 then
                local col = Art.BALL_COLORS[b.kind] or Art.BALL_COLORS.steel
                local idx = b.trailN
                local px, py = b.x, b.y
                for k = 1, n - 1 do
                    idx = (idx - 2) % n + 1
                    local p = tr[idx]
                    if p then
                        nvgBeginPath(vg)
                        nvgMoveTo(vg, px, py)
                        nvgLineTo(vg, p[1], p[2])
                        nvgStrokeWidth(vg, b.r * 1.6 * (1 - k / n))
                        nvgStrokeColor(vg, Art.c(col, 110 * (1 - k / n)))
                        nvgStroke(vg)
                        px, py = p[1], p[2]
                    end
                end
            end
            Art.Ball(vg, b.kind, b.x, b.y, b.r, t + b.id * 0.13)
        end
    end
    -- 轨道上的珠子
    for i = 1, #st.rail do
        local it = st.rail[i]
        Art.Ball(vg, it.kind, it.x, it.y, 5, t)
    end
end

local function drawIdleHints(vg, st, t)
    if st.phase ~= "idle" then return end
    local cy = B.H * 0.70
    if st.info.boss then
        local bdef = C.BOSSES[st.info.boss]
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 50, cy - 70, B.W - 100, 54, 12)
        nvgFillColor(vg, Art.rgba(60, 0, 20, 200))
        nvgFill(vg)
        st._bossTitle = st._bossTitle or ("头目 · " .. bdef.name)
        Art.TextStroke(vg, B.W / 2, cy - 54, st._bossTitle, 18, { 255, 90, 90 }, { 30, 0, 0 }, 2)
        Art.Text(vg, B.W / 2, cy - 30, bdef.desc, 13, { 255, 220, 220 }, 255)
    end
    local bob = sin(t * 5) * 6
    Art.TextStroke(vg, B.W / 2, cy + 20 + bob, "▼ 大力干! ▼", 24, { 255, 230, 120 }, { 60, 20, 0 }, 2.5, 200 + 55 * sin(t * 5))
end

function BoardView:Render(vg)
    local app = W.app
    local st = app and app.stage
    if not st then return end
    local fx = app.fx
    local l = self:GetAbsoluteLayout()
    local s = min(l.w / B.W, l.h / B.H)
    local ox = l.x + (l.w - B.W * s) / 2
    local oy = l.y + (l.h - B.H * s) / 2
    local t = W.time
    local fever = st.fever and 1 or 0

    nvgSave(vg)
    nvgTranslate(vg, ox + fx.shakeX * s, oy + fx.shakeY * s)
    nvgScale(vg, s, s)
    nvgIntersectScissor(vg, -20, -20, B.W + 40, B.H + 40)

    drawBackground(self, vg, st.info.theme, fever, t)
    drawFrame(vg, st.info.theme, t, fever)
    drawPockets(vg, st, t)
    drawLCD(vg, st, fx, t)
    drawStartPocket(vg, st, t)
    local pegs = st.board.pegs
    for i = 1, #pegs do Art.Peg(vg, pegs[i], t, st.fever ~= nil) end
    drawBalls(vg, st, t)
    fx:DrawWorld(vg, t)
    drawIdleHints(vg, st, t)
    fx:DrawOverlay(vg, t, B.W, B.H)
    fx:DrawFlash(vg, B.W, B.H)
    nvgRestore(vg)
end

-- ===========================================================================
-- ScoreBar：左 目标进度；右 珠分 × 倍率（预计过关时着火）
-- ===========================================================================
local ScoreBar = UI.Widget:Extend("ScoreBar")
W.ScoreBar = ScoreBar

function ScoreBar:Init(props)
    props = props or {}
    UI.Widget.Init(self, props)
end

local function flame(vg, x, y, w, h, t, col)
    for i = 0, 5 do
        local fx = x + (i + 0.5) * w / 6
        local fh = h * (0.55 + 0.45 * sin(t * 13 + i * 1.7))
        nvgBeginPath(vg)
        nvgMoveTo(vg, fx - w / 12, y)
        nvgQuadTo(vg, fx + sin(t * 9 + i) * 3, y - fh * 1.2, fx + w / 12, y)
        nvgFillColor(vg, Art.c(col, 200))
        nvgFill(vg)
    end
end

function ScoreBar:Render(vg)
    local app = W.app
    local st = app and app.stage
    local l = self:GetAbsoluteLayout()
    local t = W.time
    nvgBeginPath(vg)
    nvgRoundedRect(vg, l.x, l.y, l.w, l.h, 12)
    nvgFillColor(vg, Art.c(Skin.C.panel))
    nvgFill(vg)
    if not st then return end

    local pad = 10
    -- 左：目标 + 进度
    local lw = l.w * 0.44
    local x, y = l.x + pad, l.y + pad
    Art.Text(vg, x, y + 9, "目标", Skin.FS.caption, Skin.C.textDim, 220, false, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    Art.Text(vg, x + 30, y + 9, Skin.Num(st.target), 16, Skin.C.gold, 255, true, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local by = y + 24
    local bw = lw - pad
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, by, bw, 12, 6)
    nvgFillColor(vg, Art.rgba(0, 0, 0, 140))
    nvgFill(vg)
    local cur = st.stageScore
    local preview = (st.phase == "launch" or st.phase == "settle") and st.chips * st.mult or 0
    if st.phase == "settle" then preview = st.lastLaunchScore end
    local k1 = min(1, cur / st.target)
    local k2 = min(1, (cur + preview) / st.target)
    if k2 > k1 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, by, max(12, bw * k2), 12, 6)
        nvgFillColor(vg, Art.rgba(255, 230, 140, 110 + 60 * sin(t * 8)))
        nvgFill(vg)
    end
    if k1 > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, by, max(12, bw * k1), 12, 6)
        nvgFillPaint(vg, nvgLinearGradient(vg, x, 0, x + bw, 0, Art.rgba(255, 180, 40), Art.rgba(255, 90, 60)))
        nvgFill(vg)
    end
    Art.Text(vg, x, by + 26, Skin.Num(cur), 15, Skin.C.text, 255, true, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- 右：珠分 × 倍率
    local rx = l.x + lw + pad
    local rw = l.w - lw - pad * 2
    local boxW = (rw - 18) / 2
    local boxH = l.h - pad * 2
    local onFire = st:WillClear() and (st.phase == "launch" or st.phase == "settle")
    if onFire then
        flame(vg, rx, l.y + pad + 2, rw, 18, t, { 255, 150, 40 })
        flame(vg, rx + 4, l.y + pad + 2, rw - 8, 11, t * 1.3, { 255, 230, 120 })
    end
    local chips = st.chips
    local mult = st.mult
    if st.phase == "settle" and app.fx.settle then
        chips, mult = app.fx.settle.chips, app.fx.settle.mult
    end
    nvgBeginPath(vg)
    nvgRoundedRect(vg, rx, l.y + pad, boxW, boxH, 10)
    nvgFillPaint(vg, nvgLinearGradient(vg, 0, l.y, 0, l.y + l.h, Art.rgba(60, 150, 255), Art.rgba(20, 70, 170)))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, rx + boxW + 18, l.y + pad, boxW, boxH, 10)
    nvgFillPaint(vg, nvgLinearGradient(vg, 0, l.y, 0, l.y + l.h, Art.rgba(255, 80, 90), Art.rgba(170, 20, 40)))
    nvgFill(vg)
    Art.Text(vg, rx + boxW + 9, l.y + l.h / 2, "×", 20, Skin.C.text, 255, true)
    local cs = (chips >= 1e5) and 17 or 22
    local ms = (mult >= 1e4) and 17 or 22
    Art.TextStroke(vg, rx + boxW / 2, l.y + l.h / 2, Skin.Num(chips), cs, { 255, 255, 255 }, { 0, 30, 90 }, 1.5)
    Art.TextStroke(vg, rx + boxW * 1.5 + 18, l.y + l.h / 2, Skin.Mult(mult), ms, { 255, 255, 255 }, { 90, 0, 20 }, 1.5)
end

-- ===========================================================================
-- ArtIcon
-- ===========================================================================
local ArtIcon = UI.Widget:Extend("ArtIcon")
W.ArtIcon = ArtIcon

function ArtIcon:Init(props)
    props = props or {}
    props.pointerEvents = "none"
    UI.Widget.Init(self, props)
end

--- 运行期切换图标（只改属性，不重建）
function ArtIcon:SetIcon(kind, iconId, locked)
    self.props.icon, self.props.iconId, self.props.locked = kind, iconId, locked
end

function ArtIcon:Render(vg)
    local p = self.props
    if not p.icon then return end
    local l = self:GetAbsoluteLayout()
    local s = min(l.w, l.h)
    local cx, cy = l.x + l.w / 2, l.y + l.h / 2
    local pulse = p.pulse and (1 + 0.15 * max(0, p.pulse)) or 1
    if p.locked then
        nvgGlobalAlpha(vg, 0.25)
        Art.Icon(vg, p.icon, p.iconId, cx, cy, s * 0.95, 0)
        nvgGlobalAlpha(vg, 1)
        Art.Lock(vg, cx + s * 0.28, cy + s * 0.28, s * 0.36, 255)
    else
        Art.Icon(vg, p.icon, p.iconId, cx, cy, s * 0.95 * pulse, W.time)
    end
end

-- ===========================================================================
-- LogoArt：标题页动态弹珠台 Logo（真实物理：复用 Game/Physics）
--
-- 本地坐标：圆心 (0,0)，半径 100；渲染时按 R/100 缩放。
--   圆形外框 = 线段近似（底部 65°~115° 留出口）
--   钉子 = 静态圆 r=2.5（蜂窝阵），珠子 = 动态圆 r=7
--   珠子从顶部生成 → 撞钉弹跳 → 从底部出口掉出后回收重生
-- ===========================================================================
local Physics = require("Game/Physics")

local LogoArt = UI.Widget:Extend("LogoArt")
W.LogoArt = LogoArt

local LOGO_KINDS = { "steel", "gold", "fire", "prism", "lucky", "rubber", "split", "ghost" }
local LOGO_MAX_BALLS = 8

function LogoArt:Init(props)
    props = props or {}
    props.pointerEvents = "none"
    UI.Widget.Init(self, props)
    self:_buildSim()
end

function LogoArt:_buildSim()
    local pegs, segs = {}, {}
    local id = 0
    for row = 0, 5 do
        for col = -4, 4 do
            local x = (col + (row % 2) * 0.5) * 24
            local y = -45 + row * 20
            if x * x + y * y < 84 * 84 then
                id = id + 1
                pegs[#pegs + 1] = { id = id, x = x, y = y, r = 2.5, alive = true, flash = 0 }
            end
        end
    end
    local N = 36
    for i = 0, N - 1 do
        local a1 = i / N * pi * 2
        local a2 = (i + 1) / N * pi * 2
        local mid = (a1 + a2) / 2
        -- y 向下：90° 为正下方，留出口
        if not (mid > pi * 65 / 180 and mid < pi * 115 / 180) then
            segs[#segs + 1] = { x1 = cos(a1) * 100, y1 = sin(a1) * 100, x2 = cos(a2) * 100, y2 = sin(a2) * 100 }
        end
    end
    self.pegs = pegs
    self.phys = Physics.new({
        gravity = 380, substeps = 4, maxSpeed = 520, pegRest = 0.55, wallRest = 0.5,
        jitter = 0.12, ballBallRest = 0.6, rand = math.random,
    })
    self.phys:SetStatic(pegs, segs, {})
    self.cb = { peg = function(ball, peg) peg.flash = 1; self.hits = self.hits + 1 end }
    self.nextId = 0
    self.spawnT = 0
    self.lastT = nil
    self.hits = 0
end

function LogoArt:_step(dt)
    local phys = self.phys
    self.spawnT = self.spawnT - dt
    if self.spawnT <= 0 and #phys.balls < LOGO_MAX_BALLS then
        self.spawnT = 0.45
        self.nextId = self.nextId + 1
        phys:AddBall({
            id = self.nextId, kind = LOGO_KINDS[(self.nextId - 1) % #LOGO_KINDS + 1],
            x = (math.random() - 0.5) * 60, y = -85, vx = (math.random() - 0.5) * 80, vy = 0,
            r = 7, rest = 0.5,
        })
    end
    phys:Step(dt, self.cb)
    for _, b in ipairs(phys.balls) do
        if b.y > 112 or b.x < -130 or b.x > 130 then b.alive = false end
    end
    phys:Compact()
    for _, p in ipairs(self.pegs) do
        if p.flash > 0 then p.flash = max(0, p.flash - dt * 4) end
    end
end

function LogoArt:Render(vg)
    local l = self:GetAbsoluteLayout()
    local t = W.time
    -- 由渲染时间驱动模拟（只在可见时推进），dt 钳制防切后台穿模
    local dt = self.lastT and (t - self.lastT) or 0
    self.lastT = t
    if dt > 0 then self:_step(min(dt, 1 / 30)) end

    local cx, cy = l.x + l.w / 2, l.y + l.h * 0.46
    local R = min(l.w, l.h) * 0.42
    local k = R / 100
    Art.Glow(vg, cx, cy, R * 1.6, { 255, 120, 200 }, 70)
    -- 圆形台框（底部出口处不描边）
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, R)
    nvgFillPaint(vg, nvgRadialGradient(vg, cx, cy - R * 0.3, R * 0.1, R, Art.rgba(80, 30, 110), Art.rgba(20, 8, 40)))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy, R, pi * 115 / 180, pi * 65 / 180 + pi * 2, NVG_CW)
    nvgStrokeWidth(vg, 4)
    nvgStrokeColor(vg, Art.c(Art.hsv(t * 0.15, 0.5, 1), 255))
    nvgStroke(vg)
    -- 钉阵（被撞闪白）
    for _, p in ipairs(self.pegs) do
        local x, y = cx + p.x * k, cy + p.y * k
        if p.flash > 0 then Art.Glow(vg, x, y, p.r * k * 5, { 255, 255, 255 }, 170 * p.flash) end
        Art.Circle(vg, x, y, p.r * k, { 230, 230, 255 }, 220)
    end
    -- 珠子
    for _, b in ipairs(self.phys.balls) do
        Art.Ball(vg, b.kind, cx + b.x * k, cy + b.y * k, b.r * k, t + b.id * 0.3)
    end
    -- 标题
    local ty = l.y + l.h * 0.88
    Art.TextStroke(vg, cx, ty, "弹珠物语", min(l.w * 0.16, 56) + sin(t * 3) * 1.5, { 255, 240, 180 }, { 120, 20, 60 }, 4)
    Art.Text(vg, cx, ty + min(l.w * 0.1, 38), "MARBLE · STORY", 12, { 255, 200, 230 }, 200, true)
end

return W
