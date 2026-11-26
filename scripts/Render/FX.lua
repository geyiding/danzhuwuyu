-- ============================================================================
-- FX.lua · 爽感反馈层：粒子 / 飘字 / 冲击环 / 横幅 / 震屏 / 闪白 / 结算大字
-- 同时是 Stage 的事件监听者（fx:PegHit / fx:Explode / fx:Fever ...）。
-- 全部对象预分配 + 环形复用：每帧零分配（性能铁律）。
-- 坐标：盘面单位（BU）。
-- ============================================================================

local Art = require("Render/Art")
local C = require("Game/Config")
local Skin = require("UIx/Skin")

local FX = {}
FX.__index = FX

local floor, sin, cos, pi, min, max, sqrt = math.floor, math.sin, math.cos, math.pi, math.min, math.max, math.sqrt

local MAX_PARTICLES = 520
local MAX_POPUPS = 64
local MAX_RINGS = 40

local STYLE = {
    chips = { col = { 110, 190, 255 }, size = 13, prefix = "+" },
    mult  = { col = { 255, 80, 100 },  size = 15, prefix = "+", suffix = "倍" },
    xmult = { col = { 210, 120, 255 }, size = 20, prefix = "×" },
    coin  = { col = { 255, 210, 70 },  size = 15, prefix = "$" },
    dim   = { col = { 180, 170, 200 }, size = 12 },
    peg   = { col = { 220, 235, 255 }, size = 9, prefix = "" },
}

function FX.new(audio)
    local self = setmetatable({}, FX)
    self.audio = audio
    self.listener = nil      -- function(eventName, ...) → App
    self.particles = {}
    for i = 1, MAX_PARTICLES do self.particles[i] = { life = 0 } end
    self.pIdx = 0
    self.popups = {}
    for i = 1, MAX_POPUPS do self.popups[i] = { life = 0 } end
    self.uIdx = 0
    self.rings = {}
    for i = 1, MAX_RINGS do self.rings[i] = { life = 0 } end
    self.rIdx = 0
    self.banners = {}
    for i = 1, 4 do self.banners[i] = { life = 0 } end
    self.bIdx = 0
    self.textCache = {}
    self:Reset()
    return self
end

function FX:Reset()
    for i = 1, MAX_PARTICLES do self.particles[i].life = 0 end
    for i = 1, MAX_POPUPS do self.popups[i].life = 0 end
    for i = 1, MAX_RINGS do self.rings[i].life = 0 end
    for i = 1, 4 do self.banners[i].life = 0 end
    self.shake = 0
    self.shakeX, self.shakeY = 0, 0
    self.flashA, self.flashCol = 0, { 255, 255, 255 }
    self.feverGlow = 0
    self.reachT = 0
    self.lcdFlash = 0
    self.settle = nil
    self.launchFlash = 0
end

local function emit(self, name, ...)
    if self.listener then self.listener(name, ...) end
end

local function sfx(self, name, pitch)
    if self.audio then self.audio:Play(name, pitch) end
end

-- ---------------------------------------------------------------------------
-- 发射器
-- ---------------------------------------------------------------------------
function FX:Particle(x, y, vx, vy, life, size, col, kind, grav)
    self.pIdx = self.pIdx % MAX_PARTICLES + 1
    local p = self.particles[self.pIdx]
    p.x, p.y, p.vx, p.vy = x, y, vx, vy
    p.life, p.max, p.size = life, life, size
    p.r, p.g, p.b = col[1], col[2], col[3]
    p.kind = kind or "dot"
    p.grav = grav or 300
end

function FX:Burst(x, y, n, speed, col, life, size, kind)
    for i = 1, n do
        local a = (i / n) * pi * 2 + math.random() * 0.6
        local sp = speed * (0.4 + math.random() * 0.8)
        self:Particle(x, y, cos(a) * sp, sin(a) * sp, life * (0.6 + math.random() * 0.6), size, col, kind)
    end
end

function FX:Ring(x, y, maxR, life, col, width)
    self.rIdx = self.rIdx % MAX_RINGS + 1
    local r = self.rings[self.rIdx]
    r.x, r.y, r.maxR, r.life, r.max, r.col, r.w = x, y, maxR, life, life, col, width or 3
end

local function formatText(self, value, style)
    if type(value) == "string" then return value end
    local st = STYLE[style] or STYLE.chips
    local key = style
    local cache = self.textCache[key]
    if not cache then cache = {}; self.textCache[key] = cache end
    local s = cache[value]
    if not s then
        local num
        if math.abs(value - floor(value)) < 0.001 then num = tostring(floor(value)) else num = string.format("%.1f", value) end
        s = (st.prefix or "") .. num .. (st.suffix or "")
        if value < 2000 then cache[value] = s end
    end
    return s
