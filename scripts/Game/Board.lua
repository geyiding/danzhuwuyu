-- ============================================================================
-- Board.lua · 台面生成：墙 / 圆弧 / 液晶 / 启动口 / 钉阵 / 口袋
-- 钉阵按 layout 模板生成（hex / waves / diamond / lanes），特殊钉每发重新随机布置。
-- ============================================================================

local C = require("Game/Config")

local Board = {}
Board.__index = Board

local B = C.BOARD
local pi, cos, sin, sqrt, floor, abs = math.pi, math.cos, math.sin, math.sqrt, math.floor, math.abs

local function inBlocked(x, y)
    -- 顶部圆弧之外
    local dx, dy = x - B.arcCx, y - B.arcCy
    if y < B.arcCy and dx * dx + dy * dy > (B.arcR - 22) ^ 2 then return true end
    if x < B.wallL + 10 or x > B.wallR - 10 then return true end
    -- 液晶周围
    local L = B.lcd
    if x > L.x - 16 and x < L.x + L.w + 16 and y > L.y - 16 and y < L.y + L.h + 18 then return true end
    -- 启动口周围
    local sx, sy = x - B.start.x, y - B.start.y
    if sx * sx + sy * sy < 26 * 26 then return true end
    return false
end

--- 生成钉位
local function genPegPositions(layout, rng)
    local pts = {}
    local sx, sy = 28, 25
    local rows = floor((B.fieldBottom - 120) / sy)
    local y0 = 120
    for row = 0, rows do
        local y = y0 + row * sy
        local off = (row % 2 == 1) and sx / 2 or 0
        local wave = 0
        if layout == "waves" then wave = sin(row * 0.9) * 7 end
        local x = B.wallL + 14 + off
        local col = 0
        while x <= B.wallR - 14 do
            local px = x + wave
            local keep = true
            if layout == "diamond" then
                -- 菱形空洞：在网格上挖出几块菱形
                local cxs = { 96, 264, 180 }
                local cys = { 410, 410, 480 }
                for k = 1, 3 do
                    if abs(px - cxs[k]) / 30 + abs(y - cys[k]) / 22 < 1 then keep = false end
                end
            elseif layout == "lanes" then
                -- 竖直通道：每 4 列抽掉 1 列（下半区）
                if y > 360 and col % 4 == 2 then keep = false end
            end
            if keep and not inBlocked(px, y) then
                pts[#pts + 1] = { px, y }
            end
            x = x + sx
            col = col + 1
        end
    end
    return pts
end

function Board.new(opts)
    local self = setmetatable({}, Board)
    self.layout = opts.layout or "hex"
    self.rng = opts.rng
    self.pegs = {}
    self.segs = {}
    self.boxes = {}
    self.pockets = {}
    self.decor = {}
    self:_build()
    return self
end

function Board:_build()
    local pegs, segs = self.pegs, self.segs
    local id = 0
    local function addPeg(x, y, extra)
        id = id + 1
        local p = { id = id, x = x, y = y, r = B.pegR, type = "normal", alive = true, flash = 0 }
        if extra then for k, v in pairs(extra) do p[k] = v end end
        pegs[#pegs + 1] = p
        return p
    end

    for _, pt in ipairs(genPegPositions(self.layout, self.rng)) do addPeg(pt[1], pt[2]) end

    -- 启动口沿钉（固定普通钉，不参与特殊化）
    local S = B.start
    addPeg(S.x - S.rimGap, S.y - 2, { rim = true })
    addPeg(S.x + S.rimGap, S.y - 2, { rim = true })
    -- 命钉（漏斗）
    addPeg(S.x - 16, S.y - 24, { rim = true })
    addPeg(S.x + 16, S.y - 24, { rim = true })

    -- 侧墙
    segs[#segs + 1] = { x1 = B.wallL, y1 = B.arcCy, x2 = B.wallL, y2 = B.floor, tag = "wall" }
    segs[#segs + 1] = { x1 = B.wallR, y1 = B.arcCy, x2 = B.wallR, y2 = B.floor, tag = "wall" }
    -- 顶部圆弧（180°→360°）
    local N = 22
    for i = 0, N - 1 do
        local a1 = pi + pi * i / N
        local a2 = pi + pi * (i + 1) / N
        segs[#segs + 1] = {
            x1 = B.arcCx + cos(a1) * B.arcR, y1 = B.arcCy + sin(a1) * B.arcR,
            x2 = B.arcCx + cos(a2) * B.arcR, y2 = B.arcCy + sin(a2) * B.arcR,
            tag = "wall",
        }
    end
    -- 底部两侧导流斜板（把边缘珠子导回中间一点）
    segs[#segs + 1] = { x1 = B.wallL, y1 = B.fieldBottom + 6, x2 = B.wallL + 16, y2 = B.pocketTop - 6, tag = "wall" }
    segs[#segs + 1] = { x1 = B.wallR, y1 = B.fieldBottom + 6, x2 = B.wallR - 16, y2 = B.pocketTop - 6, tag = "wall" }

    -- 口袋隔板
    local n = #C.POCKETS
    local pw = (B.wallR - B.wallL) / n
    self.pocketW = pw
    for i = 1, n do
        local x0 = B.wallL + (i - 1) * pw
        local def = C.POCKETS[i]
        self.pockets[i] = { index = i, x = x0, w = pw, kind = def.kind, value = def.value, label = def.label, flash = 0, disabled = false }
        if i > 1 then
            segs[#segs + 1] = { x1 = x0, y1 = B.pocketTop, x2 = x0, y2 = B.floor, tag = "divider" }
            addPeg(x0, B.pocketTop, { rim = true, cap = true, r = 3 })
        end
    end

    -- 液晶
    local L = B.lcd
    self.boxes[1] = { x = L.x, y = L.y, w = L.w, h = L.h, r = L.r, tag = "lcd" }

    -- 可特殊化的钉子池
    self.pool = {}
    for _, p in ipairs(pegs) do
        if not p.rim then self.pool[#self.pool + 1] = p end
    end
    print(string.format("[Board] layout=%s pegs=%d pool=%d segs=%d", self.layout, #pegs, #self.pool, #segs))
end

--- 每发开始：复活所有钉、按数量表重新布置特殊钉
--- counts = { gold=4, red=5, ... }；bumperSet 为本台固定的弹力柱（只在台开始时决定）
function Board:Rearrange(counts, rng)
    for _, p in ipairs(self.pegs) do
        p.alive = true
        p.flash = 0
        p.pop = nil
        if not p.bumper then
            p.type = "normal"
            p.r = p.cap and 3 or B.pegR
        end
    end
    local free = {}
    for _, p in ipairs(self.pool) do
        if not p.bumper then free[#free + 1] = p end
    end
    rng:shuffle(free)
    local idx = 1
    for _, kind in ipairs(C.PEG_ORDER) do
        if kind ~= "bumper" then
            local n = counts[kind] or 0
            for _ = 1, n do
                local p = free[idx]
                if not p then break end
                p.type = kind
                idx = idx + 1
            end
        end
    end
end

--- 台开始：决定弹力柱位置（本台不变）
function Board:SetupBumpers(n, rng)
    for _, p in ipairs(self.pegs) do
        if p.bumper then p.bumper = nil; p.type = "normal"; p.r = B.pegR end
    end
    -- 优先放在中段两侧，避免挤在一起
    local cands = {}
    for _, p in ipairs(self.pool) do
        if p.y > 230 and p.y < 500 then cands[#cands + 1] = p end
    end
    rng:shuffle(cands)
    local placed = {}
    for _, p in ipairs(cands) do
        if #placed >= n then break end
        local ok = true
        for _, q in ipairs(placed) do
            local dx, dy = p.x - q.x, p.y - q.y
            if dx * dx + dy * dy < 70 * 70 then ok = false; break end
        end
        if ok then
            p.bumper = true
            p.type = "bumper"
            p.r = C.PEGS.bumper.r
            p.rest = 0.9
            placed[#placed + 1] = p
        end
    end
end

function Board:PocketAt(x)
    local i = floor((x - B.wallL) / self.pocketW) + 1
    if i < 1 then i = 1 elseif i > #self.pockets then i = #self.pockets end
    return self.pockets[i]
end

--- 发射轨道路径：返回 (x, y, angle) ；dist 为沿轨道的距离
function Board.RailPoint(dist, releaseAngleDeg)
    local up = B.railBottom - B.arcCy
    if dist <= up then
        return B.railX, B.railBottom - dist, false
    end
    local arcDist = dist - up
    local a = pi + arcDist / B.railR
    local aEnd = releaseAngleDeg * pi / 180
    if a >= aEnd then return nil end
    return B.arcCx + cos(a) * B.railR, B.arcCy + sin(a) * B.railR, a
end

function Board.RailLength(releaseAngleDeg)
    return (B.railBottom - B.arcCy) + (releaseAngleDeg * pi / 180 - pi) * B.railR
end

return Board
