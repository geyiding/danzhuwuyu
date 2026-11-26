-- ============================================================================
-- Stage.lua · 一台（一个关卡）的完整局内逻辑：发射 → 物理 → 计分 → 老虎机 → FEVER → 结算
--
-- 局内玩家唯一操作：Launch()（"大力干!"）。其余全部交给天意（随机发射角度/力度、
-- 撞钉偏转、老虎机）与奇迹（护符连锁、FEVER 珠雨、爆炸链）。
--
-- 纯逻辑，不依赖引擎。所有视觉反馈通过 self.fx（监听者）发出，测试时可传空监听者。
-- phase: "idle"（等待发射）→ "launch"（珠子飞行中）→ "settle"（结算动画）
--        → "idle" / "cleared"（过关）/ "failed"（失败）
-- ============================================================================

local C = require("Game/Config")
local Physics = require("Game/Physics")
local Board = require("Game/Board")
local Charms = require("Game/Charms")

local Stage = {}
Stage.__index = Stage

local B, P = C.BOARD, C.PHYS
local floor, min, max, sqrt, cos, sin, pi = math.floor, math.min, math.max, math.sqrt, math.cos, math.sin, math.pi

local NOOP = function() end
local NULL_FX = setmetatable({}, { __index = function() return NOOP end })

--- run: Game/Run 实例；info: run:CurrentStageInfo()
function Stage.new(run, info, fx)
    local self = setmetatable({}, Stage)
    self.run = run
    self.info = info
    self.fx = fx or NULL_FX
    self.rng = run.rng
    self.time = 0

    -- 头目规则
    self.rules = {}
    if info.boss then self.rules[info.boss] = true end

    -- 静态参数：基础 + 改造 + 护符
    local s = {
        peg = {}, bumpers = C.PEGS.bumper.count,
        gravityMul = 1, feverChance = C.SLOT.jackpotChance, feverChipsMul = C.FEVER.chipsMul,
        blastMul = 1, recycleMax = 1, interestCap = C.ECON.interestCap, clearBonus = 0,
        goldCoinChance = C.PEGS.gold.coinChance,
        launches = C.BASE_LAUNCHES + (run.mods.launches or 0),
        magazine = C.BASE_MAGAZINE + (run.mods.magazine or 0),
    }
    for _, k in ipairs(C.PEG_ORDER) do
        s.peg[k] = (C.PEGS[k].count or 0) + ((run.mods.peg and run.mods.peg[k]) or 0)
    end
    for _, id in ipairs(run.charms) do
        local h = Charms[id]
        if h and h.stats then h.stats(s) end
    end
    if self.rules.stingy then s.peg.gold = 0 end
    if self.rules.fog then
        for k, v in pairs(s.peg) do s.peg[k] = floor(v / 2) end
    end
    if self.rules.storm then s.gravityMul = s.gravityMul * 1.4 end
    self.stats = s

    self.board = Board.new({ layout = info.layout, rng = self.rng })
    self.board:SetupBumpers(s.bumpers, self.rng)
    if self.rules.narrow then
        for _, pk in ipairs(self.board.pockets) do
            if pk.kind == "bigmult" then pk.disabled = true end
        end
    end
    self.startBlocked = self.rules.wall or false

    self.phys = Physics.new({
        gravity = P.gravity * s.gravityMul, substeps = P.substeps, maxSpeed = P.maxSpeed,
        pegRest = P.pegRest, wallRest = P.wallRest, jitter = P.jitter, ballBallRest = P.ballBallRest,
        bumperKick = P.bumperKick, rand = function() return self.rng:next() end,
    })
    self.phys:SetStatic(self.board.pegs, self.board.segs, self.board.boxes)

    self.target = info.target
    self.stageScore = 0
    self.launchesLeft = s.launches
    self.launchIndex = 0
    self.phase = "idle"
    self.chips, self.mult = 0, C.SCORE.baseMult
    self.nextBallId = 0
    self.rail = {}
    self.railQueue = {}
    self.rainPending = 0
    self.rainTimer = 0
    self.slot = { holds = {}, spin = nil, reels = { "seven", "star", "cherry" } }
    self.fever = nil
    self.settleT = 0
    self.lastLaunchScore = 0
    self.drawPile = {}
    self.slow = { t = 0, scale = 1 }
    self.result = { hits = 0, maxCombo = 0, jackpots = 0, bestLaunch = 0 }
    self.comboChain, self.comboTimer = 0, 0

    self.board:Rearrange(s.peg, self.rng)
    self._cb = {
        peg = function(ball, peg, impact) self:_onPegContact(ball, peg, impact) end,
        seg = function(ball, seg, impact) self:_onWall(ball, seg, impact) end,
        box = function(ball, box, impact) self:_onWall(ball, box, impact) end,
    }
    print(string.format("[Stage] ante=%d %s target=%d boss=%s launches=%d mag=%d",
        info.ante, info.kindName, self.target, tostring(info.boss), s.launches, s.magazine))
    return self
