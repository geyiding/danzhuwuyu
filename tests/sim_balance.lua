-- 纯 Lua 数值模拟：lua5.4 tests/sim_balance.lua [runs]
-- 用简单 AI（贪心买东西）跑完整局，统计每层通过率 / 单发分数，用来校准 Config.ANTE_TARGETS
package.path = "scripts/?.lua;tests/?.lua;" .. package.path
local quiet = os.getenv("SIM_VERBOSE") ~= "1"
if quiet then _G.print = function() end end
local out = io.write
local C = require("Game/Config")
local Run = require("Game/Run")
local Stage = require("Game/Stage")

local RUNS = tonumber(arg[1]) or 20
local DT = 1 / 60

local function playStage(run)
  local fx = setmetatable({ Settle = function(_, c, m) CHIPS[#CHIPS+1] = c; MULTS[#MULTS+1] = m end }, { __index = function() return function() end end })
  local st = Stage.new(run, run:CurrentStageInfo(), fx)
  local guard = 0
  local launches = {}
  while st.phase ~= "cleared" and st.phase ~= "failed" do
    if st.phase == "idle" then st:Launch() end
    local prev = st.phase
    st:Update(DT)
    if prev == "launch" and st.phase == "settle" then launches[#launches+1] = st.lastLaunchScore end
    guard = guard + 1
    assert(guard < 60 * 60 * 10, "stage timeout")
  end
  return st, launches, guard * DT
end

local function shopAI(run)
  for _ = 1, 6 do
    local best, bi = nil, nil
    for i, it in ipairs(run.shop) do
      if run:CanBuy(i) and not (it.type == "mod" and it.id == "remove") then
        local v = (it.type == "charm" and 3 or (it.type == "mod" and 2.5 or 1.5)) / it.price
        if not best or v > best then best, bi = v, i end
      end
    end
    if not bi then break end
    run:Buy(bi)
  end
end

CHIPS, MULTS = {}, {}
local reach = {}
local launchByAnte = {}
local timeTotal, timeN = 0, 0
for r = 1, RUNS do
  local run = Run.new(C.STARTERS[(r % 3) + 1].key, 1000 + r)
  while run.phase ~= "over" and run.phase ~= "win" do
    local st, ls, secs = playStage(run)
    timeTotal, timeN = timeTotal + secs, timeN + 1
    launchByAnte[run.ante] = launchByAnte[run.ante] or {}
    for _, v in ipairs(ls) do table.insert(launchByAnte[run.ante], v) end
    if st.phase == "cleared" then
      run:OnStageCleared(st)
      if run.phase == "shop" then shopAI(run); run:NextStage() end
    else
      run:OnStageFailed(st)
    end
  end
  reach[run.ante] = (reach[run.ante] or 0) + 1
  if run.phase == "win" then reach.win = (reach.win or 0) + 1 end
end

out(string.format("runs=%d avg stage time=%.1fs\n", RUNS, timeTotal / timeN))
for a = 1, 8 do
  local t = launchByAnte[a]
  if t and #t > 0 then
    table.sort(t)
    out(string.format("ante %d target=%7d  launches=%4d  p25=%8d  med=%8d  p75=%8d  max=%9d  died_here=%d\n",
      a, C.ANTE_TARGETS[a], #t, t[math.floor(#t*0.25)+1], t[math.floor(#t*0.5)+1], t[math.floor(#t*0.75)+1], t[#t], reach[a] or 0))
  end
end
out("wins=" .. (reach.win or 0) .. "\n")
table.sort(CHIPS); table.sort(MULTS)
out(string.format("chips med=%d p90=%d | mult med=%.1f p90=%.1f max=%.1f\n", CHIPS[#CHIPS//2+1], CHIPS[math.floor(#CHIPS*0.9)+1], MULTS[#MULTS//2+1], MULTS[math.floor(#MULTS*0.9)+1], MULTS[#MULTS]))
