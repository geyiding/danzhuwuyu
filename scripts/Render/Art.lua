-- ============================================================================
-- Art.lua · 程序化美术（NanoVG）
-- 所有图标 / 珠子 / 钉子 / 台主立绘 / 老虎机符号都在这里画。
-- 后期替换贴图：在 Art.TEXTURES 里登记同名 PNG（见 docs/ART_PROMPTS.md 映射表），
-- 绘制函数会优先画贴图，缺图时自动回退到程序化绘制。
-- ============================================================================

local Art = {}

local pi, cos, sin, floor, max, min, abs = math.pi, math.cos, math.sin, math.floor, math.max, math.min, math.abs

Art.FONT = "sans"
Art.FONT_BOLD = "sans"

-- ---------------------------------------------------------------------------
-- 贴图替换表：key → 图片路径（存在即使用）
-- 例：Art.TEXTURES["charm:lantern"] = "Textures/charms/lantern.png"
-- ---------------------------------------------------------------------------
Art.TEXTURES = {}
-- 未手动登记时按约定路径自动查找：assets/Textures/<目录>/<id>.png
Art.AUTO_DIRS = { ball = "balls", charm = "charms", mod = "mods", portrait = "portraits",
    peg = "pegs", slot = "slots", boss = "bosses" }
local imageCache = {}

local function resolvePath(key)
    local p = Art.TEXTURES[key]
    if p then return p end
    local kind, id = key:match("^(%w+):(.+)$")
    local dir = kind and Art.AUTO_DIRS[kind]
    if not dir then return nil end
    return "Textures/" .. dir .. "/" .. id .. ".png"
end

local function tryImage(vg, key)
    local img = imageCache[key]
    if img == nil then
        img = false
        local path = resolvePath(key)
        local exists = false
        if path and cache and cache.Exists then
            local ok, r = pcall(function() return cache:Exists(path) end)
            exists = ok and r
        end
        if exists and nvgCreateImage then
            local ok, h = pcall(nvgCreateImage, vg, path, 0)
            if ok and h and h > 0 then img = h end
            print("[Art] texture " .. key .. " -> " .. path .. (img and " OK" or " FAILED"))
        end
        imageCache[key] = img
    end
    return img or nil
end
Art.TryImage = tryImage

local function drawImage(vg, img, cx, cy, s)
    local x, y = cx - s / 2, cy - s / 2
    local paint = nvgImagePattern(vg, x, y, s, s, 0, img, 1)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, s, s)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

-- ---------------------------------------------------------------------------
-- 颜色工具
-- ---------------------------------------------------------------------------
local function clamp255(v)
    v = floor(v + 0.5)
    if v < 0 then return 0 elseif v > 255 then return 255 end
    return v
end

function Art.rgba(r, g, b, a)
    return nvgRGBA(clamp255(r), clamp255(g), clamp255(b), clamp255(a or 255))
end
local rgba = Art.rgba

function Art.c(t, a)
    return nvgRGBA(clamp255(t[1]), clamp255(t[2]), clamp255(t[3]), clamp255(a or t[4] or 255))
end
local ct = Art.c

local function lerp(a, b, k) return a + (b - a) * k end
function Art.mix(c1, c2, k)
    return { lerp(c1[1], c2[1], k), lerp(c1[2], c2[2], k), lerp(c1[3], c2[3], k) }
end

function Art.hsv(h, s, v)
    h = (h % 1) * 6
    local i = floor(h)
    local f = h - i
    local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    local r, g, b
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return { r * 255, g * 255, b * 255 }
end

-- ---------------------------------------------------------------------------
-- 基础图元
-- ---------------------------------------------------------------------------
function Art.Glow(vg, x, y, r, col, a)
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, r)
    nvgFillPaint(vg, nvgRadialGradient(vg, x, y, r * 0.15, r, ct(col, a), ct(col, 0)))
    nvgFill(vg)
end

function Art.Circle(vg, x, y, r, col, a)
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, r)
    nvgFillColor(vg, ct(col, a))
    nvgFill(vg)
end

function Art.Ring(vg, x, y, r, w, col, a)
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, r)
    nvgStrokeWidth(vg, w)
    nvgStrokeColor(vg, ct(col, a))
    nvgStroke(vg)
end

function Art.StarPath(vg, cx, cy, r, inner, points, rot)
    points = points or 5
    inner = inner or 0.45
    rot = rot or -pi / 2
    nvgBeginPath(vg)
    for i = 0, points * 2 - 1 do
        local a = rot + i * pi / points
        local rr = (i % 2 == 0) and r or r * inner
        local x, y = cx + cos(a) * rr, cy + sin(a) * rr
        if i == 0 then nvgMoveTo(vg, x, y) else nvgLineTo(vg, x, y) end
    end
    nvgClosePath(vg)
end

function Art.Star(vg, cx, cy, r, col, a, rot)
    Art.StarPath(vg, cx, cy, r, 0.45, 5, rot)
    nvgFillColor(vg, ct(col, a))
    nvgFill(vg)
end

