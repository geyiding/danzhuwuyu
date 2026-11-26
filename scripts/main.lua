-- ============================================================================
-- 弹珠物语 / Marble Story · 入口
-- UrhoX · Lua 5.4 · urhox-libs/UI（Yoga + NanoVG）· 手机竖屏
--
-- 结构：
--   Game/    纯逻辑（Config / RNG / Physics / Board / Stage / Charms / Run / Save / Audio）
--   Render/  程序化美术与特效（Art / FX / Widgets）
--   UIx/     界面与流程（Skin / App）
-- 本文件只负责引擎初始化、事件订阅、每帧驱动。
-- ============================================================================

local UI = require("urhox-libs/UI")
local Skin = require("UIx/Skin")
local Art = require("Render/Art")
local Save = require("Game/Save")
local Audio = require("Game/Audio")
local App = require("UIx/App")

---@type Scene
local scene_
---@type Node
local cameraNode_

function Start()
    print("=== 弹珠物语 Start() ===")
    graphics.windowTitle = "弹珠物语"

    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
                bold = "Fonts/MiSans-Bold.ttf",
            } },
        },
        scale = UI.Scale.DEFAULT,
    })
    -- NanoVG 自绘字体名（与 UI 主题保持一致）
    local okN, normalFace = pcall(UI.Theme.FontFace, "sans", "normal")
    local okB, boldFace = pcall(UI.Theme.FontFace, "sans", "bold")
    Art.FONT = (okN and normalFace) or "sans"
    Art.FONT_BOLD = (okB and boldFace) or Art.FONT
    Skin.FONT, Skin.FONT_BOLD = Art.FONT, Art.FONT_BOLD
    print("[Main] fonts:", Art.FONT, Art.FONT_BOLD)

    CreateScene()

    Save.LoadPrefs()
    local audio = Audio.new(scene_)
    audio:SetMusic(Save.prefs.music)
    audio:SetSfx(Save.prefs.sfx)

    App.Build(audio)
    App.Boot()

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("InputFocus", "HandleInputFocus")
    print("=== Start() complete, screen " .. graphics:GetWidth() .. "x" .. graphics:GetHeight() .. " ===")
end

function Stop()
    App.SaveLocal()
    UI.Shutdown()
end

--- 空场景：只用于音频节点与清屏（游戏画面全部由 NanoVG 绘制）
function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    local zoneNode = scene_:CreateChild("Zone")
    local zone = zoneNode:CreateComponent("Zone")
    zone.backgroundColor = Color(0.05, 0.03, 0.09)
    zone.ambientColor = Color(1, 1, 1)

    cameraNode_ = scene_:CreateChild("Camera")
    local camera = cameraNode_:CreateComponent("Camera")
    camera.orthographic = true
    cameraNode_.position = Vector3(0, 0, -10)
    renderer:SetViewport(0, Viewport:new(scene_, camera))
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    if dt > 0.05 then dt = 0.05 end      -- 切后台回来防穿墙 / 防连存
    App.Update(dt)
end

--- 切后台：暂停 + 存本地
function HandleInputFocus(eventType, eventData)
    local focus = eventData["Focus"]:GetBool()
    print("[Main] focus:", focus)
    if not focus then
        App.SetPaused(true)
        if App.audio then App.audio:Pause(true) end
        App.SaveLocal()
    else
        App.SetPaused(false)
        if App.audio then App.audio:Pause(false) end
    end
end
