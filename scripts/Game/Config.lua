-- ============================================================================
-- Config.lua · 弹珠物语 全部数值 / 内容配置（配置与逻辑分离）
-- 新增内容只需要在这里加表项 + 在 Render/Art.lua 里补一个程序化图标即可。
-- 坐标单位：盘面单位（Board Unit, BU），盘面 360 x 640，y 轴向下。
-- ============================================================================

local C = {}

C.VERSION = 1            -- 存档结构版本号
C.BUILD = "0.1.0-demo"

-- ---------------------------------------------------------------------------
-- 盘面几何
-- ---------------------------------------------------------------------------
C.BOARD = {
    W = 360, H = 640,
    wallL = 24, wallR = 336,          -- 场地左右墙
    arcCx = 180, arcCy = 196,         -- 顶部圆弧圆心
    arcR = 156,                        -- 场地顶部圆弧半径（碰撞）
    railR = 168,                       -- 发射轨道半径（仅视觉）
    railX = 13,                        -- 左侧上行轨道 x
    railBottom = 610,                  -- 轨道起点 y
    lcd = { x = 118, y = 92, w = 124, h = 84, r = 14 },     -- 中央液晶（碰撞体）
    start = { x = 180, y = 300, rimGap = 12, sensorR = 8 }, -- 启动口
    fieldTop = 206, fieldBottom = 532,
    pocketTop = 566, pocketCapture = 598, floor = 640,
    pegR = 4,
}

-- ---------------------------------------------------------------------------
-- 物理参数
-- ---------------------------------------------------------------------------
C.PHYS = {
    gravity = 760,
    substeps = 4,
    maxSpeed = 980,
    pegRest = 0.52,
    wallRest = 0.45,
    bumperKick = 430,
    jitter = 0.10,          -- 撞钉随机偏转（弧度），"天意"
    ballBallRest = 0.6,
    railSpeed = 1500,       -- 轨道上行速度 BU/s
    fireInterval = 0.075,   -- 连发间隔
    releaseSpeedMin = 260,
    releaseSpeedMax = 470,
    releaseAngleMin = 206,  -- 度（y 向下坐标系，180=左 270=上 360=右）
    releaseAngleMax = 322,
    maxBallLife = 22,       -- 超时强制回收
    maxBalls = 220,
}

-- ---------------------------------------------------------------------------
-- 计分：珠分(chips) × 倍率(mult)
-- ---------------------------------------------------------------------------
C.SCORE = {
    baseMult = 1,
    hitCooldown = 0.12,
}

-- 钉子类型。count = 每发默认数量（从普通钉中随机替换）。
-- consumed = 命中后本发内熄灭（下一发重新随机布置）
C.PEGS = {
    normal = { name = "普通钉", chips = 2, color = { 210, 220, 240 } },
    gold   = { name = "金钉",   chips = 15, coinChance = 0.35, count = 4, consumed = true, color = { 255, 200, 60 } },
    red    = { name = "红钉",   mult = 2, count = 5, consumed = true, color = { 255, 70, 80 } },
    purple = { name = "紫钉",   xmult = 2, count = 1, consumed = true, color = { 190, 90, 255 } },
    bomb   = { name = "炸弹钉", chips = 5, radius = 54, count = 2, consumed = true, color = { 255, 130, 30 } },
    split  = { name = "分裂钉", chips = 3, spawn = 2, count = 0, consumed = true, color = { 60, 230, 200 } },
    bumper = { name = "弹力柱", chips = 6, count = 2, consumed = false, color = { 80, 200, 255 }, r = 7 },
}
C.PEG_ORDER = { "gold", "red", "purple", "bomb", "split", "bumper" }

-- 底部口袋（从左到右 7 个）
C.POCKETS = {
    { kind = "recycle", label = "回收" },
    { kind = "chips", value = 20, label = "+20" },
    { kind = "mult", value = 1, label = "+1" },
    { kind = "bigmult", value = 3, label = "+3" },
    { kind = "mult", value = 1, label = "+1" },
    { kind = "chips", value = 20, label = "+20" },
    { kind = "recycle", label = "回收" },
}

-- ---------------------------------------------------------------------------
-- 老虎机（启动口 → 液晶抽奖）
-- ---------------------------------------------------------------------------
C.SLOT = {
    maxHold = 4,                  -- 保留上限
    symbols = { "seven", "star", "cherry", "bell", "marble" },
    jackpotChance = 0.16,         -- 大当概率（3 连）
    sevenShare = 0.25,            -- 大当中 777 占比（超级大当）
    reachMissChance = 0.32,       -- 前两格相同但最后一格落空
    reel1 = 0.45, reel2 = 0.75, reel3 = 1.05, reachExtra = 1.0,
    smallChips = 10,              -- 无奖安慰
    reachMult = 1,                -- 听牌落空也给 +1 倍率
}