end

-- ---------------------------------------------------------------------------
-- 钩子派发
-- ---------------------------------------------------------------------------
function Stage:_hook(name, ...)
    for _, id in ipairs(self.run.charms) do
        local h = Charms[id]
        if h and h[name] then h[name](self, ...) end
    end
end

function Stage:Charm(id) self.fx:Charm(id) end
function Stage:Banner(text, color) self.fx:Banner(text, color) end

-- ---------------------------------------------------------------------------
-- 计分 API（护符 / 珠子 / 钉子共用）
-- ---------------------------------------------------------------------------
function Stage:AddChips(n, x, y, charmId)
    if n == 0 then return end
    self.chips = self.chips + n
    if x then self.fx:Popup(x, y, n, "chips") end
    if charmId then self.fx:Charm(charmId) end
end

function Stage:AddMult(n, x, y, charmId)
    if n == 0 then return end
    self.mult = self.mult + n
    if x then self.fx:Popup(x, y, n, "mult") end
    if charmId then self.fx:Charm(charmId) end
end

function Stage:MulMult(f, x, y, charmId)
    self.mult = self.mult * f
    if x then self.fx:Popup(x, y, f, "xmult") end
    if charmId then self.fx:Charm(charmId) end
    self:SlowMo(0.18, 0.35)
    self.fx:Shake(4)
end

function Stage:AddCoins(n, x, y)
    self.run.coins = self.run.coins + n
    if x then self.fx:Popup(x, y, n, "coin") end
end

function Stage:SlowMo(t, scale)
    if t > self.slow.t then self.slow.t = t end
    self.slow.scale = math.min(self.slow.scale, scale)
end

-- ---------------------------------------------------------------------------
-- 珠子
-- ---------------------------------------------------------------------------
function Stage:SpawnBall(kind, x, y, vx, vy, opts)
    if #self.phys.balls >= P.maxBalls then return nil end
    local def = C.BALLS[kind] or C.BALLS.steel
    self.nextBallId = self.nextBallId + 1
    local b = {
        id = self.nextBallId, kind = kind, x = x, y = y, vx = vx or 0, vy = vy or 0,
        r = def.r, rest = def.rest, ghost = def.ghostT or 0, hits = 0, age = 0, still = 0,
        recycles = 0, blasts = def.blasts or 0, trail = {}, trailN = 0,
        launchOrder = opts and opts.launchOrder or 0, child = opts and opts.child or false,
        gravityMul = 1,
    }
    self.phys:AddBall(b)
    self.fx:Spawn(b)
    return b
end

function Stage:QueueRain(n)
    self.rainPending = self.rainPending + n
end

local function makeRailItem(self, kind, order, delay)
    local ang = self.rng:range(P.releaseAngleMin, P.releaseAngleMax)
    return {
        kind = kind, order = order, delay = delay, dist = 0, angle = ang,
        len = Board.RailLength(ang), speed = self.rng:range(P.releaseSpeedMin, P.releaseSpeedMax),
        x = B.railX, y = B.railBottom, recycles = 0,
    }
end