end

function FX:Popup(x, y, value, style)
    self.uIdx = self.uIdx % MAX_POPUPS + 1
    local u = self.popups[self.uIdx]
    local st = STYLE[style] or STYLE.chips
    u.x, u.y = x + (math.random() - 0.5) * 8, y - 6
    u.text = formatText(self, value, style)
    u.col = st.col
    u.size = st.size
    u.life, u.max = 0.9, 0.9
    u.vy = -46
    if style == "xmult" then u.life, u.max = 1.3, 1.3 end
end

-- ---------------------------------------------------------------------------
-- Stage 监听接口
-- ---------------------------------------------------------------------------
function FX:Charm(id)
    emit(self, "charm", id)
    sfx(self, "charm")
end

function FX:Banner(text, col, big)
    self.bIdx = self.bIdx % 4 + 1
    local b = self.banners[self.bIdx]
    b.text, b.col, b.life, b.max, b.big = text, col or { 255, 255, 255 }, 1.4, 1.4, big
end

function FX:Shake(n)
    self.shake = min(14, max(self.shake, n))
end

function FX:Flash(col, a)
    self.flashCol = col
    self.flashA = max(self.flashA, a)
end

function FX:Spawn(ball)
end

function FX:Launch(n)
    self.launchFlash = 1
    sfx(self, "launch")
    emit(self, "launch", n)
end

function FX:Wall(ball, impact)
    if impact > 200 then
        self:Burst(ball.x, ball.y, 2, 60, { 200, 220, 255 }, 0.25, 1.5)
    end
end

function FX:PegScore(peg, chips)
    if peg.type == "normal" then
        if math.random() < 0.55 then self:Popup(peg.x, peg.y - 4, chips, "peg") end
    else
        self:Popup(peg.x, peg.y - 6, chips, "chips")
    end
end

local PEG_COL = {
    normal = { 220, 235, 255 }, gold = { 255, 200, 60 }, red = { 255, 70, 80 }, purple = { 200, 110, 255 },
    bomb = { 255, 140, 40 }, split = { 60, 230, 200 }, bumper = { 90, 210, 255 },
}

function FX:PegHit(peg, ball)
    local col = PEG_COL[peg.type] or PEG_COL.normal
    if peg.type == "normal" then
        self:Burst(peg.x, peg.y, 2, 70, col, 0.25, 1.4)
        sfx(self, "peg", 1 + min(0.5, (ball and ball.hits or 0) * 0.02))
    else
        self:Burst(peg.x, peg.y, 12, 150, col, 0.55, 2.4, "spark")
        self:Ring(peg.x, peg.y, 26, 0.35, col, 3)
        if peg.type == "purple" then
            self:Flash({ 200, 110, 255 }, 90)
            self:Ring(peg.x, peg.y, 70, 0.5, col, 5)
            sfx(self, "xmult")
        elseif peg.type == "gold" then
            sfx(self, "coin")
        elseif peg.type == "red" then
            sfx(self, "mult")
        elseif peg.type == "bumper" then
            sfx(self, "bumper")
        end
    end
end

function FX:Explode(x, y, r, big)
    self:Ring(x, y, r, 0.4, { 255, 200, 80 }, big and 6 or 3)
    self:Ring(x, y, r * 0.6, 0.3, { 255, 255, 220 }, 3)
    self:Burst(x, y, big and 26 or 10, big and 260 or 160, { 255, 150, 40 }, 0.6, big and 3.2 or 2.2, "spark")
    self:Burst(x, y, big and 10 or 4, 80, { 90, 80, 90 }, 0.9, 5, "smoke")
    if big then self:Flash({ 255, 200, 120 }, 70) end
    sfx(self, big and "boom" or "pop")
end

function FX:Pocket(pk, ball)
    local cx = pk.x + pk.w / 2
    local col = ({ recycle = { 120, 255, 160 }, chips = { 110, 190, 255 }, mult = { 255, 80, 100 }, bigmult = { 255, 60, 90 } })[pk.kind] or { 255, 255, 255 }
    for i = 1, 5 do
        self:Particle(cx + (math.random() - 0.5) * pk.w * 0.7, C.BOARD.pocketCapture + 10, (math.random() - 0.5) * 40,
            -160 - math.random() * 120, 0.6, 2.2, col, "spark", 200)
    end
    sfx(self, "pocket")