--- 立体球体（所有珠子的基础）
function Art.Sphere(vg, x, y, r, base, a)
    a = a or 255
    local hi = Art.mix(base, { 255, 255, 255 }, 0.75)
    local lo = Art.mix(base, { 0, 0, 0 }, 0.55)
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, r)
    nvgFillPaint(vg, nvgRadialGradient(vg, x - r * 0.35, y - r * 0.4, r * 0.1, r * 1.25, ct(hi, a), ct(lo, a)))
    nvgFill(vg)
    -- 高光
    nvgBeginPath(vg)
    nvgEllipse(vg, x - r * 0.32, y - r * 0.4, r * 0.32, r * 0.2)
    nvgFillColor(vg, rgba(255, 255, 255, a * 0.85))
    nvgFill(vg)
end

function Art.Text(vg, x, y, text, size, col, a, bold, align)
    nvgFontFace(vg, bold and Art.FONT_BOLD or Art.FONT)
    nvgFontSize(vg, size)
    nvgTextAlign(vg, align or (NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE))
    nvgFillColor(vg, ct(col, a))
    nvgText(vg, x, y, text)
end

--- 描边大字（NanoVG 无原生描边：8 方向偏移叠画）
function Art.TextStroke(vg, x, y, text, size, col, strokeCol, sw, a, bold)
    a = a or 255
    nvgFontFace(vg, bold == false and Art.FONT or Art.FONT_BOLD)
    nvgFontSize(vg, size)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, ct(strokeCol, a))
    for i = 0, 7 do
        local ang = i * pi / 4
        nvgText(vg, x + cos(ang) * sw, y + sin(ang) * sw, text)
    end
    nvgFillColor(vg, ct(col, a))
    nvgText(vg, x, y, text)
end

function Art.Lock(vg, cx, cy, s, a)
    a = a or 255
    local u = s / 100
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 26 * u, cy - 6 * u, 52 * u, 40 * u, 8 * u)
    nvgFillColor(vg, rgba(170, 160, 190, a))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy - 6 * u, 17 * u, pi, 0, NVG_CW)
    nvgStrokeWidth(vg, 8 * u)
    nvgStrokeColor(vg, rgba(170, 160, 190, a))
    nvgStroke(vg)
    Art.Circle(vg, cx, cy + 12 * u, 6 * u, { 60, 50, 80 }, a)
end

function Art.Coin(vg, cx, cy, r, a)
    a = a or 255
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r)
    nvgFillPaint(vg, nvgRadialGradient(vg, cx - r * 0.3, cy - r * 0.3, r * 0.1, r * 1.1, rgba(255, 245, 170, a), rgba(225, 140, 20, a)))
    nvgFill(vg)
    Art.Ring(vg, cx, cy, r * 0.72, r * 0.12, { 200, 120, 10 }, a)
    Art.Text(vg, cx, cy + r * 0.05, "$", r * 1.1, { 170, 90, 0 }, a, true)
end

-- ---------------------------------------------------------------------------
-- 珠子
-- ---------------------------------------------------------------------------
Art.BALL_COLORS = {
    steel = { 200, 210, 225 }, gold = { 255, 196, 50 }, fire = { 255, 110, 40 },
    split = { 60, 220, 200 }, heavy = { 110, 110, 130 }, ghost = { 200, 180, 255 },
    prism = { 255, 255, 255 }, rubber = { 255, 110, 170 }, lucky = { 90, 230, 110 },
}

function Art.Ball(vg, kind, x, y, r, t, a)
    t = t or 0
    a = a or 255
    local base = Art.BALL_COLORS[kind] or Art.BALL_COLORS.steel
    if kind == "fire" then
        local fl = 0.8 + 0.2 * sin(t * 20 + x)
        Art.Glow(vg, x, y, r * 2.4 * fl, { 255, 120, 30 }, a * 0.55)
    elseif kind == "gold" then
        Art.Glow(vg, x, y, r * 2.0, { 255, 210, 80 }, a * 0.35)
    elseif kind == "ghost" then
        a = a * 0.75
    elseif kind == "lucky" then
        Art.Glow(vg, x, y, r * 2.2, { 120, 255, 140 }, a * 0.35)
    end
    if kind == "prism" then
        local hue = (t * 0.6 + x * 0.01) % 1
        base = Art.hsv(hue, 0.55, 1)
    end
    Art.Sphere(vg, x, y, r, base, a)
    if kind == "split" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - r * 0.8, y); nvgLineTo(vg, x + r * 0.8, y)
        nvgMoveTo(vg, x, y - r * 0.8); nvgLineTo(vg, x, y + r * 0.8)
        nvgStrokeWidth(vg, max(1, r * 0.18))
        nvgStrokeColor(vg, rgba(10, 90, 80, a))
        nvgStroke(vg)
    elseif kind == "heavy" then
        for i = 0, 5 do
            local ang = i * pi / 3 + 0.3
            Art.Circle(vg, x + cos(ang) * r * 0.68, y + sin(ang) * r * 0.68, r * 0.11, { 60, 60, 70 }, a)
        end
    elseif kind == "ghost" then
        Art.Circle(vg, x - r * 0.3, y, r * 0.16, { 40, 20, 80 }, a)
        Art.Circle(vg, x + r * 0.3, y, r * 0.16, { 40, 20, 80 }, a)
    elseif kind == "rubber" then
        nvgBeginPath(vg)
        nvgArc(vg, x, y, r * 0.62, pi * 0.15, pi * 0.85, NVG_CW)
        nvgStrokeWidth(vg, max(1, r * 0.22))
        nvgStrokeColor(vg, rgba(255, 255, 255, a * 0.9))
        nvgStroke(vg)
    elseif kind == "lucky" then
        for i = 0, 3 do
            local ang = i * pi / 2 + pi / 4
            Art.Circle(vg, x + cos(ang) * r * 0.26, y + sin(ang) * r * 0.26, r * 0.24, { 30, 140, 50 }, a)
        end
    elseif kind == "fire" then
        Art.Circle(vg, x, y + r * 0.1, r * 0.35, { 255, 240, 150 }, a * 0.8)
    end
