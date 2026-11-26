-- ============================================================================
-- Skin.lua · 全局样式常量（颜色 / 字号 / 间距）与数字格式化
-- 颜色语义：绿=增益 红=倍率/危险 蓝=珠分 金=金币/稀有 灰=不可用
-- ============================================================================

local Skin = {}

Skin.C = {
    bg        = { 12, 8, 24, 255 },
    panel     = { 30, 22, 52, 235 },
    panelHi   = { 48, 36, 84, 255 },
    line      = { 120, 96, 200, 160 },
    text      = { 255, 248, 236, 255 },
    textDim   = { 190, 176, 220, 200 },
    chips     = { 70, 170, 255, 255 },
    mult      = { 255, 70, 90, 255 },
    xmult     = { 200, 110, 255, 255 },
    gold      = { 255, 200, 60, 255 },
    good      = { 90, 230, 130, 255 },
    bad       = { 255, 80, 80, 255 },
    disabled  = { 90, 84, 110, 255 },
    overlay   = { 6, 4, 16, 120 },     -- 弹窗遮罩：半透明微暗（Alpha 120 ≈ 47%）
    rarity    = { { 190, 200, 220, 255 }, { 90, 200, 255, 255 }, { 255, 190, 60, 255 } },
}

Skin.FS = {
    caption = 12, body = 14, button = 16, title = 22, big = 30, huge = 44,
}

-- 字体（UI.Init 后由 main 写入真实字体名）
Skin.FONT = "sans"
Skin.FONT_BOLD = "sans"

--- 大数字紧凑格式：≥1万 → 1.2万，≥1亿 → 3.4亿（B2：窄标签防溢出）
function Skin.Num(n)
    n = n or 0
    if n ~= n then return "0" end
    local a = math.abs(n)
    if a >= 1e12 then return string.format("%.1f万亿", n / 1e12) end
    if a >= 1e8 then return string.format("%.2f亿", n / 1e8) end
    if a >= 1e5 then return string.format("%.1f万", n / 1e4) end
    if a >= 1e4 then return string.format("%.2f万", n / 1e4) end
    return tostring(math.floor(n + 0.5))
end

--- 倍率显示：整数不带小数
function Skin.Mult(m)
    if m >= 1e4 then return Skin.Num(m) end
    if math.abs(m - math.floor(m)) < 0.01 then return tostring(math.floor(m + 0.5)) end
    return string.format("%.1f", m)
end

function Skin.Rgba(c, a)
    return { c[1], c[2], c[3], a or c[4] or 255 }
end

return Skin