--- 从珠袋抽一个弹匣
function Stage:_drawMagazine()
    local bag = self.run.bag
    local n = min(self.stats.magazine, #bag)
    local out = {}
    for _ = 1, n do
        if #self.drawPile == 0 then
            for i = 1, #bag do self.drawPile[i] = bag[i] end
            self.rng:shuffle(self.drawPile)
        end
        out[#out + 1] = table.remove(self.drawPile)
    end
    return out
end

-- ---------------------------------------------------------------------------
-- 唯一的局内操作：大力干！
-- ---------------------------------------------------------------------------
function Stage:CanLaunch()
    return self.phase == "idle" and self.launchesLeft > 0
end

function Stage:Launch()
    if not self:CanLaunch() then return false end
    self.launchIndex = self.launchIndex + 1
    self.phase = "launch"
    self.chips, self.mult = 0, C.SCORE.baseMult
    self.comboCharmDone = false
    self.board:Rearrange(self.stats.peg, self.rng)
    local mag = self:_drawMagazine()
    for i, kind in ipairs(mag) do
        self.railQueue[#self.railQueue + 1] = makeRailItem(self, kind, i, (i - 1) * P.fireInterval)
    end
    self.launchClock = 0
    self:_hook("onLaunchStart")
    self.fx:Launch(#mag)
    print(string.format("[Stage] launch #%d balls=%d", self.launchIndex, #mag))
    return true
end

-- ---------------------------------------------------------------------------
-- 碰撞回调
-- ---------------------------------------------------------------------------
function Stage:_onWall(ball, seg, impact)
    local def = C.BALLS[ball.kind]
    if def and def.wallChips and impact > 80 then
        self:AddChips(def.wallChips, ball.x, ball.y)
    end
    self.fx:Wall(ball, impact)
end

function Stage:_onPegContact(ball, peg, impact)
    if ball.lastPeg == peg and (self.time - (ball.lastPegT or -1)) < C.SCORE.hitCooldown then return end
    ball.lastPeg, ball.lastPegT = peg, self.time
    self:HitPeg(peg, ball)
end

--- 钉子被触发（ball 为 nil 表示被爆炸波及）
function Stage:HitPeg(peg, ball)
    if not peg.alive then return end
    local def = C.PEGS[peg.type] or C.PEGS.normal
    local bdef = ball and C.BALLS[ball.kind] or nil
    peg.flash = 1
    self.result.hits = self.result.hits + 1
    self.comboChain = self.comboChain + 1
    self.comboTimer = 0.6
    if self.comboChain > self.result.maxCombo then self.result.maxCombo = self.comboChain end

    if ball then
        ball.hits = ball.hits + 1
    end

    local chips = 0
    local t = peg.type
    if t == "normal" then
        chips = self.rules.dull and 0 or def.chips
        if self.fever then chips = chips * self.stats.feverChipsMul end
    elseif t == "gold" then
        chips = def.chips
        if self.fever then chips = chips * 2 end
        if self.rng:chance(self.stats.goldCoinChance) then self:AddCoins(1, peg.x, peg.y - 10) end
    elseif t == "red" then
        if self.rules.lock then
            self.fx:Popup(peg.x, peg.y, "锁", "dim")
        else
            self:AddMult(def.mult, peg.x, peg.y)
        end
    elseif t == "purple" then
        self:MulMult(def.xmult, peg.x, peg.y)
    elseif t == "bomb" then
        chips = def.chips
    elseif t == "split" then
        chips = def.chips
    elseif t == "bumper" then
        chips = def.chips
    end

    if bdef then
        if bdef.hitChips then chips = chips + bdef.hitChips end
        if bdef.hitMul then chips = chips * bdef.hitMul end
    end
    if chips > 0 then
        self.chips = self.chips + chips
        self.fx:PegScore(peg, chips)
    end
    self.fx:PegHit(peg, ball)

    if def.consumed then
        peg.alive = false
        peg.pop = 1
    end

    -- 钉子的连锁效果（放在熄灭之后，避免爆炸递归自身）
    if t == "bomb" then
        self:Explode(peg.x, peg.y, def.radius * self.stats.blastMul, true)
    elseif t == "split" then
        for i = 1, def.spawn do
            local a = -pi / 2 + (i - 1.5) * 1.2
            self:SpawnBall("steel", peg.x, peg.y, cos(a) * 200, sin(a) * 200, { child = true })
        end
        self.fx:Popup(peg.x, peg.y - 12, "分裂!", "chips")
    end

    -- 珠子特性
    if ball and bdef then
        if bdef.blasts and ball.blasts > 0 then
            ball.blasts = ball.blasts - 1
            self:Explode(ball.x, ball.y, bdef.blastR * self.stats.blastMul, false)
        end
        if bdef.splitN and not ball.splitDone then
            ball.splitDone = true
            for i = 1, bdef.splitN do
                local a = -pi / 2 + (i == 1 and -0.9 or 0.9)
                self:SpawnBall("steel", ball.x, ball.y, cos(a) * 180, sin(a) * 180, { child = true })
            end
        end
        if bdef.prismEvery and ball.hits % bdef.prismEvery == 0 then
            self:AddMult(1, ball.x, ball.y)
        end
    end

    self:_hook("onPegHit", ball, peg)
end

--- 爆炸：波及半径内所有钉 + 推开珠子（连锁反应的来源）
function Stage:Explode(x, y, radius, big)
    self.fx:Explode(x, y, radius, big)
    self.fx:Shake(big and 7 or 3)
    if big then self:SlowMo(0.12, 0.5) end
    for _, b in ipairs(self.phys.balls) do
        local dx, dy = b.x - x, b.y - y
        local d2 = dx * dx + dy * dy
        if d2 < radius * radius and d2 > 1 then
            local d = sqrt(d2)
            local k = (1 - d / radius) * 380
            b.vx, b.vy = b.vx + dx / d * k, b.vy + dy / d * k
        end
    end
    local hit = self.phys:QueryPegs(x, y, radius)
    for _, p in ipairs(hit) do
        if not p.bumper then self:HitPeg(p, nil) end
    end
end

-- ---------------------------------------------------------------------------
-- 口袋 / 启动口
-- ---------------------------------------------------------------------------
function Stage:_onPocket(ball, pk)
    ball.alive = false
    pk.flash = 1
    local bdef = C.BALLS[ball.kind]
    if pk.disabled then
        self.fx:Popup(ball.x, B.pocketCapture, "失效", "dim")
    elseif pk.kind == "recycle" then
        if ball.recycles < self.stats.recycleMax then
            local item = makeRailItem(self, ball.kind, 0, 0.15)
            item.recycles = ball.recycles + 1
            item.child = ball.child
            self.railQueue[#self.railQueue + 1] = item
            self.fx:Popup(ball.x, B.pocketCapture, "再来!", "chips")
        else
            self:AddChips(10, ball.x, B.pocketCapture)
        end
    elseif pk.kind == "chips" then
        self:AddChips(pk.value, ball.x, B.pocketCapture)
    elseif pk.kind == "mult" or pk.kind == "bigmult" then
        self:AddMult(pk.value, ball.x, B.pocketCapture)
    elseif pk.kind == "xmult" then
        self:MulMult(pk.value, ball.x, B.pocketCapture)
    end
    if bdef and bdef.pocketCoin then self:AddCoins(bdef.pocketCoin, ball.x, B.pocketCapture - 16) end
    self.fx:Pocket(pk, ball)
    self:_hook("onPocket", ball, pk)
end

function Stage:_onStartPocket(ball)
    ball.alive = false
    self:AddChips(5, B.start.x, B.start.y)
    local holds = self.slot.holds
    if #holds < C.SLOT.maxHold then
        holds[#holds + 1] = { lucky = C.BALLS[ball.kind] and C.BALLS[ball.kind].luckyJackpot or false }
        self.fx:StartPocket(#holds)
    else
        self.fx:Popup(B.start.x, B.start.y - 14, "满", "dim")
    end
end

-- ---------------------------------------------------------------------------
-- 老虎机
-- ---------------------------------------------------------------------------
function Stage:_startSpin()
    local hold = table.remove(self.slot.holds, 1)
    local S = C.SLOT
    local syms = S.symbols
    local r = self.rng:next()
    local res
    local jackpot = hold.lucky or r < self.stats.feverChance
    if self.rules.wall then jackpot = false end
    if jackpot then
        local sym = self.rng:chance(S.sevenShare) and "seven" or syms[self.rng:int(2, #syms)]
        res = { sym, sym, sym }
    elseif r < self.stats.feverChance + S.reachMissChance then
        local sym = syms[self.rng:int(1, #syms)]
        local other
        repeat other = syms[self.rng:int(1, #syms)] until other ~= sym
        res = { sym, sym, other }
    else
        local a = syms[self.rng:int(1, #syms)]
        local b
        repeat b = syms[self.rng:int(1, #syms)] until b ~= a
        res = { a, b, syms[self.rng:int(1, #syms)] }
    end
    local reach = res[1] == res[2]
    self.slot.spin = {
        t = 0, res = res, reach = reach, jackpot = jackpot, super = jackpot and res[1] == "seven",
        stop = { S.reel1, S.reel2, S.reel3 + (reach and S.reachExtra or 0) },
        stopped = 0, reachAnnounced = false,
    }
    self:_hook("onSlotSpin")
    self.fx:SlotSpin(self.slot.spin)
end

function Stage:_updateSlot(dt)
    local spin = self.slot.spin
    if not spin then
        if #self.slot.holds > 0 and not self.fever then self:_startSpin() end
        return
    end
    spin.t = spin.t + dt
    while spin.stopped < 3 and spin.t >= spin.stop[spin.stopped + 1] do
        spin.stopped = spin.stopped + 1
        self.slot.reels[spin.stopped] = spin.res[spin.stopped]
        self.fx:ReelStop(spin.stopped, spin)
        if spin.stopped == 2 and spin.reach and not spin.reachAnnounced then
            spin.reachAnnounced = true
            self.fx:Reach()
            self:SlowMo(0.25, 0.6)
        end
    end
    if spin.stopped >= 3 and spin.t >= spin.stop[3] + 0.25 then
        self.slot.spin = nil
        if spin.jackpot then
            self:_startFever(spin.super)
        elseif spin.reach then
            self:AddMult(C.SLOT.reachMult, B.start.x, B.lcd.y + B.lcd.h + 8)
        else
            self:AddChips(C.SLOT.smallChips, B.start.x, B.lcd.y + B.lcd.h + 8)
        end
    end
end

function Stage:_startFever(super)
    local F = C.FEVER
    self.fever = { t = 0, dur = super and F.superDuration or F.duration, super = super }
    self.result.jackpots = self.result.jackpots + 1
    self:QueueRain(super and F.superRain or F.rain)
    self:AddMult(F.startMult, B.start.x, B.lcd.y + B.lcd.h + 10)
    if super then self:MulMult(F.superXMult, B.start.x, B.lcd.y + B.lcd.h + 30) end
    self:SlowMo(0.35, 0.25)
    self.fx:Fever(super)
    self:_hook("onFever", super)
end

-- ---------------------------------------------------------------------------
-- 主更新
-- ---------------------------------------------------------------------------
function Stage:Update(rawDt)
    -- 慢动作
    local dt = rawDt
    if self.slow.t > 0 then
        self.slow.t = self.slow.t - rawDt
        dt = rawDt * self.slow.scale
        if self.slow.t <= 0 then self.slow.scale = 1 end
    end
    self.time = self.time + dt
    if self.comboTimer > 0 then
        self.comboTimer = self.comboTimer - dt
        if self.comboTimer <= 0 then
            if self.comboChain >= 20 then self.fx:Combo(self.comboChain) end
            self.comboChain = 0
        end
    end

    if self.phase == "launch" then
        self:_updateLaunch(dt)
    elseif self.phase == "settle" then
        self.settleT = self.settleT + rawDt
        if self.settleT >= 1.5 then self:_finishSettle() end
    end
    return dt
end

function Stage:_updateLaunch(dt)
    self.launchClock = self.launchClock + dt
    -- 轨道队列
    local q = self.railQueue
    local i = 1
    while i <= #q do
        local it = q[i]
        it.delay = it.delay - dt
        if it.delay <= 0 then
            table.remove(q, i)
            self.rail[#self.rail + 1] = it
        else
            i = i + 1
        end
    end
    -- 轨道运动
    local rail = self.rail
    i = 1
    while i <= #rail do
        local it = rail[i]
        it.dist = it.dist + P.railSpeed * dt
        local x, y = Board.RailPoint(it.dist, it.angle)
        if x then
            it.x, it.y = x, y
            i = i + 1
        else
            table.remove(rail, i)
            local a = it.angle * pi / 180
            local rr = B.arcR - 8
            local bx, by = B.arcCx + cos(a) * rr, B.arcCy + sin(a) * rr
            local tx, ty = -sin(a), cos(a)
            local b = self:SpawnBall(it.kind, bx, by, tx * it.speed, ty * it.speed, { launchOrder = it.order, child = it.child })
            if b then b.recycles = it.recycles end
        end
    end
    -- 珠雨
    if self.rainPending > 0 then
        self.rainTimer = self.rainTimer - dt
        if self.rainTimer <= 0 then
            self.rainTimer = 0.07
            self.rainPending = self.rainPending - 1
            local x = self.rng:range(B.arcCx - 110, B.arcCx + 110)
            local y = B.arcCy - sqrt(max(0, (B.arcR - 12) ^ 2 - (x - B.arcCx) ^ 2)) + 6
            self:SpawnBall("steel", x, y, self.rng:range(-60, 60), 40, { child = true })
        end
    end

    -- 物理
    self.phys:Step(dt, self._cb)

    -- 珠子状态
    local balls = self.phys.balls
    local S = B.start
    for bi = 1, #balls do
        local b = balls[bi]
        if b.alive then
            b.age = b.age + dt
            -- 拖尾采样
            b.trailN = (b.trailN % 6) + 1
            b.trail[b.trailN] = b.trail[b.trailN] or {}
            b.trail[b.trailN][1], b.trail[b.trailN][2] = b.x, b.y
            -- 启动口
            if not self.startBlocked then
                local dx, dy = b.x - S.x, b.y - (S.y + 4)
                if dx * dx + dy * dy < S.sensorR * S.sensorR then self:_onStartPocket(b) end
            end
            if b.alive and b.y > B.pocketCapture then
                self:_onPocket(b, self.board:PocketAt(b.x))
            elseif b.alive and (b.x < -20 or b.x > B.W + 20 or b.y < -40 or b.age > P.maxBallLife) then
                b.alive = false
                self.fx:Popup(b.x, b.y, "噗", "dim")
            elseif b.alive then
                -- 卡住检测
                if b.vx * b.vx + b.vy * b.vy < 15 * 15 then
                    b.still = b.still + dt
                    if b.still > 1.0 then
                        b.vx, b.vy = self.rng:range(-120, 120), -80
                        b.still = 0
                    end
                else
                    b.still = 0
                end
            end
        end
    end
    self.phys:Compact()

    -- 老虎机 & FEVER
    self:_updateSlot(dt)
    if self.fever then
        self.fever.t = self.fever.t + dt
        if self.fever.t >= self.fever.dur and #self.phys.balls == 0 and self.rainPending == 0 then
            self.fever = nil
            self.fx:FeverEnd()
        elseif self.fever.t >= self.fever.dur + 6 then
            self.fever = nil
            self.fx:FeverEnd()
        end
    end

    -- 结束判定
    if #self.railQueue == 0 and #self.rail == 0 and #self.phys.balls == 0 and self.rainPending == 0
        and not self.slot.spin and #self.slot.holds == 0 and not self.fever then
        self:_beginSettle()
    end
end

function Stage:_beginSettle()
    self:_hook("onLaunchEnd")
    self.phase = "settle"
    self.settleT = 0
    self.lastLaunchScore = floor(self.chips * self.mult + 0.5)
    if self.lastLaunchScore > self.result.bestLaunch then self.result.bestLaunch = self.lastLaunchScore end
    self.fx:Settle(self.chips, self.mult, self.lastLaunchScore, self.stageScore + self.lastLaunchScore >= self.target)
    print(string.format("[Stage] settle chips=%d mult=%.2f score=%d", self.chips, self.mult, self.lastLaunchScore))
end

function Stage:_finishSettle()
    self.stageScore = self.stageScore + self.lastLaunchScore
    self.launchesLeft = self.launchesLeft - 1
    if self.stageScore >= self.target then
        self.phase = "cleared"
        self.fx:Cleared()
    elseif self.launchesLeft <= 0 then
        self.phase = "failed"
        self.fx:Failed()
    else
        self.phase = "idle"
    end
    self.chips, self.mult = 0, C.SCORE.baseMult
    print(string.format("[Stage] after settle total=%d/%d left=%d phase=%s", self.stageScore, self.target, self.launchesLeft, self.phase))
end

--- 预估：本发结算后是否过关（用于分数板火焰）
function Stage:WillClear()
    return self.stageScore + self.chips * self.mult >= self.target
end

return Stage
