-- Everything Auras step 5: the Aura trigger keeps what it cannot read in combat as last known, and own casts
-- restart own buffs as estimated. Loads the real BuffTrigger2.lua with stubs for the measured Forever behavior:
-- by-ID and by-name lookups return nil while auras are secret, enumeration throws, every in-combat UNIT_AURA
-- payload has a secret isFullUpdate (probe U, 2026-10-11), and UNIT_SPELLCAST_SUCCEEDED has a plain spellID.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")
local function noop() end
local function yes() return true end
local function no() return false end
local file = assert(io.open(T.repoRoot .. "/EverythingAuras/Prototypes.lua"))
local prototypes = file:read("*a")
file:close()
local functionStrings = assert(loadstring("return " .. assert(prototypes:match("Private.function_strings = (%b{})"))))()

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local NAMES = { [6673] = "Battle Shout", [100] = "Seal A", [101] = "Seal B", [102] = "Shout C" }

local function newFixture(neverSecret, triggers)
  local world = { now = 100, secret = false, enumerateWhileSecret = 0, timers = {}, nextInstance = 10,
    auras = { [6673] = { instance = 1, duration = 120, expirationTime = 200 } } }
  local states, data = {}, {}
  local private = {
    frames = {}, watched_trigger_events = {}, player_target_events = {},
    StartProfileSystem = noop, StopProfileSystem = noop,
    StartProfileAura = noop, StopProfileAura = noop,
    UpdatedTriggerState = noop,
    AuraWarnings = { UpdateWarning = noop },
    multiUnitUnits = { group = {}, party = {}, raid = {}, boss = {}, arena = {} },
    ExecEnv = {
      UnitName = function(unit) return unit end,
      UnitIsUnit = function(a, b) return a == b end,
      GetSpellName = function(id) return NAMES[id] end,
      GetSpellInfo = function(id) return NAMES[id], nil, 132333 end,
    },
    LibSpecWrapper = { Register = noop, SpecForUnit = function() return 71 end },
    ParseNumber = function(value) return tonumber(value) end,
    LoadFunction = function(source) return assert(loadstring(source))() end,
    function_strings = functionStrings,
  }
  local timer = {
    ScheduleTimerFixed = function(_, func, delay, arg)
      local handle = { func = func, at = world.now + delay, arg = arg }
      world.timers[handle] = true
      return handle
    end,
    CancelTimer = function(_, handle) if handle then world.timers[handle] = nil end end,
  }
  local addon = {
    IsLibsOK = yes, IsRetail = no, IsForever = yes, IsCataOrMistsOrRetail = no,
    IsWrathOrCataOrMistsOrRetail = no, IsClassicOrWrathOrCataOrMists = no, IsClassicEra = no,
    IsPaused = no, IsUntrackableSoftTarget = no, IsTWW = no,
    L = setmetatable({}, { __index = function(_, key) return key end }),
    EJIcons = {}, timer = timer,
    UnitIsPet = function(unit) return unit == "pet" end,
    SafeToNumber = function(v) return tonumber(v) end,
    UnitNameWithRealm = function(u) return u, "" end, GetPlayerReaction = noop, UnitRaidRole = noop,
    raidUnits = {}, raidpetUnits = {}, partyUnits = {}, partypetUnits = {},
    unitToPetUnit = { player = "pet" }, petUnitToUnit = { pet = "player" },
    GetTriggerStateForTrigger = function(id)
      states[id] = states[id] or {}
      return states[id]
    end,
    GetData = function(id) return data[id] end,
  }
  private.multiUnitUnits.group.player = true
  local function record(id)
    local a = world.auras[id]
    return a and { name = NAMES[id], spellId = id, auraInstanceID = a.instance, isHelpful = true, icon = 132333,
      applications = 0, duration = a.duration, expirationTime = a.expirationTime, timeMod = 1,
      isFromPlayerOrPlayerPet = true }
  end
  local function readable()
    return not world.secret or neverSecret
  end
  local function frameStub()
    return {
      events = {}, scripts = {},
      RegisterEvent = function(self, event) self.events[event] = true end,
      RegisterUnitEvent = function(self, event) self.events[event] = true end,
      UnregisterEvent = noop,
      SetScript = function(self, event, handler) self.scripts[event] = handler end,
    }
  end
  local env = setmetatable({
    EverythingAuras = addon,
    GetTime = function() return world.now end,
    IsInRaid = no,
    GetNumGroupMembers = function() return 0 end,
    GetNumSubgroupMembers = function() return 0 end,
    UnitExists = function(unit) return unit == "player" end,
    UnitGUID = function(unit) return unit end,
    UnitName = function(unit) return unit == "player" and "Me" or unit end,
    UnitIsVisible = yes, UnitIsDeadOrGhost = no, UnitIsConnected = yes,
    issecretvalue = function(v) return v == SECRET end,
    hasanysecretvalues = function(...)
      for i = 1, select("#", ...) do if select(i, ...) == SECRET then return true end end
      return false
    end,
    wipe = function(t) for key in pairs(t) do t[key] = nil end return t end,
    tinsert = table.insert, tremove = table.remove, min = math.min, max = math.max,
    tContains = function(t, value) for _, v in ipairs(t) do if v == value then return true end end end,
    GetTexCoordsByGrid = noop, CreateTextureMarkup = noop,
    C_Spell = { GetSpellName = function(id) return NAMES[id] end },
    C_Secrets = {
      ShouldAurasBeSecret = function() return world.secret end,
      ShouldSpellAuraBeSecret = function() return world.secret and not neverSecret end,
    },
    C_UnitAuras = {
      GetUnitAuraBySpellID = function(unit, id)
        if unit == "player" and readable() then return record(id) end
      end,
      GetAuraDataBySpellName = function(unit, name)
        if unit ~= "player" or not readable() then return end
        for id in pairs(world.auras) do
          if NAMES[id] == name then return record(id) end
        end
      end,
      IsAuraFilteredOutByInstanceID = no,
      GetAuraDataByAuraInstanceID = function()
        if world.secret then error("Auras cannot be accessed when secret while tainted") end
      end,
    },
    Enum = { AddOnRestrictionState = { Inactive = 0, Active = 2 } },
    AuraUtil = {
      ForEachAura = function(unit, filter, _, callback)
        if world.secret then
          world.enumerateWhileSecret = world.enumerateWhileSecret + 1
          error("Auras cannot be accessed when secret while tainted")
        end
        if unit == "player" and filter == "HELPFUL" then
          for id in pairs(world.auras) do callback(record(id)) end
        end
      end,
    },
    CreateFrame = frameStub,
  }, { __index = _G })
  local triggerSystem
  addon.RegisterTriggerSystem = function(_, system) triggerSystem = system end
  local chunk = assert(loadfile(T.repoRoot .. "/EverythingAuras/BuffTrigger2.lua"))
  setfenv(chunk, env)("EverythingAuras", private)
  local frame = private.frames["EverythingAuras Buff2 Frame"]
  local castFrame = private.frames["Everything Auras Cast Estimates"]
  local function update() frame.scripts.OnUpdate() end
  local function event(name, ...)
    if frame.events[name] then frame.scripts.OnEvent(frame, name, ...) end
    update()
  end
  local function advance(seconds)
    world.now = world.now + seconds
    for handle in pairs(world.timers) do
      if handle.at <= world.now then
        world.timers[handle] = nil
        handle.func(handle.arg)
      end
    end
    update()
  end
  local loaded = {}
  local function add(id, trigger)
    trigger.type, trigger.unit, trigger.debuffType = "aura2", "player", "HELPFUL"
    data[id] = { id = id, uid = id, triggers = {{ trigger = trigger }} }
    triggerSystem.Add(data[id])
    loaded[id] = true
  end
  add("FoundByID", { useExactSpellId = true, auraspellids = { "6673" } })
  add("MissingByID", { useExactSpellId = true, auraspellids = { "6673" }, matchesShowOn = "showOnMissing" })
  add("FoundByName", { useName = true, auranames = { "Battle Shout" } })
  for id, trigger in pairs(triggers or {}) do
    add(id, trigger)
  end
  triggerSystem.LoadDisplays(loaded)
  update()
  local function state(id) return states[id] and states[id][""] end
  local guid = 0
  return {
    world = world, event = event, advance = advance,
    show = function(id)
      local s = state(id)
      return s and s.show and true or false
    end,
    unsure = function(id)
      local s = state(id)
      return s and s.eaUnsure
    end,
    expires = function(id)
      local s = state(id)
      return s and s.expirationTime
    end,
    give = function(id, duration)
      world.nextInstance = world.nextInstance + 1
      world.auras[id] = { instance = world.nextInstance, duration = duration, expirationTime = world.now + duration }
      event("UNIT_AURA", "player", world.secret and { isFullUpdate = SECRET } or { isFullUpdate = true })
    end,
    take = function(id)
      world.auras[id] = nil
      event("UNIT_AURA", "player", world.secret and { isFullUpdate = SECRET } or { isFullUpdate = true })
    end,
    cast = function(id, target)
      guid = guid + 1
      castFrame.scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SENT", "player", target, "cast" .. guid, id)
      castFrame.scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast" .. guid, id)
      update()
    end,
    pull = function()
      world.secret = true
      event("ADDON_RESTRICTION_STATE_CHANGED", 0, 2)
      event("UNIT_AURA", "player", { isFullUpdate = SECRET, addedAuras = {} })
    end,
    combatEnds = function()
      world.secret = false
      event("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
    end,
  }
end

T.section("Buff up before the pull, still up after it")
local f = newFixture(false)
T.expect(f.show("FoundByID") and f.show("FoundByName") and not f.show("MissingByID"), "out of combat: Found shows, Missing hidden")
T.expect(f.unsure("FoundByID") == nil, "out of combat the state is exact")
local ok, err = pcall(f.pull)
T.expect(ok, "in-combat UNIT_AURA handled without a Lua error" .. (ok and "" or (": " .. tostring(err))))
T.expect(f.world.enumerateWhileSecret == 0, "no throwing enumeration while secret")
T.expect(f.show("FoundByID") and f.show("FoundByName"), "in combat the buff stays shown (no wipe)")
T.expect(f.unsure("FoundByID") == "lastKnown" and f.unsure("FoundByName") == "lastKnown", "in combat the buff is marked last known")
T.expect(not f.show("MissingByID"), "in combat Missing stays hidden")
f.combatEnds()
T.expect(f.show("FoundByID") and f.unsure("FoundByID") == nil, "after combat the buff is exact again")
T.expect(not f.show("MissingByID"), "after combat Missing stays hidden")

T.section("Last known expires on its timer, Missing holds")
f = newFixture(false)
f.pull()
f.world.auras[6673] = nil
f.advance(99)
T.expect(f.show("FoundByID") and f.unsure("FoundByID") == "lastKnown", "before its expiration the buff is still last known")
f.advance(2)
T.expect(not f.show("FoundByID") and not f.show("FoundByName"), "at its expiration the last known buff lets go")
T.expect(f.unsure("FoundByID") == "lastKnown", "the hide is marked unsure, so On Hide stays silent")
T.expect(not f.show("MissingByID"), "in combat a Missing reminder does not appear from a guess")
f.combatEnds()
T.expect(f.show("MissingByID") and f.unsure("MissingByID") == nil, "after combat Missing shows from an exact read")

T.section("Restrictions starting mark hidden auras last known at once")
f = newFixture(false)
f.world.secret = true
f.event("ADDON_RESTRICTION_STATE_CHANGED", 0, 2)
T.expect(f.show("FoundByID") and f.unsure("FoundByID") == "lastKnown", "no aura change needed: the buff is last known")
f.advance(101)
T.expect(not f.show("FoundByID"), "and it still lets go on its timer")
f = newFixture(true)
f.world.secret = true
f.event("ADDON_RESTRICTION_STATE_CHANGED", 0, 2)
T.expect(f.show("FoundByID") and f.unsure("FoundByID") == nil, "a never-secret buff stays exact")

T.section("One restriction ending while another stays on")
f = newFixture(false)
f.pull()
f.event("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
T.expect(f.show("FoundByID") and f.unsure("FoundByID") == "lastKnown", "no wipe while auras are still secret")

T.section("A spell Blizzard does not hide reads exactly in combat")
f = newFixture(true)
f.pull()
T.expect(f.show("FoundByID") and f.unsure("FoundByID") == nil, "a never-secret buff stays exact")
f.take(6673)
T.expect(not f.show("FoundByID"), "a never-secret buff that is gone is dropped at once")
T.expect(f.show("MissingByID") and f.unsure("MissingByID") == nil, "and its Missing reminder shows as exact")

T.section("Recasting your own buff in combat restarts it as estimated")
f = newFixture(false)
f.give(6673, 120)
f.pull()
f.advance(60)
T.expect(f.unsure("FoundByID") == "lastKnown" and f.expires("FoundByID") == 220, "before the recast: last known, old timer")
f.cast(6673)
T.expect(f.show("FoundByID") and f.unsure("FoundByID") == "estimated", "after the recast: estimated")
T.expect(f.expires("FoundByID") == 280 and f.expires("FoundByName") == 280, "with a fresh timer of the learned length")
f.advance(100)
T.expect(f.show("FoundByID"), "still shown where the old timer would have run out")
f.advance(21)
T.expect(not f.show("FoundByID"), "and the estimate lets go on its own timer")
f.world.auras[6673] = nil
f.combatEnds()
T.expect(not f.show("FoundByID") and f.show("MissingByID"), "after combat the real state takes over")

T.section("A buff cast on someone else or never read stays unestimated")
f = newFixture(false)
f.pull()
f.advance(10)
f.cast(6673, "Friend")
T.expect(f.unsure("FoundByID") == "lastKnown" and f.expires("FoundByID") == 200, "a cast on another player does not restart your buff")
f.cast(6673, "Me")
T.expect(f.unsure("FoundByID") == "estimated", "a cast on yourself by name does")
f = newFixture(false, { SealA = { useName = true, auranames = { "Seal A" } } })
f.pull()
f.cast(100)
T.expect(not f.show("SealA"), "a buff never read out of combat has no length to estimate")

T.section("Seals swap: buffs of one length never read together are exclusive")
f = newFixture(false, {
  SealA = { useName = true, auranames = { "Seal A" } },
  SealB = { useName = true, auranames = { "Seal B" } },
  ShoutC = { useName = true, auranames = { "Shout C" } },
})
f.give(102, 300)
f.give(100, 30)
f.take(100)
f.give(101, 30)
f.take(101)
f.give(100, 30)
T.expect(f.show("SealA") and not f.show("SealB") and f.show("ShoutC"), "out of combat: Seal A and Shout C")
f.pull()
f.cast(101)
T.expect(f.show("SealB") and f.unsure("SealB") == "estimated", "casting Seal B in combat shows it estimated")
T.expect(not f.show("SealA"), "and drops Seal A, never read beside it")
T.expect(f.show("ShoutC") and f.unsure("ShoutC") == "lastKnown", "Shout C, a different length, stays")
T.finish()