end

--- 珠子图标（格子 / 详情用，带底光）
function Art.BallIcon(vg, kind, cx, cy, s, t)
    local img = tryImage(vg, "ball:" .. kind)
    if img then drawImage(vg, img, cx, cy, s); return end
    local col = Art.BALL_COLORS[kind] or Art.BALL_COLORS.steel
    Art.Glow(vg, cx, cy, s * 0.5, col, 90)
    Art.Ball(vg, kind, cx, cy, s * 0.3, t or 0, 255)
end

-- ---------------------------------------------------------------------------
-- 钉子
-- ---------------------------------------------------------------------------
function Art.Peg(vg, p, t, fever)
    local x, y, r = p.x, p.y, p.r
    local tp = p.type
    if not p.alive then
        if p.pop and p.pop > 0 then
            local k = 1 - p.pop
            Art.Ring(vg, x, y, r + k * 14, 2 * p.pop, { 255, 255, 255 }, 255 * p.pop)
        end
        Art.Circle(vg, x, y, r * 0.6, { 60, 60, 80 }, 120)
        return
    end
    local flash = p.flash or 0
    if tp == "normal" then
        local col = fever and Art.hsv((t * 0.5 + (x + y) * 0.004) % 1, 0.35, 1) or { 205, 215, 235 }
        if flash > 0 then
            Art.Glow(vg, x, y, r * 4, { 255, 255, 255 }, 160 * flash)
        end
        nvgBeginPath(vg)
        nvgCircle(vg, x, y, r)
        nvgFillPaint(vg, nvgRadialGradient(vg, x - r * 0.4, y - r * 0.4, 0.5, r * 1.4,
            rgba(255, 255, 255, 255), ct(col, 255)))
        nvgFill(vg)
        return
    end
    local img = tryImage(vg, "peg:" .. tp)
    if img then
        if flash > 0 then Art.Glow(vg, x, y, r * 4, { 255, 255, 255 }, 160 * flash) end
        drawImage(vg, img, x, y, r * (tp == "normal" and 2.6 or 3.4))
        return
    end
    local col = ({ gold = { 255, 200, 60 }, red = { 255, 70, 80 }, purple = { 190, 90, 255 },
        bomb = { 255, 130, 30 }, split = { 60, 230, 200 }, bumper = { 80, 200, 255 } })[tp] or { 255, 255, 255 }
    local pulse = 0.75 + 0.25 * sin(t * 6 + x * 0.1)
    Art.Glow(vg, x, y, r * 3.4 * pulse + flash * 6, col, 150 + 90 * flash)
    if tp == "bumper" then
        Art.Circle(vg, x, y, r + 1.5, { 20, 60, 110 }, 255)
        Art.Sphere(vg, x, y, r, col, 255)
        Art.Ring(vg, x, y, r + 2 + flash * 4, 1.5, { 200, 240, 255 }, 200)
    elseif tp == "purple" then
        Art.StarPath(vg, x, y, r * 1.7, 0.5, 4, t * 2)
        nvgFillColor(vg, ct(col))
        nvgFill(vg)
        Art.Circle(vg, x, y, r * 0.55, { 255, 230, 255 }, 255)
    elseif tp == "bomb" then
        Art.Sphere(vg, x, y, r * 1.25, { 60, 50, 60 }, 255)
        local sp = 0.6 + 0.4 * sin(t * 18 + y)
        Art.Star(vg, x + r * 0.9, y - r * 1.1, r * 0.8 * sp, { 255, 220, 80 }, 255, t * 5)
    elseif tp == "split" then
        Art.Sphere(vg, x, y, r * 1.2, col, 255)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - r * 0.6, y); nvgLineTo(vg, x + r * 0.6, y)
        nvgStrokeWidth(vg, max(1, r * 0.3))
        nvgStrokeColor(vg, rgba(10, 80, 70))
        nvgStroke(vg)
    else
        Art.Sphere(vg, x, y, r * 1.2, col, 255)
    end
end

