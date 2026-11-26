-- ============================================================================
-- Charms.lua · 护符效果（钩子式实现，新增护符 = 新增一张表）
--
-- 钩子一览（全部可选）：
--   stats(s)                        台开始时修改静态参数（钉数、重力、概率…）
--   onLaunchStart(st)               每发开始
--   onPegHit(st, ball, peg)         每次命中钉子（ball 可能为 nil：被爆炸波及）
--   onPocket(st, ball, pocket)      珠子落袋
--   onSlotSpin(st)                  老虎机开始转
--   onFever(st, super)              进入 FEVER
--   onLaunchEnd(st)                 每发结算前（可改 chips / mult）
-- st 为 Game/Stage 实例，可用 st:AddChips / AddMult / MulMult / AddCoins / SpawnBall / QueueRain
-- ============================================================================

local H = {}

H.lantern = {
    onPegHit = function(st, ball, peg)
        if peg.type == "red" and not st.rules.lock then st:AddMult(2, peg.x, peg.y, "lantern") end
    end,
}

H.cat = {
    onLaunchEnd = function(st)
        local n = math.floor(st.run.coins / 5)
        if n > 0 then st:AddMult(n, nil, nil, "cat") end
    end,
}

H.cracker = {
    stats = function(s)
        s.peg.bomb = s.peg.bomb + 2
        s.blastMul = s.blastMul * 1.4
    end,
}

H.pinwheel = {
    onSlotSpin = function(st) st:AddMult(3, nil, nil, "pinwheel") end,
}

H.soul = {
    stats = function(s) s.feverChance = s.feverChance + 0.12 end,
}

H.drum = {
    stats = function(s) s.feverChipsMul = s.feverChipsMul * 2 end,
}

H.kannon = {
    onPegHit = function(st, ball, peg)
        if ball and ball.launchOrder == 1 and ball.hits == 1 and not ball.child then
            for i = 1, 6 do
                local a = -math.pi + (i - 0.5) * math.pi / 6
                st:SpawnBall("steel", ball.x, ball.y, math.cos(a) * 240, math.sin(a) * 240 - 80, { child = true })
            end
            st:Charm("kannon")
            st:Banner("千手观音!", { 255, 220, 120 })
        end
    end,
}

H.spring = {
    stats = function(s) s.bumpers = s.bumpers + 3 end,
    onPegHit = function(st, ball, peg)
        if peg.type == "bumper" then st:AddMult(1, peg.x, peg.y, "spring") end
    end,
}

H.feather = {
    stats = function(s) s.gravityMul = s.gravityMul * 0.75 end,
}

H.miser = {
    stats = function(s)
        s.interestCap = s.interestCap + 5
        s.clearBonus = s.clearBonus + 1
    end,
}

H.combo = {
    onPegHit = function(st, ball, peg)
        if ball and ball.hits == 15 and not st.comboCharmDone then
            st.comboCharmDone = true
            st:MulMult(2, ball.x, ball.y, "combo")
        end
    end,
}

H.goldrule = {
    stats = function(s)
        s.peg.gold = s.peg.gold + 4
        s.goldCoinChance = 1.0
    end,
}

H.lastshot = {
    onLaunchEnd = function(st)
        if st.launchesLeft == 1 then st:MulMult(3, nil, nil, "lastshot") end
    end,
}

H.prismlens = {
    stats = function(s) s.peg.purple = s.peg.purple + 2 end,
}

H.boomer = {
    stats = function(s) s.recycleMax = 3 end,
}

H.rain = {
    onLaunchStart = function(st)
        st:QueueRain(6)
        st:Charm("rain")
    end,
}

return H