C.FEVER = {
    duration = 7, superDuration = 10,
    rain = 10, superRain = 18,
    chipsMul = 3,                 -- FEVER 中钉子珠分 ×3
    startMult = 3,                -- 进入 FEVER 立刻 +3 倍率
    superXMult = 2,               -- 777 立刻 ×2 倍率
}

-- ---------------------------------------------------------------------------
-- 珠子（局外决策：买什么珠子）
-- ---------------------------------------------------------------------------
C.BALLS = {
    steel  = { name = "钢珠",   price = 2, rarity = 1, r = 6, rest = 0.5,  desc = "朴实无华，量大管饱" },
    gold   = { name = "金珠",   price = 5, rarity = 1, r = 6, rest = 0.5,  desc = "每次命中 +3珠分，落袋 +$1", hitChips = 3, pocketCoin = 1 },
    fire   = { name = "火珠",   price = 6, rarity = 2, r = 6, rest = 0.5,  desc = "前 3 次命中引发爆炸", blasts = 3, blastR = 38 },
    split  = { name = "分裂珠", price = 5, rarity = 1, r = 6, rest = 0.5,  desc = "首次命中分裂出 2 颗钢珠", splitN = 2 },
    heavy  = { name = "重珠",   price = 5, rarity = 2, r = 9, rest = 0.35, desc = "体型巨大，命中珠分 ×2", hitMul = 2 },
    ghost  = { name = "幽灵珠", price = 6, rarity = 2, r = 6, rest = 0.5,  desc = "前 1.4 秒穿透钉子", ghostT = 1.4 },
    prism  = { name = "彩虹珠", price = 6, rarity = 2, r = 6, rest = 0.5,  desc = "每命中 5 钉 +1 倍率", prismEvery = 5 },
    rubber = { name = "弹力珠", price = 3, rarity = 1, r = 6, rest = 0.88, desc = "超级弹，撞墙 +5珠分", wallChips = 5 },
    lucky  = { name = "幸运珠", price = 7, rarity = 3, r = 6, rest = 0.5,  desc = "进启动口必中大当", luckyJackpot = true },
}
C.BALL_ORDER = { "steel", "gold", "fire", "split", "heavy", "ghost", "prism", "rubber", "lucky" }

-- ---------------------------------------------------------------------------
-- 护符（=小丑牌，被动规则改写），具体效果由 Game/Charms.lua 实现
-- ---------------------------------------------------------------------------
C.CHARMS = {
    lantern  = { name = "红灯笼",   price = 5, rarity = 1, desc = "红钉额外 +2 倍率" },
    cat      = { name = "招财猫",   price = 6, rarity = 1, desc = "结算时每 $5 存款 +1 倍率" },
    cracker  = { name = "鞭炮串",   price = 6, rarity = 1, desc = "炸弹钉 +2，爆炸范围 +40%" },
    pinwheel = { name = "七彩风车", price = 5, rarity = 1, desc = "老虎机每转一次 +3 倍率" },
    soul     = { name = "确变之魂", price = 7, rarity = 2, desc = "大当概率 +12%" },
    drum     = { name = "狂热太鼓", price = 7, rarity = 2, desc = "FEVER 中钉子珠分再 ×2" },
    kannon   = { name = "千手观音", price = 8, rarity = 3, desc = "每发首颗珠首撞分裂 6 颗" },
    spring   = { name = "弹簧鞋",   price = 4, rarity = 1, desc = "弹力柱 +3，命中 +1 倍率" },
    feather  = { name = "轻羽",     price = 5, rarity = 1, desc = "重力 -25%，珠子飘得更久" },
    miser    = { name = "守财奴",   price = 4, rarity = 1, desc = "利息上限 +$5，过关 +$1" },
    combo    = { name = "连击鬼",   price = 6, rarity = 2, desc = "每发首个 15 连击珠 ×2 倍率" },
    goldrule = { name = "黄金律",   price = 5, rarity = 1, desc = "金钉 +4，金钉必掉 $1" },
    lastshot = { name = "背水一战", price = 6, rarity = 2, desc = "最后一发 倍率 ×3" },
    prismlens= { name = "棱镜",     price = 8, rarity = 3, desc = "紫钉 +2" },
    boomer   = { name = "回旋镖",   price = 5, rarity = 2, desc = "回收口每珠可用 3 次" },
    rain     = { name = "天降甘霖", price = 7, rarity = 2, desc = "每发开局额外降 6 颗钢珠" },
}
C.CHARM_ORDER = { "lantern", "cat", "cracker", "pinwheel", "soul", "drum", "kannon", "spring",
                  "feather", "miser", "combo", "goldrule", "lastshot", "prismlens", "boomer", "rain" }
C.MAX_CHARMS = 5

