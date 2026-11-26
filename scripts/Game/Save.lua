-- ============================================================================
-- Save.lua · 双端存档（本地文件 + clientCloud 云变量）
--
--  · 本地每 30 秒自动存、云端每 120 秒自动存（仅局内、未暂停、且启动云同步检查通过）
--  · 总设置「保存游戏」同时写两端，界面显示两端实际保存时间；失败显示红色「保存失败」
--  · 启动时对比 savedAt → saveSeq → 进度，谁领先读谁；云端同步回本地保持原时间戳
--  · 无本地档时先探测云端：确认无云档才建新号；读取失败/超时 → 弹窗「重试读取 / 开始新档」，
--    严禁静默建新号或自动保存覆盖
--  · 音乐/音效偏好单独存 prefs 文件
--  · 所有网络请求带 10 秒看门狗，迟到回调按请求号丢弃
-- ============================================================================

local C = require("Game/Config")

local Save = {}

local okJson, cjson = pcall(require, "cjson")

Save.prefs = { music = true, sfx = true }
Save.localTime, Save.cloudTime = nil, nil      -- 最近一次成功保存的 os.time()
Save.localFail, Save.cloudFail = false, false
Save.cloudState = "off"   -- off（无云接口）| checking | ready | failed
Save.seq = 0
Save.envelope = nil       -- 启动时选中的存档
Save.timers = { localT = 0, cloudT = 0 }
Save.pending = nil        -- { id, t, onTimeout }
Save.reqId = 0

local function encode(t)
    if not okJson then return nil end
    local ok, s = pcall(cjson.encode, t)
    return ok and s or nil
end

local function decode(s)
    if not okJson or type(s) ~= "string" then return nil end
    local ok, t = pcall(cjson.decode, s)
    return ok and t or nil
end

local function readFile(name)
    if not File or not fileSystem then return nil end
    if not fileSystem:FileExists(name) then return nil end
    local f = File(name, FILE_READ)
    if not f:IsOpen() then return nil end
    local s = f:ReadString()
    f:Close()
    return s
end

local function writeFile(name, s)
    if not File or not s then return false end
    local f = File(name, FILE_WRITE)
    if not f:IsOpen() then return false end
    f:WriteString(s)
    f:Close()
    return true
end

-- ---------------------------------------------------------------------------
-- 偏好
-- ---------------------------------------------------------------------------
function Save.LoadPrefs()
    local t = decode(readFile(C.SAVE.prefsFile))
    if type(t) == "table" then
        if t.music ~= nil then Save.prefs.music = t.music end
        if t.sfx ~= nil then Save.prefs.sfx = t.sfx end
    end
    return Save.prefs
end

function Save.SavePrefs()
    writeFile(C.SAVE.prefsFile, encode(Save.prefs))
end

-- ---------------------------------------------------------------------------
-- 信封
-- ---------------------------------------------------------------------------
local function progressOf(env)
    local m = env and env.body and env.body.meta
    return m and ((m.bestAnte or 0) * 1000 + (m.runs or 0)) or 0
end

--- a 是否领先 b
local function leads(a, b)
    if not b then return a ~= nil end
    if not a then return false end
    if (a.savedAt or 0) ~= (b.savedAt or 0) then return (a.savedAt or 0) > (b.savedAt or 0) end
    if (a.saveSeq or 0) ~= (b.saveSeq or 0) then return (a.saveSeq or 0) > (b.saveSeq or 0) end
    return progressOf(a) > progressOf(b)
end

local function makeEnvelope(body)
    Save.seq = Save.seq + 1
    return {
        version = C.VERSION,
        savedAt = os.time(),
        saveSeq = Save.seq,
        summary = { bestAnte = body.meta and body.meta.bestAnte or 0, inRun = body.run ~= nil },
        body = body,
    }
end

function Save.LoadLocal()
    local env = decode(readFile(C.SAVE.localFile))
    if type(env) == "table" and env.body then return env end
    return nil
end

function Save.WriteLocal(env)
    local ok = writeFile(C.SAVE.localFile, encode(env))
    Save.localFail = not ok
    if ok then Save.localTime = os.time() end
    return ok
end

-- ---------------------------------------------------------------------------
-- 云端
-- ---------------------------------------------------------------------------
local function cloudAvailable()
    return clientCloud ~= nil
end

local function newRequest(onTimeout)
    Save.reqId = Save.reqId + 1
    Save.pending = { id = Save.reqId, t = 0, onTimeout = onTimeout }
    return Save.reqId
end

local function finishRequest(id)
    if Save.pending and Save.pending.id == id then
        Save.pending = nil
        return true
    end
    return false   -- 迟到回调
end

