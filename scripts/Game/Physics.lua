-- ============================================================================
-- Physics.lua · 轻量 2D 弹珠物理（纯 Lua，无引擎依赖，可无头测试）
--
-- 为什么不用 Box2D：弹珠台只需要「圆 vs 静态圆/线段/圆角矩形」+「圆 vs 圆」，
-- 自写物理可以 100% 控制手感（撞钉随机偏转 = 天意、弹力柱加速、穿透珠），
-- 并且能在纯 Lua 里跑数值模拟来校准关卡目标分。
--
-- 碰撞设计图（盘面单位 BU，y 向下）：
--
--   ┌────────── 顶部圆弧（线段近似，半径 156）──────────┐
--   │            ┌──────────────┐                       │
--   │  · · · ·   │  液晶 rbox   │   · · · ·            │  ← 钉子：静态圆 r=4
--   │ · · · · ·  └──────────────┘  · · · · ·           │
--   │  · · · ·  ·   ◖启动口◗  ·   · · · ·             │  ← 启动口：两颗沿钉 + 传感圆
--   │ · · · · · · · · · · · · · · · · · · ·            │
--   │  ◎弹力柱 · · · · · · · · · · · ◎                 │  ← 弹力柱：r=7，反弹时补速度
--   │ · · · · · · · · · · · · · · · · · · ·            │
--   ├──┬──┬──┬──┬──┬──┬──┤  ← 口袋隔板：竖线段
--   │回│25│+2│×2│+2│25│回│  ← y > pocketCapture 即判定落袋
--   └──┴──┴──┴──┴──┴──┴──┘
--   珠子：动态圆 r=6（重珠 9）
--
-- 检测目的：撞钉 → 回调计分；撞墙 → 回调（弹力珠加分）；珠珠互撞 → 只做物理
-- 边界情况：珠子擦边（只在 vn<0 时反弹）、珠子停在钉顶（随机偏转打破平衡）、
--          穿透珠（ghost>0 时不反弹但触发一次回调）、高速穿透（4 子步 + 限速）
-- ============================================================================

local Physics = {}
Physics.__index = Physics

local sqrt, floor, cos, sin, max, min = math.sqrt, math.floor, math.cos, math.sin, math.max, math.min

local CELL = 24

local function cellKey(cx, cy) return cy * 1024 + cx end

function Physics.new(opts)
    local self = setmetatable({}, Physics)
    self.gravity = opts.gravity or 760
    self.substeps = opts.substeps or 4
    self.maxSpeed = opts.maxSpeed or 980
    self.pegRest = opts.pegRest or 0.5
    self.wallRest = opts.wallRest or 0.45
    self.jitter = opts.jitter or 0.1
    self.ballBallRest = opts.ballBallRest or 0.6
    self.bumperKick = opts.bumperKick or 420
    self.rand = opts.rand or math.random
    self.balls = {}
    self.pegs = {}
    self.segs = {}
    self.boxes = {}
    self.pegGrid = {}
    self.segGrid = {}
    self.ballGrid = {}
    self.ballGridKeys = {}
    return self
end