end

function FX:StartPocket(n)
    local S = C.BOARD.start
    self:Ring(S.x, S.y + 4, 34, 0.5, { 255, 230, 100 }, 4)
    self:Burst(S.x, S.y, 14, 160, { 255, 230, 120 }, 0.6, 2.4, "spark")
    self.lcdFlash = 1
    self:Banner("入赏!", { 255, 230, 100 })
    sfx(self, "start")
end

function FX:SlotSpin(spin)
    sfx(self, "spin")
end

function FX:ReelStop(i, spin)
    sfx(self, "reel")
end

function FX:Reach()
    self.reachT = 2.0
    self:Banner("就差一个!", { 255, 90, 90 }, true)
    self:Shake(5)
    sfx(self, "reach")
end

function FX:Fever(super)
    self.feverGlow = 1
    self:Flash(super and { 255, 90, 90 } or { 255, 220, 100 }, 200)
    self:Shake(12)
    self:Banner(super and "超级大当 777!!" or "大当 FEVER!!", super and { 255, 80, 80 } or { 255, 220, 60 }, true)
    local L = C.BOARD.lcd
    for i = 1, 3 do
        self:Ring(L.x + L.w / 2, L.y + L.h / 2, 120 + i * 60, 0.5 + i * 0.2, { 255, 220, 120 }, 6)
    end
    self:Burst(L.x + L.w / 2, L.y + L.h / 2, 60, 360, { 255, 220, 90 }, 1.2, 3.2, "spark")
    sfx(self, "fever")
    emit(self, "fever", super)
end

function FX:FeverEnd()
    emit(self, "feverEnd")
end

function FX:Combo(n)
    self:Banner(n .. " 连击!", { 120, 230, 255 })
end

function FX:Settle(chips, mult, score, willClear)
    self.settle = { chips = chips, mult = mult, score = score, t = 0, clear = willClear }
    self:Shake(willClear and 10 or 5)
    if willClear then self:Flash({ 255, 240, 200 }, 120) end
    sfx(self, willClear and "bigwin" or "settle")
    emit(self, "settle", chips, mult, score, willClear)
end

function FX:Cleared() emit(self, "cleared") end
function FX:Failed() emit(self, "failed") end

-- ---------------------------------------------------------------------------
-- 更新
-- ---------------------------------------------------------------------------
function FX:Update(dt)
    local ps = self.particles
    for i = 1, MAX_PARTICLES do
        local p = ps[i]
        if p.life > 0 then
            p.life = p.life - dt
            p.vy = p.vy + p.grav * dt
            p.vx = p.vx * (1 - 2.2 * dt)
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
        end
    end
    for i = 1, MAX_POPUPS do
        local u = self.popups[i]
        if u.life > 0 then
            u.life = u.life - dt
            u.y = u.y + u.vy * dt
            u.vy = u.vy * (1 - 3 * dt)
        end
    end
    for i = 1, MAX_RINGS do
        local r = self.rings[i]
        if r.life > 0 then r.life = r.life - dt end
    end
    for i = 1, 4 do
        local b = self.banners[i]
        if b.life > 0 then b.life = b.life - dt end
    end
    if self.shake > 0 then
        self.shake = max(0, self.shake - dt * 30)
        self.shakeX = (math.random() - 0.5) * 2 * self.shake
        self.shakeY = (math.random() - 0.5) * 2 * self.shake
    else
        self.shakeX, self.shakeY = 0, 0
    end
    if self.flashA > 0 then self.flashA = max(0, self.flashA - dt * 400) end
    if self.reachT > 0 then self.reachT = self.reachT - dt end
    if self.lcdFlash > 0 then self.lcdFlash = max(0, self.lcdFlash - dt * 2) end
    if self.launchFlash > 0 then self.launchFlash = max(0, self.launchFlash - dt * 2) end
    if self.settle then
        self.settle.t = self.settle.t + dt
        if self.settle.t > 1.6 then self.settle = nil end
    end
end