-- ---------------------------------------------------------------------------
-- 改造（永久修改本局台面）与服务
-- ---------------------------------------------------------------------------
C.MODS = {
    mag     = { name = "弹匣扩容", price = 6, desc = "每发多装 2 颗珠", apply = { magazine = 2 } },
    launch  = { name = "加一发",   price = 9, desc = "每台发射次数 +1", apply = { launches = 1 }, rare = true },
    redpeg  = { name = "红钉+2",   price = 4, desc = "每发红钉数量 +2", apply = { peg = "red", n = 2 } },
    goldpeg = { name = "金钉+3",   price = 4, desc = "每发金钉数量 +3", apply = { peg = "gold", n = 3 } },
    purppeg = { name = "紫钉+1",   price = 7, desc = "每发紫钉数量 +1", apply = { peg = "purple", n = 1 } },
    bombpeg = { name = "炸弹钉+1", price = 5, desc = "每发炸弹钉 +1", apply = { peg = "bomb", n = 1 } },
    splitpeg= { name = "分裂钉+2", price = 5, desc = "每发分裂钉 +2", apply = { peg = "split", n = 2 } },
    remove  = { name = "熔掉一颗", price = 3, desc = "从珠袋移除 1 颗钢珠", service = true },
}
C.MOD_ORDER = { "mag", "launch", "redpeg", "goldpeg", "purppeg", "bombpeg", "splitpeg", "remove" }

-- ---------------------------------------------------------------------------
-- 关卡：8 层（Ante）× 3 台（小台 / 大台 / 头目台）
-- ---------------------------------------------------------------------------
C.ANTE_TARGETS = { 6000, 14000, 36000, 85000, 190000, 400000, 850000, 1800000 }
C.STAGE_KINDS = {
    { key = "small", name = "小台",   mul = 1.0, reward = 3 },
    { key = "big",   name = "大台",   mul = 1.5, reward = 4 },
    { key = "boss",  name = "头目台", mul = 2.0, reward = 5 },
}
C.BASE_LAUNCHES = 3
C.BASE_MAGAZINE = 10

C.BOSSES = {
    wall   = { name = "铁壁",   desc = "启动口被封死" },
    stingy = { name = "吝啬鬼", desc = "本台不出现金钉", mild = true },
    fog    = { name = "浓雾",   desc = "特殊钉数量减半" },
    storm  = { name = "逆风",   desc = "重力 +40%" },
    dull   = { name = "钝钉",   desc = "普通钉 0 珠分" },
    lock   = { name = "锁链",   desc = "红钉无效" },
    narrow = { name = "窄门",   desc = "底部 +3 倍率口袋失效", mild = true },
}
C.BOSS_ORDER = { "wall", "stingy", "fog", "storm", "dull", "lock", "narrow" }

-- 台面主题（每台换一套配色 + 钉阵）
C.THEMES = {
    { key = "sakura", name = "樱花台", bg1 = { 58, 18, 52 },  bg2 = { 20, 8, 30 },  frame = { 255, 120, 170 }, accent = { 255, 210, 230 } },
    { key = "neon",   name = "霓虹台", bg1 = { 14, 30, 70 },  bg2 = { 6, 8, 26 },   frame = { 80, 220, 255 },  accent = { 200, 250, 255 } },
    { key = "gold",   name = "黄金台", bg1 = { 70, 40, 10 },  bg2 = { 26, 14, 4 },  frame = { 255, 196, 70 },  accent = { 255, 240, 190 } },
    { key = "abyss",  name = "深海台", bg1 = { 8, 50, 60 },   bg2 = { 2, 14, 22 },  frame = { 60, 255, 200 },  accent = { 190, 255, 240 } },
}
C.LAYOUTS = { "hex", "waves", "diamond", "lanes" }

-- ---------------------------------------------------------------------------
-- 经济
-- ---------------------------------------------------------------------------
C.ECON = {
    startCoins = 4,
    perLaunchLeft = 1,
    interestPer = 5, interestCap = 5,
    rerollBase = 2,
    shopBalls = 2, shopCharms = 2, shopMods = 1,
    sellRatio = 0.5,
}

-- ---------------------------------------------------------------------------
-- 台主（起始角色，局外解锁）
-- ---------------------------------------------------------------------------
C.STARTERS = {
    { key = "tie",  name = "阿铁", title = "钢珠少年", desc = "12 钢珠 · $4",
      bag = { steel = 12 }, charms = {}, coins = 4, unlock = nil },
    { key = "huo",  name = "火花", title = "烟火师",   desc = "9 钢珠 3 火珠 · 鞭炮串",
      bag = { steel = 9, fire = 3 }, charms = { "cracker" }, coins = 4, unlock = { bestAnte = 2 } },
    { key = "miao", name = "金喵", title = "招财喵",   desc = "10 钢珠 2 金珠 · 招财猫",
      bag = { steel = 10, gold = 2 }, charms = { "cat" }, coins = 8, unlock = { bestAnte = 4 } },
}

-- ---------------------------------------------------------------------------
-- 存档
-- ---------------------------------------------------------------------------
C.SAVE = {
    localFile = "danzhu_save.json",
    prefsFile = "danzhu_prefs.json",
    localInterval = 30,
    cloudInterval = 120,
    cloudTimeout = 10,
}

return C