-- ---------------------------------------------------------------------------
-- 静态体
-- ---------------------------------------------------------------------------
function Physics:SetStatic(pegs, segs, boxes)
    self.pegs, self.segs, self.boxes = pegs or {}, segs or {}, boxes or {}
    self.pegGrid, self.segGrid = {}, {}
    for _, p in ipairs(self.pegs) do
        local reach = p.r + 10
        for cy = floor((p.y - reach) / CELL), floor((p.y + reach) / CELL) do
            for cx = floor((p.x - reach) / CELL), floor((p.x + reach) / CELL) do
                local k = cellKey(cx, cy)
                local list = self.pegGrid[k]
                if not list then list = {}; self.pegGrid[k] = list end
                list[#list + 1] = p
            end
        end
    end
    for _, s in ipairs(self.segs) do
        local reach = 10
        local x0, x1 = min(s.x1, s.x2) - reach, max(s.x1, s.x2) + reach
        local y0, y1 = min(s.y1, s.y2) - reach, max(s.y1, s.y2) + reach
        for cy = floor(y0 / CELL), floor(y1 / CELL) do
            for cx = floor(x0 / CELL), floor(x1 / CELL) do
                local k = cellKey(cx, cy)
                local list = self.segGrid[k]
                if not list then list = {}; self.segGrid[k] = list end
                list[#list + 1] = s
            end
        end
    end
end

function Physics:AddBall(b)
    b.alive = true
    b.ghost = b.ghost or 0
    self.balls[#self.balls + 1] = b
    return b
end

function Physics:Clear()
    self.balls = {}
end

--- 移除死亡珠子（帧末调用，避免遍历中删除）
function Physics:Compact()
    local j = 0
    local balls = self.balls
    for i = 1, #balls do
        local b = balls[i]
        if b.alive then
            j = j + 1
            balls[j] = b
        end
    end
    for i = #balls, j + 1, -1 do balls[i] = nil end
end

-- ---------------------------------------------------------------------------
-- 反弹（带随机偏转）
-- ---------------------------------------------------------------------------
local function reflect(self, b, nx, ny, rest)
    local vn = b.vx * nx + b.vy * ny
    if vn >= 0 then return 0 end
    b.vx = b.vx - (1 + rest) * vn * nx
    b.vy = b.vy - (1 + rest) * vn * ny
    -- 切向轻微阻尼
    b.vx = b.vx * 0.985
    b.vy = b.vy * 0.985
    -- 天意：随机偏转
    local j = self.jitter
    if j > 0 then
        local a = (self.rand() - 0.5) * 2 * j
        local ca, sa = cos(a), sin(a)
        b.vx, b.vy = b.vx * ca - b.vy * sa, b.vx * sa + b.vy * ca
    end
    return -vn
end

-- ---------------------------------------------------------------------------
-- 单步
-- cb.peg(ball, peg, impact) / cb.seg(ball, seg, impact) / cb.box(ball, box, impact)
-- ---------------------------------------------------------------------------
function Physics:Step(dt, cb)
    local n = self.substeps
    local h = dt / n
    for _ = 1, n do
        self:_substep(h, cb)
    end
end

function Physics:_substep(h, cb)
    local g = self.gravity
    local maxV = self.maxSpeed
    local balls = self.balls
    local pegGrid, segGrid = self.pegGrid, self.segGrid

    for i = 1, #balls do
        local b = balls[i]
        if b.alive and not b.frozen then
            b.vy = b.vy + g * (b.gravityMul or 1) * h
            local sp2 = b.vx * b.vx + b.vy * b.vy
            if sp2 > maxV * maxV then
                local k = maxV / sqrt(sp2)
                b.vx, b.vy = b.vx * k, b.vy * k
            end
            b.x = b.x + b.vx * h
            b.y = b.y + b.vy * h
            if b.ghost > 0 then b.ghost = b.ghost - h end

            local cx, cy = floor(b.x / CELL), floor(b.y / CELL)
            local key = cellKey(cx, cy)

            -- 钉子
            local plist = pegGrid[key]
            if plist then
                for pi = 1, #plist do
                    local p = plist[pi]
                    if p.alive then
                        local dx, dy = b.x - p.x, b.y - p.y
                        local rr = b.r + p.r
                        local d2 = dx * dx + dy * dy
                        if d2 < rr * rr and d2 > 1e-6 then
                            local d = sqrt(d2)
                            local nx, ny = dx / d, dy / d
                            if b.ghost > 0 and not p.bumper then
                                -- 穿透：每颗钉只触发一次
                                b.ghostHits = b.ghostHits or {}
                                if not b.ghostHits[p] then
                                    b.ghostHits[p] = true
                                    if cb and cb.peg then cb.peg(b, p, 0) end
                                end
                            else
                                local pen = rr - d
                                b.x, b.y = b.x + nx * pen, b.y + ny * pen
                                local impact = reflect(self, b, nx, ny, p.rest or self.pegRest)
                                if p.bumper then
                                    local kick = self.bumperKick
                                    local vn = b.vx * nx + b.vy * ny
                                    if vn < kick then
                                        b.vx = b.vx + (kick - vn) * nx
                                        b.vy = b.vy + (kick - vn) * ny
                                    end
                                end
                                if impact > 0 and cb and cb.peg then cb.peg(b, p, impact) end
                            end
                        end
                    end
                end
            end

            -- 线段
            local slist = segGrid[key]
            if slist then
                for si = 1, #slist do
                    local s = slist[si]
                    local ex, ey = s.x2 - s.x1, s.y2 - s.y1
                    local len2 = ex * ex + ey * ey
                    local t = ((b.x - s.x1) * ex + (b.y - s.y1) * ey) / len2
                    if t < 0 then t = 0 elseif t > 1 then t = 1 end
                    local px, py = s.x1 + ex * t, s.y1 + ey * t
                    local dx, dy = b.x - px, b.y - py
                    local d2 = dx * dx + dy * dy
                    if d2 < b.r * b.r and d2 > 1e-6 then
                        local d = sqrt(d2)
                        local nx, ny = dx / d, dy / d
                        local pen = b.r - d
                        b.x, b.y = b.x + nx * pen, b.y + ny * pen
                        local impact = reflect(self, b, nx, ny, s.rest or self.wallRest)
                        if impact > 40 and cb and cb.seg then cb.seg(b, s, impact) end
                    end
                end
            end

            -- 圆角矩形（液晶）
            local boxes = self.boxes
            for bi = 1, #boxes do
                local q = boxes[bi]
                local r = q.r
                local qx = max(q.x + r, min(b.x, q.x + q.w - r))
                local qy = max(q.y + r, min(b.y, q.y + q.h - r))
                local dx, dy = b.x - qx, b.y - qy
                local rr = b.r + r
                local d2 = dx * dx + dy * dy
                if d2 < rr * rr then
                    local d = sqrt(d2)
                    local nx, ny
                    if d > 1e-6 then nx, ny = dx / d, dy / d else nx, ny = 0, -1; d = 0 end
                    local pen = rr - d
                    b.x, b.y = b.x + nx * pen, b.y + ny * pen
                    local impact = reflect(self, b, nx, ny, q.rest or self.wallRest)
                    if impact > 40 and cb and cb.box then cb.box(b, q, impact) end
                end
            end
        end
    end

    self:_ballBall()
end

-- 珠珠碰撞：空间哈希
function Physics:_ballBall()
    local balls = self.balls
    if #balls < 2 then return end
    local grid = self.ballGrid
    local keys = self.ballGridKeys
    for i = 1, #keys do grid[keys[i]] = nil; keys[i] = nil end
    local C2 = 20
    for i = 1, #balls do
        local b = balls[i]
        if b.alive and not b.frozen then
            local k = cellKey(floor(b.x / C2), floor(b.y / C2))
            local list = grid[k]
            if not list then
                list = {}
                grid[k] = list
                keys[#keys + 1] = k
            end
            list[#list + 1] = b
        end
    end
    local e = self.ballBallRest
    for i = 1, #balls do
        local a = balls[i]
        if a.alive and not a.frozen and a.ghost <= 0 then
            local cx, cy = floor(a.x / C2), floor(a.y / C2)
            for oy = 0, 1 do
                for ox = -1, 1 do
                    if not (oy == 0 and ox == -1) then
                        local list = grid[cellKey(cx + ox, cy + oy)]
                        if list then
                            for j = 1, #list do
                                local b = list[j]
                                if b ~= a and (oy > 0 or ox > 0 or b.id > a.id) and b.ghost <= 0 then
                                    local dx, dy = b.x - a.x, b.y - a.y
                                    local rr = a.r + b.r
                                    local d2 = dx * dx + dy * dy
                                    if d2 < rr * rr and d2 > 1e-6 then
                                        local d = sqrt(d2)
                                        local nx, ny = dx / d, dy / d
                                        local ma, mb = a.r * a.r, b.r * b.r
                                        local tot = ma + mb
                                        local pen = rr - d
                                        a.x, a.y = a.x - nx * pen * (mb / tot), a.y - ny * pen * (mb / tot)
                                        b.x, b.y = b.x + nx * pen * (ma / tot), b.y + ny * pen * (ma / tot)
                                        local rv = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny
                                        if rv < 0 then
                                            local jimp = -(1 + e) * rv / tot
                                            a.vx, a.vy = a.vx - jimp * mb * nx, a.vy - jimp * mb * ny
                                            b.vx, b.vy = b.vx + jimp * ma * nx, b.vy + jimp * ma * ny
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

--- 查询半径内的钉子（爆炸用）
function Physics:QueryPegs(x, y, radius, out)
    out = out or {}
    local seen = {}
    for cy = floor((y - radius) / CELL), floor((y + radius) / CELL) do
        for cx = floor((x - radius) / CELL), floor((x + radius) / CELL) do
            local list = self.pegGrid[cellKey(cx, cy)]
            if list then
                for i = 1, #list do
                    local p = list[i]
                    if p.alive and not seen[p] then
                        seen[p] = true
                        local dx, dy = p.x - x, p.y - y
                        if dx * dx + dy * dy <= radius * radius then out[#out + 1] = p end
                    end
                end
            end
        end
    end
    return out
end

return Physics