-- ---------------------------------------------------------------------------
-- 老虎机符号
-- ---------------------------------------------------------------------------
function Art.SlotSymbol(vg, sym, cx, cy, s, t, a)
    a = a or 255
    local img = tryImage(vg, "slot:" .. sym)
    if img then drawImage(vg, img, cx, cy, s); return end
    local u = s / 100
    if sym == "seven" then
        Art.TextStroke(vg, cx, cy + 2 * u, "7", 92 * u, { 255, 60, 70 }, { 255, 220, 80 }, 3.5 * u, a)
    elseif sym == "star" then
        Art.Star(vg, cx, cy, 42 * u, { 255, 210, 50 }, a)
        Art.Star(vg, cx, cy, 22 * u, { 255, 250, 200 }, a)
    elseif sym == "cherry" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - 18 * u, cy + 8 * u)
        nvgQuadTo(vg, cx - 4 * u, cy - 30 * u, cx + 14 * u, cy - 36 * u)
        nvgMoveTo(vg, cx + 18 * u, cy + 12 * u)
        nvgQuadTo(vg, cx + 14 * u, cy - 14 * u, cx + 14 * u, cy - 36 * u)
        nvgStrokeWidth(vg, 5 * u)
        nvgStrokeColor(vg, rgba(80, 170, 60, a))
        nvgStroke(vg)
        Art.Sphere(vg, cx - 18 * u, cy + 18 * u, 18 * u, { 230, 30, 60 }, a)
        Art.Sphere(vg, cx + 18 * u, cy + 22 * u, 18 * u, { 230, 30, 60 }, a)
    elseif sym == "bell" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - 34 * u, cy + 24 * u)
        nvgBezierTo(vg, cx - 30 * u, cy - 40 * u, cx + 30 * u, cy - 40 * u, cx + 34 * u, cy + 24 * u)
        nvgClosePath(vg)
        nvgFillPaint(vg, nvgLinearGradient(vg, cx - 30 * u, cy, cx + 30 * u, cy, rgba(255, 240, 140, a), rgba(220, 150, 20, a)))
        nvgFill(vg)
        Art.Circle(vg, cx, cy + 30 * u, 9 * u, { 200, 120, 10 }, a)
    else
        Art.Sphere(vg, cx, cy, 32 * u, { 120, 200, 255 }, a)
    end
end

-- ---------------------------------------------------------------------------
-- 护符图标（16 个）
-- ---------------------------------------------------------------------------
local CHARM = {}

CHARM.lantern = function(vg, cx, cy, u, t)
    Art.Glow(vg, cx, cy, 52 * u, { 255, 80, 60 }, 120)
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, cy + 2 * u, 30 * u, 34 * u)
    nvgFillPaint(vg, nvgRadialGradient(vg, cx, cy, 4 * u, 36 * u, rgba(255, 170, 90), rgba(210, 20, 30)))
    nvgFill(vg)
    for i = -2, 2 do
        nvgBeginPath(vg)
        nvgEllipse(vg, cx, cy + 2 * u, abs(i) * 7 * u + 0.5, 34 * u)
        nvgStrokeWidth(vg, 1.5 * u)
        nvgStrokeColor(vg, rgba(150, 0, 10, 160))
        nvgStroke(vg)
    end
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 16 * u, cy - 38 * u, 32 * u, 9 * u, 3 * u)
    nvgRoundedRect(vg, cx - 16 * u, cy + 31 * u, 32 * u, 9 * u, 3 * u)
    nvgFillColor(vg, rgba(255, 200, 60))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, cy + 40 * u)
    nvgLineTo(vg, cx + sin(t * 3) * 3 * u, cy + 50 * u)
    nvgStrokeWidth(vg, 3 * u)
    nvgStrokeColor(vg, rgba(255, 200, 60))
    nvgStroke(vg)
end

CHARM.cat = function(vg, cx, cy, u, t)
    local wave = sin(t * 5) * 0.35
    -- 招手
    nvgSave(vg)
    nvgTranslate(vg, cx + 26 * u, cy - 4 * u)
    nvgRotate(vg, wave)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -7 * u, -26 * u, 14 * u, 26 * u, 7 * u)
    nvgFillColor(vg, rgba(255, 255, 255))
    nvgFill(vg)
    nvgRestore(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - 30 * u, cy - 6 * u); nvgLineTo(vg, cx - 24 * u, cy - 38 * u); nvgLineTo(vg, cx - 8 * u, cy - 22 * u)
    nvgMoveTo(vg, cx + 30 * u, cy - 6 * u); nvgLineTo(vg, cx + 24 * u, cy - 38 * u); nvgLineTo(vg, cx + 8 * u, cy - 22 * u)
    nvgFillColor(vg, rgba(255, 255, 255))
    nvgFill(vg)
    Art.Circle(vg, cx, cy + 4 * u, 30 * u, { 255, 255, 255 }, 255)
    Art.Circle(vg, cx - 24 * u, cy - 28 * u, 5 * u, { 255, 150, 170 }, 255)
    -- 眯眼
    for s = -1, 1, 2 do
        nvgBeginPath(vg)
        nvgArc(vg, cx + s * 11 * u, cy, 6 * u, pi * 1.1, pi * 1.9, NVG_CW)
        nvgStrokeWidth(vg, 2.5 * u)
        nvgStrokeColor(vg, rgba(40, 30, 40))
        nvgStroke(vg)
    end
    Art.Circle(vg, cx, cy + 9 * u, 3 * u, { 255, 120, 140 }, 255)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 26 * u, cy + 22 * u, 52 * u, 7 * u, 3 * u)
    nvgFillColor(vg, rgba(220, 30, 40))
    nvgFill(vg)
    Art.Sphere(vg, cx, cy + 32 * u, 7 * u, { 255, 200, 50 }, 255)
end