-- ---------------------------------------------------------------------------
-- 绘制（盘面坐标系内调用）
-- ---------------------------------------------------------------------------
function FX:DrawWorld(vg, t)
    -- 冲击环
    for i = 1, MAX_RINGS do
        local r = self.rings[i]
        if r.life > 0 then
            local k = 1 - r.life / r.max
            local ease = 1 - (1 - k) * (1 - k)
            nvgBeginPath(vg)
            nvgCircle(vg, r.x, r.y, 2 + r.maxR * ease)
            nvgStrokeWidth(vg, r.w * (1 - k) + 0.5)
            nvgStrokeColor(vg, Art.c(r.col, 255 * (1 - k)))
            nvgStroke(vg)
        end
    end
    -- 粒子
    local ps = self.particles
    for i = 1, MAX_PARTICLES do
        local p = ps[i]
        if p.life > 0 then
            local k = p.life / p.max
            if p.kind == "smoke" then
                nvgBeginPath(vg)
                nvgCircle(vg, p.x, p.y, p.size * (2 - k))
                nvgFillColor(vg, Art.rgba(p.r, p.g, p.b, 110 * k))
                nvgFill(vg)
            elseif p.kind == "spark" then
                nvgBeginPath(vg)
                nvgMoveTo(vg, p.x, p.y)
                nvgLineTo(vg, p.x - p.vx * 0.035, p.y - p.vy * 0.035)
                nvgStrokeWidth(vg, p.size * k + 0.4)
                nvgStrokeColor(vg, Art.rgba(p.r, p.g, p.b, 255 * k))
                nvgStroke(vg)
            else
                nvgBeginPath(vg)
                nvgCircle(vg, p.x, p.y, p.size * k + 0.3)
                nvgFillColor(vg, Art.rgba(p.r, p.g, p.b, 255 * k))
                nvgFill(vg)
            end
        end
    end
    -- 飘字
    nvgFontFace(vg, Art.FONT_BOLD)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for i = 1, MAX_POPUPS do
        local u = self.popups[i]
        if u.life > 0 then
            local k = u.life / u.max
            local a = min(1, k * 2.5) * 255
            local pop = 1 + max(0, (k - 0.8)) * 2.5
            nvgFontSize(vg, u.size * pop)
            nvgFillColor(vg, Art.rgba(0, 0, 0, a * 0.7))
            nvgText(vg, u.x + 1, u.y + 1, u.text)
            nvgFillColor(vg, Art.c(u.col, a))
            nvgText(vg, u.x, u.y, u.text)
        end
    end
end

--- 覆盖层：横幅、结算大字（盘面坐标系）
function FX:DrawOverlay(vg, t, W, H)
    -- 横幅（最新一个在最上）
    local y = H * 0.40
    for n = 0, 3 do
        local i = (self.bIdx - n - 1) % 4 + 1
        local b = self.banners[i]
        if b.life > 0 then
            local k = 1 - b.life / b.max
            local s = (k < 0.12) and (0.6 + k / 0.12 * 0.6) or (k < 0.2 and (1.2 - (k - 0.12) / 0.08 * 0.2) or 1)
            local a = (b.life < 0.3) and (b.life / 0.3 * 255) or 255
            local size = (b.big and 34 or 24) * s
            Art.TextStroke(vg, W / 2, y, b.text, size, b.col, { 30, 10, 40 }, b.big and 3 or 2, a)
            y = y + (b.big and 42 or 30)
        end
    end
    -- 结算：珠分 × 倍率 = 分数
    local st = self.settle
    if st then
        local k = st.t
        local a = (k > 1.3) and max(0, (1.6 - k) / 0.3) * 255 or 255
        local cy = H * 0.62
        local pop = k < 0.15 and (k / 0.15) or 1
        nvgBeginPath(vg)
        nvgRoundedRect(vg, 30, cy - 46, W - 60, 92, 16)
        nvgFillColor(vg, Art.rgba(10, 6, 24, a * 0.82))
        nvgFill(vg)
        Art.TextStroke(vg, W / 2 - 62, cy - 18, Skin.Num(st.chips), 22 * pop, { 110, 190, 255 }, { 0, 20, 60 }, 2, a)
        Art.Text(vg, W / 2, cy - 18, "×", 20, { 255, 255, 255 }, a, true)
        Art.TextStroke(vg, W / 2 + 62, cy - 18, Skin.Mult(st.mult), 22 * pop, { 255, 90, 100 }, { 60, 0, 10 }, 2, a)
        local grow = min(1, max(0, (k - 0.25) / 0.5))
        local shown = st.score * (grow * grow * (3 - 2 * grow))
        local col = st.clear and { 255, 220, 80 } or { 255, 255, 255 }
        Art.TextStroke(vg, W / 2, cy + 20, Skin.Num(shown), (30 + 12 * grow) * (st.clear and 1.1 or 1), col, { 40, 10, 0 }, 3, a)
    end
end

function FX:DrawFlash(vg, W, H)
    if self.flashA > 0 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, W, H)
        nvgFillColor(vg, Art.c(self.flashCol, self.flashA))
        nvgFill(vg)
    end
end

return FX
