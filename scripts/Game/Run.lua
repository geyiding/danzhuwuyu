-- ============================================================================
-- Run.lua · 一局（Run）的状态：层数 / 台 / 金币 / 珠袋 / 护符 / 改造 / 商店
-- 全部字段为纯数据，可 JSON 序列化（存档 / 云存档 / 断点续玩）。
-- ============================================================================

local C = require("Game/Config")
local RNG = require("Game/RNG")

local Run = {}
Run.__index = Run

local floor, min = math.floor, math.min

local function starterByKey(key)
    for _, s in ipairs(C.STARTERS) do
        if s.key == key then return s end
    end
    return C.STARTERS[1]
end

function Run.new(starterKey, seed)
    local self = setmetatable({}, Run)
    local st = starterByKey(starterKey)
    self.version = C.VERSION
    self.seed = seed or (os.time() % 1000000)
    self.rng = RNG.new(self.seed)
    self.starter = st.key
    self.ante, self.stageIdx = 1, 1
    self.coins = st.coins or C.ECON.startCoins
    self.bag = {}
    for _, kind in ipairs(C.BALL_ORDER) do
        for _ = 1, (st.bag[kind] or 0) do self.bag[#self.bag + 1] = kind end
    end
    self.charms = {}
    for _, id in ipairs(st.charms or {}) do self.charms[#self.charms + 1] = id end
    self.mods = { magazine = 0, launches = 0, peg = {} }
    self.rerollCost = C.ECON.rerollBase
    self.phase = "stage"    -- "stage" | "shop" | "over" | "win"
    self.stats = { bestLaunch = 0, totalScore = 0, jackpots = 0, maxCombo = 0, stagesCleared = 0 }
    self.stageSave = nil    -- 断点：{ score, launchesLeft }
    self.discovered = {}
    -- 每层头目
    local pool = {}
    for i, k in ipairs(C.BOSS_ORDER) do pool[i] = k end
    self.rng:shuffle(pool)
    -- 第一层头目只用温和规则（前 3 关基本不会失败）
    for i, k in ipairs(pool) do
        if C.BOSSES[k].mild then pool[1], pool[i] = pool[i], pool[1]; break end
    end
    self.bosses = {}
    for a = 1, #C.ANTE_TARGETS do self.bosses[a] = pool[(a - 1) % #pool + 1] end
    self.shop = nil
    print(string.format("[Run] new starter=%s seed=%d bag=%d coins=%d", self.starter, self.seed, #self.bag, self.coins))
    return self
end

-- ---------------------------------------------------------------------------
-- 关卡信息
-- ---------------------------------------------------------------------------
function Run:CurrentStageInfo()
    local kind = C.STAGE_KINDS[self.stageIdx]
    local base = C.ANTE_TARGETS[self.ante] or C.ANTE_TARGETS[#C.ANTE_TARGETS]
    local n = (self.ante - 1) * 3 + self.stageIdx
    local theme = C.THEMES[(n - 1) % #C.THEMES + 1]
    local layout = C.LAYOUTS[((n - 1) * 3) % #C.LAYOUTS + 1]
    if kind.key == "boss" then theme = C.THEMES[(self.ante % #C.THEMES) + 1] end
    return {
        ante = self.ante, idx = self.stageIdx, kind = kind.key, kindName = kind.name,
        target = floor(base * kind.mul), reward = kind.reward,
        boss = kind.key == "boss" and self.bosses[self.ante] or nil,
        theme = theme, layout = layout, number = n,
    }
end

function Run:IsFinalStage()
    return self.ante == #C.ANTE_TARGETS and self.stageIdx == 3
end

-- ---------------------------------------------------------------------------
-- 过关结算
-- ---------------------------------------------------------------------------
--- stage: Game/Stage 实例（已 cleared）
function Run:OnStageCleared(stage)
    local info = stage.info
    local s = stage.stats
    local reward = {
        base = info.reward,
        launches = stage.launchesLeft * C.ECON.perLaunchLeft,
        interest = min(floor(self.coins / C.ECON.interestPer), s.interestCap),
        bonus = s.clearBonus,
    }
    reward.total = reward.base + reward.launches + reward.interest + reward.bonus
    self.coins = self.coins + reward.total
    local r = stage.result
    self.stats.bestLaunch = math.max(self.stats.bestLaunch, r.bestLaunch)
    self.stats.totalScore = self.stats.totalScore + stage.stageScore
    self.stats.jackpots = self.stats.jackpots + r.jackpots
    self.stats.maxCombo = math.max(self.stats.maxCombo, r.maxCombo)
    self.stats.stagesCleared = self.stats.stagesCleared + 1
    self.stageSave = nil
    if self:IsFinalStage() then
        self.phase = "win"
    else
        self.phase = "shop"
        self.rerollCost = C.ECON.rerollBase
        self:GenerateShop()
    end
    print(string.format("[Run] cleared ante=%d idx=%d reward=%d coins=%d", self.ante, self.stageIdx, reward.total, self.coins))
    return reward
end

function Run:OnStageFailed(stage)
    local r = stage.result
    self.stats.bestLaunch = math.max(self.stats.bestLaunch, r.bestLaunch)
    self.stats.totalScore = self.stats.totalScore + stage.stageScore
    self.stats.jackpots = self.stats.jackpots + r.jackpots
    self.stats.maxCombo = math.max(self.stats.maxCombo, r.maxCombo)
    self.phase = "over"
    self.stageSave = nil
end

function Run:NextStage()
    self.stageIdx = self.stageIdx + 1
    if self.stageIdx > 3 then
        self.stageIdx = 1
        self.ante = self.ante + 1
    end
    self.phase = "stage"
    self.shop = nil
end

-- ---------------------------------------------------------------------------
-- 商店
-- ---------------------------------------------------------------------------
local RARITY_W = { 60, 30, 10 }

local function pickWeighted(rng, order, defs, exclude)
    local items = {}
    for _, id in ipairs(order) do
        if not (exclude and exclude[id]) then
            local d = defs[id]
            local w = d.rarity and RARITY_W[d.rarity] or (d.rare and 12 or 40)
            items[#items + 1] = { id, w }
        end
    end
    if #items == 0 then return nil end
    return rng:weighted(items)
end

function Run:GenerateShop()
    local rng = self.rng
    local slots = {}
    local usedB = {}
    for _ = 1, C.ECON.shopBalls do
        local id = pickWeighted(rng, C.BALL_ORDER, C.BALLS, usedB)
        if id then
            usedB[id] = true
            slots[#slots + 1] = { type = "ball", id = id, price = C.BALLS[id].price }
        end
    end
    local owned = {}
    for _, id in ipairs(self.charms) do owned[id] = true end
    for _ = 1, C.ECON.shopCharms do
        local id = pickWeighted(rng, C.CHARM_ORDER, C.CHARMS, owned)
        if id then
            owned[id] = true
            slots[#slots + 1] = { type = "charm", id = id, price = C.CHARMS[id].price }
        end
    end
    local usedM = {}
    for _ = 1, C.ECON.shopMods do
        local id = pickWeighted(rng, C.MOD_ORDER, C.MODS, usedM)
        usedM[id] = true
        slots[#slots + 1] = { type = "mod", id = id, price = C.MODS[id].price }
    end
    -- 固定服务位：熔掉一颗钢珠（瘦身珠袋）
    slots[#slots + 1] = { type = "mod", id = "remove", price = C.MODS.remove.price }
    self.shop = slots
    return slots
end

function Run:CountBag(kind)
    local n = 0
    for _, k in ipairs(self.bag) do if k == kind then n = n + 1 end end
    return n
end

--- 返回 ok, reasonText
function Run:CanBuy(i)
    local it = self.shop and self.shop[i]
    if not it then return false, "无" end
    if it.sold then return false, "已售" end
    if self.coins < it.price then return false, "缺钱" end
    if it.type == "charm" and #self.charms >= C.MAX_CHARMS then return false, "满了" end
    if it.type == "mod" and it.id == "remove" and (self:CountBag("steel") == 0 or #self.bag <= 4) then return false, "不可" end
    return true
end

function Run:Buy(i)
    local ok, why = self:CanBuy(i)
    if not ok then return false, why end
    local it = self.shop[i]
    self.coins = self.coins - it.price
    if it.type == "ball" then
        self.bag[#self.bag + 1] = it.id
    elseif it.type == "charm" then
        self.charms[#self.charms + 1] = it.id
    elseif it.type == "mod" then
        local def = C.MODS[it.id]
        if it.id == "remove" then
            for k = #self.bag, 1, -1 do
                if self.bag[k] == "steel" then table.remove(self.bag, k); break end
            end
        elseif def.apply.magazine then
            self.mods.magazine = self.mods.magazine + def.apply.magazine
        elseif def.apply.launches then
            self.mods.launches = self.mods.launches + def.apply.launches
        elseif def.apply.peg then
            self.mods.peg[def.apply.peg] = (self.mods.peg[def.apply.peg] or 0) + def.apply.n
        end
    end
    -- 服务位可重复购买（涨价），其余售罄
    if it.type == "mod" and it.id == "remove" then
        it.price = it.price + 1
    else
        it.sold = true
    end
    self.discovered[it.type .. ":" .. it.id] = true
    print(string.format("[Run] buy %s:%s coins=%d", it.type, it.id, self.coins))
    return true
end

function Run:Reroll()
    if self.coins < self.rerollCost then return false end
    self.coins = self.coins - self.rerollCost
    self.rerollCost = self.rerollCost + 1
    self:GenerateShop()
    return true
end

function Run:SellPrice(id)
    local d = C.CHARMS[id]
    return d and math.max(1, floor(d.price * C.ECON.sellRatio)) or 0
end

function Run:SellCharm(index)
    local id = self.charms[index]
    if not id then return false end
    self.coins = self.coins + self:SellPrice(id)
    table.remove(self.charms, index)
    return true
end

-- ---------------------------------------------------------------------------
-- 序列化
-- ---------------------------------------------------------------------------
function Run:Serialize()
    return {
        version = self.version, seed = self.seed, rngState = self.rng:getState(),
        starter = self.starter, ante = self.ante, stageIdx = self.stageIdx, coins = self.coins,
        bag = self.bag, charms = self.charms, mods = self.mods, rerollCost = self.rerollCost,
        phase = self.phase, stats = self.stats, stageSave = self.stageSave, bosses = self.bosses,
        shop = self.shop, discovered = self.discovered,
    }
end

function Run.Deserialize(t)
    if type(t) ~= "table" or not t.bag then return nil end
    local self = setmetatable({}, Run)
    for k, v in pairs(t) do self[k] = v end
    self.rng = RNG.new(t.seed or 1)
    if t.rngState then self.rng:setState(t.rngState) end
    self.mods = self.mods or { magazine = 0, launches = 0, peg = {} }
    self.mods.peg = self.mods.peg or {}
    self.charms = self.charms or {}
    self.stats = self.stats or { bestLaunch = 0, totalScore = 0, jackpots = 0, maxCombo = 0, stagesCleared = 0 }
    self.discovered = self.discovered or {}
    if self.phase == "shop" and not self.shop then self:GenerateShop() end
    return self
end

return Run