CHARM.cracker = function(vg, cx, cy, u, t)
    for i = -1, 1 do
        nvgSave(vg)
        nvgTranslate(vg, cx + i * 16 * u, cy + 8 * u)
        nvgRotate(vg, i * 0.25)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -8 * u, -26 * u, 16 * u, 48 * u, 4 * u)
        nvgFillPaint(vg, nvgLinearGradient(vg, -8 * u, 0, 8 * u, 0, rgba(255, 90, 80), rgba(170, 10, 20)))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, -8 * u, -6 * u, 16 * u, 6 * u)
        nvgFillColor(vg, rgba(255, 210, 70))
        nvgFill(vg)
        nvgRestore(vg)
    end
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, cy - 18 * u)
    nvgQuadTo(vg, cx + 8 * u, cy - 34 * u, cx + 20 * u, cy - 36 * u)
    nvgStrokeWidth(vg, 2.5 * u)
    nvgStrokeColor(vg, rgba(240, 220, 180))
    nvgStroke(vg)
    local sp = 0.7 + 0.3 * sin(t * 16)
    Art.Glow(vg, cx + 22 * u, cy - 37 * u, 18 * u * sp, { 255, 220, 80 }, 220)
    Art.Star(vg, cx + 22 * u, cy - 37 * u, 9 * u * sp, { 255, 255, 200 }, 255, t * 4)
end

CHARM.pinwheel = function(vg, cx, cy, u, t)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, cy); nvgLineTo(vg, cx + 4 * u, cy + 46 * u)
    nvgStrokeWidth(vg, 4 * u)
    nvgStrokeColor(vg, rgba(200, 160, 110))
    nvgStroke(vg)
    local cols = { { 255, 80, 100 }, { 255, 210, 60 }, { 70, 200, 255 }, { 120, 240, 120 } }
    for i = 0, 3 do
        local a = t * 3 + i * pi / 2
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy)
        nvgLineTo(vg, cx + cos(a) * 34 * u, cy + sin(a) * 34 * u)
        nvgLineTo(vg, cx + cos(a + 0.9) * 22 * u, cy + sin(a + 0.9) * 22 * u)
        nvgClosePath(vg)
        nvgFillColor(vg, ct(cols[i + 1]))
        nvgFill(vg)
    end
    Art.Circle(vg, cx, cy, 5 * u, { 255, 255, 255 }, 255)
end

CHARM.soul = function(vg, cx, cy, u, t)
    local f = sin(t * 8) * 3 * u
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, cy - 42 * u + f)
    nvgBezierTo(vg, cx + 14 * u, cy - 20 * u, cx + 32 * u, cy, cx + 26 * u, cy + 18 * u)
    nvgBezierTo(vg, cx + 20 * u, cy + 38 * u, cx - 20 * u, cy + 38 * u, cx - 26 * u, cy + 18 * u)
    nvgBezierTo(vg, cx - 32 * u, cy, cx - 10 * u, cy - 14 * u, cx, cy - 42 * u + f)
    nvgFillPaint(vg, nvgRadialGradient(vg, cx, cy + 14 * u, 4 * u, 40 * u, rgba(220, 250, 255), rgba(40, 120, 255)))
    nvgFill(vg)
    Art.Circle(vg, cx - 9 * u, cy + 14 * u, 4 * u, { 10, 30, 90 }, 255)
    Art.Circle(vg, cx + 9 * u, cy + 14 * u, 4 * u, { 10, 30, 90 }, 255)
end

CHARM.drum = function(vg, cx, cy, u, t)
    local hit = max(0, sin(t * 7)) * 4 * u
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 32 * u, cy - 18 * u, 64 * u, 44 * u, 14 * u)
    nvgFillPaint(vg, nvgLinearGradient(vg, cx, cy - 18 * u, cx, cy + 26 * u, rgba(190, 90, 40), rgba(110, 40, 20)))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, cy - 18 * u, 32 * u, 10 * u)
    nvgFillColor(vg, rgba(250, 235, 200))
    nvgFill(vg)
    Art.Ring(vg, cx, cy - 18 * u, 6 * u, 2.5 * u, { 220, 40, 40 }, 255)
    for s = -1, 1, 2 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + s * 40 * u, cy - 44 * u)
        nvgLineTo(vg, cx + s * 8 * u, cy - 22 * u - hit)
        nvgStrokeWidth(vg, 5 * u)
        nvgStrokeColor(vg, rgba(240, 200, 140))
        nvgStroke(vg)
    end
end

CHARM.kannon = function(vg, cx, cy, u, t)
    Art.Glow(vg, cx, cy, 50 * u, { 255, 210, 90 }, 180)
    Art.Ring(vg, cx, cy, 34 * u, 3 * u, { 255, 220, 120 }, 255)
    for i = 0, 11 do
        local a = i * pi / 6 + t * 0.6
        local x1, y1 = cx + cos(a) * 16 * u, cy + sin(a) * 16 * u
        local x2, y2 = cx + cos(a) * 34 * u, cy + sin(a) * 34 * u
        nvgBeginPath(vg)
        nvgMoveTo(vg, x1, y1); nvgLineTo(vg, x2, y2)
        nvgStrokeWidth(vg, 3 * u)
        nvgStrokeColor(vg, rgba(255, 200, 120))
        nvgStroke(vg)
        Art.Sphere(vg, x2, y2, 5 * u, { 220, 225, 240 }, 255)
    end
    Art.Sphere(vg, cx, cy, 14 * u, { 255, 200, 60 }, 255)
end