--- 启动：读取本地 + 探测云端
--- cb.onReady(envelope|nil)       选出领先存档后调用（nil = 全新玩家）
--- cb.onCloudFail()               无本地档且云读取失败 → 由 UI 弹窗
function Save.Startup(cb)
    local localEnv = Save.LoadLocal()
    if localEnv then
        Save.seq = localEnv.saveSeq or 0
        Save.localTime = localEnv.savedAt
    end
    if not cloudAvailable() then
        Save.cloudState = "off"
        print("[Save] cloud unavailable, local only")
        Save.envelope = localEnv
        cb.onReady(localEnv)
        return
    end
    Save.cloudState = "checking"
    local id
    id = newRequest(function()
        print("[Save] cloud probe timeout")
        Save.cloudState = "failed"
        if localEnv then
            Save.envelope = localEnv
            cb.onReady(localEnv)
        else
            cb.onCloudFail()
        end
    end)
    clientCloud:BatchGet()
        :Key("has_save")
        :Key("save_body")
        :Fetch({
            ok = function(values, iscores)
                if not finishRequest(id) then return end
                local has = iscores and iscores.has_save or 0
                local cloudEnv = nil
                if has == 1 then
                    cloudEnv = decode(values and values.save_body)
                    if not cloudEnv then
                        -- 有标记却解析失败：视同读取失败，防覆盖
                        Save.cloudState = "failed"
                        if localEnv then Save.envelope = localEnv; cb.onReady(localEnv) else cb.onCloudFail() end
                        return
                    end
                    Save.cloudTime = cloudEnv.savedAt
                end
                Save.cloudState = "ready"
                local pick = localEnv
                if leads(cloudEnv, localEnv) then
                    pick = cloudEnv
                    Save.seq = math.max(Save.seq, cloudEnv.saveSeq or 0)
                    writeFile(C.SAVE.localFile, encode(cloudEnv))   -- 同步回本地，保持原时间戳
                    print("[Save] cloud save leads, adopted")
                end
                Save.envelope = pick
                cb.onReady(pick)
            end,
            error = function(code, reason)
                if not finishRequest(id) then return end
                print("[Save] cloud probe error", tostring(code), tostring(reason))
                Save.cloudState = "failed"
                if localEnv then Save.envelope = localEnv; cb.onReady(localEnv) else cb.onCloudFail() end
            end,
        })
end

--- 重试读取云端（云读取失败弹窗）
function Save.RetryStartup(cb)
    Save.Startup(cb)
end

--- 玩家明确选择「开始新档」：允许之后的云保存覆盖
function Save.ConfirmNewProfile()
    Save.cloudState = cloudAvailable() and "ready" or "off"
end

function Save.WriteCloud(env, done)
    if not cloudAvailable() or Save.cloudState ~= "ready" then
        if done then done(false) end
        return
    end
    local body = encode(env)
    if not body then if done then done(false) end return end
    local id
    id = newRequest(function()
        Save.cloudFail = true
        if done then done(false) end
    end)
    clientCloud:BatchSet()
        :SetInt("has_save", 1)
        :Set("save_meta", env.summary)
        :Set("save_body", body)
        :Save("autosave", {
            ok = function()
                if not finishRequest(id) then return end
                Save.cloudFail = false
                Save.cloudTime = os.time()
                if done then done(true) end
            end,
            error = function(code, reason)
                if not finishRequest(id) then return end
                print("[Save] cloud write error", tostring(code), tostring(reason))
                Save.cloudFail = true
                if done then done(false) end
            end,
        })
end

-- ---------------------------------------------------------------------------
-- 自动 / 手动保存
-- ---------------------------------------------------------------------------
--- collect(): 返回 body = { meta = ..., run = ... }
function Save.Commit(collect, toCloud, done)
    local env = makeEnvelope(collect())
    local okL = Save.WriteLocal(env)
    if toCloud then
        Save.WriteCloud(env, function(okC) if done then done(okL, okC) end end)
    elseif done then
        done(okL, nil)
    end
    return okL
end

--- 每帧调用。active = 局内且未暂停
function Save.Update(dt, active, collect)
    if Save.pending then
        Save.pending.t = Save.pending.t + dt
        if Save.pending.t > C.SAVE.cloudTimeout then
            local p = Save.pending
            Save.pending = nil
            if p.onTimeout then p.onTimeout() end
        end
    end
    if not active then return end
    local T = Save.timers
    T.localT = T.localT + dt
    T.cloudT = T.cloudT + dt
    if T.localT >= C.SAVE.localInterval then
        T.localT = 0
        local env = makeEnvelope(collect())
        Save.WriteLocal(env)
        if T.cloudT >= C.SAVE.cloudInterval then
            T.cloudT = 0
            if Save.cloudState == "ready" and not Save.pending then Save.WriteCloud(env) end
        end
    end
end

function Save.FormatTime(t)
    if not t then return nil end
    return os.date("%H:%M:%S", t)
end

return Save
