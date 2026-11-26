-- ============================================================================
-- stubs.lua · 纯 Lua 测试桩：严格 NanoVG / UI / File / clientCloud / cjson
-- 「测试期严检」：任何 nil / NaN / 非法颜色立即报错，定位到调用点。
-- ============================================================================

local Stubs = {}
Stubs.calls = 0

local function isNum(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function fail(name, i, v)
    error(string.format("[strict-nvg] %s arg#%d invalid: %s", name, i, tostring(v)), 3)
end

local function color(r, g, b, a)
    return { __color = true, r = r, g = g, b = b, a = a }
end

-- 参数规格：n = number, c = color, p = paint, s = string, i = int-ish, x = any
local SPEC = {
    nvgBeginPath = "", nvgClosePath = "", nvgFill = "", nvgStroke = "", nvgSave = "", nvgRestore = "",
    nvgMoveTo = "nn", nvgLineTo = "nn", nvgRect = "nnnn", nvgRoundedRect = "nnnnn", nvgCircle = "nnn",
    nvgEllipse = "nnnn", nvgArc = "nnnnni", nvgQuadTo = "nnnn", nvgBezierTo = "nnnnnn",
    nvgFillColor = "c", nvgStrokeColor = "c", nvgStrokeWidth = "n", nvgFillPaint = "p", nvgStrokePaint = "p",
    nvgTranslate = "nn", nvgRotate = "n", nvgScale = "nn", nvgGlobalAlpha = "n",
    nvgFontFace = "s", nvgFontSize = "n", nvgTextAlign = "i", nvgText = "nns",
    nvgIntersectScissor = "nnnn", nvgScissor = "nnnn",
}

local function makeFn(name, spec)
    return function(vg, ...)
        Stubs.calls = Stubs.calls + 1
        if vg == nil then error("[strict-nvg] " .. name .. " vg is nil", 2) end
        local args = { ... }
        for i = 1, #spec do
            local k = spec:sub(i, i)
            local v = args[i]
            if k == "n" or k == "i" then
                if not isNum(v) then fail(name, i, v) end
            elseif k == "c" then
                if type(v) ~= "table" or not v.__color then fail(name, i, v) end
            elseif k == "p" then
                if type(v) ~= "table" or not v.__paint then fail(name, i, v) end
            elseif k == "s" then
                if type(v) ~= "string" then fail(name, i, v) end
            end
        end
    end
end

function Stubs.InstallNVG()
    for name, spec in pairs(SPEC) do _G[name] = makeFn(name, spec) end
    _G.nvgRGBA = function(r, g, b, a)
        for i, v in ipairs({ r, g, b, a }) do
            if not isNum(v) or v < 0 or v > 255 or v ~= math.floor(v) then fail("nvgRGBA", i, v) end
        end
        return color(r, g, b, a)
    end
    _G.nvgRGBAf = function(r, g, b, a) return color(r, g, b, a) end
    local function paint(name, n)
        return function(vg, ...)
            local args = { ... }
            for i = 1, n do if not isNum(args[i]) then fail(name, i, args[i]) end end
            if type(args[n + 1]) ~= "table" or not args[n + 1].__color then fail(name, n + 1, args[n + 1]) end
            if type(args[n + 2]) ~= "table" or not args[n + 2].__color then fail(name, n + 2, args[n + 2]) end
            return { __paint = true }
        end
    end
    _G.nvgRadialGradient = paint("nvgRadialGradient", 4)
    _G.nvgLinearGradient = paint("nvgLinearGradient", 4)
    _G.nvgBoxGradient = function() return { __paint = true } end
    _G.nvgImagePattern = function() return { __paint = true } end
    _G.NVG_CW, _G.NVG_CCW = 2, 1
    _G.NVG_ALIGN_LEFT, _G.NVG_ALIGN_CENTER, _G.NVG_ALIGN_RIGHT = 1, 2, 4
    _G.NVG_ALIGN_TOP, _G.NVG_ALIGN_MIDDLE, _G.NVG_ALIGN_BOTTOM = 8, 16, 32
end

-- ---------------------------------------------------------------------------
-- UI 桩：只允许官方文档中出现的方法（未知方法 → 报错）
-- ---------------------------------------------------------------------------
local ALLOWED = {
    AddChild = true, InsertChild = true, RemoveChild = true, ClearChildren = true, FindById = true,
    Show = true, Hide = true, SetVisible = true, IsVisible = true, SetStyle = true, SetText = true, GetText = true,
    SetFontColor = true, SetFontSize = true, SetDisabled = true, IsDisabled = true, SetChecked = true, IsChecked = true,
    Animate = true, StopAnimation = true, GetAbsoluteLayout = true, GetLayout = true, Destroy = true, SetValue = true,
    GetChildren = true, Init = true, Render = true, SetIcon = true,
}

local Widget = {}
Widget.__index = function(t, k)
    local v = rawget(Widget, k)
    if v ~= nil then return v end
    if type(k) == "string" and k:match("^[A-Z]") and not ALLOWED[k] then
        error("[strict-ui] unknown widget method: " .. k, 2)
    end
    return nil
end

function Widget.Init(self, props)
    self.props = props or {}
    self.children = {}
    self.visible = true
    for _, c in ipairs(self.props.children or {}) do self:AddChild(c) end
end
function Widget:AddChild(c)
    assert(type(c) == "table" and c.props, "[strict-ui] AddChild non-widget")
    self.children[#self.children + 1] = c
    c.parent = self
end
function Widget:InsertChild(c, i) table.insert(self.children, i, c) end
function Widget:RemoveChild(c) end
function Widget:ClearChildren() self.children = {} end
function Widget:GetChildren() return self.children end
function Widget:Show() self.visible = true end
function Widget:Hide() self.visible = false end
function Widget:SetVisible(v) assert(type(v) == "boolean", "SetVisible expects boolean"); self.visible = v end
function Widget:IsVisible() return self.visible end
function Widget:SetStyle(t) assert(type(t) == "table"); for k, v in pairs(t) do self.props[k] = v end end
function Widget:SetText(t)
    assert(type(t) == "string", "[strict-ui] SetText expects string, got " .. type(t))
    self.props.text = t
end
function Widget:GetText() return self.props.text end
function Widget:SetFontColor(c) assert(type(c) == "table"); self.props.fontColor = c end
function Widget:SetDisabled(b) self.props.disabled = b and true or false end
function Widget:IsDisabled() return self.props.disabled end
function Widget:SetChecked(b) self.props.checked = b end
function Widget:Animate(t) assert(type(t) == "table" and t.keyframes, "[strict-ui] Animate needs keyframes") end
function Widget:GetAbsoluteLayout() return self.layout or { x = 0, y = 0, w = 390, h = 640 } end
function Widget:Destroy() end
function Widget:FindById() return nil end

local function ctor(kind)
    return function(props)
        local w = setmetatable({ kind = kind }, Widget)
        w:Init(props or {})
        return w
    end
end

function Stubs.MakeUI()
    local UI = {}
    for _, k in ipairs({ "Panel", "Label", "Button", "Row", "Column", "SafeAreaView", "ScrollView", "Toggle",
        "SimpleGrid", "ProgressBar" }) do
        UI[k] = ctor(k)
    end
    UI.Spacer = function() return ctor("Spacer")({ flexGrow = 1 }) end
    UI.Widget = {}
    UI.Widget.Init = Widget.Init
    function UI.Widget:Extend(name)
        local cls = {}
        cls.__index = function(t, k)
            local v = rawget(cls, k)
            if v ~= nil then return v end
            return Widget.__index(t, k)
        end
        setmetatable(cls, {
            __call = function(c, props)
                local w = setmetatable({ kind = name }, cls)
                w:Init(props or {})
                return w
            end,
            __index = Widget,
        })
        return cls
    end
    UI.Scale = { DEFAULT = 1 }
    UI.Theme = { FontFace = function(f, w) return f .. "-" .. (w or "normal") end }
    UI.Init = function() end
    UI.Shutdown = function() end
    UI.SetRoot = function(r) UI.root = r end
    return UI
end

--- 遍历控件树，对可见的自定义控件调用 Render（模拟渲染器）
function Stubs.RenderTree(w, vg, n)
    n = n or 0
    if not w.visible then return n end
    if w.Render and rawget(getmetatable(w), "Render") then
        w:Render(vg)
        n = n + 1
    end
    for _, c in ipairs(w.children or {}) do n = Stubs.RenderTree(c, vg, n) end
    return n
end

-- ---------------------------------------------------------------------------
-- 迷你 JSON（替代引擎内置 cjson）
-- ---------------------------------------------------------------------------
local function jsonEncode(v, out)
    local t = type(v)
    if t == "nil" then out[#out + 1] = "null"
    elseif t == "boolean" then out[#out + 1] = tostring(v)
    elseif t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then out[#out + 1] = string.format("%d", v)
        else out[#out + 1] = string.format("%.17g", v) end
    elseif t == "string" then
        out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(ch)
            if ch == '"' then return '\\"' elseif ch == "\\" then return "\\\\" elseif ch == "\n" then return "\\n" end
            return string.format("\\%03d", ch:byte())
        end) .. '"'
    elseif t == "table" then
        local n = #v
        local isArr = n > 0 or next(v) == nil
        if isArr then
            for k in pairs(v) do if type(k) ~= "number" then isArr = false break end end
        end
        if isArr and n > 0 then
            out[#out + 1] = "["
            for i = 1, n do if i > 1 then out[#out + 1] = "," end jsonEncode(v[i], out) end
            out[#out + 1] = "]"
        else
            out[#out + 1] = "{"
            local first = true
            for k, val in pairs(v) do
                if type(val) ~= "function" then
                    if not first then out[#out + 1] = "," end
                    first = false
                    jsonEncode(tostring(k), out)
                    out[#out + 1] = ":"
                    jsonEncode(val, out)
                end
            end
            out[#out + 1] = "}"
        end
    else
        error("cannot encode " .. t)
    end
end

local function jsonDecode(str)
    local pos = 1
    local function ws() pos = str:find("[^ \t\r\n]", pos) or #str + 1 end
    local value
    local function parseString()
        local out = {}
        pos = pos + 1
        while true do
            local c = str:sub(pos, pos)
            if c == '"' then pos = pos + 1 break end
            if c == "\\" then
                local n = str:sub(pos + 1, pos + 1)
                local map = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
                if map[n] then out[#out + 1] = map[n]; pos = pos + 2
                elseif n:match("%d") then out[#out + 1] = string.char(tonumber(str:sub(pos + 1, pos + 3))); pos = pos + 4
                else error("bad escape " .. n) end
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(out)
    end
    function value()
        ws()
        local c = str:sub(pos, pos)
        if c == "{" then
            local t = {}
            pos = pos + 1; ws()
            if str:sub(pos, pos) == "}" then pos = pos + 1 return t end
            while true do
                ws()
                local k = parseString()
                ws(); assert(str:sub(pos, pos) == ":"); pos = pos + 1
                t[k] = value()
                ws()
                local d = str:sub(pos, pos); pos = pos + 1
                if d == "}" then return t end
                assert(d == ",", "expected , got " .. d)
            end
        elseif c == "[" then
            local t = {}
            pos = pos + 1; ws()
            if str:sub(pos, pos) == "]" then pos = pos + 1 return t end
            while true do
                t[#t + 1] = value()
                ws()
                local d = str:sub(pos, pos); pos = pos + 1
                if d == "]" then return t end
                assert(d == ",")
            end
        elseif c == '"' then
            return parseString()
        elseif str:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif str:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        elseif str:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
        else
            local num = str:match("^-?[%d%.eE+-]+", pos)
            pos = pos + #num
            return tonumber(num)
        end
    end
    return value()
end

function Stubs.InstallJSON()
    package.preload["cjson"] = function()
        return {
            encode = function(v) local out = {} jsonEncode(v, out) return table.concat(out) end,
            decode = jsonDecode,
        }
    end
end

-- ---------------------------------------------------------------------------
-- 内存文件系统
-- ---------------------------------------------------------------------------
function Stubs.InstallFiles()
    Stubs.files = {}
    _G.FILE_READ, _G.FILE_WRITE = 0, 1
    _G.fileSystem = { FileExists = function(_, n) return Stubs.files[n] ~= nil end }
    _G.File = function(name, mode)
        local f = { name = name, mode = mode, open = true }
        function f:IsOpen() return self.open end
        function f:ReadString() return Stubs.files[self.name] end
        function f:WriteString(s) Stubs.files[self.name] = s end
        function f:Close() self.open = false end
        return f
    end
end

-- ---------------------------------------------------------------------------
-- 云变量桩：mode = "ok" | "error" | "hang"
-- ---------------------------------------------------------------------------
function Stubs.InstallCloud(mode, store)
    store = store or { values = {}, iscores = {} }
    Stubs.cloud = store
    local function builder(kind)
        local b = { ops = {} }
        function b:Key(k) self.ops[#self.ops + 1] = k return self end
        function b:Set(k, v) self.ops[#self.ops + 1] = { "v", k, v } return self end
        function b:SetInt(k, v) self.ops[#self.ops + 1] = { "i", k, v } return self end
        function b:Fetch(ev)
            if mode == "ok" then
                local vals, isc = {}, {}
                for _, k in ipairs(self.ops) do vals[k] = store.values[k]; isc[k] = store.iscores[k] end
                ev.ok(vals, isc)
            elseif mode == "error" then
                ev.error(-1, "net")
            end
        end
        function b:Save(desc, ev)
            if mode == "ok" then
                for _, op in ipairs(self.ops) do
                    if op[1] == "v" then store.values[op[2]] = op[3] else store.iscores[op[2]] = op[3] end
                end
                if ev and ev.ok then ev.ok() end
            elseif mode == "error" then
                if ev and ev.error then ev.error(-1, "net") end
            end
        end
        return b
    end
    _G.clientCloud = {
        BatchGet = function() return builder("get") end,
        BatchSet = function() return builder("set") end,
    }
end

return Stubs