CHARM.spring = function(vg, cx, cy, u, t)
    local sq = 1 + 0.15 * sin(t * 8)
    nvgBeginPath(vg)
    local top = cy - 30 * u * sq
    nvgMoveTo(vg, cx - 18 * u, cy + 20 * u)
    for i = 0, 6 do
        local y = cy + 20 * u - (i + 1) * (cy + 20 * u - top) / 7
        nvgLineTo(vg, cx + ((i % 2 == 0) and 18 or -18) * u, y)
    end
    nvgStrokeWidth(vg, 4 * u)
    nvgStrokeColor(vg, rgba(120, 220, 255))
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 30 * u, cy + 20 * u, 60 * u, 14 * u, 6 * u)
    nvgFillColor(vg, rgba(255, 110, 80))
    nvgFill(vg)
    Art.Sphere(vg, cx, top - 10 * u, 10 * u, { 80, 200, 255 }, 255)
end

CHARM.feather = function(vg, cx, cy, u, t)
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, -0.6 + sin(t * 2) * 0.12)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -44 * u)
    nvgBezierTo(vg, 22 * u, -24 * u, 16 * u, 22 * u, 0, 40 * u)
    nvgBezierTo(vg, -16 * u, 22 * u, -22 * u, -24 * u, 0, -44 * u)
    nvgFillPaint(vg, nvgLinearGradient(vg, 0, -44 * u, 0, 40 * u, rgba(255, 255, 255), rgba(170, 220, 255)))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -40 * u); nvgLineTo(vg, 0, 48 * u)
    nvgStrokeWidth(vg, 2.5 * u)
    nvgStrokeColor(vg, rgba(120, 150, 200))
    nvgStroke(vg)
    nvgRestore(vg)
end

CHARM.miser = function(vg, cx, cy, u, t)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - 10 * u, cy - 20 * u)
    nvgBezierTo(vg, cx - 44 * u, cy, cx - 36 * u, cy + 36 * u, cx, cy + 36 * u)
    nvgBezierTo(vg, cx + 36 * u, cy + 36 * u, cx + 44 * u, cy, cx + 10 * u, cy - 20 * u)
    nvgClosePath(vg)
    nvgFillPaint(vg, nvgRadialGradient(vg, cx - 8 * u, cy + 6 * u, 4 * u, 44 * u, rgba(220, 170, 110), rgba(130, 80, 40)))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 14 * u, cy - 26 * u, 28 * u, 8 * u, 3 * u)
    nvgFillColor(vg, rgba(200, 40, 40))
    nvgFill(vg)
    Art.Text(vg, cx, cy + 12 * u, "$", 30 * u, { 255, 220, 90 }, 255, true)
    Art.Coin(vg, cx + 30 * u, cy - 26 * u + sin(t * 4) * 3 * u, 10 * u)
end

CHARM.combo = function(vg, cx, cy, u, t)
    Art.Glow(vg, cx, cy, 46 * u, { 255, 230, 80 }, 120 + 60 * sin(t * 10))
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + 8 * u, cy - 44 * u)
    nvgLineTo(vg, cx - 20 * u, cy + 4 * u)
    nvgLineTo(vg, cx - 2 * u, cy + 4 * u)
    nvgLineTo(vg, cx - 10 * u, cy + 44 * u)
    nvgLineTo(vg, cx + 22 * u, cy - 8 * u)
    nvgLineTo(vg, cx + 4 * u, cy - 8 * u)
    nvgClosePath(vg)
    nvgFillColor(vg, rgba(255, 230, 60))
    nvgFill(vg)
    Art.TextStroke(vg, cx + 22 * u, cy + 28 * u, "15", 22 * u, { 255, 255, 255 }, { 200, 40, 40 }, 2 * u)
end

CHARM.goldrule = function(vg, cx, cy, u, t)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - 36 * u, cy + 22 * u)
    nvgLineTo(vg, cx - 22 * u, cy - 14 * u)
    nvgLineTo(vg, cx + 22 * u, cy - 14 * u)
    nvgLineTo(vg, cx + 36 * u, cy + 22 * u)
    nvgClosePath(vg)
    nvgFillPaint(vg, nvgLinearGradient(vg, cx, cy - 14 * u, cx, cy + 22 * u, rgba(255, 245, 160), rgba(220, 140, 20)))
    nvgFill(vg)
    local sh = (t * 0.8) % 1
    Art.Star(vg, cx - 30 * u + sh * 60 * u, cy - 6 * u, 7 * u, { 255, 255, 255 }, 230, t)
    Art.Text(vg, cx, cy + 6 * u, "金", 18 * u, { 160, 90, 0 }, 255, true)
end

CHARM.lastshot = function(vg, cx, cy, u, t)
    Art.Circle(vg, cx, cy, 38 * u, { 255, 255, 255 }, 255)
    Art.Circle(vg, cx, cy, 30 * u, { 230, 40, 50 }, 255)
    Art.Circle(vg, cx, cy, 21 * u, { 255, 255, 255 }, 255)
    Art.Circle(vg, cx, cy, 12 * u, { 230, 40, 50 }, 255)
    Art.TextStroke(vg, cx + 16 * u, cy + 26 * u, "×3", 24 * u, { 255, 230, 80 }, { 60, 0, 0 }, 2.5 * u)
end

CHARM.prismlens = function(vg, cx, cy, u, t)
    for i = 0, 5 do
        local c = Art.hsv(i / 6 + t * 0.1, 0.8, 1)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + 4 * u, cy)
        nvgLineTo(vg, cx + 46 * u, cy - 18 * u + i * 7 * u)
        nvgStrokeWidth(vg, 3 * u)
        nvgStrokeColor(vg, ct(c, 230))
        nvgStroke(vg)
    end
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - 8 * u, cy - 34 * u)
    nvgLineTo(vg, cx + 22 * u, cy + 26 * u)
    nvgLineTo(vg, cx - 38 * u, cy + 26 * u)
    nvgClosePath(vg)
    nvgFillPaint(vg, nvgLinearGradient(vg, cx - 30 * u, cy, cx + 20 * u, cy, rgba(255, 255, 255, 230), rgba(180, 140, 255, 200)))
    nvgFill(vg)
