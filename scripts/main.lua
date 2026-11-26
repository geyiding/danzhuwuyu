-- ============================================================================
-- 弹珠物语 / Marble Story
-- 2D 物理（Box2D）起点 · 手机竖屏 720 x 1280
-- ============================================================================

local UI = require("urhox-libs/UI")

---@type Scene
local scene_
---@type Node
local cameraNode_
---@type Widget
local uiRoot_
---@type Widget
local titleLayer_
local debugDraw_ = false

local CONFIG = {
    Title = "弹珠物语",
    Width = 720,
    Height = 1280,
    Gravity = 9.81,
    PixelPerUnit = 100.0,
}

function Start()
    graphics.windowTitle = CONFIG.Title

    InitUI()
    CreateScene()
    SetupViewport()
    CreateUI()
    SubscribeToEvents()

    print("=== " .. CONFIG.Title .. " started, screen " ..
        graphics:GetWidth() .. "x" .. graphics:GetHeight() .. " ===")
end

function Stop()
    UI.Shutdown()
end

function InitUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    local physicsWorld = scene_:CreateComponent("PhysicsWorld2D")
    physicsWorld.gravity = Vector2(0, -CONFIG.Gravity)
    physicsWorld.drawShape = true

    local zoneNode = scene_:CreateChild("Zone")
    local zone = zoneNode:CreateComponent("Zone")
    zone.backgroundColor = Color(0.05, 0.06, 0.12)
    zone.ambientColor = Color(1, 1, 1)
end

function SetupViewport()
    cameraNode_ = scene_:CreateChild("Camera")
    local camera = cameraNode_:CreateComponent("Camera")
    camera.orthographic = true
    camera.orthoSize = CONFIG.Height / CONFIG.PixelPerUnit
    cameraNode_.position = Vector3(0, 0, -10)

    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)
end

function CreateUI()
    titleLayer_ = UI.Panel {
        id = "titleLayer",
        position = "absolute",
        top = 0,
        left = 0,
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                width = 96,
                height = 96,
                borderRadius = 48,
                backgroundColor = { 255, 196, 84, 255 },
                borderWidth = 4,
                borderColor = { 255, 240, 200, 255 },
                boxShadow = {
                    { x = 0, y = 8, blur = 24, color = { 255, 170, 60, 110 } },
                },
                marginBottom = 28,
            },
            UI.Label {
                text = CONFIG.Title,
                fontSize = 48,
                fontColor = { 255, 255, 255, 255 },
                marginBottom = 8,
            },
            UI.Label {
                text = "MARBLE STORY",
                fontSize = 14,
                fontColor = { 150, 170, 220, 200 },
                letterSpacing = 6,
                marginBottom = 64,
            },
            UI.Button {
                text = "开始游戏",
                variant = "primary",
                width = 200,
                height = 52,
                fontSize = 18,
                onClick = function()
                    titleLayer_:Hide()
                    print("Start button clicked")
                end,
            },
        },
    }

    uiRoot_ = UI.SafeAreaView {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            titleLayer_,
            UI.Label {
                id = "versionLabel",
                text = "v1.0.0",
                fontSize = 12,
                fontColor = { 255, 255, 255, 90 },
                position = "absolute",
                bottom = 16,
                left = 0,
                right = 0,
                textAlign = "center",
            },
        },
    }

    UI.SetRoot(uiRoot_)
end

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if debugDraw_ then
        local physicsWorld = scene_:GetComponent("PhysicsWorld2D")
        if physicsWorld then
            physicsWorld:DrawDebugGeometry()
        end
    end
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_Z then
        debugDraw_ = not debugDraw_
        print("Physics debug: " .. (debugDraw_ and "ON" or "OFF"))
    end
end
