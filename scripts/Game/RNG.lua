-- ============================================================================
-- RNG.lua · 可存档、可复现的伪随机数（LCG 31 bit）
-- 局内所有"天意"都走这里，便于回放 / 数值模拟 / 种子分享。
-- ============================================================================

local RNG = {}
RNG.__index = RNG

local MOD = 2147483648 -- 2^31

function RNG.new(seed)
    local self = setmetatable({}, RNG)
    self.s = math.floor(math.abs(seed or os.time())) % MOD
    if self.s == 0 then self.s = 1 end
    return self
end

--- [0, 1)
function RNG:next()
    self.s = (self.s * 1103515245 + 12345) % MOD
    return self.s / MOD
end

--- [a, b] 整数
function RNG:int(a, b)
    return a + math.floor(self:next() * (b - a + 1))
end

function RNG:range(a, b)
    return a + self:next() * (b - a)
end

function RNG:chance(p)
    return self:next() < p
end

function RNG:pick(t)
    if #t == 0 then return nil end
    return t[self:int(1, #t)]
end

function RNG:shuffle(t)
    for i = #t, 2, -1 do
        local j = self:int(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

--- 按权重挑选：items = { {value, weight}, ... }
function RNG:weighted(items)
    local total = 0
    for i = 1, #items do total = total + items[i][2] end
    local r = self:next() * total
    for i = 1, #items do
        r = r - items[i][2]
        if r <= 0 then return items[i][1] end
    end
    return items[#items][1]
end

function RNG:getState() return self.s end
function RNG:setState(s) self.s = s end

return RNG