end

CHARM.boomer = function(vg, cx, cy, u, t)
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, t * 2.5)
    nvgBeginPath(vg)
    nvgMoveTo(vg, -34 * u, -8 * u)
    nvgQuadTo(vg, 0, -30 * u, 34 * u, -8 * u)
    nvgLineTo(vg, 28 * u, 4 * u)
    nvgQuadTo(vg, 0, -14 * u, -28 * u, 4 * u)
    nvgClosePath(vg)
    nvgFillPaint(vg, nvgLinearGradient(vg, -30 * u, 0, 30 * u, 0, rgba(255, 180, 80), rgba(200, 90, 30)))
    nvgFill(vg)
    nvgRestore(vg)
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy, 40 * u, 0.2, pi * 1.2, NVG_CW)
    nvgStrokeWidth(vg, 2.5 * u)
    nvgStrokeColor(vg, rgba(255, 255, 255, 120))
    nvgStroke(vg)
end

CHARM.rain = function(vg, cx, cy, u, t)
    for i = 0, 4 do
        local ph = (t * 1.2 + i * 0.23) % 1
        Art.Sphere(vg, cx - 24 * u + i * 12 * u, cy - 4 * u + ph * 44 * u, 5 * u, { 210, 220, 235 }, 255 * (1 - ph))
    end
    nvgBeginPath(vg)
    nvgCircle(vg, cx - 16 * u, cy - 18 * u, 16 * u)
    nvgCircle(vg, cx + 4 * u, cy - 28 * u, 20 * u)
    nvgCircle(vg, cx + 22 * u, cy - 16 * u, 14 * u)
    nvgRoundedRect(vg, cx - 32 * u, cy - 20 * u, 66 * u, 18 * u, 9 * u)
    nvgFillColor(vg, rgba(235, 240, 255))
    nvgFill(vg)
end

function Art.CharmIcon(vg, id, cx, cy, s, t)
    local img = tryImage(vg, "charm:" .. id)
    if img then drawImage(vg, img, cx, cy, s); return end
    local f = CHARM[id]
    if f then
        f(vg, cx, cy, s / 100, t or 0)
    else
        Art.Text(vg, cx, cy, "?", s * 0.5, { 255, 255, 255 }, 255, true)
    end
end

-- ---------------------------------------------------------------------------
-- 改造 / 服务图标
-- ---------------------------------------------------------------------------
local PEGMOD = { redpeg = "red", goldpeg = "gold", purppeg = "purple", bombpeg = "bomb", splitpeg = "split" }

function Art.ModIcon(vg, id, cx, cy, s, t)
    local img = tryImage(vg, "mod:" .. id)
    if img then drawImage(vg, img, cx, cy, s); return end
    local u = s / 100
    t = t or 0
    if PEGMOD[id] then
        local fake = { x = cx - 6 * u, y = cy + 4 * u, r = 16 * u, type = PEGMOD[id], alive = true, flash = 0 }
        Art.Peg(vg, fake, t, false)
        local n = ({ redpeg = "+2", goldpeg = "+3", purppeg = "+1", bombpeg = "+1", splitpeg = "+2" })[id]
        Art.TextStroke(vg, cx + 22 * u, cy - 22 * u, n, 26 * u, { 255, 255, 255 }, { 20, 10, 40 }, 2.5 * u)
    elseif id == "mag" then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - 18 * u, cy - 40 * u, 36 * u, 80 * u, 10 * u)
        nvgFillColor(vg, rgba(60, 60, 90, 220))
        nvgFill(vg)
        for i = 0, 4 do Art.Sphere(vg, cx, cy - 30 * u + i * 15 * u, 7 * u, { 210, 220, 235 }, 255) end
        Art.TextStroke(vg, cx + 28 * u, cy - 26 * u, "+2", 24 * u, { 120, 255, 150 }, { 10, 40, 20 }, 2.5 * u)
    elseif id == "launch" then
        Art.Sphere(vg, cx - 6 * u, cy + 14 * u, 18 * u, { 210, 220, 235 }, 255)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - 6 * u, cy - 42 * u)
        nvgLineTo(vg, cx + 14 * u, cy - 16 * u)
        nvgLineTo(vg, cx - 26 * u, cy - 16 * u)
        nvgClosePath(vg)
        nvgFillColor(vg, rgba(255, 200, 60))
        nvgFill(vg)
        Art.TextStroke(vg, cx + 26 * u, cy + 24 * u, "+1", 24 * u, { 255, 255, 255 }, { 120, 60, 0 }, 2.5 * u)
    elseif id == "remove" then
        Art.Glow(vg, cx, cy + 10 * u, 40 * u, { 255, 100, 30 }, 160)
        Art.Sphere(vg, cx, cy, 22 * u, { 210, 220, 235 }, 255)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - 28 * u, cy - 28 * u); nvgLineTo(vg, cx + 28 * u, cy + 28 * u)
        nvgMoveTo(vg, cx + 28 * u, cy - 28 * u); nvgLineTo(vg, cx - 28 * u, cy + 28 * u)
        nvgStrokeWidth(vg, 7 * u)
        nvgStrokeColor(vg, rgba(255, 70, 70))
        nvgStroke(vg)
    end
