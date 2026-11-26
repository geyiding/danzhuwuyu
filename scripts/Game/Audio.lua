-- ============================================================================
-- Audio.lua · 音效 / BGM（缺文件时静默跳过，方便先跑程序化 Demo 再补音频）
-- 规则：首次用户手势后才解锁播放；同名音效 50ms 节流；音乐/音效开关独立持久化。
-- 需要的音频文件清单见 docs/GDD.md「音频」章节。
-- ============================================================================

local Audio = {}
Audio.__index = Audio

Audio.FILES = {
    bgm_title = "Sounds/bgm_title.ogg",
    bgm_game  = "Sounds/bgm_game.ogg",
    bgm_fever = "Sounds/bgm_fever.ogg",
    launch = "Sounds/sfx_launch.ogg", peg = "Sounds/sfx_peg.ogg", bumper = "Sounds/sfx_bumper.ogg",
    coin = "Sounds/sfx_coin.ogg", mult = "Sounds/sfx_mult.ogg", xmult = "Sounds/sfx_xmult.ogg",
    pop = "Sounds/sfx_pop.ogg", boom = "Sounds/sfx_boom.ogg", pocket = "Sounds/sfx_pocket.ogg",
    start = "Sounds/sfx_start.ogg", spin = "Sounds/sfx_spin.ogg", reel = "Sounds/sfx_reel.ogg",
    reach = "Sounds/sfx_reach.ogg", fever = "Sounds/sfx_fever.ogg", settle = "Sounds/sfx_settle.ogg",
    bigwin = "Sounds/sfx_bigwin.ogg", charm = "Sounds/sfx_charm.ogg", click = "Sounds/sfx_click.ogg",
    buy = "Sounds/sfx_buy.ogg", fail = "Sounds/sfx_fail.ogg",
}

function Audio.new(scene)
    local self = setmetatable({}, Audio)
    self.scene = scene
    self.music, self.sfx = true, true
    self.unlocked = false
    self.clock = 0
    self.last = {}
    self.sounds = {}
    self.bgmName = nil
    return self
end

function Audio:_get(name)
    local s = self.sounds[name]
    if s ~= nil then return s or nil end
    s = false
    local path = Audio.FILES[name]
    if path and cache and cache.Exists then
        local ok, exists = pcall(function() return cache:Exists(path) end)
        if ok and exists then
            s = cache:GetResource("Sound", path) or false
        end
    end
    self.sounds[name] = s
    return s or nil
end

function Audio:Unlock()
    if self.unlocked then return end
    self.unlocked = true
    if self.bgmName then self:PlayBGM(self.bgmName, true) end
end

function Audio:Update(dt)
    self.clock = self.clock + dt
end

function Audio:Play(name, pitch)
    if not self.sfx or not self.unlocked or not self.scene then return end
    local last = self.last[name]
    if last and self.clock - last < 0.05 then return end
    self.last[name] = self.clock
    local snd = self:_get(name)
    if not snd then return end
    local node = self.scene:CreateChild("SFX")
    local src = node:CreateComponent("SoundSource")
    src.soundType = SOUND_EFFECT
    src.autoRemoveMode = REMOVE_NODE
    if pitch and pitch ~= 1 and snd.frequency then src.frequency = snd.frequency * pitch end
    src:Play(snd)
end

function Audio:PlayBGM(name, force)
    if self.bgmName == name and not force and self.bgmSrc then return end
    self.bgmName = name
    if self.bgmSrc then self.bgmSrc:Stop() end
    if not self.music or not self.unlocked or not self.scene then return end
    local snd = self:_get(name)
    if not snd then return end
    snd.looped = true
    if not self.bgmNode then
        self.bgmNode = self.scene:CreateChild("BGM")
        self.bgmSrc = self.bgmNode:CreateComponent("SoundSource")
        self.bgmSrc.soundType = SOUND_MUSIC
    end
    self.bgmSrc:Play(snd)
end

function Audio:SetMusic(on)
    self.music = on
    if not on then
        if self.bgmSrc then self.bgmSrc:Stop() end
    elseif self.bgmName then
        self:PlayBGM(self.bgmName, true)
    end
end

function Audio:SetSfx(on)
    self.sfx = on
end

function Audio:Pause(paused)
    if self.bgmSrc then
        if paused then self.bgmSrc:Stop() elseif self.music and self.bgmName then self:PlayBGM(self.bgmName, true) end
    end
end

return Audio
