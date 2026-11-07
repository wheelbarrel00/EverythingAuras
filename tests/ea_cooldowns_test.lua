-- Learned cooldown lengths: the real cooldown tracker and EA/Cooldowns.lua, the conditions compiler and the trigger text.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local function read(path)
  local file = assert(io.open(T.repoRoot .. "/" .. path))
  local text = file:read("*a"):gsub("\r\n", "\n")
  file:close()
  return text
end

local function noop() end
local secret = newproxy(true)
local function forbidden() error("Arithmetic or comparison on secret cooldown") end
for _, key in ipairs({"__add", "__sub", "__mul", "__div", "__lt", "__le", "__eq", "__concat"}) do
  getmetatable(secret)[key] = forbidden
end
local function issecret(value) return rawequal(value, secret) end
local function hassecret(...)
  for i = 1, select("#", ...) do if issecret(select(i, ...)) then return true end end
  return false
end

local source = read("EverythingAuras/GenericTrigger.lua")
local first = assert(source:find("-- CD/Rune/GCD support code", 1, true))
local last = assert(source:find("-- Swing timer support code", first, true))
local trackerSource = source:sub(first, last - 1)

local function fixture()
  local f = {now = 100, spells = {}, base = {}, frames = {}}
  local function frame()
    local fr = {RegisterEvent = noop, RegisterUnitEvent = noop,
      SetScript = function(self, name, fn) self[name] = fn end,
      Show = function(self) self.shown = true end,
      Hide = function(self) self.shown = false end}
    f.frames[#f.frames + 1] = fr
    return fr
  end
  local wa = {IsRetail = function() return true end, IsForever = function() return false end,
    IsTWW = function() return true end, IsWrathOrCata = function() return false end,
    IsClassicOrWrath = function() return false end,
    IsWrathOrCataOrMistsOrRetail = function() return true end,
    IsPaused = function() return false end, IsSpellKnownIncludingPet = function() return true end,
    IsLibsOK = function() return true end, L = setmetatable({}, {__index = function(_, key) return key end})}
  local private = {frames = {}, callbacks = {RegisterCallback = noop}, ExecEnv = {},
    StartProfileSystem = noop, StopProfileSystem = noop, ScanEvents = noop, ScanEventsByID = noop,
    db = {}, event_prototypes = {["Cooldown Progress (Spell)"] = {args = {
      {name = "secretValuesDescription", text = "old"}, {name = "remaining", desc = "old"}}}}}
  private.ExecEnv.GetSpellInfo = function(id) return id, nil, id, nil, nil, nil, id end
  private.ExecEnv.GetSpellName = function(id) return id end
  local env = setmetatable({EverythingAuras = wa, Private = private, CreateFrame = frame,
    GetTime = function() return f.now end, issecretvalue = issecret, hasanysecretvalues = hassecret,
    Constants = {SpellCooldownConsts = {GLOBAL_RECOVERY_CATEGORY = 133}},
    abs = math.abs, C_Secrets = {ShouldSpellCooldownBeSecret = function(id)
      return f.combat and (id == 61304 or (f.spells[id] ~= nil)) or false
    end},
    C_Spell = {GetSpellCooldown = function(id) return f.spells[id] and f.spells[id].info end,
      GetSpellCharges = function(id) return f.spells[id] and f.spells[id].charges end,
      GetSpellCastCount = function() return 0 end,
      GetOverrideSpell = function(id) return id end},
    C_Container = {GetItemCooldown = function() return 0, 0, true end},
    UnitName = function() return "Krivos" end, GetRealmName = function() return "Realm" end,
    GetSpellBaseCooldown = function(id)
      local ms = f.base[id]
      if ms and f.combat and f.baseSecretInCombat then return secret end
      return ms
    end,
    timer = {ScheduleTimerFixed = function() return {} end, CancelTimer = noop},
  }, {__index = _G})
  setfenv(assert(loadstring(trackerSource)), env)()
  local chunk = assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/Cooldowns.lua"))
  setfenv(chunk, env)("EverythingAuras", private)
  f.wa, f.private, f.env = wa, private, env
  f.eaFrame = f.frames[#f.frames]
  f.cdFrame = function() return private.frames["Cooldown Trigger Handler"] end

  -- Plain out of combat, secret in combat, isActive and isOnGCD plain as measured.
  function f:set(id, active, duration, onGCD, modRate)
    local spell = self.spells[id] or {}
    self.spells[id] = spell
    spell.active, spell.duration, spell.start = active, duration, active and self.now or 0
    spell.onGCD, spell.modRate = onGCD or false, modRate or 1
    self:refresh(id)
  end
  function f:refresh(id)
    local spell = self.spells[id]
    spell.info = {isActive = spell.active, isEnabled = true, isOnGCD = spell.onGCD,
      startTime = self.combat and secret or spell.start,
      duration = self.combat and secret or (spell.active and spell.duration or 0),
      modRate = self.combat and secret or spell.modRate}
  end
  function f:watch(id)
    self.wa.WatchSpellCooldown(id, false, true, false)
  end
  function f:send(event, ...)
    if self.cdFrame() then self.cdFrame():HandleEvent(event, ...) end
  end
  function f:combatStart()
    self.combat = true
    for id in pairs(self.spells) do self:refresh(id) end
    self:send("WA_SECRET_STATE_UPDATE")
  end
  function f:combatEnd()
    self.combat = false
    for id in pairs(self.spells) do self:refresh(id) end
    self:send("WA_SECRET_STATE_UPDATE")
  end
  function f:estimate(id, track)
    return self.private.ExecEnv.EAGetSpellCooldown(id, false, false, false, track or "auto")
  end
  function f:lengths()
    return self.private.db.eaCooldownLengths and self.private.db.eaCooldownLengths["Krivos-Realm"] or {}
  end
  f.eaFrame.OnEvent(f.eaFrame, "PLAYER_ENTERING_WORLD")
  f.now = f.now + 5
  return f
end

T.section("Learning out of combat")
local f = fixture()
f:set(100, false, 0)
f:watch(100)
f:set(100, true, 8)
f:send("SPELL_UPDATE_COOLDOWN", 100)
T.expect(f:lengths()[100] == 8, "a plain cooldown read saves its length for this character")
f:set(100, true, 1.5, true)
f:send("SPELL_UPDATE_COOLDOWN", 100)
T.expect(f:lengths()[100] == 8, "a GCD-only blip does not overwrite the length")
f.now = f.now + 20
f:set(100, true, 6.995)
f:send("SPELL_UPDATE_COOLDOWN", 100)
T.expect(f:lengths()[100] == 6.995, "every out-of-combat use learns again, so haste changes are followed")
f:set(101, false, 0)
f:watch(101)
f:set(101, true, 10, false, 2)
f:send("SPELL_UPDATE_COOLDOWN", 101)
T.expect(f:lengths()[101] == 5, "a cooldown running at twice the rate is saved as its real length")
local start, duration = f.wa.GetSpellCooldown(100)
T.expect(start == f.now and duration == 6.995, "out of combat the public function still returns the plain values")

T.section("In combat")
f = fixture()
f:set(100, false, 0)
f:watch(100)
f:set(100, true, 8)
f:send("SPELL_UPDATE_COOLDOWN", 100)
f.now = f.now + 9
f:set(100, false, 0)
f:send("SPELL_UPDATE_COOLDOWN", 100)
f:combatStart()
local s, d, _, _, rate, paused, estimated = f:estimate(100)
T.expect(s == 0 and d == 0 and estimated == false, "a ready spell reads ready, which is exact")
T.expect(f.wa.GetSpellCooldown(100) == nil, "the public function custom code calls still returns nothing in combat")
local castAt = f.now
f.spells[100].active, f.spells[100].onGCD = true, false
f:refresh(100)
f:send("SPELL_UPDATE_COOLDOWN", 100)
s, d, _, _, rate, paused, estimated = f:estimate(100)
T.expect(s == castAt and d == 8 and estimated == true and rate == 1.0 and paused == false,
  "a cast in combat starts the learned length at the cooldown's start")
T.expect(f.wa.GetSpellCooldown(100) == nil, "the estimate never reaches the public function")
f.now = f.now + 5
T.expect(f:estimate(100) == castAt, "the start stays put while the cooldown runs")
f:send("SPELL_UPDATE_COOLDOWN")
f:send("SPELL_UPDATE_COOLDOWN", 100)
T.expect(f:estimate(100) == castAt, "another spell's GCD and later cooldown events do not restart the estimate")
f.now = castAt + 9
T.expect(f:estimate(100) == nil, "past its length while still not ready, the time is unknown again")
f.spells[100].active = false
f:refresh(100)
f:send("SPELL_UPDATE_COOLDOWN", 100)
s, d, _, _, _, _, estimated = f:estimate(100)
T.expect(s == 0 and d == 0 and estimated == false, "ready in combat is read exactly")
f.spells[100].active, f.spells[100].onGCD = true, true
f:refresh(100)
f:send("SPELL_UPDATE_COOLDOWN", 100)
s = f:estimate(100)
T.expect(s == 0, "the GCD on a ready spell is not a cooldown start")
T.expect(f:estimate(100, "charges") == nil, "Track Charges asks for no estimate")
f.spells[100].active, f.spells[100].onGCD = false, false
f:refresh(100)
f:send("SPELL_UPDATE_COOLDOWN", 100)
f.spells[100].active = true
f:refresh(100)
f:send("SPELL_UPDATE_USABLE")
T.expect(f:estimate(100) == nil, "a refresh that leaves readiness unknown right after a cast is not reported as ready")
f:send("SPELL_UPDATE_COOLDOWN", 100)
T.expect(f:estimate(100) == f.now, "the cast's own cooldown event then starts the estimate")

T.section("Before a length is learned")
f = fixture()
f.base[200] = 30000
f:set(200, false, 0)
f:watch(200)
f:combatStart()
f.spells[200].active = true
f:refresh(200)
f:send("SPELL_UPDATE_COOLDOWN", 200)
s, d, _, _, _, _, estimated = f:estimate(200)
T.expect(s == f.now and d == 30 and estimated == true, "the base cooldown read out of combat stands in")
f = fixture()
f.base[201] = 30000
f.baseSecretInCombat = true
f:combatStart()
f:set(201, false, 0)
f:watch(201)
f.spells[201].active = true
f:refresh(201)
f:send("SPELL_UPDATE_COOLDOWN", 201)
T.expect(f:estimate(201) == nil, "a base cooldown that reads secret in combat is never compared, so no estimate")
f = fixture()
f.base[202] = 1500
f:set(202, false, 0)
f:watch(202)
f:combatStart()
f.spells[202].active = true
f:refresh(202)
f:send("SPELL_UPDATE_COOLDOWN", 202)
T.expect(f:estimate(202) == nil, "a GCD-length base cooldown means none is known")

T.section("Cooldowns that started before the pull")
f = fixture()
f:set(300, false, 0)
f:watch(300)
f:set(300, true, 20)
f:send("SPELL_UPDATE_COOLDOWN", 300)
local before = f.now
f.now = f.now + 5
f:combatStart()
s, d, _, _, _, _, estimated = f:estimate(300)
T.expect(s == before and d == 20 and estimated == true, "the last plain read carries into combat, marked as an estimate")

T.section("What gets no estimate")
f = fixture()
f:set(400, false, 0)
f.spells[400].charges = {currentCharges = 2, maxCharges = 2, cooldownStartTime = 0, cooldownDuration = 0, chargeModRate = 1}
f:watch(400)
f:combatStart()
f.spells[400].charges = {currentCharges = secret, maxCharges = 2, cooldownStartTime = secret,
  cooldownDuration = secret, chargeModRate = secret}
f.spells[400].active = true
f:refresh(400)
f:send("SPELL_UPDATE_COOLDOWN", 400)
T.expect(f:estimate(400) == nil, "a spell with charges keeps today's behavior")
f = fixture()
f:combatStart()
f:set(401, true, 10)
f:watch(401)
T.expect(f:estimate(401) == nil, "a cooldown first seen running in combat has no known start")
f = fixture()
f.base[402] = 10000
f:set(402, false, 0)
f:watch(402)
f:combatStart()
f.eaFrame.OnEvent(f.eaFrame, "PLAYER_LEAVING_WORLD")
f.eaFrame.OnEvent(f.eaFrame, "PLAYER_ENTERING_WORLD")
f.now = f.now + 2.5
f.spells[402].active = true
f:refresh(402)
f.cdFrame().inWorld = f.now - 5
f:send("SPELL_UPDATE_COOLDOWN", 402)
f.now = f.now + 1
f:send("SPELL_UPDATE_COOLDOWN", 402)
T.expect(f:estimate(402) == nil, "after a loading screen a running cooldown has no known start, even once settled")
f.spells[402].active = false
f:refresh(402)
f:send("SPELL_UPDATE_COOLDOWN", 402)
f.spells[402].active = true
f:refresh(402)
f:send("SPELL_UPDATE_COOLDOWN", 402)
T.expect(f:estimate(402) == f.now, "the next ready reading and cast start estimates again")

T.section("Right after a loading screen")
f = fixture()
f:set(600, false, 0)
f:watch(600)
f.eaFrame.OnEvent(f.eaFrame, "PLAYER_ENTERING_WORLD")
f.cdFrame().inWorld = f.now - 5
f:set(600, true, 12)
f:send("SPELL_UPDATE_COOLDOWN", 600)
T.expect(f:lengths()[600] == nil, "a plain read in the settle window teaches nothing either")
f.now = f.now + 4
f:send("SPELL_UPDATE_COOLDOWN", 600)
T.expect(f:lengths()[600] == 12, "after it, plain reads teach again")

T.section("Lengths per character")
f = fixture()
f.env.UnitName = function() return "Other" end
f:set(500, false, 0)
f:watch(500)
f:set(500, true, 12)
f:send("SPELL_UPDATE_COOLDOWN", 500)
T.expect(f.private.db.eaCooldownLengths["Other-Realm"][500] == 12 and f:lengths()[500] == nil,
  "each character keeps its own lengths in the saved file")

T.section("Conditions that fire things")
local private = f.private
local has = private.EAConditionHasAlert
T.expect(has({changes = {{property = "sound"}}}) and has({changes = {{property = "chat"}}})
  and has({changes = {{property = "customcode"}}}) and has({changes = {{property = "glowexternal"}}})
  and has({changes = {{property = "sub.3.glow"}}}), "sound, chat, custom code and both kinds of glow count as alerts")
T.expect(not has({changes = {{property = "alpha"}, {property = "sub.3.text_color"}, {property = "sub.4.glowColor"}}})
  and not has({}) and not has(nil), "looks are not alerts")

T.section("Trigger option text")
local args = private.event_prototypes["Cooldown Progress (Spell)"].args
T.expect(args[1].text:find("estimated", 1, true) ~= nil, "the trigger's secret-values note says the time left is estimated")
T.expect(args[2].desc:find("plays no sounds, sends no chat, runs no custom code and shows no glows", 1, true) ~= nil
  and args[2].desc:find("charges", 1, true) ~= nil, "the Remaining Time tooltip names what waits and what is not estimated")

T.section("The conditions compiler")
local compiled
local cprivate = {ExecEnv = {conditionHelpers = {}, customConditionsFunctions = {}, conditionTextFormatters = {}},
  regionTypes = {icon = {properties = {
    sound = {display = "Sound", action = "SoundPlay", type = "sound"},
    alpha = {display = "Alpha", setter = "SetAlpha", type = "number"},
  }}},
  subRegionTypes = {}, callbacks = {RegisterCallback = noop}, QuotedString = function(text) return ("%q"):format(text) end,
  GetTriggerConditions = function() return {[1] = {expirationTime = {type = "timer"}, onCooldown = {type = "bool",
    test = function(state, needle) return state and state.show and (state.expirationTime > 1000) == (needle == 1) end}}} end,
  GetErrorHandlerUid = function() return function(err) error(err) end end,
  GetProgressSourceFor = function() return {} end,
  LoadFunction = function(code) compiled = code; return nil end,
  EAConditionHasAlert = private.EAConditionHasAlert,
}
local cenv = setmetatable({EverythingAuras = {IsLibsOK = function() return true end, L = setmetatable({}, {__index = function(_, k) return k end}),
  timer = {CancelTimer = noop}, newFeatureString = ""}, tinsert = table.insert,
  -- WoW's xpcall passes extra arguments on, Lua 5.1's does not.
  xpcall = function(fn, handler, ...)
    local args, n = {...}, select("#", ...)
    return xpcall(function() return fn(unpack(args, 1, n)) end, handler)
  end, CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end},
  {__index = _G})
local cchunk = assert(loadfile(T.repoRoot .. "/EverythingAuras/Conditions.lua"))
setfenv(cchunk, cenv)("EverythingAuras", cprivate)

local function compile(changes, check)
  compiled = nil
  cprivate.LoadConditionFunction({id = "CD", uid = "uid", regionType = "icon", conditions = {
    {check = check or {trigger = 1, variable = "expirationTime", op = "<", value = "5"}, changes = changes}}})
  local played, alpha = 0, nil
  local runEnv = setmetatable({Private = cprivate, EverythingAuras = {GetActiveConditions = function() return {} end},
    GetTime = function() return 1000 end, wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    issecretvalue = function() return false end, abs = math.abs}, {__index = _G})
  local fn = setfenv(assert(loadstring(compiled)), runEnv)()
  cprivate.ExecEnv.ScheduleConditionCheck = noop
  cprivate.ExecEnv.CancelConditionCheck = noop
  local function run(estimated)
    local region = {id = "CD", states = {[1] = {show = true, expirationTime = 1003, eaTimeEstimated = estimated}},
      SoundPlay = function() played = played + 1 end, SetAlpha = function(_, value) alpha = value end}
    played, alpha = 0, nil
    fn(region)
    return played, alpha
  end
  return run
end

local run = compile({{property = "sound", value = {sound = "x"}}, {property = "alpha", value = 0.4}})
T.expect(compiled:find("eaTimeEstimated", 1, true) ~= nil, "a condition that plays a sound checks for an estimate")
local played = run(true)
T.expect(played == 0, "an estimated time left never plays a condition's sound")
played = run(nil)
T.expect(played == 1, "an exact time left plays it as before")
run = compile({{property = "alpha", value = 0.4}})
T.expect(compiled:find("eaTimeEstimated", 1, true) == nil, "a looks-only condition is compiled as before")
local _, alpha = run(true)
T.expect(alpha == 0.4, "an estimated time left changes looks")
run = compile({{property = "sound", value = {sound = "x"}}}, {trigger = 1, variable = "onCooldown", value = 1})
played = run(true)
T.expect(played == 0, "On Cooldown, which reads the time left, never plays a sound from an estimate")
played = run(nil)
T.expect(played == 1, "and plays it from an exact time as before")

T.section("The trigger uses the private function")
local prototypes = read("EverythingAuras/Prototypes.lua")
T.expect(prototypes:find("paused, eaEstimated = Private.ExecEnv.EAGetSpellCooldown(effectiveSpellId, ignoreRuneCD, showgcd, ignoreSpellKnown, track)", 1, true) ~= nil,
  "the cooldown trigger reads the estimate through ExecEnv, the only part of Private built-in code can see")
local initStart = assert(prototypes:find('["Cooldown Progress (Spell)"] = {', 1, true))
local initEnd = assert(prototypes:find("GetNameAndIcon = GetNameAndIconForSpellName", initStart, true))
local outside = {}
for name in prototypes:sub(initStart, initEnd):gmatch("Private%.([%w_]+)") do
  if name ~= "ExecEnv" then outside[#outside + 1] = name end
end
T.expect(#outside == 0, "the generated trigger code names nothing in Private but ExecEnv (AuraEnvironment.lua PrivateForBuiltIn)"
  .. (#outside > 0 and (": " .. table.concat(outside, ", ")) or ""))
T.expect(prototypes:find("state.eaTimeEstimated = eaEstimated or nil", 1, true) ~= nil
  and prototypes:find("state.eaQuiet = isSecret or nil", 1, true) ~= nil,
  "the state carries the estimate mark, and Remaining Time on any hidden cooldown silences the aura (the goat, 2026-11-07)")
local toc = read("EverythingAuras/EverythingAuras_Camelot.toc")
T.expect(toc:find("EA\\Combat.lua\nEA\\Cooldowns.lua\n", 1, true) ~= nil, "the core TOC loads EA\\Cooldowns.lua after Combat")

T.finish()