end

-- ---------------------------------------------------------------------------
-- 台主立绘（程序化 Q 版头像）
-- ---------------------------------------------------------------------------
function Art.Portrait(vg, key, cx, cy, s, t)
    local img = tryImage(vg, "portrait:" .. key)
    if img then drawImage(vg, img, cx, cy, s); return end
    local u = s / 100
    t = t or 0
    local bob = sin(t * 2.5) * 1.5 * u
    cy = cy + bob
    local skin = { 255, 222, 196 }
    if key == "miao" then
        -- 招财猫
        Art.Glow(vg, cx, cy, 50 * u, { 255, 200, 60 }, 120)
        CHARM.cat(vg, cx, cy + 6 * u, u * 1.15, t)
        return
    end
    -- 身体
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 26 * u, cy + 22 * u, 52 * u, 30 * u, 14 * u)
    nvgFillColor(vg, key == "huo" and rgba(230, 60, 60) or rgba(60, 110, 220))
    nvgFill(vg)
    -- 头
    if key == "huo" then
        -- 火焰发髻
        for i = -1, 1 do
            local fl = 1 + 0.12 * sin(t * 10 + i)
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx + i * 14 * u - 10 * u, cy - 22 * u)
            nvgQuadTo(vg, cx + i * 16 * u, cy - 56 * u * fl, cx + i * 14 * u + 10 * u, cy - 22 * u)
            nvgFillColor(vg, rgba(255, 120 + i * 30, 30))
            nvgFill(vg)
        end
    end
    Art.Circle(vg, cx, cy, 28 * u, skin, 255)
    -- 头发
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy - 2 * u, 29 * u, pi, 0, NVG_CW)
    nvgClosePath(vg)
    nvgFillColor(vg, key == "huo" and rgba(200, 50, 30) or rgba(40, 40, 60))
    nvgFill(vg)
    if key == "tie" then
        -- 头带
        nvgBeginPath(vg)
        nvgRect(vg, cx - 29 * u, cy - 10 * u, 58 * u, 7 * u)
        nvgFillColor(vg, rgba(255, 255, 255))
        nvgFill(vg)
        Art.Circle(vg, cx, cy - 6.5 * u, 4 * u, { 230, 40, 50 }, 255)
    end
    -- 眼睛
    local blink = (t % 3.2) < 0.12
    for sgn = -1, 1, 2 do
        if blink then
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx + sgn * 11 * u - 4 * u, cy + 6 * u)
            nvgLineTo(vg, cx + sgn * 11 * u + 4 * u, cy + 6 * u)
            nvgStrokeWidth(vg, 2 * u)
            nvgStrokeColor(vg, rgba(30, 20, 30))
            nvgStroke(vg)
        else
            Art.Circle(vg, cx + sgn * 11 * u, cy + 6 * u, 5 * u, { 30, 20, 40 }, 255)
            Art.Circle(vg, cx + sgn * 11 * u - 1.5 * u, cy + 4.5 * u, 1.8 * u, { 255, 255, 255 }, 255)
        end
        Art.Circle(vg, cx + sgn * 19 * u, cy + 13 * u, 4 * u, { 255, 150, 150 }, 150)
    end
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy + 13 * u, 6 * u, 0.2, pi - 0.2, NVG_CW)
    nvgStrokeWidth(vg, 2 * u)
    nvgStrokeColor(vg, rgba(120, 40, 40))
    nvgStroke(vg)
    -- 手持物
    if key == "tie" then
        Art.Ball(vg, "steel", cx + 30 * u, cy + 30 * u, 10 * u, t)
    else
        Art.Ball(vg, "fire", cx + 30 * u, cy + 30 * u, 10 * u, t)
    end
end

function Art.Gear(vg, cx, cy, s, a)
    a = a or 255
    local r1, r2 = s * 0.46, s * 0.34
    nvgBeginPath(vg)
    for i = 0, 15 do
        local ang = i * pi / 8
        local r = (i % 2 == 0) and r1 or r2
        local x, y = cx + cos(ang) * r, cy + sin(ang) * r
        if i == 0 then nvgMoveTo(vg, x, y) else nvgLineTo(vg, x, y) end
    end
    nvgClosePath(vg)
    nvgFillColor(vg, rgba(230, 225, 245, a))
    nvgFill(vg)
    Art.Circle(vg, cx, cy, s * 0.15, { 48, 36, 84 }, a)
end

function Art.Icon(vg, kind, id, cx, cy, s, t)
    if kind == "ball" then Art.BallIcon(vg, id, cx, cy, s, t)
    elseif kind == "charm" then Art.CharmIcon(vg, id, cx, cy, s, t)
    elseif kind == "mod" then Art.ModIcon(vg, id, cx, cy, s, t)
    elseif kind == "portrait" then Art.Portrait(vg, id, cx, cy, s, t)
    elseif kind == "coin" then Art.Coin(vg, cx, cy, s * 0.42)
    elseif kind == "lock" then Art.Lock(vg, cx, cy, s)
    elseif kind == "gear" then Art.Gear(vg, cx, cy, s)
    end
end

return Art
